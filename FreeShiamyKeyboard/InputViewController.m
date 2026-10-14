#import "InputViewController.h"
#import "FSHCandidateBarView.h"
#import "FSHKeyboardView.h"
#import "FSHShiamyEngine.h"
#import "FSHCandidate.h"
#import "FSHSettings.h"
#import <math.h>

typedef NS_ENUM(NSInteger, FSHReverseState) {
    FSHReverseStateNone,
    FSHReverseStateEntering,
    FSHReverseStateActive,
};

typedef NS_ENUM(NSInteger, FSHDictionaryLoadState) {
    FSHDictionaryLoadStateLoading,
    FSHDictionaryLoadStateReady,
    FSHDictionaryLoadStateFailed,
};

@interface InputViewController () <FSHKeyboardViewDelegate, FSHCandidateBarViewDelegate>

@property (nonatomic, strong) FSHCandidateBarView *candidateBar;
@property (nonatomic, strong) FSHKeyboardView *keyboardView;
@property (nonatomic, strong) FSHShiamyEngine *engine;
@property (nonatomic, assign) FSHDictionaryLoadState engineLoadState;
@property (nonatomic, strong) NSError *engineLoadError;
@property (nonatomic, assign) NSUInteger engineLoadGeneration;
@property (nonatomic, assign) BOOL literalFallbackActive;
@property (nonatomic, copy) NSUUID *literalFallbackDocumentIdentifier;

@property (nonatomic, strong) NSMutableString *rawBuffer;
@property (nonatomic, copy) NSUUID *compositionDocumentIdentifier;
@property (nonatomic, copy) NSArray<FSHCandidate *> *candidates;
@property (nonatomic, assign) NSUInteger exactCount;
@property (nonatomic, assign) FSHReverseState reverseState;

@property (nonatomic, assign) BOOL shiftOn;
@property (nonatomic, assign) BOOL capsLockOn;
@property (nonatomic, strong) NSDate *lastShiftTapDate;

@property (nonatomic, strong) NSTimer *deleteRepeatTimer;
@property (nonatomic, assign) BOOL deleteLockout;
@property (nonatomic, assign) BOOL deletePressActive;
@property (nonatomic, copy) NSUUID *deleteDocumentIdentifier;

@property (nonatomic, copy) NSString *shortestHint;
@property (nonatomic, strong) UIButton *settingsHelpBanner;
@property (nonatomic, copy) NSUUID *settingsHelpDocumentIdentifier;
@property (nonatomic, strong) NSLayoutConstraint *settingsHelpHeightConstraint;

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

    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    }
    self.rawBuffer = [NSMutableString string];
    self.candidates = @[];
    self.reverseState = FSHReverseStateNone;
    [FSHSettings registerDefaults];

    self.candidateBar = [[FSHCandidateBarView alloc] initWithFrame:CGRectZero];
    self.candidateBar.delegate = self;
    [self.view addSubview:self.candidateBar];

    self.keyboardView = [[FSHKeyboardView alloc] initWithFrame:CGRectZero];
    self.keyboardView.delegate = self;
    [self.view addSubview:self.keyboardView];

    self.settingsHelpBanner = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsHelpBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsHelpBanner.hidden = YES;
    self.settingsHelpBanner.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.settingsHelpBanner.layer.cornerRadius = 6.0;
    self.settingsHelpBanner.layer.borderWidth = 1.0;
    self.settingsHelpBanner.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.settingsHelpBanner.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.settingsHelpBanner.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.settingsHelpBanner.titleLabel.minimumScaleFactor = 0.8;
    [self.settingsHelpBanner setTitle:@"請開啟 FreeShiamy App → 設定  ×" forState:UIControlStateNormal];
    [self.settingsHelpBanner setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    self.settingsHelpBanner.accessibilityIdentifier = @"settingsHelpBanner";
    self.settingsHelpBanner.accessibilityLabel = @"請開啟 FreeShiamy App，點選設定。輕點關閉提示。";
    [self.settingsHelpBanner addTarget:self action:@selector(dismissSettingsHelp) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.settingsHelpBanner];

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

        [self.settingsHelpBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.settingsHelpBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.settingsHelpBanner.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.settingsHelpBanner.bottomAnchor constraintLessThanOrEqualToAnchor:self.keyboardView.topAnchor],
    ]];
    self.settingsHelpHeightConstraint = [self.settingsHelpBanner.heightAnchor constraintEqualToConstant:self.candidateBar.barHeight];
    self.settingsHelpHeightConstraint.priority = 999;
    self.settingsHelpHeightConstraint.active = YES;
    self.candidateBarHeightConstraint = [self.candidateBar.heightAnchor constraintEqualToConstant:self.candidateBar.barHeight];
    self.candidateBarHeightConstraint.priority = UILayoutPriorityDefaultHigh;
    self.candidateBarHeightConstraint.active = YES;
    self.engineLoadState = FSHDictionaryLoadStateLoading;
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat available = MAX(0.0, CGRectGetHeight(self.candidateBar.bounds));
    CGFloat helpHeight = MIN(44.0, MIN(self.candidateBar.barHeight, available));
    if (fabs(self.settingsHelpHeightConstraint.constant - helpHeight) > 0.5) {
        self.settingsHelpHeightConstraint.constant = helpHeight;
    }
    [self refreshInputModeSwitchKey];
}

- (void)refreshInputModeSwitchKey {
    BOOL shouldShow = self.needsInputModeSwitchKey;
    if (self.keyboardView.showsGlobe != shouldShow) {
        self.keyboardView.showsGlobe = shouldShow;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self dismissSettingsHelp];
    [self endLiteralFallback];
    self.shortestHint = @"";
    [self clearComposingState];
    [self.keyboardView cancelActivePress];
    [self stopDeleteRepeat];
    self.deleteLockout = NO;
}

- (void)dealloc {
    [self.deleteRepeatTimer invalidate];
}

- (void)textWillChange:(id<UITextInput>)textInput {
    [super textWillChange:textInput];
    [self dismissSettingsHelpIfDocumentChanged];
    [self reconcileLiteralFallbackDocument];
    [self reconcileCompositionDocument];
    [self handleSensitiveFieldIfNeeded];
}

- (void)textDidChange:(id<UITextInput>)textInput {
    [super textDidChange:textInput];
    [self dismissSettingsHelpIfDocumentChanged];
    self.hasHostConnection = YES;
    [self reconcileLiteralFallbackDocument];
    [self reconcileCompositionDocument];
    [self handleSensitiveFieldIfNeeded];
}

- (void)selectionWillChange:(id<UITextInput>)textInput {
    [super selectionWillChange:textInput];
    [self dismissSettingsHelpIfDocumentChanged];
    [self reconcileLiteralFallbackDocument];
    [self clearComposingState];
}

- (void)selectionDidChange:(id<UITextInput>)textInput {
    [super selectionDidChange:textInput];
    [self dismissSettingsHelpIfDocumentChanged];
    [self reconcileLiteralFallbackDocument];
    [self clearComposingState];
    [self handleSensitiveFieldIfNeeded];
}

#pragma mark - Engine

- (void)loadEngineAsync {
    NSUInteger generation = [self beginEngineLoad];
    NSBundle *bundle = [NSBundle bundleForClass:[InputViewController class]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FSHShiamyEngine *loadedEngine = [[FSHShiamyEngine alloc] init];
        NSError *error = nil;
        BOOL loaded = [loadedEngine loadFromBundle:bundle error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            [strongSelf finishEngineLoad:loadedEngine loaded:loaded error:error generation:generation];
        });
    });
}

- (void)finishEngineLoad:(FSHShiamyEngine *)loadedEngine
                  loaded:(BOOL)loaded
                   error:(NSError *)error
              generation:(NSUInteger)generation {
    NSAssert([NSThread isMainThread], @"Dictionary publication must occur on the main thread");
    if (generation != self.engineLoadGeneration) {
        return;
    }
    self.engine = loaded ? loadedEngine : nil;
    self.engineLoadError = loaded ? nil : error;
    self.engineLoadState = loaded ? FSHDictionaryLoadStateReady : FSHDictionaryLoadStateFailed;
    [self refreshCandidatesAndUI];
}

- (NSUInteger)beginEngineLoad {
    NSUInteger generation = ++self.engineLoadGeneration;
    self.engineLoadState = FSHDictionaryLoadStateLoading;
    self.engineLoadError = nil;
    self.engine = nil;
    self.candidates = @[];
    self.exactCount = 0;
    self.reverseState = FSHReverseStateNone;
    [self updateReverseStateIfNeeded];
    [self refreshCandidatesAndUI];
    return generation;
}

#pragma mark - Candidate Updates

- (void)refreshCandidatesAndUI {
    NSString *raw = [self.rawBuffer copy];
    NSString *prefix = [self currentPrefix];

    NSUInteger exactCount = 0;
    NSArray<FSHCandidate *> *candidates = @[];
    BOOL canQuery = ([prefix rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound);
    if (prefix.length > 0 && canQuery) {
        candidates = [self.engine prefixCandidatesForCode:prefix exactCount:&exactCount];
    }

    if (self.reverseState == FSHReverseStateActive) {
        candidates = self.candidates;
        exactCount = candidates.count;
    }

    self.candidates = candidates ?: @[];
    self.exactCount = exactCount;

    NSString *hint = self.shortestHint;
    if (self.engineLoadState == FSHDictionaryLoadStateLoading) {
        hint = @"字庫載入中，暫以原文輸入";
    } else if (self.engineLoadState == FSHDictionaryLoadStateFailed) {
        hint = @"字庫載入失敗，暫以原文輸入";
    } else if (self.literalFallbackActive) {
        hint = @"正在原文輸入，空白後恢復字碼";
    } else if (prefix.length > 0 && candidates.count == 0) {
        hint = @"無候選字，點字碼可直接輸入";
    }

    [self.candidateBar updateRawBuffer:raw
                             candidates:self.candidates
                             exactCount:self.exactCount
                            inlineLimit:self.inlineLimit
                              moreLimit:self.moreLimit
                               hintText:hint];
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
    if (keyCode != FSHKeyCodeSettings) {
        [self dismissSettingsHelp];
    }
    [self reconcileLiteralFallbackDocument];
    [self reconcileCompositionDocument];
    BOOL wasInSensitiveField = self.isInSensitiveField;
    BOOL hadHostConnection = self.hasHostConnection;
    if ([self blockSensitiveInputIfNeeded]) {
        if (keyCode == FSHKeyCodeGlobe && (wasInSensitiveField || !hadHostConnection)) {
            [self advanceToNextInputMode];
        } else if (keyCode == FSHKeyCodeCancel && (wasInSensitiveField || !hadHostConnection)) {
            [self dismissKeyboard];
        }
        return;
    }
    if (keyCode != FSHKeyCodeShift) {
        self.lastShiftTapDate = nil;
    }
    [self clearHint];

    if (keyCode == FSHKeyCodeShift) {
        [self handleShift];
        return;
    }
    if (keyCode == FSHKeyCodeModeChange) {
        [self endLiteralFallback];
        [self handleModeChange];
        return;
    }
    if (keyCode == FSHKeyCodeEmoji) {
        [self endLiteralFallback];
        self.keyboardView.mode = FSHKeyboardModeEmoji;
        return;
    }
    if (keyCode == FSHKeyCodeGlobe) {
        [self endLiteralFallback];
        [self advanceToNextInputMode];
        return;
    }
    if (keyCode == FSHKeyCodeCancel) {
        [self endLiteralFallback];
        [self handleDone];
        return;
    }
    if (keyCode == FSHKeyCodeSettings) {
        [self openSettings];
        return;
    }
    if ((self.engineLoadState != FSHDictionaryLoadStateReady || self.literalFallbackActive) && self.rawBuffer.length == 0) {
        [self handleLiteralKeyCode:keyCode output:output];
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

- (void)keyboardView:(FSHKeyboardView *)keyboardView didReceiveInputModeEvent:(UIEvent *)event fromView:(UIView *)view {
    [self dismissSettingsHelp];
    self.lastShiftTapDate = nil;
    [self handleInputModeListFromView:view withEvent:event];
}

- (void)handleLiteralKeyCode:(NSInteger)keyCode output:(NSString *)output {
    if (keyCode == FSHKeyCodeDelete) {
        [self handleDeleteOnce];
    } else if (keyCode == FSHKeyCodeSpace) {
        [self.textDocumentProxy insertText:@" "];
        [self endLiteralFallback];
    } else if (keyCode == FSHKeyCodeEnter) {
        [self handleEnter];
        [self endLiteralFallback];
    } else if (output.length > 0) {
        NSString *literal = output;
        BOOL isLetter = (output.length == 1 && [[NSCharacterSet letterCharacterSet] characterIsMember:[output characterAtIndex:0]]);
        if (self.keyboardView.mode == FSHKeyboardModeLetters && isLetter && (self.shiftOn || self.capsLockOn)) {
            literal = output.uppercaseString;
        }
        [self.textDocumentProxy insertText:literal];
        self.literalFallbackActive = YES;
        self.literalFallbackDocumentIdentifier = self.textDocumentProxy.documentIdentifier;
        [self refreshCandidatesAndUI];
        if (isLetter && self.shiftOn && !self.capsLockOn) {
            self.shiftOn = NO;
            self.lastShiftTapDate = nil;
            self.keyboardView.shiftOn = NO;
        }
    }
}

- (void)endLiteralFallback {
    if (!self.literalFallbackActive) {
        return;
    }
    self.literalFallbackActive = NO;
    self.literalFallbackDocumentIdentifier = nil;
    [self refreshCandidatesAndUI];
}

- (void)reconcileLiteralFallbackDocument {
    if (!self.literalFallbackActive) {
        return;
    }
    NSUUID *current = self.textDocumentProxy.documentIdentifier;
    if (!self.literalFallbackDocumentIdentifier) {
        // The host may assign its document ID after the first insertion.
        self.literalFallbackDocumentIdentifier = current;
    } else if (![self.literalFallbackDocumentIdentifier isEqual:current]) {
        [self endLiteralFallback];
    }
}

- (void)keyboardView:(FSHKeyboardView *)keyboardView didBeginPressKeyCode:(NSInteger)keyCode output:(NSString *)output {
    if (keyCode == FSHKeyCodeDelete) {
        [self dismissSettingsHelp];
        self.lastShiftTapDate = nil;
        if ([self reconcileCompositionDocument]) {
            return;
        }
        if ([self blockSensitiveInputIfNeeded]) {
            return;
        }
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
        self.lastShiftTapDate = nil;
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
        BOOL isLetter = [[NSCharacterSet letterCharacterSet] characterIsMember:ch];
        if (isLetter) {
            if (self.shiftOn || self.capsLockOn) {
                finalChar = [single uppercaseString];
            } else {
                finalChar = [single lowercaseString];
            }
        }
        [self appendToRawBuffer:finalChar];
        if (isLetter && self.shiftOn && !self.capsLockOn) {
            self.shiftOn = NO;
            self.lastShiftTapDate = nil;
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
    if ([self reconcileCompositionDocument]) {
        [self stopDeleteRepeat];
        return;
    }
    if (self.deletePressActive && [self deleteTargetChanged]) {
        [self stopDeleteRepeat];
        return;
    }
    if ([self blockSensitiveInputIfNeeded]) {
        return;
    }
    if (self.reverseState == FSHReverseStateActive) {
        self.reverseState = FSHReverseStateEntering;
        [self refreshCandidatesAndUI];
        return;
    }
    if (self.rawBuffer.length > 0) {
        NSRange lastCharacter = [self.rawBuffer rangeOfComposedCharacterSequenceAtIndex:self.rawBuffer.length - 1];
        [self.rawBuffer deleteCharactersInRange:lastCharacter];
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
    [self stopDeleteRepeat];
    self.deleteDocumentIdentifier = self.textDocumentProxy.documentIdentifier;
    self.deletePressActive = YES;
    [self handleDeleteOnce];
    if (!self.deletePressActive) {
        return;
    }
    [self scheduleDeleteRepeatAfter:0.4];
}

- (void)stopDeleteRepeat {
    self.deletePressActive = NO;
    self.deleteDocumentIdentifier = nil;
    [self.deleteRepeatTimer invalidate];
    self.deleteRepeatTimer = nil;
}

- (BOOL)deleteTargetChanged {
    NSUUID *current = self.textDocumentProxy.documentIdentifier;
    return self.deleteDocumentIdentifier != current && ![self.deleteDocumentIdentifier isEqual:current];
}

- (void)scheduleDeleteRepeatAfter:(NSTimeInterval)delay {
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *firedTimer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.deletePressActive || strongSelf.deleteRepeatTimer != firedTimer) {
            return;
        }
        [strongSelf handleDeleteOnce];
        if (strongSelf.deletePressActive) {
            [strongSelf scheduleDeleteRepeatAfter:0.12];
        }
    }];
    self.deleteRepeatTimer = timer;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

#pragma mark - Reverse Lookup

- (void)triggerReverseLookupWithBaseIndex:(NSUInteger)index {
    if (index >= self.candidates.count) {
        return;
    }
    FSHCandidate *baseCandidate = self.candidates[index];
    if (![self isSingleComposedCharacter:baseCandidate.value]) {
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
    if ([self reconcileCompositionDocument]) {
        return;
    }
    if ([self blockSensitiveInputIfNeeded]) {
        return;
    }
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
    if ([self reconcileCompositionDocument]) {
        return;
    }
    if ([self blockSensitiveInputIfNeeded]) {
        return;
    }
    if (self.rawBuffer.length == 0) {
        return;
    }
    [self.textDocumentProxy insertText:[self.rawBuffer copy]];
    if (self.showShortestHint && [self isSingleComposedCharacter:self.rawBuffer]) {
        [self updateHintForCommittedValue:self.rawBuffer typedCodeLength:self.rawBuffer.length isReverse:NO];
    }
    [self clearComposingState];
}

#pragma mark - Candidate Bar Delegate

- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView {
    [self dismissSettingsHelp];
    self.lastShiftTapDate = nil;
    if ([self reconcileCompositionDocument]) {
        return;
    }
    if ([self blockSensitiveInputIfNeeded]) {
        return;
    }
    [self commitRawBuffer];
}

- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index {
    [self dismissSettingsHelp];
    self.lastShiftTapDate = nil;
    if ([self reconcileCompositionDocument]) {
        return;
    }
    if ([self blockSensitiveInputIfNeeded]) {
        return;
    }
    if (self.reverseState == FSHReverseStateEntering && index < self.exactCount) {
        [self triggerReverseLookupWithBaseIndex:index];
        return;
    }
    BOOL isReverse = (self.reverseState == FSHReverseStateActive);
    NSUInteger typedLength = [self currentPrefix].length;
    [self commitCandidateAtIndex:index typedCodeLength:typedLength isReverse:isReverse];
}

- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded {
    self.lastShiftTapDate = nil;
    [self updatePreferredContentSize];
    [self updateCandidateBarHeight];
}

#pragma mark - Helpers

- (void)appendToRawBuffer:(NSString *)text {
    if (self.rawBuffer.length == 0) {
        self.compositionDocumentIdentifier = self.textDocumentProxy.documentIdentifier;
    }
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
    self.compositionDocumentIdentifier = nil;
    self.candidates = @[];
    self.exactCount = 0;
    self.reverseState = FSHReverseStateNone;
    [self refreshCandidatesAndUI];
}

- (BOOL)reconcileCompositionDocument {
    if (self.rawBuffer.length == 0 && self.reverseState != FSHReverseStateActive) {
        return NO;
    }
    NSUUID *current = self.textDocumentProxy.documentIdentifier;
    if (!self.compositionDocumentIdentifier) {
        self.compositionDocumentIdentifier = current;
        return NO;
    }
    if (![self.compositionDocumentIdentifier isEqual:current]) {
        self.shortestHint = @"";
        [self clearComposingState];
        return YES;
    }
    return NO;
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
    if (![self isSingleComposedCharacter:value]) {
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

- (BOOL)isSingleComposedCharacter:(NSString *)value {
    if (value.length == 0) {
        return NO;
    }
    NSRange first = [value rangeOfComposedCharacterSequenceAtIndex:0];
    return NSMaxRange(first) == value.length;
}

- (void)openSettings {
    self.settingsHelpDocumentIdentifier = self.textDocumentProxy.documentIdentifier;
    BOOL shouldAnnounce = self.settingsHelpBanner.hidden;
    self.settingsHelpBanner.hidden = NO;
    self.candidateBar.accessibilityElementsHidden = YES;
    [self.view bringSubviewToFront:self.settingsHelpBanner];
    if (shouldAnnounce) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.settingsHelpBanner.accessibilityLabel);
    }
}

- (void)dismissSettingsHelp {
    self.settingsHelpBanner.hidden = YES;
    self.candidateBar.accessibilityElementsHidden = NO;
    self.settingsHelpDocumentIdentifier = nil;
}

- (void)dismissSettingsHelpIfDocumentChanged {
    NSUUID *current = self.textDocumentProxy.documentIdentifier;
    if (!self.settingsHelpBanner.hidden && self.settingsHelpDocumentIdentifier != current &&
        ![self.settingsHelpDocumentIdentifier isEqual:current]) {
        [self dismissSettingsHelp];
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
    NSLog(@"[Keyboard] layout setting = %@", layout);
    BOOL labelTop = [FSHSettings keyboardLabelTop];
    BOOL leftShift = [FSHSettings keyboardLeftShift];
    BOOL showNumberRow = [FSHSettings showNumberRow];
    FSHKeyboardLayout effectiveLayout = FSHKeyboardLayoutStandard;
    if ([layout isEqualToString:@"standard_spacious"]) {
        effectiveLayout = FSHKeyboardLayoutStandardSpacious;
    } else if ([layout isEqualToString:@"original"]) {
        effectiveLayout = FSHKeyboardLayoutOriginal;
    } else if ([layout isEqualToString:@"original_no_number"]) {
        effectiveLayout = FSHKeyboardLayoutOriginalNoNumber;
        showNumberRow = NO;
    } else if ([layout isEqualToString:@"standard_label_top"]) {
        labelTop = YES;
        if (![FSHSettings keyboardLabelTop]) {
            [FSHSettings setKeyboardLabelTop:YES];
        }
        [FSHSettings setKeyboardLayout:@"standard"];
    }
    [self.keyboardView applyLayout:effectiveLayout
                    showNumberRow:showNumberRow
                       showsGlobe:self.needsInputModeSwitchKey
                          labelTop:labelTop
                         leftShift:leftShift];

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
        [self endLiteralFallback];
        [self stopDeleteRepeat];
        self.deleteLockout = NO;
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
    if (!self.disableIMEInSensitive) {
        return NO;
    }
    return self.isInSensitiveField || [self isSensitiveField];
}

- (BOOL)blockSensitiveInputIfNeeded {
    if (![self shouldBlockForSensitiveField]) {
        return NO;
    }
    [self stopDeleteRepeat];
    [self endLiteralFallback];
    self.deleteLockout = NO;
    [self clearComposingState];
    if (!self.isInSensitiveField) {
        [self handleSensitiveFieldIfNeeded];
    }
    return YES;
}

@end
