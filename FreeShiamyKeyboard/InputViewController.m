#import "InputViewController.h"
#import "FSHCandidateBarView.h"
#import "FSHKeyboardView.h"
#import "FSHShiamyEngine.h"
#import "FSHCandidate.h"
#import "FSHSettings.h"

typedef NS_ENUM(NSInteger, FSHReverseState) {
    FSHReverseStateNone,
    FSHReverseStateEntering,
    FSHReverseStateActive,
};

@interface InputViewController () <FSHKeyboardViewDelegate, FSHCandidateBarViewDelegate>

@property (nonatomic, strong) FSHCandidateBarView *candidateBar;
@property (nonatomic, strong) FSHKeyboardView *keyboardView;
@property (nonatomic, strong) FSHShiamyEngine *engine;

@property (nonatomic, strong) NSMutableString *rawBuffer;
@property (nonatomic, copy) NSArray<FSHCandidate *> *candidates;
@property (nonatomic, assign) NSUInteger exactCount;
@property (nonatomic, assign) FSHReverseState reverseState;

@property (nonatomic, assign) BOOL shiftOn;
@property (nonatomic, assign) BOOL capsLockOn;
@property (nonatomic, strong) NSDate *lastShiftTapDate;

@property (nonatomic, strong) NSTimer *deleteRepeatTimer;
@property (nonatomic, assign) BOOL deleteLockout;

@property (nonatomic, copy) NSString *shortestHint;

@property (nonatomic, assign) NSUInteger inlineLimit;
@property (nonatomic, assign) NSUInteger moreLimit;
@property (nonatomic, assign) BOOL showShortestHint;
@property (nonatomic, assign) BOOL disableIMEInSensitive;
@property (nonatomic, assign) BOOL sensitiveIncludeNoPersonalized;
@property (nonatomic, assign) BOOL isInSensitiveField;
@property (nonatomic, assign) BOOL hasHostConnection;
@property (nonatomic, strong) NSLayoutConstraint *candidateBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;

@end

@implementation InputViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemGray5Color];
    self.rawBuffer = [NSMutableString string];
    self.candidates = @[];
    self.reverseState = FSHReverseStateNone;
    [FSHSettings registerDefaults];

    self.candidateBar = [[FSHCandidateBarView alloc] initWithFrame:CGRectZero];
    self.candidateBar.delegate = self;
    [self.view addSubview:self.candidateBar];

    self.keyboardView = [[FSHKeyboardView alloc] initWithFrame:CGRectZero];
    self.keyboardView.delegate = self;
    self.keyboardView.showsGlobe = NO;
    [self.view addSubview:self.keyboardView];

    self.candidateBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.keyboardView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.candidateBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.candidateBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.candidateBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],

        [self.keyboardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.keyboardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.keyboardView.topAnchor constraintEqualToAnchor:self.candidateBar.bottomAnchor],
        [self.keyboardView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.candidateBarHeightConstraint = [self.candidateBar.heightAnchor constraintEqualToConstant:self.candidateBar.barHeight];
    self.candidateBarHeightConstraint.priority = UILayoutPriorityDefaultHigh;
    self.candidateBarHeightConstraint.active = YES;
    self.engine = [[FSHShiamyEngine alloc] init];
    [self loadEngineAsync];

    [self applySettings];
    [self refreshCandidatesAndUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applySettings];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)textWillChange:(id<UITextInput>)textInput {
    [super textWillChange:textInput];
    [self handleSensitiveFieldIfNeeded];
}

- (void)textDidChange:(id<UITextInput>)textInput {
    [super textDidChange:textInput];
    self.hasHostConnection = YES;
    [self handleSensitiveFieldIfNeeded];
}

- (void)selectionWillChange:(id<UITextInput>)textInput {
    [super selectionWillChange:textInput];
    [self clearComposingState];
}

- (void)selectionDidChange:(id<UITextInput>)textInput {
    [super selectionDidChange:textInput];
    [self clearComposingState];
    [self handleSensitiveFieldIfNeeded];
}

#pragma mark - Engine

- (void)loadEngineAsync {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        [weakSelf.engine loadFromBundle:[NSBundle mainBundle] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf refreshCandidatesAndUI];
        });
    });
}

#pragma mark - Candidate Updates

- (void)refreshCandidatesAndUI {
    NSString *raw = [self.rawBuffer copy];
    NSString *prefix = [self currentPrefix];

    NSUInteger exactCount = 0;
    NSArray<FSHCandidate *> *candidates = @[];
    if (prefix.length > 0) {
        candidates = [self.engine prefixCandidatesForCode:prefix exactCount:&exactCount];
    }

    if (self.reverseState == FSHReverseStateActive) {
        candidates = self.candidates;
        exactCount = candidates.count;
    }

    self.candidates = candidates ?: @[];
    self.exactCount = exactCount;

    [self.candidateBar updateRawBuffer:raw
                             candidates:self.candidates
                             exactCount:self.exactCount
                            inlineLimit:self.inlineLimit
                              moreLimit:self.moreLimit
                               hintText:self.shortestHint];
}

- (NSString *)currentPrefix {
    if (self.rawBuffer.length == 0) {
        return @"";
    }
    if (self.reverseState == FSHReverseStateEntering && self.rawBuffer.length > 1) {
        return [self.rawBuffer substringFromIndex:1];
    }
    return [self.rawBuffer copy];
}

- (BOOL)isReverseEnteringCandidate {
    if (self.rawBuffer.length < 2) {
        return NO;
    }
    unichar first = [self.rawBuffer characterAtIndex:0];
    unichar second = [self.rawBuffer characterAtIndex:1];
    BOOL secondIsLetter = [[NSCharacterSet letterCharacterSet] characterIsMember:second];
    return (first == '\'' && secondIsLetter);
}

#pragma mark - Input Handling

- (void)keyboardView:(FSHKeyboardView *)keyboardView didPressKeyCode:(NSInteger)keyCode output:(NSString *)output {
    if ([self shouldBlockForSensitiveField]) {
        [self clearComposingState];
        [self advanceToNextInputMode];
        return;
    }
    [self clearHint];

    if (keyCode == FSHKeyCodeShift) {
        [self handleShift];
        return;
    }
    if (keyCode == FSHKeyCodeModeChange) {
        [self handleModeChange];
        return;
    }
    if (keyCode == FSHKeyCodeEmoji) {
        self.keyboardView.mode = FSHKeyboardModeEmoji;
        return;
    }
    if (keyCode == FSHKeyCodeGlobe) {
        [self advanceToNextInputMode];
        return;
    }
    if (keyCode == FSHKeyCodeCancel) {
        [self handleDone];
        return;
    }
    if (keyCode == FSHKeyCodeSettings) {
        [self openSettings];
        return;
    }
    if (keyCode == FSHKeyCodeSpace) {
        [self handleSpace];
        return;
    }
    if (keyCode == FSHKeyCodeEnter) {
        [self handleEnter];
        return;
    }
    if (keyCode == FSHKeyCodeDelete) {
        [self handleDeleteOnce];
        return;
    }

    if (output.length > 0) {
        [self handleCharacter:output];
    }
}

- (void)keyboardView:(FSHKeyboardView *)keyboardView didBeginPressKeyCode:(NSInteger)keyCode output:(NSString *)output {
    if (keyCode == FSHKeyCodeDelete) {
        self.deleteLockout = (self.rawBuffer.length > 0 || self.reverseState == FSHReverseStateActive);
        [self startDeleteRepeat];
    }
}

- (void)keyboardView:(FSHKeyboardView *)keyboardView didEndPressKeyCode:(NSInteger)keyCode output:(NSString *)output {
    if (keyCode == FSHKeyCodeDelete) {
        [self stopDeleteRepeat];
        self.deleteLockout = NO;
    }
}

- (void)handleShift {
    if (self.keyboardView.mode == FSHKeyboardModeSymbols) {
        self.keyboardView.mode = FSHKeyboardModeSymbolsShift;
        return;
    }
    if (self.keyboardView.mode == FSHKeyboardModeSymbolsShift) {
        self.keyboardView.mode = FSHKeyboardModeSymbols;
        return;
    }
    if (self.keyboardView.mode == FSHKeyboardModeEmoji) {
        return;
    }
    NSTimeInterval interval = self.lastShiftTapDate ? [[NSDate date] timeIntervalSinceDate:self.lastShiftTapDate] : CGFLOAT_MAX;
    self.lastShiftTapDate = [NSDate date];

    if (self.capsLockOn) {
        self.capsLockOn = NO;
        self.shiftOn = NO;
    } else if (interval < 0.8) {
        self.capsLockOn = YES;
        self.shiftOn = NO;
    } else {
        self.shiftOn = !self.shiftOn;
    }

    self.keyboardView.shiftOn = self.shiftOn;
    self.keyboardView.capsLockOn = self.capsLockOn;
}

- (void)handleModeChange {
    if (self.keyboardView.mode == FSHKeyboardModeLetters) {
        self.keyboardView.mode = FSHKeyboardModeSymbols;
    } else {
        self.keyboardView.mode = FSHKeyboardModeLetters;
    }
}

- (void)handleDone {
    if (self.rawBuffer.length > 0) {
        [self commitRawBuffer];
    }
    [self dismissKeyboard];
}

- (void)handleEnter {
    if (self.rawBuffer.length > 0) {
        [self commitRawBuffer];
        return;
    }
    id<UITextInputTraits> traits = (id)self.textDocumentProxy;
    UIReturnKeyType returnKeyType = UIReturnKeyDefault;
    if ([traits respondsToSelector:@selector(returnKeyType)]) {
        returnKeyType = traits.returnKeyType;
    }
    switch (returnKeyType) {
        case UIReturnKeyNext:
            [self.textDocumentProxy insertText:@"\t"];
            break;
        case UIReturnKeyGo:
        case UIReturnKeySearch:
        case UIReturnKeySend:
        case UIReturnKeyDone:
        case UIReturnKeyJoin:
        case UIReturnKeyRoute:
        case UIReturnKeyGoogle:
        case UIReturnKeyYahoo:
        case UIReturnKeyEmergencyCall:
        case UIReturnKeyContinue:
            [self dismissKeyboard];
            break;
        case UIReturnKeyDefault:
        default:
            [self.textDocumentProxy insertText:@"\n"];
            break;
    }
}

- (void)handleSpace {
    if (self.reverseState == FSHReverseStateActive) {
        [self commitCandidateAtIndex:0 typedCodeLength:0 isReverse:YES];
        return;
    }
    if (self.reverseState == FSHReverseStateEntering && self.exactCount > 0) {
        [self triggerReverseLookupWithBaseIndex:0];
        return;
    }
    if (self.rawBuffer.length == 0) {
        [self.textDocumentProxy insertText:@" "];
        return;
    }
    if (self.exactCount > 0) {
        [self commitCandidateAtIndex:0 typedCodeLength:[self currentPrefix].length isReverse:NO];
        return;
    }
    [self appendToRawBuffer:@" "];
}

- (void)handleCharacter:(NSString *)output {
    NSString *single = output;
    BOOL isLettersMode = (self.keyboardView.mode == FSHKeyboardModeLetters);
    if (single.length != 1) {
        if (self.reverseState == FSHReverseStateActive) {
            self.reverseState = FSHReverseStateEntering;
        }
        if (!isLettersMode && self.reverseState != FSHReverseStateActive && self.rawBuffer.length > 0) {
            [self appendToRawBuffer:single];
        } else {
            [self.textDocumentProxy insertText:single];
        }
        return;
    }
    unichar ch = [single characterAtIndex:0];

    if (self.reverseState == FSHReverseStateActive && ![self isDigit:ch]) {
        self.reverseState = FSHReverseStateEntering;
    }

    if ([self isDigit:ch]) {
        NSInteger index = [self digitIndex:ch];
        if (self.reverseState == FSHReverseStateActive) {
            [self commitCandidateAtIndex:index typedCodeLength:0 isReverse:YES];
            return;
        }
        if (self.reverseState == FSHReverseStateEntering && self.exactCount > 0) {
            if (index < (NSInteger)self.exactCount) {
                [self triggerReverseLookupWithBaseIndex:index];
            }
            return;
        }
        if (!isLettersMode) {
            if (self.rawBuffer.length == 0) {
                [self.textDocumentProxy insertText:single];
            } else {
                [self appendToRawBuffer:single];
            }
            return;
        }
        if (self.rawBuffer.length == 0) {
            [self.textDocumentProxy insertText:single];
            return;
        }
        if (self.exactCount > 0) {
            if (index < (NSInteger)self.exactCount) {
                [self commitCandidateAtIndex:index typedCodeLength:[self currentPrefix].length isReverse:NO];
            }
            return;
        }
        [self appendToRawBuffer:single];
        return;
    }

    if (!isLettersMode && self.reverseState != FSHReverseStateActive) {
        if (self.rawBuffer.length == 0) {
            [self.textDocumentProxy insertText:single];
        } else {
            [self appendToRawBuffer:single];
        }
        return;
    }

    if ([self isCodeChar:ch]) {
        NSString *finalChar = single;
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:ch]) {
            if (self.shiftOn || self.capsLockOn) {
                finalChar = [single uppercaseString];
            } else {
                finalChar = [single lowercaseString];
            }
        }
        [self appendToRawBuffer:finalChar];
        if (self.shiftOn && !self.capsLockOn) {
            self.shiftOn = NO;
            self.keyboardView.shiftOn = NO;
        }
        return;
    }

    if (self.rawBuffer.length == 0) {
        [self.textDocumentProxy insertText:single];
    } else {
        [self appendToRawBuffer:single];
    }
}

- (void)handleDeleteOnce {
    if (self.reverseState == FSHReverseStateActive) {
        self.reverseState = FSHReverseStateEntering;
        [self refreshCandidatesAndUI];
        return;
    }
    if (self.rawBuffer.length > 0) {
        [self.rawBuffer deleteCharactersInRange:NSMakeRange(self.rawBuffer.length - 1, 1)];
        [self updateReverseStateIfNeeded];
        [self refreshCandidatesAndUI];
        return;
    }
    if (self.deleteLockout) {
        return;
    }
    [self.textDocumentProxy deleteBackward];
}

- (void)startDeleteRepeat {
    [self handleDeleteOnce];
    [self stopDeleteRepeat];
    self.deleteRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.16 target:self selector:@selector(handleDeleteOnce) userInfo:nil repeats:YES];
}

- (void)stopDeleteRepeat {
    [self.deleteRepeatTimer invalidate];
    self.deleteRepeatTimer = nil;
}

#pragma mark - Reverse Lookup

- (void)triggerReverseLookupWithBaseIndex:(NSUInteger)index {
    if (index >= self.candidates.count) {
        return;
    }
    FSHCandidate *baseCandidate = self.candidates[index];
    if (baseCandidate.value.length != 1) {
        [self commitCandidateAtIndex:index typedCodeLength:[self currentPrefix].length isReverse:NO];
        return;
    }
    NSArray<FSHCandidate *> *reverse = [self.engine reverseLookupCandidatesForBaseValue:baseCandidate.value];
    self.candidates = reverse ?: @[];
    self.reverseState = FSHReverseStateActive;
    self.exactCount = self.candidates.count;
    [self.candidateBar updateRawBuffer:self.rawBuffer
                             candidates:self.candidates
                             exactCount:self.exactCount
                            inlineLimit:self.inlineLimit
                              moreLimit:self.moreLimit
                               hintText:self.shortestHint];
}

#pragma mark - Commit

- (void)commitCandidateAtIndex:(NSUInteger)index typedCodeLength:(NSUInteger)typedCodeLength isReverse:(BOOL)isReverse {
    if (index >= self.candidates.count) {
        return;
    }
    FSHCandidate *candidate = self.candidates[index];
    [self.textDocumentProxy insertText:candidate.value];

    if (self.showShortestHint) {
        [self updateHintForCommittedValue:candidate.value typedCodeLength:typedCodeLength isReverse:isReverse];
    }

    [self clearComposingState];
}

- (void)commitRawBuffer {
    if (self.rawBuffer.length == 0) {
        return;
    }
    [self.textDocumentProxy insertText:[self.rawBuffer copy]];
    if (self.showShortestHint && self.rawBuffer.length == 1) {
        [self updateHintForCommittedValue:self.rawBuffer typedCodeLength:self.rawBuffer.length isReverse:NO];
    }
    [self clearComposingState];
}

#pragma mark - Candidate Bar Delegate

- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView {
    [self commitRawBuffer];
}

- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index {
    if (self.reverseState == FSHReverseStateEntering && index < self.exactCount) {
        [self triggerReverseLookupWithBaseIndex:index];
        return;
    }
    BOOL isReverse = (self.reverseState == FSHReverseStateActive);
    NSUInteger typedLength = [self currentPrefix].length;
    [self commitCandidateAtIndex:index typedCodeLength:typedLength isReverse:isReverse];
}

- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded {
    [self updatePreferredContentSize];
    [self updateCandidateBarHeight];
}

#pragma mark - Helpers

- (void)appendToRawBuffer:(NSString *)text {
    [self.rawBuffer appendString:text];
    [self updateReverseStateIfNeeded];
    [self refreshCandidatesAndUI];
}

- (void)updateReverseStateIfNeeded {
    if (self.reverseState == FSHReverseStateActive) {
        return;
    }
    self.reverseState = [self isReverseEnteringCandidate] ? FSHReverseStateEntering : FSHReverseStateNone;
}

- (void)clearComposingState {
    [self.rawBuffer setString:@""];
    self.candidates = @[];
    self.exactCount = 0;
    self.reverseState = FSHReverseStateNone;
    [self refreshCandidatesAndUI];
}

- (void)clearHint {
    if (self.shortestHint.length > 0) {
        self.shortestHint = @"";
        [self refreshCandidatesAndUI];
    }
}

- (BOOL)isCodeChar:(unichar)ch {
    if ([[NSCharacterSet letterCharacterSet] characterIsMember:ch]) {
        return YES;
    }
    return (ch == '\'' || ch == ',' || ch == '.' || ch == '[' || ch == ']');
}

- (BOOL)isDigit:(unichar)ch {
    return (ch >= '0' && ch <= '9');
}

- (NSInteger)digitIndex:(unichar)ch {
    return ch == '0' ? 0 : (ch - '0');
}

- (void)updateHintForCommittedValue:(NSString *)value typedCodeLength:(NSUInteger)typedCodeLength isReverse:(BOOL)isReverse {
    if (value.length != 1) {
        self.shortestHint = @"";
        return;
    }
    NSString *shortest = [self.engine shortestCodeForValue:value];
    if (shortest.length == 0) {
        self.shortestHint = @"";
        return;
    }
    if (!isReverse && typedCodeLength <= 2) {
        self.shortestHint = @"";
        return;
    }
    if (!isReverse && shortest.length >= typedCodeLength) {
        self.shortestHint = @"";
        return;
    }
    NSString *upper = [shortest uppercaseString];
    self.shortestHint = [NSString stringWithFormat:@"字根：%@", upper];
}

- (void)openSettings {
    NSURL *url = [NSURL URLWithString:@"freeshiamy://settings"];
    if (url) {
        [self.extensionContext openURL:url completionHandler:nil];
    }
}

- (void)applySettings {
    [FSHSettings registerDefaults];
    self.inlineLimit = [FSHSettings candidateInlineLimit];
    self.moreLimit = [FSHSettings candidateMoreLimit];
    self.showShortestHint = [FSHSettings showShortestCodeHint];
    self.disableIMEInSensitive = [FSHSettings disableImeInSensitiveFields];
    self.sensitiveIncludeNoPersonalized = [FSHSettings sensitiveIncludeNoPersonalizedLearning];

    NSString *layout = [FSHSettings keyboardLayout];
    BOOL labelTop = [FSHSettings keyboardLabelTop];
    BOOL leftShift = [FSHSettings keyboardLeftShift];
    BOOL showNumberRow = [FSHSettings showNumberRow];
    if ([layout isEqualToString:@"standard_spacious"]) {
        self.keyboardView.layout = FSHKeyboardLayoutStandardSpacious;
    } else if ([layout isEqualToString:@"original"]) {
        self.keyboardView.layout = FSHKeyboardLayoutOriginal;
    } else if ([layout isEqualToString:@"original_no_number"]) {
        self.keyboardView.layout = FSHKeyboardLayoutOriginalNoNumber;
        showNumberRow = NO;
    } else if ([layout isEqualToString:@"standard_label_top"]) {
        self.keyboardView.layout = FSHKeyboardLayoutStandard;
        labelTop = YES;
        if (![FSHSettings keyboardLabelTop]) {
            [FSHSettings setKeyboardLabelTop:YES];
        }
        [FSHSettings setKeyboardLayout:@"standard"];
    } else {
        self.keyboardView.layout = FSHKeyboardLayoutStandard;
    }
    self.keyboardView.labelTop = labelTop;
    self.keyboardView.leftShift = leftShift;
    self.keyboardView.showNumberRow = showNumberRow;
    [self.keyboardView reloadKeys];

    [self updatePreferredContentSize];
    [self refreshCandidatesAndUI];
}

- (void)updatePreferredContentSize {
    NSInteger percent = [FSHSettings keyboardHeightPercent];
    if (percent < 90) { percent = 90; }
    if (percent > 220) { percent = 220; }
    CGFloat baseHeight = 216.0;
    CGFloat keyboardHeight = baseHeight * ((CGFloat)percent / 100.0);
    CGFloat total = keyboardHeight + self.candidateBar.barHeight;
    if (self.candidateBar.isExpanded) {
        total += self.candidateBar.expandedHeight;
    }
    self.preferredContentSize = CGSizeMake(0, total);
    if (!self.heightConstraint) {
        self.heightConstraint = [self.view.heightAnchor constraintEqualToConstant:total];
        self.heightConstraint.priority = UILayoutPriorityDefaultHigh;
        self.heightConstraint.active = YES;
    } else {
        self.heightConstraint.constant = total;
    }
    [self.view setNeedsLayout];
    if (self.view.window) {
        [self.view layoutIfNeeded];
    }
}

- (void)updateCandidateBarHeight {
    if (!self.candidateBarHeightConstraint) {
        return;
    }
    CGFloat height = self.candidateBar.barHeight;
    if (self.candidateBar.isExpanded) {
        height += self.candidateBar.expandedHeight;
    }
    self.candidateBarHeightConstraint.constant = height;
    [self.view setNeedsLayout];
    if (self.view.window) {
        [self.view layoutIfNeeded];
    }
}

- (void)handleSensitiveFieldIfNeeded {
    if (!self.hasHostConnection) {
        return;
    }
    if (!self.disableIMEInSensitive) {
        self.isInSensitiveField = NO;
        return;
    }
    BOOL sensitive = [self isSensitiveField];
    if (sensitive && !self.isInSensitiveField) {
        self.isInSensitiveField = YES;
        [self clearComposingState];
        [self advanceToNextInputMode];
        [self dismissKeyboard];
    } else if (!sensitive && self.isInSensitiveField) {
        self.isInSensitiveField = NO;
    }
}

- (BOOL)isSensitiveField {
    id<UITextInputTraits> traits = (id)self.textDocumentProxy;
    if ([traits respondsToSelector:@selector(isSecureTextEntry)]) {
        if (traits.secureTextEntry) {
            return YES;
        }
    }
    if (self.sensitiveIncludeNoPersonalized && [traits respondsToSelector:@selector(textContentType)]) {
        NSString *contentType = traits.textContentType;
        if ([contentType isEqualToString:UITextContentTypePassword] ||
            [contentType isEqualToString:UITextContentTypeNewPassword] ||
            [contentType isEqualToString:UITextContentTypeOneTimeCode]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)shouldBlockForSensitiveField {
    if (!self.disableIMEInSensitive || !self.hasHostConnection) {
        return NO;
    }
    return self.isInSensitiveField;
}

@end
