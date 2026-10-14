#import <XCTest/XCTest.h>
#import <math.h>
#import "InputViewController.h"
#import "FSHKeyboardView.h"
#import "FSHKeyButton.h"
#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"
#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"
#import "FSHSettings.h"
#import "FSHKeyboardMetrics.h"
#import "CodeSearchViewController.h"
#import "SettingsViewController.h"
#import "ViewController.h"

@interface ViewController (CodeSearchTests)
- (void)openCodeSearch;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;
@end

@interface SettingsViewController (KeyboardInputTests)
- (void)refreshUI;
- (void)layoutChanged:(UISegmentedControl *)segment;
@end

@class FSHFakeDocumentProxy;

@interface InputViewController (KeyboardInputTests)
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView;
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index;
- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didPressKeyCode:(NSInteger)keyCode output:(NSString *)output;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didBeginPressKeyCode:(NSInteger)keyCode output:(NSString *)output;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didReceiveInputModeEvent:(UIEvent *)event fromView:(UIView *)view;
- (void)triggerReverseLookupWithBaseIndex:(NSUInteger)index;
- (void)updateHintForCommittedValue:(NSString *)value typedCodeLength:(NSUInteger)typedCodeLength isReverse:(BOOL)isReverse;
- (NSUInteger)beginEngineLoad;
- (void)refreshCandidatesAndUI;
- (void)refreshInputModeSwitchKey;
- (void)applySettings;
- (void)finishEngineLoad:(FSHShiamyEngine *)loadedEngine loaded:(BOOL)loaded error:(NSError *)error generation:(NSUInteger)generation;
- (void)updatePreferredContentSize;
- (CGFloat)preferredHeightLimitForScene;
@end

@interface FSHKeyboardView (KeyboardInputTests)
- (void)handleKeyPress:(FSHKeyButton *)sender;
- (void)handleGlobeEvent:(FSHKeyButton *)sender forEvent:(UIEvent *)event;
- (void)handleBracketLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@interface FSHStatefulLongPress : UILongPressGestureRecognizer
@property (nonatomic, assign) UIGestureRecognizerState simulatedState;
@end

@implementation FSHStatefulLongPress
- (UIGestureRecognizerState)state { return self.simulatedState; }
@end

@interface FSHTestEngine : FSHShiamyEngine
@property (nonatomic, assign) NSUInteger reverseCallCount;
@end

@implementation FSHTestEngine
- (BOOL)ready { return YES; }
- (NSArray<FSHCandidate *> *)reverseLookupCandidatesForBaseValue:(NSString *)baseValue {
    self.reverseCallCount++;
    return @[[[FSHCandidate alloc] initWithCode:@"reading" value:baseValue]];
}
- (NSString *)shortestCodeForValue:(NSString *)value {
    return @"a";
}
@end

@interface FSHManyCandidatesEngine : FSHTestEngine
@property (nonatomic, copy) NSArray<FSHCandidate *> *fixtureCandidates;
@end

@implementation FSHManyCandidatesEngine
- (NSArray<FSHCandidate *> *)prefixCandidatesForCode:(NSString *)code exactCount:(NSUInteger *)exactCount {
    if (exactCount) { *exactCount = MIN((NSUInteger)10, self.fixtureCandidates.count); }
    return code.length > 0 ? self.fixtureCandidates : @[];
}
@end

@interface FSHAsyncInputController : InputViewController
@property (nonatomic, strong) FSHFakeDocumentProxy *fakeProxy;
@end

@implementation FSHAsyncInputController
- (id<UITextDocumentProxy>)textDocumentProxy {
    return (id<UITextDocumentProxy>)self.fakeProxy;
}
- (void)advanceToNextInputMode {}
- (void)dismissKeyboard {}
@end

@interface FSHFixtureEngine : FSHShiamyEngine
@property (nonatomic, copy) NSString *mainPath;
@property (nonatomic, copy) NSString *spellPath;
@end

@implementation FSHFixtureEngine
- (NSString *)pathForResource:(NSString *)name type:(NSString *)type inBundle:(NSBundle *)bundle {
    return [name isEqualToString:@"freeshiamy"] ? self.mainPath : self.spellPath;
}
@end

@interface FSHCodeSearchFixtureController : CodeSearchViewController
@property (nonatomic, assign) BOOL failNextLoad;
@end

@implementation FSHCodeSearchFixtureController
- (FSHShiamyEngine *)newDictionaryEngine {
    if (!self.failNextLoad) {
        return [[FSHShiamyEngine alloc] init];
    }
    FSHFixtureEngine *engine = [[FSHFixtureEngine alloc] init];
    engine.mainPath = @"/missing-main.cin";
    engine.spellPath = @"/missing-spell.cin";
    return engine;
}
@end

static id FSHFixtureDefaults;
static NSString *FSHFixtureSuiteName;

@interface FSHDictionaryDefaults : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *values;
@end

@implementation FSHDictionaryDefaults
- (id)objectForKey:(NSString *)key {
    return self.values[key];
}
@end

@interface FSHIsolatedSettings : FSHSettings
@end

@implementation FSHIsolatedSettings
+ (NSUserDefaults *)sharedDefaults {
    return (NSUserDefaults *)FSHFixtureDefaults;
}
+ (BOOL)hasPersistedSettingForKey:(NSString *)key {
    return [[FSHFixtureDefaults persistentDomainForName:FSHFixtureSuiteName] objectForKey:key] != nil;
}
@end

@interface FSHCandidateBarTestDelegate : NSObject <FSHCandidateBarViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSNumber *> *selectedIndexes;
@property (nonatomic, assign) NSUInteger expansionChangeCount;
@end

@implementation FSHCandidateBarTestDelegate
- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedIndexes = [NSMutableArray array];
    }
    return self;
}
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView {}
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index {
    [self.selectedIndexes addObject:@(index)];
}
- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded {
    self.expansionChangeCount++;
}
@end

@interface FSHCountingKeyboardView : FSHKeyboardView
@property (nonatomic, assign) NSUInteger reloadCount;
@end

@implementation FSHCountingKeyboardView
- (void)reloadKeys {
    [super reloadKeys];
    self.reloadCount++;
}
@end

@interface FSHFakeDocumentProxy : NSObject
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, assign, getter=isSecureTextEntry) BOOL secureTextEntry;
@property (nonatomic, copy) NSString *textContentType;
@property (nonatomic, copy) NSUUID *documentIdentifier;
@property (nonatomic, assign) UIReturnKeyType returnKeyType;
@end

@interface FSHNoContentTypeProxy : FSHFakeDocumentProxy
@end

@implementation FSHNoContentTypeProxy
- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(textContentType)) {
        return NO;
    }
    return [super respondsToSelector:aSelector];
}
@end

@implementation FSHFakeDocumentProxy

- (instancetype)init {
    self = [super init];
    if (self) {
        _text = [NSMutableString string];
        _documentIdentifier = [NSUUID UUID];
    }
    return self;
}

- (void)insertText:(NSString *)text {
    [self.text appendString:text];
}

- (void)deleteBackward {
    if (self.text.length > 0) {
        NSRange last = [self.text rangeOfComposedCharacterSequenceAtIndex:self.text.length - 1];
        [self.text deleteCharactersInRange:last];
    }
}
@end

@interface FSHTestInputController : InputViewController
@property (nonatomic, strong) FSHFakeDocumentProxy *fakeProxy;
@property (nonatomic, assign) NSUInteger inputModeAdvanceCount;
@property (nonatomic, assign) NSUInteger dismissCount;
@property (nonatomic, assign) BOOL fakeNeedsInputModeSwitchKey;
@property (nonatomic, assign) NSUInteger inputModeEventCount;
@property (nonatomic, weak) UIView *lastInputModeEventView;
@property (nonatomic, strong) UIEvent *lastInputModeEvent;
@end

@implementation FSHTestInputController

- (void)loadEngineAsync {
    // These controller-event tests isolate proxy behavior. Dictionary loading is
    // covered separately using the extension's actual resource bundle.
}

- (id<UITextDocumentProxy>)textDocumentProxy {
    return (id<UITextDocumentProxy>)self.fakeProxy;
}

- (void)advanceToNextInputMode {
    self.inputModeAdvanceCount++;
}

- (void)dismissKeyboard {
    self.dismissCount++;
}

- (BOOL)needsInputModeSwitchKey {
    return self.fakeNeedsInputModeSwitchKey;
}

- (void)handleInputModeListFromView:(UIView *)view withEvent:(UIEvent *)event {
    self.inputModeEventCount++;
    self.lastInputModeEventView = view;
    self.lastInputModeEvent = event;
}
@end

@interface FSHHeightLimitInputController : FSHTestInputController
@property (nonatomic, assign) CGFloat simulatedSceneLimit;
@end

@implementation FSHHeightLimitInputController
- (CGFloat)preferredHeightLimitForScene { return self.simulatedSceneLimit; }
@end

@interface KeyboardInputTests : XCTestCase
@property (nonatomic, strong) FSHTestInputController *controller;
@property (nonatomic, strong) FSHFakeDocumentProxy *proxy;
@property (nonatomic, strong) FSHKeyboardView *keyboard;
@property (nonatomic, strong) FSHKeyButton *deleteButton;
@end

@implementation KeyboardInputTests

- (void)setUp {
    [super setUp];
    self.proxy = [[FSHFakeDocumentProxy alloc] init];
    self.controller = [[FSHTestInputController alloc] init];
    self.controller.fakeProxy = self.proxy;
    [self.controller loadViewIfNeeded];
    [self.controller beginAppearanceTransition:YES animated:NO];
    [self.controller endAppearanceTransition];
    self.keyboard = [self.controller valueForKey:@"keyboardView"];
    self.deleteButton = [self.keyboard valueForKey:@"deleteButton"];
    XCTAssertNotNil(self.deleteButton);
}

- (void)tearDown {
    [self.keyboard cancelActivePress];
    self.deleteButton = nil;
    self.keyboard = nil;
    self.controller = nil;
    self.proxy = nil;
    [super tearDown];
}

- (NSMutableString *)rawBuffer {
    return [self.controller valueForKey:@"rawBuffer"];
}

- (void)tapDelete {
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (NSArray<FSHCandidate *> *)candidatesWithCount:(NSUInteger)count code:(NSString *)code {
    NSMutableArray<FSHCandidate *> *candidates = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        [candidates addObject:[[FSHCandidate alloc] initWithCode:code
                                                          value:[NSString stringWithFormat:@"候%lu", (unsigned long)index]]];
    }
    return candidates;
}

- (UIView *)hostForCandidateBar:(FSHCandidateBarView *)bar width:(CGFloat)width height:(CGFloat)height {
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, height)];
    [host addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:host.topAnchor],
    ]];
    return host;
}

- (void)waitForSeconds:(NSTimeInterval)seconds {
    XCTestExpectation *elapsed = [self expectationWithDescription:@"Timer elapsed"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [elapsed fulfill];
    });
    [self waitForExpectations:@[elapsed] timeout:seconds + 1.0];
}

- (BOOL)waitForView:(UIView *)view toAttachToWindow:(UIWindow *)window {
    [window layoutIfNeeded];
    NSPredicate *attachedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        [window layoutIfNeeded];
        return view.window == window && !CGRectIsEmpty(view.bounds);
    }];
    XCTNSPredicateExpectation *attached = [[XCTNSPredicateExpectation alloc] initWithPredicate:attachedPredicate object:view];
    return [XCTWaiter waitForExpectations:@[attached] timeout:5.0] == XCTWaiterResultCompleted;
}

- (UIImage *)snapshotOfWindow:(UIWindow *)window {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    __block BOOL rendered = NO;
    UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        rendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    XCTAssertTrue(rendered);
    return snapshot;
}

- (NSData *)rgbaForImageCrop:(CGImageRef)crop {
    if (!crop) {
        return nil;
    }
    size_t width = CGImageGetWidth(crop), height = CGImageGetHeight(crop);
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4,
                                                colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return nil;
    }
    // The order of rows does not matter for contrast within this cropped glyph.
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), crop);
    CGContextRelease(context);
    return pixels;
}

- (CGFloat)titleContrastForButton:(UIButton *)button inWindow:(UIWindow *)window
                            image:(UIImage *)image {
    XCTAssertEqual(image.imageOrientation, UIImageOrientationUp);
    if (image.imageOrientation != UIImageOrientationUp) {
        return 0;
    }
    CGRect titleRect = [button.titleLabel convertRect:button.titleLabel.bounds toView:window];
    CGFloat scale = image.scale;
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    NSInteger left = MAX(0, (NSInteger)floor(CGRectGetMinX(titleRect) * scale));
    NSInteger right = MIN((NSInteger)width, (NSInteger)ceil(CGRectGetMaxX(titleRect) * scale));
    NSInteger top = MAX(0, (NSInteger)floor(CGRectGetMinY(titleRect) * scale));
    NSInteger bottom = MIN((NSInteger)height, (NSInteger)ceil(CGRectGetMaxY(titleRect) * scale));
    if (right <= left || bottom <= top) {
        return 0;
    }
    CGImageRef crop = CGImageCreateWithImageInRect(image.CGImage,
                                                   CGRectMake(left, top, right - left, bottom - top));
    NSData *pixels = [self rgbaForImageCrop:crop];
    CGImageRelease(crop);
    if (!pixels) {
        return 0;
    }
    const uint8_t *bytes = pixels.bytes;
    CGFloat low = 1, high = 0;
    size_t cropWidth = (size_t)(right - left), cropHeight = (size_t)(bottom - top);
    for (size_t y = 0; y < cropHeight; y++) {
        for (size_t x = 0; x < cropWidth; x++) {
            const uint8_t *pixel = bytes + (y * cropWidth + x) * 4;
            CGFloat luminance = (pixel[0] + pixel[1] + pixel[2]) / (3.0 * 255.0);
            low = MIN(low, luminance);
            high = MAX(high, luminance);
        }
    }
    return high - low;
}

- (void)testSnapshotCropsUseUIKitTopLeftCoordinates {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2, 2) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor redColor] setFill];
        UIRectFill(CGRectMake(0, 0, 2, 1));
        [[UIColor blueColor] setFill];
        UIRectFill(CGRectMake(0, 1, 2, 1));
    }];
    XCTAssertEqual(image.imageOrientation, UIImageOrientationUp);
    CGImageRef top = CGImageCreateWithImageInRect(image.CGImage, CGRectMake(0, 0, 1, 1));
    CGImageRef bottom = CGImageCreateWithImageInRect(image.CGImage, CGRectMake(0, 1, 1, 1));
    NSData *topPixel = [self rgbaForImageCrop:top];
    NSData *bottomPixel = [self rgbaForImageCrop:bottom];
    CGImageRelease(top);
    CGImageRelease(bottom);
    XCTAssertEqual(topPixel.length, (NSUInteger)4);
    XCTAssertEqual(bottomPixel.length, (NSUInteger)4);
    if (topPixel.length != 4 || bottomPixel.length != 4) {
        return;
    }
    const uint8_t *topBytes = topPixel.bytes, *bottomBytes = bottomPixel.bytes;
    XCTAssertGreaterThan(topBytes[0], topBytes[2], @"The top crop must be red");
    XCTAssertGreaterThan(bottomBytes[2], bottomBytes[0], @"The bottom crop must be blue");
}

- (void)testTapDeletesHostExactlyOnce {
    [self.proxy.text setString:@"abc"];
    [self tapDelete];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
    XCTAssertNil([self.controller valueForKey:@"deleteRepeatTimer"]);
}

- (void)testSettingsSanitizePersistedValuesAndSetterInputs {
    NSString *suite = [@"freeshiamy.settings.tests." stringByAppendingString:[[NSUUID UUID] UUIDString]];
    NSUserDefaults *suiteDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    FSHFixtureDefaults = suiteDefaults;
    @try {
        [FSHFixtureDefaults removePersistentDomainForName:suite];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)100);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)10);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)200);
        XCTAssertEqualObjects([FSHIsolatedSettings keyboardLayout], @"standard");
        XCTAssertTrue([FSHIsolatedSettings showNumberRow]);
        XCTAssertTrue([FSHIsolatedSettings keyboardLeftShift]);
        XCTAssertTrue([FSHIsolatedSettings showShortestCodeHint]);
        XCTAssertTrue([FSHIsolatedSettings disableImeInSensitiveFields]);
        XCTAssertFalse([FSHIsolatedSettings keyboardLabelTop]);
        XCTAssertFalse([FSHIsolatedSettings sensitiveIncludeNoPersonalizedLearning]);

        for (id malformed in @[@"17", @"garbage", @[], @{}, @1.5]) {
            [FSHFixtureDefaults setObject:malformed forKey:@"keyboard_height_percent"];
            [FSHFixtureDefaults setObject:malformed forKey:@"candidate_inline_limit"];
            [FSHFixtureDefaults setObject:malformed forKey:@"candidate_more_limit"];
            XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)100);
            XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)10);
            XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)200);
        }

        [FSHFixtureDefaults setObject:@130 forKey:@"keyboard_height_percent"];
        [FSHFixtureDefaults setObject:@12 forKey:@"candidate_inline_limit"];
        [FSHFixtureDefaults setObject:@350 forKey:@"candidate_more_limit"];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)130);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)12);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)350);

        FSHDictionaryDefaults *nonfiniteDefaults = [[FSHDictionaryDefaults alloc] init];
        nonfiniteDefaults.values = @{@"keyboard_height_percent": @(NAN),
                                     @"candidate_inline_limit": @(INFINITY),
                                     @"candidate_more_limit": @(-INFINITY)};
        FSHFixtureDefaults = nonfiniteDefaults;
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)100);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)10);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)200);
        FSHFixtureDefaults = suiteDefaults;

        [FSHFixtureDefaults setObject:@(NSIntegerMin) forKey:@"keyboard_height_percent"];
        [FSHFixtureDefaults setObject:@(NSIntegerMax) forKey:@"candidate_inline_limit"];
        [FSHFixtureDefaults setObject:@0 forKey:@"candidate_more_limit"];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)90);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)20);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)50);
        [FSHFixtureDefaults setObject:@(NSIntegerMax) forKey:@"keyboard_height_percent"];
        [FSHFixtureDefaults setObject:@(NSIntegerMin) forKey:@"candidate_inline_limit"];
        [FSHFixtureDefaults setObject:@(NSIntegerMax) forKey:@"candidate_more_limit"];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)220);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)5);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)500);

        [FSHIsolatedSettings setKeyboardHeightPercent:90];
        [FSHIsolatedSettings setCandidateInlineLimit:5];
        [FSHIsolatedSettings setCandidateMoreLimit:50];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)90);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)5);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)50);
        [FSHIsolatedSettings setKeyboardHeightPercent:220];
        [FSHIsolatedSettings setCandidateInlineLimit:20];
        [FSHIsolatedSettings setCandidateMoreLimit:500];
        XCTAssertEqual([FSHIsolatedSettings keyboardHeightPercent], (NSInteger)220);
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)20);
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)500);
        [FSHIsolatedSettings setKeyboardHeightPercent:NSIntegerMin];
        [FSHIsolatedSettings setCandidateInlineLimit:NSIntegerMax];
        [FSHIsolatedSettings setCandidateMoreLimit:NSIntegerMax];
        XCTAssertEqual([FSHFixtureDefaults integerForKey:@"keyboard_height_percent"], (NSInteger)90);
        XCTAssertEqual([FSHFixtureDefaults integerForKey:@"candidate_inline_limit"], (NSInteger)20);
        XCTAssertEqual([FSHFixtureDefaults integerForKey:@"candidate_more_limit"], (NSInteger)500);

        for (NSString *layout in @[@"standard", @"standard_spacious", @"original",
                                     @"original_no_number", @"standard_label_top"]) {
            [FSHFixtureDefaults setObject:layout forKey:@"keyboard_layout"];
            XCTAssertEqualObjects([FSHIsolatedSettings keyboardLayout], layout);
            [FSHIsolatedSettings setKeyboardLayout:layout];
            XCTAssertEqualObjects([FSHFixtureDefaults stringForKey:@"keyboard_layout"], layout);
        }
        for (id malformed in @[@"unknown", @"", @42, @[], @{}]) {
            [FSHFixtureDefaults setObject:malformed forKey:@"keyboard_layout"];
            XCTAssertEqualObjects([FSHIsolatedSettings keyboardLayout], @"standard");
            [FSHIsolatedSettings setKeyboardLayout:malformed];
            XCTAssertEqualObjects([FSHFixtureDefaults stringForKey:@"keyboard_layout"], @"standard");
        }
    } @finally {
        [suiteDefaults removePersistentDomainForName:suite];
        FSHFixtureDefaults = nil;
    }
}

- (void)testLegacySettingsMigrationCopiesOnlyKnownPersistentValuesOnce {
    NSString *suffix = [[NSUUID UUID] UUIDString];
    NSString *legacyName = [@"freeshiamy.migration.legacy." stringByAppendingString:suffix];
    NSString *sharedName = [@"freeshiamy.migration.shared." stringByAppendingString:suffix];
    NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:legacyName];
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:sharedName];
    @try {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
        [shared registerDefaults:@{@"keyboard_height_percent": @100, @"show_number_row": @YES}];
        NSDictionary *source = @{
            @"keyboard_height_percent": @144,
            @"keyboard_layout": @"standard_label_top",
            @"show_number_row": @NO,
            @"keyboard_label_top": @NO,
            @"keyboard_left_shift": @NO,
            @"candidate_inline_limit": @12,
            @"candidate_more_limit": @350,
            @"show_shortest_code_hint": @NO,
            @"disable_ime_in_sensitive_fields": @NO,
            @"sensitive_field_include_no_personalized_learning": @YES,
            @"unrelated_key": @"leave behind",
        };
        [legacy setPersistentDomain:source forName:legacyName];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        NSDictionary *migrated = [shared persistentDomainForName:sharedName];
        XCTAssertEqual(migrated.count, (NSUInteger)10);
        XCTAssertEqualObjects(migrated[@"keyboard_height_percent"], @144);
        XCTAssertEqualObjects(migrated[@"keyboard_layout"], @"standard");
        XCTAssertEqualObjects(migrated[@"keyboard_label_top"], @NO,
                              @"An explicit source companion flag is preserved");
        XCTAssertEqualObjects(migrated[@"show_number_row"], @NO);
        XCTAssertNil(migrated[@"unrelated_key"]);
        XCTAssertEqualObjects([legacy persistentDomainForName:legacyName], source);
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        XCTAssertEqualObjects([shared persistentDomainForName:sharedName], migrated);
    } @finally {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
    }
}

- (void)testLegacySettingsMigrationPreservesDestinationEvenWhenMalformed {
    NSString *suffix = [[NSUUID UUID] UUIDString];
    NSString *legacyName = [@"freeshiamy.migration.legacy." stringByAppendingString:suffix];
    NSString *sharedName = [@"freeshiamy.migration.shared." stringByAppendingString:suffix];
    NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:legacyName];
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:sharedName];
    @try {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
        [legacy setPersistentDomain:@{@"keyboard_layout": @"original_no_number",
                                      @"show_number_row": @YES,
                                      @"keyboard_height_percent": @180,
                                      @"candidate_inline_limit": @12,
                                      @"candidate_more_limit": @350}
                         forName:legacyName];
        [shared setPersistentDomain:@{@"keyboard_layout": @"standard_spacious",
                                      @"show_number_row": @YES,
                                      @"candidate_inline_limit": @"broken",
                                      @"unrelated_key": @7}
                         forName:sharedName];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        NSDictionary *migrated = [shared persistentDomainForName:sharedName];
        XCTAssertEqualObjects(migrated[@"keyboard_layout"], @"standard_spacious");
        XCTAssertEqualObjects(migrated[@"show_number_row"], @YES);
        XCTAssertEqualObjects(migrated[@"candidate_inline_limit"], @"broken");
        XCTAssertEqualObjects(migrated[@"keyboard_height_percent"], @180);
        XCTAssertEqualObjects(migrated[@"candidate_more_limit"], @350);
        XCTAssertEqualObjects(migrated[@"unrelated_key"], @7);
        FSHFixtureDefaults = shared;
        XCTAssertEqual([FSHIsolatedSettings candidateInlineLimit], (NSInteger)10);
    } @finally {
        FSHFixtureDefaults = nil;
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
    }
}

- (void)testLegacyOriginalNoNumberMigrationDoesNotOverwriteExistingCompanionFlag {
    NSString *suffix = [[NSUUID UUID] UUIDString];
    NSString *legacyName = [@"freeshiamy.migration.legacy." stringByAppendingString:suffix];
    NSString *sharedName = [@"freeshiamy.migration.shared." stringByAppendingString:suffix];
    NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:legacyName];
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:sharedName];
    @try {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
        [legacy setPersistentDomain:@{@"keyboard_layout": @"original_no_number"}
                         forName:legacyName];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        XCTAssertEqualObjects([shared objectForKey:@"keyboard_layout"], @"original");
        XCTAssertEqualObjects([shared objectForKey:@"show_number_row"], @NO);

        [shared removePersistentDomainForName:sharedName];
        [shared setObject:@YES forKey:@"show_number_row"];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        XCTAssertEqualObjects([shared objectForKey:@"keyboard_layout"], @"original");
        XCTAssertEqualObjects([shared objectForKey:@"show_number_row"], @YES);

        [shared removePersistentDomainForName:sharedName];
        [legacy setPersistentDomain:@{@"keyboard_layout": @"original_no_number", @"show_number_row": @YES}
                         forName:legacyName];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        XCTAssertEqualObjects([shared objectForKey:@"keyboard_layout"], @"original");
        XCTAssertEqualObjects([shared objectForKey:@"show_number_row"], @YES,
                              @"Explicit source companion wins over implied legacy setting");
    } @finally {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
    }
}

- (void)testMigrationSkipsMalformedSourceAndLeavesDestinationLegacyFlagsForReadOnlyResolution {
    NSString *suffix = [[NSUUID UUID] UUIDString];
    NSString *legacyName = [@"freeshiamy.migration.legacy." stringByAppendingString:suffix];
    NSString *sharedName = [@"freeshiamy.migration.shared." stringByAppendingString:suffix];
    NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:legacyName];
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:sharedName];
    @try {
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
        [legacy setPersistentDomain:@{@"keyboard_layout": @"unknown",
                                      @"keyboard_height_percent": @"250",
                                      @"candidate_inline_limit": @12.5,
                                      @"candidate_more_limit": @999,
                                      @"show_number_row": @"false",
                                      @"keyboard_label_top": @[],
                                      @"disable_ime_in_sensitive_fields": @2,
                                      @"keyboard_left_shift": @NO,
                                      @"unknown_key": @"unmigrated"}
                         forName:legacyName];
        [shared registerDefaults:@{@"show_number_row": @YES, @"keyboard_left_shift": @YES}];
        [FSHSettings migrateLegacySettingsFromDefaults:legacy suiteName:legacyName
                                            toDefaults:shared suiteName:sharedName];
        NSDictionary *migrated = [shared persistentDomainForName:sharedName];
        XCTAssertEqual(migrated.count, (NSUInteger)2);
        XCTAssertEqualObjects(migrated[@"candidate_more_limit"], @999);
        XCTAssertEqualObjects(migrated[@"keyboard_left_shift"], @NO);
        XCTAssertNil(migrated[@"show_number_row"]);
        XCTAssertNil(migrated[@"unknown_key"]);
        FSHFixtureDefaults = shared;
        FSHFixtureSuiteName = sharedName;
        XCTAssertEqual([FSHIsolatedSettings candidateMoreLimit], (NSInteger)500);
        XCTAssertTrue([FSHIsolatedSettings showNumberRow]);
        XCTAssertTrue([FSHIsolatedSettings disableImeInSensitiveFields]);
        [shared setPersistentDomain:@{@"keyboard_layout": @"original_no_number",
                                      @"show_number_row": @YES,
                                      @"disable_ime_in_sensitive_fields": @"invalid"}
                         forName:sharedName];
        XCTAssertTrue([FSHIsolatedSettings effectiveShowNumberRow],
                      @"Explicit destination companion wins over legacy layout");
        XCTAssertTrue([FSHIsolatedSettings disableImeInSensitiveFields],
                      @"Malformed destination boolean uses its documented default");
        [shared removeObjectForKey:@"show_number_row"];
        XCTAssertFalse([FSHIsolatedSettings effectiveShowNumberRow],
                       @"Legacy layout implies no number row only when flag is absent");
        [shared setPersistentDomain:@{@"keyboard_layout": @"standard_label_top",
                                      @"keyboard_label_top": @NO}
                         forName:sharedName];
        XCTAssertFalse([FSHIsolatedSettings effectiveKeyboardLabelTop]);
        [shared removeObjectForKey:@"keyboard_label_top"];
        XCTAssertTrue([FSHIsolatedSettings effectiveKeyboardLabelTop]);
    } @finally {
        FSHFixtureDefaults = nil;
        FSHFixtureSuiteName = nil;
        [legacy removePersistentDomainForName:legacyName];
        [shared removePersistentDomainForName:sharedName];
    }
}

- (void)testExtensionSettingsRefreshDoesNotPersistValues {
    NSUserDefaults *shared = [FSHSettings sharedDefaults];
    NSString *suiteName = @"group.osku.me.freeshiamy_ios";
    NSDictionary *original = [shared persistentDomainForName:suiteName];
    @try {
        for (NSString *legacyLayout in @[@"standard_label_top", @"original_no_number"]) {
            [shared setPersistentDomain:@{@"keyboard_layout": legacyLayout} forName:suiteName];
            NSDictionary *before = [shared persistentDomainForName:suiteName];
            [self.controller applySettings];
            [self.controller applySettings];
            (void)[FSHSettings keyboardLayout];
            (void)[FSHSettings effectiveShowNumberRow];
            (void)[FSHSettings effectiveKeyboardLabelTop];
            NSDictionary *after = [shared persistentDomainForName:suiteName];
            XCTAssertEqualObjects(after, before, @"Extension read path persisted settings for %@", legacyLayout);
        }
    } @finally {
        if (original) {
            [shared setPersistentDomain:original forName:suiteName];
        } else {
            [shared removePersistentDomainForName:suiteName];
        }
    }
}

- (void)testChangingLegacyLayoutRefreshesImpliedSettingsControls {
    NSString *suiteName = @"group.osku.me.freeshiamy_ios";
    NSUserDefaults *shared = [FSHSettings sharedDefaults];
    NSDictionary *original = [shared persistentDomainForName:suiteName];
    @try {
        [shared setPersistentDomain:@{@"keyboard_layout": @"original_no_number"} forName:suiteName];
        SettingsViewController *settings = [[SettingsViewController alloc] init];
        [settings loadViewIfNeeded];
        [settings refreshUI];
        UISwitch *numberRow = [settings valueForKey:@"numberRowSwitch"];
        UISegmentedControl *segment = [settings valueForKey:@"layoutSegment"];
        XCTAssertFalse(numberRow.isOn);
        segment.selectedSegmentIndex = 0;
        [settings layoutChanged:segment];
        XCTAssertTrue(numberRow.isOn, @"Switch should refresh when implied legacy value no longer applies");

        [shared setPersistentDomain:@{@"keyboard_layout": @"standard_label_top"} forName:suiteName];
        [settings refreshUI];
        UISwitch *labelTop = [settings valueForKey:@"labelTopSwitch"];
        XCTAssertTrue(labelTop.isOn);
        segment.selectedSegmentIndex = 1;
        [settings layoutChanged:segment];
        XCTAssertFalse(labelTop.isOn, @"Switch should refresh after leaving legacy label-top layout");
    } @finally {
        if (original) {
            [shared setPersistentDomain:original forName:suiteName];
        } else {
            [shared removePersistentDomainForName:suiteName];
        }
    }
}

- (void)testKeyboardConfigurationAppliesOneSnapshotAndCancelsHeldDelete {
    FSHCountingKeyboardView *keyboard = [[FSHCountingKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 375, 216)];
    keyboard.mode = FSHKeyboardModeEmoji;
    keyboard.reloadCount = 0;
    keyboard.shiftOn = YES;
    keyboard.capsLockOn = YES;
    [keyboard applyLayout:FSHKeyboardLayoutStandardSpacious showNumberRow:NO showsGlobe:YES
                labelTop:YES leftShift:NO];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)1);
    XCTAssertEqual(keyboard.layout, FSHKeyboardLayoutStandardSpacious);
    XCTAssertFalse(keyboard.showNumberRow);
    XCTAssertTrue(keyboard.showsGlobe);
    XCTAssertTrue(keyboard.labelTop);
    XCTAssertFalse(keyboard.leftShift);
    XCTAssertEqual(keyboard.mode, FSHKeyboardModeEmoji);
    XCTAssertTrue(keyboard.shiftOn);
    XCTAssertTrue(keyboard.capsLockOn);

    [keyboard applyLayout:FSHKeyboardLayoutStandardSpacious showNumberRow:NO showsGlobe:YES
                labelTop:YES leftShift:NO];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)1);
    [keyboard applyLayout:FSHKeyboardLayoutStandardSpacious showNumberRow:NO showsGlobe:YES
                labelTop:YES leftShift:YES];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)1);
    XCTAssertTrue(keyboard.leftShift);

    [keyboard applyLayout:FSHKeyboardLayoutStandardLabelTop showNumberRow:NO showsGlobe:YES
                labelTop:NO leftShift:YES];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)2);
    XCTAssertEqual(keyboard.layout, FSHKeyboardLayoutStandard);
    XCTAssertTrue(keyboard.labelTop);
    [keyboard applyLayout:FSHKeyboardLayoutStandardLabelTop showNumberRow:NO showsGlobe:YES
                labelTop:NO leftShift:YES];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)2);
    XCTAssertEqual(keyboard.mode, FSHKeyboardModeEmoji);

    FSHKeyButton *delete = [keyboard valueForKey:@"deleteButton"];
    [delete sendActionsForControlEvents:UIControlEventTouchDown];
    XCTAssertTrue([[keyboard valueForKey:@"deleteIsPressed"] boolValue]);
    [keyboard applyLayout:FSHKeyboardLayoutOriginal showNumberRow:YES showsGlobe:YES
                labelTop:NO leftShift:NO];
    XCTAssertEqual(keyboard.reloadCount, (NSUInteger)3);
    XCTAssertFalse([[keyboard valueForKey:@"deleteIsPressed"] boolValue]);
    XCTAssertEqual(keyboard.mode, FSHKeyboardModeEmoji);
    XCTAssertTrue(keyboard.shiftOn);
    XCTAssertTrue(keyboard.capsLockOn);
}

- (FSHKeyButton *)keyWithOutput:(NSString *)output inKeyboard:(FSHKeyboardView *)keyboard {
    for (NSArray<FSHKeyButton *> *row in [keyboard valueForKey:@"rowButtons"]) {
        for (FSHKeyButton *button in row) {
            if ([button.output isEqualToString:output]) {
                return button;
            }
        }
    }
    return nil;
}

- (void)testQAZDeletePreferenceShiftsAllThreeLettersAndKeepsDeleteReachable {
    for (NSNumber *width in @[@320, @375, @393, @768]) {
        for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious)]) {
            for (NSNumber *numbers in @[@NO, @YES]) {
                for (NSNumber *globe in @[@NO, @YES]) {
                    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc]
                        initWithFrame:CGRectMake(0, 0, width.doubleValue, 220)];
                    keyboard.layout = layout.integerValue;
                    keyboard.showNumberRow = numbers.boolValue;
                    keyboard.showsGlobe = globe.boolValue;
                    keyboard.leftShift = NO;
                    [keyboard layoutIfNeeded];
                    FSHKeyButton *q = [self keyWithOutput:@"q" inKeyboard:keyboard];
                    FSHKeyButton *a = [self keyWithOutput:@"a" inKeyboard:keyboard];
                    FSHKeyButton *z = [self keyWithOutput:@"z" inKeyboard:keyboard];
                    FSHKeyButton *delete = [keyboard valueForKey:@"deleteButton"];
                    FSHKeyButton *shift = [keyboard valueForKey:@"shiftButton"];
                    FSHKeyButton *number = [self keyWithOutput:@"1" inKeyboard:keyboard];
                    XCTAssertNotNil(q);
                    XCTAssertNotNil(a);
                    XCTAssertNotNil(z);
                    XCTAssertNotNil(delete);
                    XCTAssertNotNil(shift);
                    if (numbers.boolValue) {
                        XCTAssertNotNil(number);
                    }
                    NSArray<NSArray<FSHKeyButton *> *> *rows = [keyboard valueForKey:@"rowButtons"];
                    NSMutableArray<NSValue *> *bottomFrames = [NSMutableArray array];
                    for (FSHKeyButton *button in rows.lastObject) {
                        [bottomFrames addObject:[NSValue valueWithCGRect:button.frame]];
                    }
                    void (^assertValidGeometry)(void) = ^{
                        for (NSArray<FSHKeyButton *> *row in rows) {
                            CGFloat previousRight = 0;
                            for (FSHKeyButton *button in row) {
                                XCTAssertTrue(isfinite(CGRectGetMinX(button.frame)));
                                XCTAssertTrue(isfinite(CGRectGetWidth(button.frame)));
                                XCTAssertGreaterThan(CGRectGetWidth(button.frame), 0);
                                XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.frame), previousRight - 0.5);
                                XCTAssertLessThanOrEqual(CGRectGetMaxX(button.frame), width.doubleValue + 0.5);
                                previousRight = CGRectGetMaxX(button.frame);
                            }
                        }
                    };
                    assertValidGeometry();
                    CGRect qBefore = q.frame, aBefore = a.frame, zBefore = z.frame;
                    CGRect deleteBefore = delete.frame, numberBefore = number.frame;
                    keyboard.leftShift = YES;
                    [keyboard layoutIfNeeded];
                    XCTAssertEqualWithAccuracy(CGRectGetMinX(qBefore) - CGRectGetMinX(q.frame),
                                               CGRectGetWidth(qBefore) * 0.5, 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetMinX(aBefore) - CGRectGetMinX(a.frame),
                                               CGRectGetWidth(aBefore) * 0.5, 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetMinX(zBefore) - CGRectGetMinX(z.frame),
                                               CGRectGetWidth(zBefore) * 0.5, 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetWidth(q.frame), CGRectGetWidth(qBefore), 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetWidth(a.frame), CGRectGetWidth(aBefore), 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetWidth(z.frame), CGRectGetWidth(zBefore), 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetWidth(delete.frame) - CGRectGetWidth(deleteBefore),
                                               CGRectGetWidth(aBefore) * 0.5, 0.5);
                    XCTAssertEqualWithAccuracy(CGRectGetMaxX(delete.frame), CGRectGetMaxX(deleteBefore), 0.5);
                    if (numbers.boolValue) {
                        XCTAssertTrue(CGRectEqualToRect(numberBefore, number.frame));
                    }
                    NSUInteger bottomIndex = 0;
                    for (FSHKeyButton *button in rows.lastObject) {
                        XCTAssertTrue(CGRectEqualToRect(button.frame, bottomFrames[bottomIndex++].CGRectValue));
                    }
                    assertValidGeometry();
                }
            }
        }
    }
}

- (void)testQAZDeletePreferenceLeavesOriginalAndNonLetterModesUnchanged {
    NSArray<NSDictionary<NSString *, NSNumber *> *> *cases = @[
        @{@"layout": @(FSHKeyboardLayoutOriginal), @"mode": @(FSHKeyboardModeLetters)},
        @{@"layout": @(FSHKeyboardLayoutOriginalNoNumber), @"mode": @(FSHKeyboardModeLetters)},
        @{@"layout": @(FSHKeyboardLayoutStandard), @"mode": @(FSHKeyboardModeSymbols)},
        @{@"layout": @(FSHKeyboardLayoutStandard), @"mode": @(FSHKeyboardModeSymbolsShift)},
        @{@"layout": @(FSHKeyboardLayoutStandard), @"mode": @(FSHKeyboardModeEmoji)},
    ];
    for (NSDictionary<NSString *, NSNumber *> *testCase in cases) {
        FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 220)];
        keyboard.layout = testCase[@"layout"].integerValue;
        keyboard.mode = testCase[@"mode"].integerValue;
        keyboard.leftShift = NO;
        [keyboard layoutIfNeeded];
        NSArray<NSArray<FSHKeyButton *> *> *rows = [keyboard valueForKey:@"rowButtons"];
        NSMutableArray<NSValue *> *frames = [NSMutableArray array];
        for (NSArray<FSHKeyButton *> *row in rows) {
            for (FSHKeyButton *button in row) {
                [frames addObject:[NSValue valueWithCGRect:button.frame]];
            }
        }
        keyboard.leftShift = YES;
        [keyboard layoutIfNeeded];
        NSUInteger index = 0;
        for (NSArray<FSHKeyButton *> *row in rows) {
            for (FSHKeyButton *button in row) {
                XCTAssertTrue(CGRectEqualToRect(button.frame, frames[index++].CGRectValue),
                              @"Unexpected movement in %@", testCase);
            }
        }
    }
}

- (void)testNarrowKeyboardHitMapAssignsEachGapToOneNeighbor {
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
            for (NSNumber *leftShift in @[@NO, @YES]) {
                for (NSNumber *globe in @[@NO, @YES]) {
                    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 220)];
                    keyboard.layout = layout.integerValue;
                    keyboard.mode = mode.integerValue;
                    keyboard.leftShift = leftShift.boolValue;
                    keyboard.showsGlobe = globe.boolValue;
                    [keyboard layoutIfNeeded];
                    FSHKeyButton *delete = [keyboard valueForKey:@"deleteButton"];
                    FSHKeyButton *enter = [keyboard valueForKey:@"enterButton"];
                    XCTAssertNotNil(delete);
                    XCTAssertNotNil(enter);
                    NSArray<NSArray<FSHKeyButton *> *> *rows = [keyboard valueForKey:@"rowButtons"];
                    NSMutableArray<NSValue *> *hitRects = [NSMutableArray array];
                    for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
                        NSArray<FSHKeyButton *> *row = rows[rowIndex];
                        CGFloat midY = CGRectGetMidY(row.firstObject.frame);
                        XCTAssertEqual([keyboard hitTest:CGPointMake(0.5, midY) withEvent:nil], row.firstObject);
                        XCTAssertEqual([keyboard hitTest:CGPointMake(319.5, midY) withEvent:nil], row.lastObject);
                        for (NSUInteger index = 0; index < row.count; index++) {
                            FSHKeyButton *button = row[index];
                            UIEdgeInsets outsets = button.hitAreaOutsets;
                            CGRect hit = CGRectMake(CGRectGetMinX(button.frame) - outsets.left,
                                                    CGRectGetMinY(button.frame) - outsets.top,
                                                    CGRectGetWidth(button.frame) + outsets.left + outsets.right,
                                                    CGRectGetHeight(button.frame) + outsets.top + outsets.bottom);
                            [hitRects addObject:[NSValue valueWithCGRect:hit]];
                            XCTAssertGreaterThan(CGRectGetWidth(hit), 0);
                            XCTAssertGreaterThan(CGRectGetHeight(hit), 0);
                            XCTAssertGreaterThanOrEqual(CGRectGetMinX(hit), -0.5);
                            XCTAssertLessThanOrEqual(CGRectGetMaxX(hit), 320.5);
                            XCTAssertEqual([keyboard hitTest:CGPointMake(CGRectGetMidX(button.frame), midY) withEvent:nil], button);
                            if (index + 1 < row.count) {
                                FSHKeyButton *next = row[index + 1];
                                CGFloat gap = CGRectGetMinX(next.frame) - CGRectGetMaxX(button.frame);
                                if (gap > 0.4) {
                                    CGFloat boundary = CGRectGetMaxX(button.frame) + gap * 0.5;
                                    XCTAssertEqual([keyboard hitTest:CGPointMake(boundary - 0.05, midY) withEvent:nil], button);
                                    XCTAssertEqual([keyboard hitTest:CGPointMake(boundary + 0.05, midY) withEvent:nil], next);
                                    UIView *owner = [keyboard hitTest:CGPointMake(boundary, midY) withEvent:nil];
                                    XCTAssertTrue(owner == button || owner == next,
                                                  @"Gap midpoint %.17g layout %@ mode %@ row %lu key %lu owner %@ left %@ right %@",
                                                  boundary, layout, mode, (unsigned long)rowIndex, (unsigned long)index,
                                                  owner, NSStringFromCGRect(button.frame), NSStringFromCGRect(next.frame));
                                    if ([owner isKindOfClass:FSHKeyButton.class]) {
                                        CGPoint localPoint = [keyboard convertPoint:CGPointMake(boundary, midY) toView:owner];
                                        XCTAssertTrue([(FSHKeyButton *)owner pointInside:localPoint withEvent:nil],
                                                      @"Hit owner must also accept tracking at shared edge");
                                    }
                                }
                            }
                        }
                        if (rowIndex + 1 < rows.count) {
                            NSArray<FSHKeyButton *> *nextRow = rows[rowIndex + 1];
                            CGFloat gap = CGRectGetMinY(nextRow.firstObject.frame) - CGRectGetMaxY(row.firstObject.frame);
                            if (gap > 0.4) {
                                CGFloat boundary = CGRectGetMaxY(row.firstObject.frame) + gap * 0.5;
                                UIView *upper = [keyboard hitTest:CGPointMake(160, boundary - 0.05) withEvent:nil];
                                UIView *lower = [keyboard hitTest:CGPointMake(160, boundary + 0.05) withEvent:nil];
                                XCTAssertTrue([row containsObject:upper],
                                              @"Upper row midpoint y %.17g layout %@ mode %@ owner %@", boundary, layout, mode, upper);
                                XCTAssertTrue([nextRow containsObject:lower],
                                              @"Lower row midpoint y %.17g layout %@ mode %@ owner %@", boundary, layout, mode, lower);
                                if ([upper isKindOfClass:FSHKeyButton.class]) {
                                    XCTAssertTrue([(FSHKeyButton *)upper pointInside:
                                        [keyboard convertPoint:CGPointMake(160, boundary - 0.05) toView:upper] withEvent:nil]);
                                }
                                if ([lower isKindOfClass:FSHKeyButton.class]) {
                                    XCTAssertTrue([(FSHKeyButton *)lower pointInside:
                                        [keyboard convertPoint:CGPointMake(160, boundary + 0.05) toView:lower] withEvent:nil]);
                                }
                            }
                        }
                    }
                    for (NSUInteger i = 0; i < hitRects.count; i++) {
                        for (NSUInteger j = i + 1; j < hitRects.count; j++) {
                            CGRect overlap = CGRectIntersection(hitRects[i].CGRectValue, hitRects[j].CGRectValue);
                            XCTAssertFalse(CGRectGetWidth(overlap) > 0.01 && CGRectGetHeight(overlap) > 0.01,
                                           @"Hit areas overlap in mode %@ layout %@ at %@ and %@", mode, layout,
                                           hitRects[i], hitRects[j]);
                        }
                    }
                    XCTAssertNil([keyboard hitTest:CGPointMake(-0.1, 110) withEvent:nil]);
                    XCTAssertNil([keyboard hitTest:CGPointMake(320.1, 110) withEvent:nil]);
                    CGPoint center = CGPointMake(CGRectGetMidX(delete.frame), CGRectGetMidY(delete.frame));
                    delete.hidden = YES;
                    XCTAssertNotEqual([keyboard hitTest:center withEvent:nil], delete);
                    delete.hidden = NO;
                    delete.userInteractionEnabled = NO;
                    XCTAssertNotEqual([keyboard hitTest:center withEvent:nil], delete);
                }
            }
        }
    }
}

- (void)testHiddenKeyboardKeyDoesNotDonateItsHitRegionToNeighbors {
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 220)];
    [keyboard layoutIfNeeded];
    FSHKeyButton *q = [self keyWithOutput:@"q" inKeyboard:keyboard];
    XCTAssertNotNil(q);
    CGPoint center = q.center;
    XCTAssertEqual([keyboard hitTest:center withEvent:nil], q);
    q.hidden = YES;
    XCTAssertEqual([keyboard hitTest:center withEvent:nil], keyboard);
    q.hidden = NO;
    q.userInteractionEnabled = NO;
    XCTAssertEqual([keyboard hitTest:center withEvent:nil], keyboard);
}

- (void)testFractionalHitEdgesAndAdjacentRepresentablePointsHaveTrackingOwners {
    for (NSNumber *width in @[@320, @375, @393]) {
        for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                                  @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
            for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                    @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
                FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, width.doubleValue, 220)];
                keyboard.layout = layout.integerValue;
                keyboard.mode = mode.integerValue;
                [keyboard layoutIfNeeded];
                NSArray<NSArray<FSHKeyButton *> *> *rows = [keyboard valueForKey:@"rowButtons"];
                for (NSArray<FSHKeyButton *> *row in rows) {
                    CGFloat y = CGRectGetMidY(row.firstObject.frame);
                    for (NSUInteger index = 0; index + 1 < row.count; index++) {
                        FSHKeyButton *left = row[index];
                        FSHKeyButton *right = row[index + 1];
                        CGFloat gap = CGRectGetMinX(right.frame) - CGRectGetMaxX(left.frame);
                        if (gap <= 0.4) { continue; }
                        CGFloat edge = CGRectGetMaxX(left.frame) + gap * 0.5;
                        for (NSNumber *x in @[@(nextafter(edge, -INFINITY)), @(edge), @(nextafter(edge, INFINITY))]) {
                            CGPoint point = CGPointMake(x.doubleValue, y);
                            UIView *owner = [keyboard hitTest:point withEvent:nil];
                            XCTAssertTrue(owner == left || owner == right,
                                          @"Missing near-edge owner at x %.17g width %@ layout %@ mode %@ left %@ right %@",
                                          point.x, width, layout, mode, NSStringFromCGRect(left.frame), NSStringFromCGRect(right.frame));
                            if ([owner isKindOfClass:FSHKeyButton.class]) {
                                XCTAssertTrue([(FSHKeyButton *)owner pointInside:[keyboard convertPoint:point toView:owner]
                                                                      withEvent:nil], @"Hit owner must also track near-edge touch");
                            }
                        }
                    }
                }
                for (NSUInteger index = 0; index + 1 < rows.count; index++) {
                    NSArray<FSHKeyButton *> *upper = rows[index];
                    NSArray<FSHKeyButton *> *lower = rows[index + 1];
                    CGFloat edge = CGRectGetMaxY(upper.firstObject.frame) +
                        (CGRectGetMinY(lower.firstObject.frame) - CGRectGetMaxY(upper.firstObject.frame)) * 0.5;
                    for (NSNumber *y in @[@(nextafter(edge, -INFINITY)), @(edge), @(nextafter(edge, INFINITY))]) {
                        CGPoint point = CGPointMake(width.doubleValue * 0.5, y.doubleValue);
                        UIView *owner = [keyboard hitTest:point withEvent:nil];
                        XCTAssertTrue([upper containsObject:owner] || [lower containsObject:owner],
                                      @"Missing near-row owner at y %.17g width %@ layout %@ mode %@",
                                      point.y, width, layout, mode);
                        if ([owner isKindOfClass:FSHKeyButton.class]) {
                            XCTAssertTrue([(FSHKeyButton *)owner pointInside:[keyboard convertPoint:point toView:owner]
                                                                  withEvent:nil], @"Hit owner must also track near-row touch");
                        }
                    }
                }
            }
        }
    }
}

- (void)testStableIdentifiersForInstalledKeyboardSmoke {
    XCTAssertEqualObjects(self.keyboard.accessibilityIdentifier, @"smoke.keyboard");
    self.keyboard.mode = FSHKeyboardModeLetters;
    self.keyboard.showsGlobe = YES;
    XCTAssertEqualObjects([self keyWithOutput:@"c" inKeyboard:self.keyboard].accessibilityIdentifier, @"key.letter.c");
    XCTAssertEqualObjects([self keyWithOutput:@"i" inKeyboard:self.keyboard].accessibilityIdentifier, @"key.letter.i");
    XCTAssertEqualObjects([self keyWithOutput:@"1" inKeyboard:self.keyboard].accessibilityIdentifier, @"key.digit.1");
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"deleteButton"] accessibilityIdentifier], @"key.delete");
    FSHKeyButton *globe = nil;
    for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
        for (FSHKeyButton *button in row) {
            if (button.keyCode == FSHKeyCodeGlobe) {
                globe = button;
            }
        }
    }
    XCTAssertEqualObjects(globe.accessibilityIdentifier, @"key.globe");

    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0, 0, 320, 37.5)];
    [bar updateRawBuffer:@"ci" candidates:[self candidatesWithCount:2 code:@"ci"]
             exactCount:2 inlineLimit:10 moreLimit:50 hintText:nil];
    XCTAssertEqualObjects([[bar valueForKey:@"rawButton"] accessibilityIdentifier], @"candidate.raw");
    UIStackView *stack = [bar valueForKey:@"candidateStack"];
    XCTAssertEqualObjects(stack.arrangedSubviews.firstObject.accessibilityIdentifier, @"candidate.inline.0");

    ViewController *host = [[ViewController alloc] init];
    [host loadViewIfNeeded];
    XCTAssertEqualObjects([[host valueForKey:@"singleLineField"] accessibilityIdentifier], @"smoke.singleLine");
    XCTAssertEqualObjects([[host valueForKey:@"multiLineView"] accessibilityIdentifier], @"smoke.multiLine");
}

- (void)testShiftStatesHaveDistinctLabelsAndKeepLetterGeometry {
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 375, 216)];
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        keyboard.layout = layout.integerValue;
        keyboard.mode = FSHKeyboardModeLetters;
        keyboard.shiftOn = NO;
        keyboard.capsLockOn = NO;
        [keyboard layoutIfNeeded];
        FSHKeyButton *shift = [keyboard valueForKey:@"shiftButton"];
        FSHKeyButton *q = [self keyWithOutput:@"q" inKeyboard:keyboard];
        FSHKeyButton *a = [self keyWithOutput:@"a" inKeyboard:keyboard];
        FSHKeyButton *z = [self keyWithOutput:@"z" inKeyboard:keyboard];
        XCTAssertNotNil(shift);
        XCTAssertNotNil(q);
        XCTAssertNotNil(a);
        XCTAssertNotNil(z);
        CGRect qFrame = q.frame, aFrame = a.frame, zFrame = z.frame;
        XCTAssertEqualObjects([q titleForState:UIControlStateNormal], @"q");
        XCTAssertEqualObjects([a titleForState:UIControlStateNormal], @"a");
        XCTAssertEqualObjects([z titleForState:UIControlStateNormal], @"z");
        XCTAssertEqualObjects([shift titleForState:UIControlStateNormal], @"⇧");
        XCTAssertEqualObjects(shift.accessibilityValue, @"關閉");
        XCTAssertFalse((shift.accessibilityTraits & UIAccessibilityTraitSelected) != 0);

        keyboard.shiftOn = YES;
        [keyboard layoutIfNeeded];
        XCTAssertEqualObjects([q titleForState:UIControlStateNormal], @"Q");
        XCTAssertEqualObjects([a titleForState:UIControlStateNormal], @"A");
        XCTAssertEqualObjects([z titleForState:UIControlStateNormal], @"Z");
        XCTAssertEqualObjects(shift.accessibilityValue, @"下一個字母");
        XCTAssertTrue((shift.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
        XCTAssertTrue(CGRectEqualToRect(q.frame, qFrame), @"Q moved in layout %@: %@ → %@", layout,
                      NSStringFromCGRect(qFrame), NSStringFromCGRect(q.frame));
        XCTAssertTrue(CGRectEqualToRect(a.frame, aFrame), @"A moved in layout %@: %@ → %@", layout,
                      NSStringFromCGRect(aFrame), NSStringFromCGRect(a.frame));
        XCTAssertTrue(CGRectEqualToRect(z.frame, zFrame), @"Z moved in layout %@: %@ → %@", layout,
                      NSStringFromCGRect(zFrame), NSStringFromCGRect(z.frame));

        keyboard.shiftOn = NO;
        keyboard.capsLockOn = YES;
        [keyboard layoutIfNeeded];
        XCTAssertEqualObjects([shift titleForState:UIControlStateNormal], @"⇪");
        XCTAssertEqualObjects(shift.accessibilityLabel, @"大寫鎖定");
        XCTAssertEqualObjects(shift.accessibilityValue, @"已鎖定");
        XCTAssertTrue((shift.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
        XCTAssertEqualObjects([q titleForState:UIControlStateNormal], @"Q");
        XCTAssertTrue(CGRectEqualToRect(q.frame, qFrame));
        XCTAssertTrue(CGRectEqualToRect(a.frame, aFrame));
        XCTAssertTrue(CGRectEqualToRect(z.frame, zFrame));

        keyboard.mode = FSHKeyboardModeSymbols;
        shift = [keyboard valueForKey:@"shiftButton"];
        XCTAssertEqualObjects([shift titleForState:UIControlStateNormal], @"#+=");
        XCTAssertEqualObjects(shift.accessibilityValue, @"第一頁");
        XCTAssertFalse((shift.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
        keyboard.mode = FSHKeyboardModeSymbolsShift;
        shift = [keyboard valueForKey:@"shiftButton"];
        XCTAssertEqualObjects([shift titleForState:UIControlStateNormal], @"123");
        XCTAssertEqualObjects(shift.accessibilityValue, @"第二頁");
        XCTAssertTrue((shift.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
        keyboard.mode = FSHKeyboardModeLetters;
        shift = [keyboard valueForKey:@"shiftButton"];
        XCTAssertEqualObjects([shift titleForState:UIControlStateNormal], @"⇪");
        XCTAssertEqualObjects([self keyWithOutput:@"q" inKeyboard:keyboard].currentTitle, @"Q");
    }
}

- (void)testSingleShiftExpiresAfterOneLetterWhileCapsLockPersists {
    self.keyboard.mode = FSHKeyboardModeLetters;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects(self.proxy.text, @"A");
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"shiftButton"] accessibilityValue], @"關閉");

    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn); // Typing a letter cleared the double-tap window.
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.capsLockOn);
    XCTAssertFalse(self.keyboard.shiftOn);
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"b"];
    XCTAssertEqualObjects(self.proxy.text, @"AB");
    XCTAssertTrue(self.keyboard.capsLockOn);

    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeModeChange output:nil];
    XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeSymbols);
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"shiftButton"] accessibilityValue], @"第一頁");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeSymbolsShift);
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"shiftButton"] accessibilityValue], @"第二頁");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeModeChange output:nil];
    XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeLetters);
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"shiftButton"] accessibilityValue], @"已鎖定");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertFalse(self.keyboard.capsLockOn);
    XCTAssertEqualObjects([[self.keyboard valueForKey:@"shiftButton"] accessibilityValue], @"關閉");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn); // Unlocking Caps cleared the double-tap window.
    XCTAssertFalse(self.keyboard.capsLockOn);
}

- (void)testReadyEnginePunctuationDoesNotConsumeOneShotShift {
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    for (NSString *punctuation in @[@",", @"'", @"[", @"]"]) {
        [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:punctuation];
        XCTAssertTrue(self.keyboard.shiftOn, @"One-shot shift was consumed by %@", punctuation);
    }
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertEqualObjects([self rawBuffer], @",'[]A");
}

- (void)testCandidateBarActionBreaksShiftDoubleTapSequence {
    [[self rawBuffer] setString:@"a"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarViewDidTapRawBuffer:bar];
    XCTAssertEqualObjects(self.proxy.text, @"a");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
}

- (void)testDeletePressBreaksShiftDoubleTapSequence {
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertNil([self.controller valueForKey:@"lastShiftTapDate"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
}

- (void)testSystemGlobeEventBreaksShiftDoubleTapSequence {
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
    [self.controller keyboardView:self.keyboard didReceiveInputModeEvent:nil fromView:self.keyboard];
    XCTAssertNil([self.controller valueForKey:@"lastShiftTapDate"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
}

- (void)testMoreToggleBreaksShiftDoubleTapSequence {
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarView:bar didToggleExpanded:YES];
    XCTAssertNil([self.controller valueForKey:@"lastShiftTapDate"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertFalse(self.keyboard.shiftOn);
    XCTAssertFalse(self.keyboard.capsLockOn);
}

- (void)testTapDeletesRawBufferExactlyOnce {
    [self.proxy.text setString:@"host"];
    [[self rawBuffer] setString:@"ab"];
    [self tapDelete];
    XCTAssertEqualObjects([self rawBuffer], @"a");
    XCTAssertEqualObjects(self.proxy.text, @"host");
}

- (void)testRepeatNeverCrossesFromRawBufferIntoHost {
    [self.proxy.text setString:@"host"];
    [[self rawBuffer] setString:@"a"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self waitForSeconds:0.75];
    XCTAssertEqualObjects([self rawBuffer], @"");
    XCTAssertEqualObjects(self.proxy.text, @"host");
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self waitForSeconds:0.2];
    XCTAssertEqualObjects(self.proxy.text, @"host");
}

- (void)testCancelAndDragExitStopRepeat {
    for (NSNumber *event in @[@(UIControlEventTouchCancel), @(UIControlEventTouchDragExit)]) {
        [self.proxy.text setString:@"abc"];
        [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
        [self.deleteButton sendActionsForControlEvents:event.unsignedIntegerValue];
        [self waitForSeconds:0.55];
        XCTAssertEqualObjects(self.proxy.text, @"ab");
    }
}

- (void)testRepeatStopsWhenHostDocumentChanges {
    [self.proxy.text setString:@"abc"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    self.proxy.documentIdentifier = [NSUUID UUID];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
    XCTAssertNil([self.controller valueForKey:@"deleteRepeatTimer"]);
}

- (void)testEquivalentDocumentUUIDKeepsRepeatActive {
    [self.proxy.text setString:@"abcdef"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    self.proxy.documentIdentifier = [[NSUUID alloc] initWithUUIDString:self.proxy.documentIdentifier.UUIDString];
    [self waitForSeconds:0.55];
    XCTAssertLessThan(self.proxy.text.length, (NSUInteger)5);
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)testMissingDocumentIdentifierRemainsStableUntilItChanges {
    self.proxy.documentIdentifier = nil;
    [self.proxy.text setString:@"abcdef"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self waitForSeconds:0.55];
    XCTAssertLessThan(self.proxy.text.length, (NSUInteger)5);
    self.proxy.documentIdentifier = [NSUUID UUID];
    NSUInteger lengthAtChange = self.proxy.text.length;
    [self waitForSeconds:0.25];
    XCTAssertEqual(self.proxy.text.length, lengthAtChange);
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)testHoldActuallyRepeatsAfterInitialDelay {
    [self.proxy.text setString:@"abcdef"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    XCTAssertEqualObjects(self.proxy.text, @"abcde");
    [self waitForSeconds:0.66];
    XCTAssertLessThan(self.proxy.text.length, (NSUInteger)5);
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)testDeleteRemovesWholeComposedCharacter {
    for (NSString *raw in @[@"a😀", @"a☹️", @"aé", @"a👨‍👩‍👧‍👦"]) {
        [[self rawBuffer] setString:raw];
        [self tapDelete];
        XCTAssertEqualObjects([self rawBuffer], @"a", @"Failed for %@", raw);
    }
}

- (void)testEmojiPageDeleteHandlesGraphemesAndStopsHeldPress {
    for (NSNumber *globe in @[@NO, @YES]) {
        self.controller.fakeNeedsInputModeSwitchKey = globe.boolValue;
        [self.controller refreshInputModeSwitchKey];
        self.keyboard.mode = FSHKeyboardModeEmoji;
        FSHKeyButton *emojiDelete = [self.keyboard valueForKey:@"deleteButton"];
        XCTAssertNotNil(emojiDelete);
        XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeEmoji);

        [self.proxy.text setString:@"a👨‍👩‍👧‍👦"];
        [emojiDelete sendActionsForControlEvents:UIControlEventTouchDown];
        [emojiDelete sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertEqualObjects(self.proxy.text, @"a");
        XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeEmoji);

        [self.proxy.text setString:@"abc"];
        XCTAssertTrue([emojiDelete accessibilityActivate]);
        XCTAssertEqualObjects(self.proxy.text, @"ab");

        [self.proxy.text setString:@"abcdef"];
        [emojiDelete sendActionsForControlEvents:UIControlEventTouchDown];
        [self waitForSeconds:0.55];
        XCTAssertLessThan(self.proxy.text.length, (NSUInteger)5);
        [emojiDelete sendActionsForControlEvents:UIControlEventTouchCancel];
        NSString *afterCancel = [self.proxy.text copy];
        [self waitForSeconds:0.25];
        XCTAssertEqualObjects(self.proxy.text, afterCancel);

        FSHKeyboardView *geometryKeyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 216.0)];
        geometryKeyboard.showsGlobe = globe.boolValue;
        geometryKeyboard.mode = FSHKeyboardModeEmoji;
        for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                                  @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
            geometryKeyboard.layout = layout.integerValue;
            for (NSNumber *width in @[@320.0, @375.0, @393.0, @768.0]) {
                geometryKeyboard.frame = CGRectMake(0.0, 0.0, width.doubleValue, 216.0);
                [geometryKeyboard setNeedsLayout];
                [geometryKeyboard layoutIfNeeded];
                XCTAssertEqualWithAccuracy(CGRectGetWidth(geometryKeyboard.bounds), width.doubleValue, 0.5,
                                           @"Standalone keyboard fixture bounds: %@", NSStringFromCGRect(geometryKeyboard.bounds));
                FSHKeyButton *laidOutDelete = [geometryKeyboard valueForKey:@"deleteButton"];
                XCTAssertNotNil(laidOutDelete);
                XCTAssertGreaterThanOrEqual(laidOutDelete.frame.size.width, 25.0, @"Layout %@ width %@ globe %@",
                                            layout, width, globe);
                XCTAssertGreaterThanOrEqual(CGRectGetMinX(laidOutDelete.frame), -0.5);
                XCTAssertLessThanOrEqual(CGRectGetMaxX(laidOutDelete.frame), width.doubleValue + 0.5);
            }
        }
    }
}

- (void)testSystemGlobeAppearsOnlyWhenNeededAndForwardsEveryTouchEvent {
    for (NSNumber *needed in @[@YES, @NO]) {
        self.controller.fakeNeedsInputModeSwitchKey = needed.boolValue;
        [self.controller viewWillAppear:NO];
        XCTAssertEqual(self.keyboard.showsGlobe, needed.boolValue);
        for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                                  @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber),
                                  @(FSHKeyboardLayoutStandardLabelTop)]) {
            self.keyboard.layout = layout.integerValue;
            for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                    @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
                self.keyboard.mode = mode.integerValue;
                NSMutableArray<FSHKeyButton *> *globes = [NSMutableArray array];
                for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
                    for (FSHKeyButton *button in row) {
                        if (button.keyCode == FSHKeyCodeGlobe) {
                            [globes addObject:button];
                        }
                    }
                }
                XCTAssertEqual(globes.count, needed.boolValue ? (NSUInteger)1 : (NSUInteger)0,
                               @"layout %@ mode %@ needed %@", layout, mode, needed);
                if (needed.boolValue && globes.count == 1) {
                    FSHKeyButton *globe = globes.firstObject;
                    XCTAssertEqualObjects(globe.accessibilityLabel, @"切換鍵盤");
                    NSArray<NSString *> *downActions = [globe actionsForTarget:self.keyboard forControlEvent:UIControlEventTouchDown];
                    NSArray<NSString *> *upActions = [globe actionsForTarget:self.keyboard forControlEvent:UIControlEventTouchUpInside];
                    NSString *systemAction = NSStringFromSelector(@selector(handleGlobeEvent:forEvent:));
                    XCTAssertTrue([downActions containsObject:systemAction]);
                    XCTAssertTrue([upActions containsObject:systemAction]);
                    XCTAssertFalse([upActions containsObject:NSStringFromSelector(@selector(handleKeyPress:))]);
                }
            }
        }

        FSHKeyButton *sameModeButton = [self.keyboard valueForKey:@"modeButton"];
        [self.controller viewDidLayoutSubviews];
        XCTAssertEqual([self.keyboard valueForKey:@"modeButton"], sameModeButton);
        if (needed.boolValue) {
            FSHKeyButton *globe = nil;
            for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
                for (FSHKeyButton *button in row) {
                    if (button.keyCode == FSHKeyCodeGlobe) {
                        globe = button;
                    }
                }
            }
            XCTAssertNotNil(globe);
            NSUInteger eventBefore = self.controller.inputModeEventCount;
            NSUInteger advancesBefore = self.controller.inputModeAdvanceCount;
            [globe sendActionsForControlEvents:UIControlEventTouchDown];
            XCTAssertEqual(self.controller.inputModeEventCount, eventBefore + 1);
            XCTAssertEqual(self.controller.lastInputModeEventView, globe);
            XCTAssertNil(self.controller.lastInputModeEvent);
            [globe sendActionsForControlEvents:UIControlEventTouchUpInside];
            XCTAssertEqual(self.controller.inputModeEventCount, eventBefore + 2);
            XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBefore);
            XCTAssertTrue([globe accessibilityActivate]);
            XCTAssertEqual(self.controller.inputModeEventCount, eventBefore + 2);
            XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBefore + 1);
        }
    }
}

- (void)testModeAndHideKeysExposeVisibleAlternateActionsWithoutClipping {
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 194.4)];
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        keyboard.layout = layout.integerValue;
        for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
            keyboard.mode = mode.integerValue;
            for (NSNumber *showsGlobe in @[@NO, @YES]) {
                keyboard.showsGlobe = showsGlobe.boolValue;
                [keyboard layoutIfNeeded];
                FSHKeyButton *modeButton = [keyboard valueForKey:@"modeButton"];
                FSHKeyButton *hideButton = nil;
                for (NSArray<FSHKeyButton *> *row in [keyboard valueForKey:@"rowButtons"]) {
                    for (FSHKeyButton *button in row) {
                        if (button.keyCode == FSHKeyCodeCancel) {
                            hideButton = button;
                        }
                    }
                }
                XCTAssertNotNil(modeButton);
                XCTAssertNotNil(hideButton);
                XCTAssertEqualObjects(modeButton.alternateHint, @"🙂");
                XCTAssertEqualObjects(hideButton.alternateHint, @"⚙︎");
                XCTAssertEqualObjects([hideButton titleForState:UIControlStateNormal], @"⌄");
                XCTAssertEqualObjects(hideButton.accessibilityLabel, @"收起鍵盤");
                XCTAssertEqual(modeButton.accessibilityCustomActions.count, (NSUInteger)1);
                XCTAssertEqual(hideButton.accessibilityCustomActions.count, (NSUInteger)1);
                XCTAssertEqualObjects(modeButton.accessibilityCustomActions.firstObject.name, @"切換至表情符號鍵盤");
                XCTAssertEqualObjects(hideButton.accessibilityCustomActions.firstObject.name, @"顯示設定位置");
                for (FSHKeyButton *button in @[modeButton, hideButton]) {
                    UILabel *hint = [button valueForKey:@"alternateHintLabel"];
                    XCTAssertNotNil(hint);
                    XCTAssertFalse(CGRectIsEmpty(hint.frame));
                    XCTAssertFalse(CGRectIsEmpty(button.titleLabel.frame));
                    XCTAssertFalse(CGRectIntersectsRect(button.titleLabel.frame, hint.frame),
                                   @"Primary/hint overlap: layout %@ mode %@ globe %@ key %@ title %@ hint %@",
                                   layout, mode, showsGlobe, button.accessibilityIdentifier,
                                   NSStringFromCGRect(button.titleLabel.frame), NSStringFromCGRect(hint.frame));
                    XCTAssertGreaterThanOrEqual(CGRectGetMinX(hint.frame), 0.0);
                    XCTAssertLessThanOrEqual(CGRectGetMaxX(hint.frame), CGRectGetWidth(button.bounds) + 0.5);
                    XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.titleLabel.frame), -0.5);
                    XCTAssertGreaterThanOrEqual(CGRectGetMinY(button.titleLabel.frame), -0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxX(button.titleLabel.frame), CGRectGetWidth(button.bounds) + 0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxY(button.titleLabel.frame), CGRectGetHeight(button.bounds) + 0.5);
                    NSMutableArray<UILongPressGestureRecognizer *> *appLongPresses = [NSMutableArray array];
                    for (UIGestureRecognizer *recognizer in button.gestureRecognizers) {
                        if ([recognizer isKindOfClass:UILongPressGestureRecognizer.class] &&
                            fabs(((UILongPressGestureRecognizer *)recognizer).minimumPressDuration - 0.4) < 0.001) {
                            [appLongPresses addObject:(UILongPressGestureRecognizer *)recognizer];
                        }
                    }
                    XCTAssertEqual(appLongPresses.count, (NSUInteger)1, @"Expected the app's 0.4-second alternate-action recognizer");
                    XCTAssertTrue(appLongPresses.firstObject.cancelsTouchesInView);
                }
            }
        }
    }
}

- (void)testAccessibleSettingsInstructionPreservesCompositionAndCandidates {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle mainBundle] error:&error], @"%@", error);
    [self.controller setValue:engine forKey:@"engine"];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [[self rawBuffer] setString:@"a"];
    [self.controller refreshCandidatesAndUI];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    NSArray<FSHCandidate *> *before = [self.controller valueForKey:@"candidates"];
    XCTAssertGreaterThan(before.count, (NSUInteger)10);
    BOOL wasExpanded = bar.isExpanded;
    XCTAssertFalse(wasExpanded);

    FSHKeyButton *hide = nil;
    for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
        for (FSHKeyButton *button in row) {
            if (button.keyCode == FSHKeyCodeCancel) {
                hide = button;
            }
        }
    }
    XCTAssertNotNil(hide);
    UIAccessibilityCustomAction *settings = hide.accessibilityCustomActions.firstObject;
    XCTAssertTrue(settings.actionHandler(settings));
    UIButton *banner = [self.controller valueForKey:@"settingsHelpBanner"];
    XCTAssertFalse(banner.hidden);
    XCTAssertTrue(bar.accessibilityElementsHidden);
    XCTAssertEqualObjects(banner.accessibilityIdentifier, @"settingsHelpBanner");
    XCTAssertTrue([banner.accessibilityLabel containsString:@"FreeShiamy App"]);
    XCTAssertEqualObjects([self rawBuffer], @"a");
    XCTAssertEqual([self.controller valueForKey:@"candidates"], before);
    XCTAssertEqual(bar.isExpanded, wasExpanded);
    XCTAssertEqualObjects(self.proxy.text, @"");
    XCTAssertEqual(self.controller.dismissCount, (NSUInteger)0);

    [banner sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(banner.hidden);
    XCTAssertFalse(bar.accessibilityElementsHidden);
    XCTAssertEqualObjects([self rawBuffer], @"a");
    [bar setExpanded:YES];
    XCTAssertTrue(bar.isExpanded);
    XCTAssertTrue(settings.actionHandler(settings));
    XCTAssertFalse(banner.hidden);
    XCTAssertTrue(bar.accessibilityElementsHidden);
    XCTAssertTrue(bar.isExpanded);
    XCTAssertEqual([self.controller valueForKey:@"candidates"], before);
    [self.controller candidateBarViewDidTapRawBuffer:bar];
    XCTAssertTrue(banner.hidden);
    XCTAssertFalse(bar.accessibilityElementsHidden);
    XCTAssertEqualObjects(self.proxy.text, @"a");
    XCTAssertEqualObjects([self rawBuffer], @"");

    self.proxy.documentIdentifier = nil;
    XCTAssertTrue(settings.actionHandler(settings));
    XCTAssertFalse(banner.hidden);
    [self.controller textDidChange:nil];
    XCTAssertFalse(banner.hidden); // Two unknown document IDs are still equal.
    self.proxy.documentIdentifier = [NSUUID UUID];
    [self.controller textDidChange:nil];
    XCTAssertTrue(banner.hidden);
    XCTAssertFalse(bar.accessibilityElementsHidden);
    XCTAssertTrue(settings.actionHandler(settings));
    [self.controller beginAppearanceTransition:NO animated:NO];
    [self.controller endAppearanceTransition];
    XCTAssertTrue(banner.hidden);
    XCTAssertFalse(bar.accessibilityElementsHidden);
}

- (void)testAccessibleModeAlternateChangesToEmojiOnce {
    FSHKeyButton *mode = [self.keyboard valueForKey:@"modeButton"];
    UIAccessibilityCustomAction *emoji = mode.accessibilityCustomActions.firstObject;
    XCTAssertNotNil(emoji);
    XCTAssertTrue(emoji.actionHandler(emoji));
    XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeEmoji);
    XCTAssertEqualObjects(self.proxy.text, @"");
    XCTAssertEqual(self.controller.dismissCount, (NSUInteger)0);
}

- (void)testLetterPunctuationExposesBracketRootsWithoutChangingPrimaryKeys {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle mainBundle] error:&error], @"%@", error);
    [self.controller setValue:engine forKey:@"engine"];
    [self.controller setValue:@1 forKey:@"engineLoadState"];

    for (NSString *root in @[@"[", @"]"]) {
        NSUInteger exactCount = 0;
        NSArray<FSHCandidate *> *matches = [engine prefixCandidatesForCode:root exactCount:&exactCount];
        XCTAssertEqual(exactCount, (NSUInteger)8, @"Root %@", root);
        XCTAssertGreaterThan(matches.count, exactCount);
        NSString *doubled = [root stringByAppendingString:root];
        XCTAssertGreaterThan([engine prefixCandidatesForCode:doubled exactCount:NULL].count, (NSUInteger)0);
    }
    XCTAssertEqualObjects([engine prefixCandidatesForCode:@"[f" exactCount:NULL].firstObject.value, @"【");
    XCTAssertEqualObjects([engine prefixCandidatesForCode:@"]f" exactCount:NULL].firstObject.value, @"】");

    self.keyboard.mode = FSHKeyboardModeLetters;
    for (NSString *punctuation in @[@",", @"."]) {
        NSString *root = [punctuation isEqualToString:@","] ? @"[" : @"]";
        FSHKeyButton *button = [self keyWithOutput:punctuation inKeyboard:self.keyboard];
        XCTAssertNotNil(button);
        XCTAssertEqualObjects(button.alternateHint, root);
        XCTAssertEqualObjects(button.accessibilityIdentifier,
                              [root isEqualToString:@"["] ? @"key.root.open" : @"key.root.close");
        XCTAssertEqual(button.accessibilityCustomActions.count, (NSUInteger)1);
        [[self rawBuffer] setString:@""];
        [self.controller refreshCandidatesAndUI];
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertEqualObjects([self rawBuffer], punctuation, @"Primary punctuation remains a code key");
        [[self rawBuffer] setString:@""];
        [self.controller refreshCandidatesAndUI];
        UIAccessibilityCustomAction *alternate = button.accessibilityCustomActions.firstObject;
        XCTAssertTrue(alternate.actionHandler(alternate));
        XCTAssertEqualObjects([self rawBuffer], root);
        XCTAssertEqualObjects(self.proxy.text, @"");
        XCTAssertEqual([[self.controller valueForKey:@"exactCount"] unsignedIntegerValue], (NSUInteger)8);
    }

    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeShift output:nil];
    XCTAssertTrue(self.keyboard.shiftOn);
    FSHKeyButton *shiftedComma = [self keyWithOutput:@"," inKeyboard:self.keyboard];
    [[self rawBuffer] setString:@""];
    [self.controller refreshCandidatesAndUI];
    UIAccessibilityCustomAction *shiftedAlternate = shiftedComma.accessibilityCustomActions.firstObject;
    XCTAssertTrue(shiftedAlternate.actionHandler(shiftedAlternate));
    XCTAssertEqualObjects([self rawBuffer], @"[");
    XCTAssertTrue(self.keyboard.shiftOn, @"Bracket roots must not consume one-shot Shift");

    for (NSString *punctuation in @[@",", @"."]) {
        FSHKeyButton *button = [self keyWithOutput:punctuation inKeyboard:self.keyboard];
        FSHStatefulLongPress *press = [[FSHStatefulLongPress alloc] init];
        [button addGestureRecognizer:press];
        [[self rawBuffer] setString:@""];
        [self.controller refreshCandidatesAndUI];
        for (NSNumber *state in @[@(UIGestureRecognizerStateBegan), @(UIGestureRecognizerStateChanged),
                                 @(UIGestureRecognizerStateEnded), @(UIGestureRecognizerStateCancelled)]) {
            press.simulatedState = state.integerValue;
            [self.keyboard handleBracketLongPress:press];
        }
        XCTAssertEqualObjects([self rawBuffer],
                              [punctuation isEqualToString:@","] ? @"[" : @"]",
                              @"One long press must append exactly one bracket without primary punctuation");
        [button removeGestureRecognizer:press];
    }

    self.keyboard.mode = FSHKeyboardModeSymbols;
    [[self rawBuffer] setString:@""];
    [self.proxy.text setString:@""];
    [self.controller refreshCandidatesAndUI];
    for (NSString *bracket in @[@"[", @"]"]) {
        FSHKeyButton *button = [self keyWithOutput:bracket inKeyboard:self.keyboard];
        XCTAssertNotNil(button);
        XCTAssertNil(button.alternateHint);
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        XCTAssertEqualObjects([self rawBuffer], @"");
    }
    XCTAssertEqualObjects(self.proxy.text, @"[]");
}

- (void)testBracketRootHintsFitAllLetterLayoutsWithoutNarrowingKeys {
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 216)];
    keyboard.mode = FSHKeyboardModeLetters;
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        keyboard.layout = layout.integerValue;
        for (NSNumber *labelTop in @[@NO, @YES]) {
            keyboard.labelTop = labelTop.boolValue;
            for (NSNumber *numbers in @[@NO, @YES]) {
                keyboard.showNumberRow = numbers.boolValue;
                for (NSNumber *globe in @[@NO, @YES]) {
                    keyboard.showsGlobe = globe.boolValue;
                    for (NSNumber *width in @[@320, @375, @768, @1024]) {
                        keyboard.frame = CGRectMake(0, 0, width.doubleValue, 216);
                        [keyboard setNeedsLayout];
                        [keyboard layoutIfNeeded];
                        FSHKeyButton *z = [self keyWithOutput:@"z" inKeyboard:keyboard];
                        XCTAssertNotNil(z);
                        for (NSString *punctuation in @[@",", @"."]) {
                            FSHKeyButton *button = [self keyWithOutput:punctuation inKeyboard:keyboard];
                            XCTAssertNotNil(button);
                            XCTAssertTrue(isfinite(CGRectGetWidth(button.frame)));
                            XCTAssertEqualWithAccuracy(CGRectGetWidth(button.frame), CGRectGetWidth(z.frame), 0.5,
                                                       @"Punctuation keeps same-weight Z-row geometry");
                            XCTAssertGreaterThan(CGRectGetWidth(button.frame), 0.0);
                            XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.frame), -0.5);
                            XCTAssertLessThanOrEqual(CGRectGetMaxX(button.frame), CGRectGetWidth(keyboard.bounds) + 0.5);
                            XCTAssertFalse(CGRectIsEmpty(button.titleLabel.frame));
                            UILabel *hint = [button valueForKey:@"alternateHintLabel"];
                            XCTAssertFalse(CGRectIsEmpty(hint.frame));
                            NSUInteger appLongPresses = 0;
                            for (UIGestureRecognizer *recognizer in button.gestureRecognizers) {
                                if ([recognizer isKindOfClass:UILongPressGestureRecognizer.class] &&
                                    fabs(((UILongPressGestureRecognizer *)recognizer).minimumPressDuration - 0.4) < 0.001) {
                                    appLongPresses++;
                                    XCTAssertTrue(recognizer.cancelsTouchesInView);
                                }
                            }
                            XCTAssertEqual(appLongPresses, (NSUInteger)1);
                            XCTAssertFalse(CGRectIntersectsRect(button.titleLabel.frame, hint.frame),
                                           @"Primary/hint overlap at width %@ layout %@ labelTop %@", width, layout, labelTop);
                            XCTAssertLessThanOrEqual(CGRectGetMaxX(hint.frame), CGRectGetWidth(button.bounds) + 0.5);
                        }
                    }
                }
            }
        }
    }
}

- (void)testReturnKeyLabelsFollowHostTraitsInEveryModeWithoutLabelOnlyRebuild {
    FSHCountingKeyboardView *keyboard = [[FSHCountingKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 194.4)];
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        keyboard.layout = layout.integerValue;
        for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
            keyboard.mode = mode.integerValue;
            FSHKeyButton *enter = [keyboard valueForKey:@"enterButton"];
            XCTAssertNotNil(enter);
            NSUInteger reloads = keyboard.reloadCount;
            keyboard.returnKeyType = UIReturnKeySearch;
            XCTAssertEqualObjects(enter.currentTitle, @"搜尋");
            XCTAssertEqualObjects(enter.accessibilityLabel, @"搜尋");
            keyboard.returnKeyType = UIReturnKeyNext;
            XCTAssertEqualObjects(enter.currentTitle, @"⇥");
            XCTAssertEqualObjects(enter.accessibilityLabel, @"下一個欄位");
            XCTAssertEqual([keyboard valueForKey:@"enterButton"], enter);
            XCTAssertEqual(keyboard.reloadCount, reloads);
        }
    }
    NSArray<NSDictionary<NSString *, id> *> *cases = @[
        @{@"type": @(UIReturnKeyDefault), @"title": @"換行", @"label": @"換行"},
        @{@"type": @(UIReturnKeyGo), @"title": @"前往", @"label": @"前往"},
        @{@"type": @(UIReturnKeyJoin), @"title": @"加入", @"label": @"加入"},
        @{@"type": @(UIReturnKeyRoute), @"title": @"路線", @"label": @"路線"},
        @{@"type": @(UIReturnKeySearch), @"title": @"搜尋", @"label": @"搜尋"},
        @{@"type": @(UIReturnKeySend), @"title": @"傳送", @"label": @"傳送"},
        @{@"type": @(UIReturnKeyDone), @"title": @"完成", @"label": @"完成"},
        @{@"type": @(UIReturnKeyContinue), @"title": @"繼續", @"label": @"繼續"},
        @{@"type": @(UIReturnKeyEmergencyCall), @"title": @"緊急", @"label": @"緊急通話"},
        @{@"type": @(UIReturnKeyGoogle), @"title": @"搜尋", @"label": @"Google 搜尋"},
        @{@"type": @(UIReturnKeyYahoo), @"title": @"搜尋", @"label": @"Yahoo 搜尋"},
        @{@"type": @(UIReturnKeyNext), @"title": @"⇥", @"label": @"下一個欄位"},
        @{@"type": @999, @"title": @"換行", @"label": @"換行"},
    ];
    FSHKeyButton *enter = [keyboard valueForKey:@"enterButton"];
    NSUInteger reloads = keyboard.reloadCount;
    for (NSDictionary<NSString *, id> *testCase in cases) {
        keyboard.returnKeyType = [testCase[@"type"] integerValue];
        XCTAssertEqualObjects(enter.currentTitle, testCase[@"title"]);
        XCTAssertEqualObjects(enter.accessibilityLabel, testCase[@"label"]);
        XCTAssertEqual(keyboard.reloadCount, reloads);
    }

    FSHKeyButton *controllerEnter = [self.keyboard valueForKey:@"enterButton"];
    self.proxy.returnKeyType = UIReturnKeySend;
    [self.controller textDidChange:nil];
    XCTAssertEqual([self.keyboard valueForKey:@"enterButton"], controllerEnter);
    XCTAssertEqualObjects(controllerEnter.currentTitle, @"傳送");
    self.proxy.returnKeyType = UIReturnKeyNext;
    [self.controller viewDidLayoutSubviews];
    XCTAssertEqual([self.keyboard valueForKey:@"enterButton"], controllerEnter);
    XCTAssertEqualObjects(controllerEnter.currentTitle, @"⇥");
}

- (void)testReturnCommitsCompositionThenForwardsExactlyOneNewlineWithoutDismissing {
    NSArray<NSNumber *> *types = @[@(UIReturnKeyDefault), @(UIReturnKeyGo), @(UIReturnKeyJoin),
                                 @(UIReturnKeyRoute), @(UIReturnKeySearch), @(UIReturnKeySend),
                                 @(UIReturnKeyDone), @(UIReturnKeyContinue), @(UIReturnKeyEmergencyCall),
                                 @(UIReturnKeyGoogle), @(UIReturnKeyYahoo), @(UIReturnKeyNext), @999];
    for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                            @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
        self.keyboard.mode = mode.integerValue;
        for (NSNumber *type in types) {
            [self.proxy.text setString:@""];
            self.proxy.returnKeyType = type.integerValue;
            [self.controller textDidChange:nil];
            NSUInteger dismisses = self.controller.dismissCount;
            [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeEnter output:nil];
            XCTAssertEqualObjects(self.proxy.text, @"\n", @"Mode %@ return type %@", mode, type);
            XCTAssertEqual(self.controller.dismissCount, dismisses);
        }
    }

    self.keyboard.mode = FSHKeyboardModeLetters;
    self.proxy.returnKeyType = UIReturnKeyNext;
    [self.proxy.text setString:@""];
    [[self rawBuffer] setString:@"abc"];
    NSUInteger dismisses = self.controller.dismissCount;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeEnter output:nil];
    XCTAssertEqualObjects(self.proxy.text, @"abc");
    XCTAssertEqualObjects([self rawBuffer], @"");
    XCTAssertEqual(self.controller.dismissCount, dismisses);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeEnter output:nil];
    XCTAssertEqualObjects(self.proxy.text, @"abc\n");
    XCTAssertEqual(self.controller.dismissCount, dismisses);
}

- (void)testBothSymbolPagesRetainUniqueSymbolsAndAddMissingPunctuation {
    NSMutableSet<NSString *> *allOutputs = [NSMutableSet set];
    for (NSNumber *mode in @[@(FSHKeyboardModeSymbols), @(FSHKeyboardModeSymbolsShift)]) {
        self.keyboard.mode = mode.integerValue;
        NSArray<NSArray<FSHKeyButton *> *> *rows = [self.keyboard valueForKey:@"rowButtons"];
        for (NSArray<FSHKeyButton *> *row in rows) {
            for (FSHKeyButton *button in row) {
                if (button.output.length > 0) {
                    [allOutputs addObject:button.output];
                }
            }
        }
    }
    NSArray<NSString *> *originalSymbols = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9",
        @"-", @"/", @":", @";", @"(", @")", @"$", @"&", @"@", @"'", @"[", @"]", @"{", @"}", @"#", @"%", @"^", @"*", @"+", @",", @".",
        @"_", @"\\", @"|", @"~", @"<", @">", @"€", @"£", @"¥", @"•", @"±", @"×", @"÷", @"…", @"=", @"°"];
    for (NSString *symbol in originalSymbols) {
        XCTAssertTrue([allOutputs containsObject:symbol], @"Lost symbol %@", symbol);
    }
    for (NSString *symbol in @[@"!", @"?", @"\"", @"`"]) {
        XCTAssertTrue([allOutputs containsObject:symbol], @"Missing direct symbol %@", symbol);
    }

    self.keyboard.mode = FSHKeyboardModeSymbolsShift;
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    NSMutableString *expected = [NSMutableString string];
    for (NSString *symbol in @[@"!", @"?", @"\"", @"`"]) {
        FSHKeyButton *key = nil;
        for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
            for (FSHKeyButton *button in row) {
                if ([button.output isEqualToString:symbol]) {
                    key = button;
                }
            }
        }
        XCTAssertNotNil(key);
        [key sendActionsForControlEvents:UIControlEventTouchUpInside];
        [expected appendString:symbol];
        XCTAssertEqualObjects(self.proxy.text, expected);
    }
    [[self rawBuffer] setString:@"ab"];
    NSString *hostBeforeComposition = [self.proxy.text copy];
    NSMutableString *expectedRaw = [@"ab" mutableCopy];
    for (NSString *symbol in @[@"!", @"?", @"\"", @"`"]) {
        FSHKeyButton *key = nil;
        for (NSArray<FSHKeyButton *> *row in [self.keyboard valueForKey:@"rowButtons"]) {
            for (FSHKeyButton *button in row) {
                if ([button.output isEqualToString:symbol]) {
                    key = button;
                }
            }
        }
        XCTAssertNotNil(key);
        [key sendActionsForControlEvents:UIControlEventTouchUpInside];
        [expectedRaw appendString:symbol];
        XCTAssertEqualObjects([self rawBuffer], expectedRaw);
        XCTAssertEqualObjects(self.proxy.text, hostBeforeComposition);
    }
}

- (void)testConstrainedKeyboardGeometryRemainsFiniteAcrossWidthsHeightsAndModes {
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectZero];
    for (NSNumber *layout in @[@(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious),
                              @(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber)]) {
        keyboard.layout = layout.integerValue;
        for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                                 @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
            keyboard.mode = mode.integerValue;
            for (NSNumber *labelTop in @[@NO, @YES]) {
              keyboard.labelTop = labelTop.boolValue;
              for (NSNumber *width in @[@0.0, @1.0, @320.0, @375.0, @393.0, @768.0, @1024.0]) {
                for (NSNumber *height in @[@0.0, @1.0, @160.0, @216.0, @253.0, @320.0]) {
                    keyboard.frame = CGRectMake(0, 0, width.doubleValue, height.doubleValue);
                    [keyboard setNeedsLayout];
                    [keyboard layoutIfNeeded];
                    for (NSArray<FSHKeyButton *> *row in [keyboard valueForKey:@"rowButtons"]) {
                        CGFloat priorRight = 0.0;
                        for (FSHKeyButton *button in row) {
                            XCTAssertTrue(isfinite(button.frame.origin.x) && isfinite(button.frame.origin.y));
                            XCTAssertTrue(isfinite(button.frame.size.width) && isfinite(button.frame.size.height));
                            XCTAssertGreaterThanOrEqual(button.frame.size.width, 0.0);
                            XCTAssertGreaterThanOrEqual(button.frame.size.height, 0.0);
                            XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.frame) + 0.5, priorRight);
                            XCTAssertLessThanOrEqual(CGRectGetMaxX(button.frame), width.doubleValue + 0.5);
                            XCTAssertLessThanOrEqual(CGRectGetMaxY(button.frame), height.doubleValue + 0.5);
                            priorRight = CGRectGetMaxX(button.frame);
                        }
                    }
                }
            }
            }
        }
    }
}

- (void)testPreferredHeightSceneCapRestoresAfterRotationWithoutChangingSetting {
    XCTAssertEqualWithAccuracy(FSHSceneKeyboardHeightLimit(390.0, 0.0, 21.0), 221.4, 0.01);
    XCTAssertEqualWithAccuracy(FSHSceneKeyboardHeightLimit(1400.0, 24.0, 20.0), 813.6, 0.01);
    FSHHeightLimitInputController *controller = [[FSHHeightLimitInputController alloc] init];
    controller.fakeProxy = [[FSHFakeDocumentProxy alloc] init];
    controller.simulatedSceneLimit = CGFLOAT_MAX;
    [controller loadViewIfNeeded];
    FSHCandidateBarView *bar = [controller valueForKey:@"candidateBar"];
    NSUserDefaults *defaults = [FSHSettings sharedDefaults];
    id storedPercent = [defaults persistentDomainForName:@"group.osku.me.freeshiamy_ios"][@"keyboard_height_percent"];
    @try {
        for (NSNumber *percent in @[@90, @100, @220]) {
            [FSHSettings setKeyboardHeightPercent:percent.integerValue];
            for (NSNumber *expanded in @[@NO, @YES]) {
                bar.expanded = expanded.boolValue;
                controller.simulatedSceneLimit = CGFLOAT_MAX;
                [controller updatePreferredContentSize];
                CGFloat desired = 216.0 * percent.doubleValue / 100.0 + bar.barHeight +
                                  (expanded.boolValue ? bar.expandedHeight : 0.0);
                XCTAssertEqualWithAccuracy(controller.preferredContentSize.height, desired, 0.5);
                controller.simulatedSceneLimit = FSHSceneKeyboardHeightLimit(390.0, 0.0, 21.0);
                [controller updatePreferredContentSize];
                XCTAssertEqualWithAccuracy(controller.preferredContentSize.height,
                                           MIN(desired, controller.simulatedSceneLimit), 0.5);
                controller.simulatedSceneLimit = FSHSceneKeyboardHeightLimit(1400.0, 24.0, 20.0);
                [controller updatePreferredContentSize];
                XCTAssertEqualWithAccuracy(controller.preferredContentSize.height, desired, 0.5);
                XCTAssertEqual([FSHSettings keyboardHeightPercent], percent.integerValue);
            }
        }
    } @finally {
        if (storedPercent) {
            [defaults setObject:storedPercent forKey:@"keyboard_height_percent"];
        } else {
            [defaults removeObjectForKey:@"keyboard_height_percent"];
        }
    }
}

- (void)testSettingsSegmentsScaleAndFitAtAccessibilitySizes {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    XCTAssertNotNil(scene);
    if (!scene) { return; }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *candidate in scene.windows) {
        if (candidate.isKeyWindow) { oldKeyWindow = candidate; break; }
    }
    UIViewController *host = [[UIViewController alloc] init];
    host.view.frame = CGRectMake(0, 0, 320, 700);
    SettingsViewController *settings = [[SettingsViewController alloc] init];
    [host addChildViewController:settings];
    settings.view.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:settings.view];
    [settings didMoveToParentViewController:host];
    [NSLayoutConstraint activateConstraints:@[
        [settings.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
        [settings.view.widthAnchor constraintEqualToConstant:320.0],
        [settings.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
        [settings.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
    ]];
    UISegmentedControl *segment = [settings valueForKey:@"layoutSegment"];
    NSInteger selection = segment.selectedSegmentIndex;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.rootViewController = host;
    [window makeKeyAndVisible];
    XCTAssertTrue([self waitForView:settings.view toAttachToWindow:window]);
    [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
              forChildViewController:settings];
    [host.view layoutIfNeeded];
    UIFont *font = [segment titleTextAttributesForState:UIControlStateNormal][NSFontAttributeName];
    XCTAssertGreaterThan(font.pointSize, 17.0);
    for (NSString *title in @[@"標準", @"間距", @"原始"]) {
        XCTAssertLessThanOrEqual([title sizeWithAttributes:@{NSFontAttributeName: font}].width,
                                 CGRectGetWidth(segment.bounds) / 3.0 - 16.0 + 0.5);
    }
    XCTAssertEqual(segment.selectedSegmentIndex, selection);
    XCTAttachment *shot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
    shot.name = @"Accessibility XXXL Settings in 320pt viewport";
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
    [window setHidden:YES];
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testHostActionTitlesWrapInAttachedAccessibilityViewport {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    XCTAssertNotNil(scene);
    if (!scene) { return; }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *candidate in scene.windows) {
        if (candidate.isKeyWindow) { oldKeyWindow = candidate; break; }
    }
    UIViewController *host = [[UIViewController alloc] init];
    ViewController *panel = [[ViewController alloc] init];
    [host addChildViewController:panel];
    panel.view.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:panel.view];
    [panel didMoveToParentViewController:host];
    [NSLayoutConstraint activateConstraints:@[
        [panel.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
        [panel.view.widthAnchor constraintEqualToConstant:320.0],
        [panel.view.topAnchor constraintEqualToAnchor:host.view.topAnchor],
        [panel.view.bottomAnchor constraintEqualToAnchor:host.view.bottomAnchor],
    ]];
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.rootViewController = host;
    [window makeKeyAndVisible];
    XCTAssertTrue([self waitForView:panel.view toAttachToWindow:window]);
    [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
              forChildViewController:panel];
    [host.view layoutIfNeeded];
    [host.view layoutIfNeeded];
    NSArray<UIButton *> *buttons = [panel valueForKey:@"actionButtons"];
    XCTAssertGreaterThan(buttons.count, (NSUInteger)0);
    for (UIButton *button in buttons) {
        CGFloat textWidth = CGRectGetWidth(button.bounds) - button.contentEdgeInsets.left - button.contentEdgeInsets.right;
        CGRect needed = [[button titleForState:UIControlStateNormal]
            boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                      attributes:@{NSFontAttributeName: button.titleLabel.font} context:nil];
        CGFloat minimum = ceil(CGRectGetHeight(needed)) + button.contentEdgeInsets.top + button.contentEdgeInsets.bottom;
        XCTAssertGreaterThanOrEqual(CGRectGetHeight(button.bounds) + 0.5, minimum,
                                    @"Action title should wrap without clipping: %@", button.currentTitle);
    }
    UIButton *longAction = nil;
    for (UIButton *button in buttons) {
        if ([[button titleForState:UIControlStateNormal] isEqualToString:@"開啟系統設定（鍵盤）"]) {
            longAction = button;
            break;
        }
    }
    XCTAssertNotNil(longAction);
    UIScrollView *scroll = (UIScrollView *)panel.view.subviews.firstObject;
    [scroll scrollRectToVisible:[longAction convertRect:longAction.bounds toView:scroll] animated:NO];
    [host.view layoutIfNeeded];
    CGRect visibleAction = [longAction convertRect:longAction.bounds toView:scroll];
    XCTAssertTrue(CGRectIntersectsRect(visibleAction, scroll.bounds));
    XCTAttachment *shot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
    shot.name = @"Accessibility XXXL host panel in 320pt viewport";
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
    [window setHidden:YES];
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testExpandedCandidateViewportUsesAssignedHeightAndPreservesScroll {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectZero];
    UIView *host = [self hostForCandidateBar:bar width:320.0 height:250.0];
    NSLayoutConstraint *height = [bar.heightAnchor constraintEqualToConstant:217.5];
    height.active = YES;
    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:80 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:80 hintText:nil];
    bar.expanded = YES;
    [host layoutIfNeeded];
    UIScrollView *more = [bar valueForKey:@"moreScrollView"];
    more.contentOffset = CGPointMake(0.0, 60.0);
    height.constant = bar.barHeight + 32.0;
    [bar applyAvailableHeight:height.constant];
    [host layoutIfNeeded];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetHeight(bar.bounds), height.constant, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetHeight(more.bounds), 32.0, 0.5);
    XCTAssertEqualWithAccuracy(more.contentOffset.y, 60.0, 0.5);
    XCTAssertTrue(bar.isExpanded);
}

- (void)testAXCompactAlternateTypographySettlesAcrossRepeatedLayouts {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    XCTAssertNotNil(scene);
    if (!scene) { return; }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *candidate in scene.windows) {
        if (candidate.isKeyWindow) { oldKeyWindow = candidate; break; }
    }
    UIViewController *host = [[UIViewController alloc] init];
    UIViewController *holder = [[UIViewController alloc] init];
    [host addChildViewController:holder];
    holder.view.frame = CGRectMake(0, 0, 320, 220);
    [host.view addSubview:holder.view];
    [holder didMoveToParentViewController:host];
    FSHKeyboardView *keyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    keyboard.mode = FSHKeyboardModeLetters;
    keyboard.showNumberRow = YES;
    [holder.view addSubview:keyboard];
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.rootViewController = host;
    [window makeKeyAndVisible];
    [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:
        UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] forChildViewController:holder];
    XCTAssertTrue([self waitForView:keyboard toAttachToWindow:window]);
    FSHKeyButton *mode = [keyboard valueForKey:@"modeButton"];
    UILabel *hint = [mode valueForKey:@"alternateHintLabel"];
    XCTAssertNotNil(mode);
    XCTAssertNotNil(hint);
    XCTAssertEqualObjects(keyboard.traitCollection.preferredContentSizeCategory,
                          UIContentSizeCategoryAccessibilityExtraExtraExtraLarge);
    for (NSNumber *height in @[@100.0, @220.0, @100.0]) {
        keyboard.frame = CGRectMake(0, 0, 320, height.doubleValue);
        NSLog(@"AdaptiveTypography checkpoint before layout height=%@", height);
        [keyboard setNeedsLayout];
        [keyboard layoutIfNeeded];
        NSLog(@"AdaptiveTypography checkpoint after layout height=%@", height);
        BOOL compact = height.doubleValue == 100.0;
        XCTAssertEqual(hint.hidden, compact);
        UIFont *settledFont = mode.titleLabel.font;
        UIEdgeInsets settledInsets = mode.contentEdgeInsets;
        UIControlContentVerticalAlignment settledAlignment = mode.contentVerticalAlignment;
        for (NSUInteger pass = 0; pass < 12; pass++) {
            [keyboard setNeedsLayout];
            [keyboard layoutIfNeeded];
            XCTAssertEqual(mode.titleLabel.font, settledFont,
                           @"Title font must not be reassigned on repeated layout pass %lu", (unsigned long)pass);
            XCTAssertTrue(UIEdgeInsetsEqualToEdgeInsets(mode.contentEdgeInsets, settledInsets));
            XCTAssertEqual(mode.contentVerticalAlignment, settledAlignment);
            XCTAssertEqual(hint.hidden, compact);
        }
    }
    [window setHidden:YES];
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testAttachedHostHeightAndDynamicTypeAdaptWithoutRebuildingComposition {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    XCTAssertNotNil(scene);
    if (!scene) { return; }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *candidate in scene.windows) {
        if (candidate.isKeyWindow) { oldKeyWindow = candidate; break; }
    }
    FSHTestInputController *controller = [[FSHTestInputController alloc] init];
    controller.fakeProxy = [[FSHFakeDocumentProxy alloc] init];
    [controller loadViewIfNeeded];
    [controller setValue:@999 forKey:@"engineLoadGeneration"];
    UIViewController *host = [[UIViewController alloc] init];
    [host addChildViewController:controller];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:controller.view];
    [controller didMoveToParentViewController:host];
    NSLayoutConstraint *width = [controller.view.widthAnchor constraintEqualToConstant:320.0];
    NSLayoutConstraint *height = [controller.view.heightAnchor constraintEqualToConstant:253.0];
    height.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [controller.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
        [controller.view.topAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.topAnchor],
        width, height,
    ]];
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.rootViewController = host;
    [window makeKeyAndVisible];
    XCTAssertTrue([self waitForView:controller.view toAttachToWindow:window]);

    FSHKeyboardView *keyboard = [controller valueForKey:@"keyboardView"];
    FSHCandidateBarView *bar = [controller valueForKey:@"candidateBar"];
    keyboard.layout = FSHKeyboardLayoutStandard;
    keyboard.showNumberRow = YES;
    FSHKeyButton *key = [self keyWithOutput:@"q" inKeyboard:keyboard];
    CGFloat defaultFont = key.titleLabel.font.pointSize;
    NSMutableString *raw = [controller valueForKey:@"rawBuffer"];
    [raw setString:@"ab"];
    FSHManyCandidatesEngine *fixture = [[FSHManyCandidatesEngine alloc] init];
    fixture.fixtureCandidates = [self candidatesWithCount:80 code:@"ab"];
    [controller setValue:fixture forKey:@"engine"];
    [controller setValue:@1 forKey:@"engineLoadState"];
    [controller setValue:@10 forKey:@"inlineLimit"];
    [controller setValue:@80 forKey:@"moreLimit"];
    [controller refreshCandidatesAndUI];
    UIButton *moreControl = [bar valueForKey:@"moreButton"];
    [moreControl sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(bar.isExpanded);
    [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
              forChildViewController:controller];
    UIScrollView *moreScroll = [bar valueForKey:@"moreScrollView"];
    for (NSNumber *rootWidth in @[@320.0, @375.0, @393.0, @768.0]) {
        width.constant = rootWidth.doubleValue;
        for (NSNumber *rootHeight in @[@160.0, @216.0, @253.0, @320.0]) {
            height.constant = rootHeight.doubleValue;
            [host.view setNeedsLayout];
            [host.view layoutIfNeeded];
            [controller.view layoutIfNeeded];
            XCTAssertEqualWithAccuracy(CGRectGetWidth(controller.view.bounds), rootWidth.doubleValue, 0.5);
            XCTAssertEqualWithAccuracy(CGRectGetHeight(controller.view.bounds), rootHeight.doubleValue, 0.5);
            XCTAssertEqualWithAccuracy(CGRectGetMaxY(keyboard.frame), rootHeight.doubleValue, 0.5);
            XCTAssertEqualWithAccuracy(CGRectGetHeight(bar.bounds) + CGRectGetHeight(keyboard.bounds),
                                       rootHeight.doubleValue, 0.5);
            UIButton *moreButton = [bar valueForKey:@"moreButton"];
            XCTAssertEqualWithAccuracy(CGRectGetWidth(moreButton.bounds), 44.0, 0.5);
            XCTAssertEqualWithAccuracy(CGRectGetHeight(moreButton.bounds), bar.barHeight, 0.5);
            XCTAssertGreaterThanOrEqual(CGRectGetHeight(moreScroll.bounds),
                                        MIN(FSHCandidateRowDesiredHeight(controller.traitCollection),
                                            MAX(0.0, rootHeight.doubleValue - bar.barHeight)) - 0.5);
            UIButton *firstCandidate = [[bar valueForKey:@"moreButtonPool"] firstObject];
            XCTAssertLessThanOrEqual(firstCandidate.titleLabel.font.lineHeight + 2.0,
                                     CGRectGetHeight(firstCandidate.bounds) + 0.5);
            CGFloat roomBelowBar = MAX(0.0, rootHeight.doubleValue - bar.barHeight);
            CGFloat keyFloor = MIN(roomBelowBar, keyboard.minimumUsableHeight);
            CGFloat ordinaryViewport = MIN(bar.expandedHeight, MAX(0.0, roomBelowBar - keyFloor));
            BOOL expectedCompact = ordinaryViewport < FSHCandidateRowDesiredHeight(controller.traitCollection);
            XCTAssertEqual(keyboard.hidden, expectedCompact);
            XCTAssertEqual(keyboard.accessibilityElementsHidden, keyboard.hidden);
            UIStackView *inlineStack = [bar valueForKey:@"candidateStack"];
            UIButton *inlineFirst = (UIButton *)inlineStack.arrangedSubviews.firstObject;
            XCTAssertEqual([inlineFirst.accessibilityHint containsString:@"數字 0"], !expectedCompact);
            XCTAssertEqual([inlineFirst.accessibilityHint containsString:@"空白鍵"], !expectedCompact);
            if (rootHeight.doubleValue == 160.0) {
                moreScroll.contentOffset = CGPointMake(0.0, 60.0);
                XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 60.0, 0.5);
            }
            if (rootWidth.doubleValue == 320.0 && rootHeight.doubleValue == 160.0) {
                NSArray<UIButton *> *moreButtons = [bar valueForKey:@"moreButtonPool"];
                UIButton *last = moreButtons.lastObject;
                XCTAssertEqual(last.tag, 79);
                CGFloat end = MAX(0.0, moreScroll.contentSize.height - CGRectGetHeight(moreScroll.bounds));
                moreScroll.contentOffset = CGPointMake(0.0, end);
                XCTAssertGreaterThan(end, 60.0);
                XCTAssertLessThanOrEqual(CGRectGetMaxY(last.frame) - moreScroll.contentOffset.y,
                                         CGRectGetHeight(moreScroll.bounds) + 0.5);
                NSPredicate *presentedCandidate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                    [host.view layoutIfNeeded];
                    [controller.view layoutIfNeeded];
                    [bar layoutIfNeeded];
                    if (last.window != window || CGRectIsEmpty(last.titleLabel.bounds)) return NO;
                    BOOL insideViewport = NO;
                    for (UIView *ancestor = last; ancestor; ancestor = ancestor.superview) {
                        if (ancestor.hidden || ancestor.alpha <= 0.01) return NO;
                        if (ancestor == moreScroll) insideViewport = YES;
                    }
                    if (!insideViewport) return NO;
                    CGRect viewport = [moreScroll convertRect:moreScroll.bounds toView:window];
                    CGRect title = [last.titleLabel convertRect:last.titleLabel.bounds toView:window];
                    if (!CGRectContainsRect(CGRectInset(viewport, -1.0, -1.0), title)) return NO;
                    UIImage *frame = [self snapshotOfWindow:window];
                    return [self titleContrastForButton:last inWindow:window image:frame] >= 0.3;
                }];
                XCTNSPredicateExpectation *candidateReady = [[XCTNSPredicateExpectation alloc]
                    initWithPredicate:presentedCandidate object:last];
                XCTWaiterResult candidateResult = [XCTWaiter waitForExpectations:@[candidateReady] timeout:5.0];
                UIImage *finalFrame = [self snapshotOfWindow:window];
                CGFloat finalContrast = [self titleContrastForButton:last inWindow:window image:finalFrame];
                XCTAttachment *shot = [XCTAttachment attachmentWithImage:finalFrame];
                shot.name = @"Accessibility XXXL compact candidate selection";
                shot.lifetime = XCTAttachmentLifetimeKeepAlways;
                [self addAttachment:shot];
                CGRect presented = [last.titleLabel convertRect:last.titleLabel.bounds toView:window];
                CGRect viewport = [moreScroll convertRect:moreScroll.bounds toView:window];
                XCTAttachment *geometry = [XCTAttachment attachmentWithString:
                    [NSString stringWithFormat:@"title=%@ viewport=%@ offset=%@ hidden=%d alpha=%g attached=%d contrast=%g",
                     NSStringFromCGRect(presented), NSStringFromCGRect(viewport),
                     NSStringFromCGPoint(moreScroll.contentOffset), last.hidden, last.alpha, last.window == window,
                     finalContrast]];
                geometry.name = @"Compact More presented-candidate geometry";
                geometry.lifetime = XCTAttachmentLifetimeKeepAlways;
                [self addAttachment:geometry];
                XCTAssertEqual(candidateResult, XCTWaiterResultCompleted,
                               @"Offscreen expanded candidate must become visibly presented after scrolling");
                XCTAssertGreaterThanOrEqual(finalContrast, 0.3,
                                           @"Offscreen candidate title must remain visible in the attached frame");
            }
            bar.expanded = NO;
            NSLog(@"AdaptiveKeyboard checkpoint before collapsed layout width=%@ height=%@", rootWidth, rootHeight);
            [host.view layoutIfNeeded];
            [controller.view layoutIfNeeded];
            NSLog(@"AdaptiveKeyboard checkpoint after collapsed layout width=%@ height=%@", rootWidth, rootHeight);
            XCTAssertFalse(keyboard.hidden);
            XCTAssertTrue([inlineFirst.accessibilityHint containsString:@"數字 0"]);
            XCTAssertTrue([inlineFirst.accessibilityHint containsString:@"空白鍵"]);
            NSUInteger visibleAlternateHints = 0;
            for (NSArray<FSHKeyButton *> *row in [keyboard valueForKey:@"rowButtons"]) {
                for (FSHKeyButton *button in row) {
                    [button layoutIfNeeded];
                    XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.titleLabel.frame), -0.5);
                    XCTAssertGreaterThanOrEqual(CGRectGetMinY(button.titleLabel.frame), -0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxX(button.titleLabel.frame), CGRectGetWidth(button.bounds) + 0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxY(button.titleLabel.frame), CGRectGetHeight(button.bounds) + 0.5);
                    UILabel *hint = [button valueForKey:@"alternateHintLabel"];
                    if (!hint || hint.hidden) { continue; }
                    visibleAlternateHints++;
                    XCTAssertLessThanOrEqual(CGRectGetMaxY(hint.frame), CGRectGetMinY(button.titleLabel.frame) + 0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxY(hint.frame), CGRectGetHeight(button.bounds) + 0.5);
                }
            }
            if (rootHeight.doubleValue >= 253.0) {
                XCTAssertGreaterThanOrEqual(visibleAlternateHints, (NSUInteger)2,
                                            @"Mode and Hide hints should reappear when rows fit");
            }
            if (rootWidth.doubleValue == 393.0 && rootHeight.doubleValue == 253.0) {
                XCTAttachment *shot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
                shot.name = @"Accessibility XXXL keyboard labels";
                shot.lifetime = XCTAttachmentLifetimeKeepAlways;
                [self addAttachment:shot];
            }
            bar.expanded = YES;
            if (rootWidth.doubleValue == 320.0 && rootHeight.doubleValue == 160.0) {
                bar.expanded = NO;
                [controller keyboardView:keyboard didBeginPressKeyCode:FSHKeyCodeDelete output:nil];
                XCTAssertTrue([[controller valueForKey:@"deletePressActive"] boolValue]);
                [moreControl sendActionsForControlEvents:UIControlEventTouchUpInside];
                [host.view layoutIfNeeded];
                XCTAssertFalse([[controller valueForKey:@"deletePressActive"] boolValue]);
                XCTAssertNil([controller valueForKey:@"deleteRepeatTimer"]);
                UIButton *commit = [[bar valueForKey:@"moreButtonPool"] firstObject];
                [commit sendActionsForControlEvents:UIControlEventTouchUpInside];
                [host.view layoutIfNeeded];
                XCTAssertEqualObjects(controller.fakeProxy.text, @"候0");
                XCTAssertFalse(bar.isExpanded);
                XCTAssertFalse(keyboard.hidden);
                XCTAssertFalse(keyboard.accessibilityElementsHidden);
                [raw setString:@"ab"];
                [controller refreshCandidatesAndUI];
                [moreControl sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }
    }
    XCTAssertEqual([self keyWithOutput:@"q" inKeyboard:keyboard], key);
    XCTAssertEqualObjects(raw, @"ab");
    XCTAssertTrue(bar.isExpanded);
    bar.expanded = NO;
    [host.view layoutIfNeeded];
    [controller.view layoutIfNeeded];
    XCTAssertGreaterThan(key.titleLabel.font.pointSize, defaultFont);
    width.constant = 320.0;
    height.constant = 160.0;
    [moreControl sendActionsForControlEvents:UIControlEventTouchUpInside];
    [host.view layoutIfNeeded];
    FSHKeyButton *compactGlobe = [bar valueForKey:@"compactGlobeButton"];
    XCTAssertTrue(compactGlobe.hidden);
    controller.fakeNeedsInputModeSwitchKey = YES;
    [controller refreshInputModeSwitchKey];
    [controller.view setNeedsLayout];
    [host.view layoutIfNeeded];
    XCTAssertFalse(compactGlobe.hidden);
    XCTAssertTrue(keyboard.hidden);
    NSUInteger beforeEvents = controller.inputModeEventCount;
    [compactGlobe sendActionsForControlEvents:UIControlEventTouchDown];
    XCTAssertEqual(controller.inputModeEventCount, beforeEvents + 1);
    XCTAssertEqual(controller.lastInputModeEventView, compactGlobe);
    NSUInteger beforeAdvance = controller.inputModeAdvanceCount;
    XCTAssertTrue([compactGlobe accessibilityActivate]);
    XCTAssertEqual(controller.inputModeAdvanceCount, beforeAdvance + 1);
    controller.fakeNeedsInputModeSwitchKey = NO;
    [controller refreshInputModeSwitchKey];
    [controller.view setNeedsLayout];
    [host.view layoutIfNeeded];
    XCTAssertTrue(compactGlobe.hidden);
    [window setHidden:YES];
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testOriginalLayoutsFillTheirAvailableHeight {
    FSHKeyboardView *geometryKeyboard = [[FSHKeyboardView alloc] initWithFrame:CGRectMake(0.0, 0.0, 375.0, 180.0)];
    for (NSNumber *mode in @[@(FSHKeyboardModeLetters), @(FSHKeyboardModeSymbols),
                            @(FSHKeyboardModeSymbolsShift), @(FSHKeyboardModeEmoji)]) {
        geometryKeyboard.mode = mode.integerValue;
        for (NSNumber *layout in @[@(FSHKeyboardLayoutOriginal), @(FSHKeyboardLayoutOriginalNoNumber),
                                  @(FSHKeyboardLayoutStandard), @(FSHKeyboardLayoutStandardSpacious)]) {
            geometryKeyboard.layout = layout.integerValue;
            CGFloat expectedGap = (layout.integerValue == FSHKeyboardLayoutOriginal ||
                                   layout.integerValue == FSHKeyboardLayoutOriginalNoNumber) ? 1.0 : 6.0;
            for (NSNumber *showNumbers in @[@NO, @YES]) {
                geometryKeyboard.showNumberRow = showNumbers.boolValue;
                for (NSNumber *height in @[@180.0, @216.0, @300.0]) {
                    geometryKeyboard.frame = CGRectMake(0.0, 0.0, 375.0, height.doubleValue);
                    [geometryKeyboard setNeedsLayout];
                    [geometryKeyboard layoutIfNeeded];
                    XCTAssertEqualWithAccuracy(CGRectGetHeight(geometryKeyboard.bounds), height.doubleValue, 0.5,
                                               @"Standalone keyboard fixture bounds: %@", NSStringFromCGRect(geometryKeyboard.bounds));
                    NSArray<NSArray<FSHKeyButton *> *> *rows = [geometryKeyboard valueForKey:@"rowButtons"];
                    XCTAssertGreaterThan(rows.count, (NSUInteger)0);
                    CGFloat previousBottom = 0.0;
                    for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
                        NSArray<FSHKeyButton *> *row = rows[rowIndex];
                        CGFloat top = CGRectGetMinY(row.firstObject.frame);
                        if (rowIndex == 0) {
                            XCTAssertEqualWithAccuracy(top, 0.0, 0.5);
                        } else {
                            XCTAssertEqualWithAccuracy(top - previousBottom, expectedGap, 0.5);
                        }
                        previousBottom = CGRectGetMaxY(row.firstObject.frame);
                    }
                    XCTAssertEqualWithAccuracy(previousBottom, height.doubleValue, 0.5,
                                               @"Mode %@ layout %@ numbers %@ height %@", mode, layout, showNumbers, height);
                }
            }
        }
    }
}

- (void)testHiddenMoreButtonGivesItsWidthBackToCandidates {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0.0, 0.0, 375.0, 37.5)];
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 375.0, bar.barHeight)];
    [host addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:host.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
    for (NSNumber *count in @[@1, @10, @11, @1]) {
        NSMutableArray<FSHCandidate *> *candidates = [NSMutableArray array];
        for (NSUInteger index = 0; index < count.unsignedIntegerValue; index++) {
            [candidates addObject:[[FSHCandidate alloc] initWithCode:@"a" value:[NSString stringWithFormat:@"候%lu", (unsigned long)index]]];
        }
        [bar updateRawBuffer:@"a" candidates:candidates exactCount:1 inlineLimit:10 moreLimit:50 hintText:nil];
        [host layoutIfNeeded];
        [bar layoutIfNeeded];
        XCTAssertEqualWithAccuracy(CGRectGetWidth(bar.bounds), 375.0, 0.5,
                                   @"Pinned candidate bar fixture bounds: %@", NSStringFromCGRect(bar.bounds));
        UIView *area = [bar valueForKey:@"candidateArea"];
        UIScrollView *scroll = [bar valueForKey:@"scrollView"];
        UIButton *more = [bar valueForKey:@"moreButton"];
        UIButton *raw = [bar valueForKey:@"rawButton"];
        NSString *geometry = [NSString stringWithFormat:@"count %@ bar %@ raw %@ area %@ scroll %@ More %@",
                              count, NSStringFromCGRect(bar.bounds), NSStringFromCGRect(raw.frame),
                              NSStringFromCGRect(area.frame), NSStringFromCGRect(scroll.frame),
                              NSStringFromCGRect(more.frame)];
        XCTAssertGreaterThan(CGRectGetWidth(raw.bounds), 0.0, @"%@", geometry);
        XCTAssertGreaterThan(CGRectGetWidth(area.bounds), 0.0, @"%@", geometry);
        XCTAssertLessThan(CGRectGetWidth(raw.bounds), 375.0 * 0.2, @"Short raw text should keep its intrinsic width: %@", geometry);
        NSLayoutConstraint *withMore = [bar valueForKey:@"scrollTrailingWithMore"];
        NSLayoutConstraint *withoutMore = [bar valueForKey:@"scrollTrailingWithoutMore"];
        XCTAssertNotEqual(withMore.active, withoutMore.active);
        XCTAssertEqual(withMore.active, !more.hidden);
        if (count.unsignedIntegerValue <= 10) {
            XCTAssertTrue(more.hidden);
            XCTAssertEqualWithAccuracy(CGRectGetMaxX(scroll.frame), CGRectGetWidth(area.bounds), 0.5, @"%@", geometry);
            XCTAssertEqualWithAccuracy(CGRectGetWidth(area.bounds) - CGRectGetWidth(scroll.frame), 0.0, 0.5,
                                       @"%@", geometry);
        } else {
            XCTAssertFalse(more.hidden);
            XCTAssertEqualWithAccuracy(CGRectGetWidth(more.bounds), 44.0, 0.5, @"%@", geometry);
            XCTAssertEqualWithAccuracy(CGRectGetHeight(more.bounds), bar.barHeight, 0.5, @"%@", geometry);
            CGPoint moreCenter = [more convertPoint:CGPointMake(CGRectGetMidX(more.bounds), CGRectGetMidY(more.bounds))
                                            toView:bar];
            XCTAssertEqual([bar hitTest:moreCenter withEvent:nil], more);
            XCTAssertEqualWithAccuracy(CGRectGetMaxX(scroll.frame), CGRectGetMinX(more.frame) - 4.0, 0.5,
                                       @"%@", geometry);
            XCTAssertEqualWithAccuracy(CGRectGetWidth(area.bounds) - CGRectGetWidth(scroll.frame), 48.0, 0.5,
                                       @"%@", geometry);
        }
    }
}

- (void)testCandidateScrollResetsOnlyForSemanticQueryChanges {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, 217.5)];
    UIView *host = [self hostForCandidateBar:bar width:200.0 height:217.5];
    NSArray<FSHCandidate *> *candidates = [self candidatesWithCount:30 code:@"a"];
    [bar updateRawBuffer:@"a" candidates:candidates exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar setExpanded:YES];
    [host layoutIfNeeded];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(bar.bounds), 200.0, 0.5);
    UIScrollView *inlineScroll = [bar valueForKey:@"scrollView"];
    UIScrollView *moreScroll = [bar valueForKey:@"moreScrollView"];
    XCTAssertGreaterThan(inlineScroll.contentSize.width - inlineScroll.bounds.size.width, 30.0);
    XCTAssertGreaterThan(moreScroll.contentSize.height - moreScroll.bounds.size.height, 40.0);
    inlineScroll.contentOffset = CGPointMake(30.0, 0.0);
    moreScroll.contentOffset = CGPointMake(0.0, 40.0);

    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 30.0, 0.5);
    XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 40.0, 0.5);
    host.frame = CGRectMake(0.0, 0.0, 220.0, 217.5);
    [host setNeedsLayout];
    [host layoutIfNeeded];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(bar.bounds), 220.0, 0.5);
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 30.0, 0.5);
    XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 40.0, 0.5);

    [bar updateRawBuffer:@"b" candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 0.0, 0.5);
    XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 0.0, 0.5);
    inlineScroll.contentOffset = CGPointMake(30.0, 0.0);
    moreScroll.contentOffset = CGPointMake(0.0, 40.0);
    [bar updateRawBuffer:@"b" candidates:[self candidatesWithCount:30 code:@"different"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 0.0, 0.5);
    XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 0.0, 0.5);

    NSMutableString *mutableRaw = [@"c" mutableCopy];
    [bar updateRawBuffer:mutableRaw candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    inlineScroll.contentOffset = CGPointMake(30.0, 0.0);
    moreScroll.contentOffset = CGPointMake(0.0, 40.0);
    [mutableRaw setString:@"d"];
    [bar updateRawBuffer:mutableRaw candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 0.0, 0.5);
    XCTAssertEqualWithAccuracy(moreScroll.contentOffset.y, 0.0, 0.5);
}

- (void)testCandidateButtonsReuseViewsAndMapCurrentIndexesOnce {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, 217.5)];
    UIView *host = [self hostForCandidateBar:bar width:200.0 height:217.5];
    FSHCandidateBarTestDelegate *delegate = [[FSHCandidateBarTestDelegate alloc] init];
    bar.delegate = delegate;
    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar setExpanded:YES];
    [host layoutIfNeeded];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(bar.bounds), 200.0, 0.5);
    UIStackView *inlineStack = [bar valueForKey:@"candidateStack"];
    UIView *moreContent = [bar valueForKey:@"moreContentView"];
    NSArray<UIButton *> *initialInline = (NSArray<UIButton *> *)[inlineStack.arrangedSubviews copy];
    NSArray<UIButton *> *initialMore = (NSArray<UIButton *> *)[moreContent.subviews copy];
    XCTAssertEqual(delegate.expansionChangeCount, (NSUInteger)1);
    XCTAssertEqual(initialInline.count, (NSUInteger)10);
    XCTAssertEqual(initialMore.count, (NSUInteger)30);
    for (NSUInteger iteration = 0; iteration < 20; iteration++) {
        [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:30 code:@"a"]
                 exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
        [bar setNeedsLayout];
        [bar layoutIfNeeded];
        XCTAssertEqualObjects(inlineStack.arrangedSubviews, initialInline);
        XCTAssertEqualObjects(moreContent.subviews, initialMore);
        XCTAssertEqual(delegate.expansionChangeCount, (NSUInteger)1);
    }

    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:11 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqual(moreContent.subviews.count, (NSUInteger)11);
    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:30 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualObjects(inlineStack.arrangedSubviews, initialInline);
    XCTAssertEqualObjects(moreContent.subviews, initialMore);
    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:45 code:@"a"]
             exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    NSArray *inlinePool = [bar valueForKey:@"inlineButtonPool"];
    NSArray *morePool = [bar valueForKey:@"moreButtonPool"];
    XCTAssertEqual(inlinePool.count, (NSUInteger)10);
    XCTAssertEqual(morePool.count, (NSUInteger)45);
    UIButton *inlineButton = (UIButton *)inlineStack.arrangedSubviews[2];
    UIButton *moreButton = (UIButton *)moreContent.subviews[12];
    XCTAssertEqual([[inlineButton actionsForTarget:bar forControlEvent:UIControlEventTouchUpInside] count], (NSUInteger)1);
    XCTAssertEqual([[moreButton actionsForTarget:bar forControlEvent:UIControlEventTouchUpInside] count], (NSUInteger)1);
    [inlineButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [moreButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqualObjects(delegate.selectedIndexes, (@[@2, @12]));

    [bar updateRawBuffer:@"" candidates:@[] exactCount:0 inlineLimit:10 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqual(moreContent.subviews.count, (NSUInteger)0);
    NSLayoutConstraint *moreHeight = [bar valueForKey:@"moreContentHeightConstraint"];
    XCTAssertEqualWithAccuracy(moreHeight.constant, 0.0, 0.5);
    XCTAssertEqual(morePool.count, (NSUInteger)45);
}

- (void)testCandidatePoolsRespectChangingLimitsAndRefreshValues {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, 217.5)];
    UIView *host = [self hostForCandidateBar:bar width:200.0 height:217.5];
    NSArray<FSHCandidate *> *candidates = [self candidatesWithCount:65 code:@"a"];
    [bar updateRawBuffer:@"a" candidates:candidates exactCount:20 inlineLimit:20 moreLimit:500 hintText:nil];
    [bar setExpanded:YES];
    [host layoutIfNeeded];
    [bar layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(bar.bounds), 200.0, 0.5);
    UIStackView *inlineStack = [bar valueForKey:@"candidateStack"];
    UIView *moreContent = [bar valueForKey:@"moreContentView"];
    UIScrollView *inlineScroll = [bar valueForKey:@"scrollView"];
    NSArray<UIButton *> *initialInline = (NSArray<UIButton *> *)[inlineStack.arrangedSubviews copy];
    NSArray<UIButton *> *initialMore = (NSArray<UIButton *> *)[moreContent.subviews copy];
    XCTAssertEqual(initialInline.count, (NSUInteger)20);
    XCTAssertEqual(initialMore.count, (NSUInteger)65);

    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:65 code:@"a"]
             exactCount:20 inlineLimit:5 moreLimit:50 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqual(inlineStack.arrangedSubviews.count, (NSUInteger)5);
    XCTAssertEqual(moreContent.subviews.count, (NSUInteger)50);
    [bar updateRawBuffer:@"a" candidates:[self candidatesWithCount:65 code:@"a"]
             exactCount:20 inlineLimit:20 moreLimit:500 hintText:nil];
    [bar layoutIfNeeded];
    XCTAssertEqualObjects(inlineStack.arrangedSubviews, initialInline);
    XCTAssertEqualObjects(moreContent.subviews, initialMore);

    NSMutableArray<FSHCandidate *> *changed = [[self candidatesWithCount:65 code:@"a"] mutableCopy];
    changed[2] = [[FSHCandidate alloc] initWithCode:@"b" value:@"新候選"];
    [bar updateRawBuffer:@"a" candidates:changed exactCount:0 inlineLimit:20 moreLimit:500 hintText:nil];
    [bar layoutIfNeeded];
    UIButton *inlineButton = (UIButton *)inlineStack.arrangedSubviews[2];
    UIButton *moreButton = (UIButton *)moreContent.subviews[2];
    XCTAssertEqualObjects([inlineButton titleForState:UIControlStateNormal], @"新候選");
    XCTAssertEqualObjects([moreButton titleForState:UIControlStateNormal], @"新候選");
    XCTAssertEqualObjects([inlineButton titleColorForState:UIControlStateNormal], [UIColor secondaryLabelColor]);
    XCTAssertEqualObjects([moreButton titleColorForState:UIControlStateNormal], [UIColor secondaryLabelColor]);
    XCTAssertEqualObjects(inlineButton, initialInline[2]);
    XCTAssertEqualObjects(moreButton, initialMore[2]);

    inlineScroll.contentOffset = CGPointMake(100.0, 0.0);
    host.frame = CGRectMake(0.0, 0.0, 1200.0, 217.5);
    [host setNeedsLayout];
    [host layoutIfNeeded];
    [bar setNeedsLayout];
    [bar layoutIfNeeded];
    CGFloat maximum = MAX(0.0, inlineScroll.contentSize.width - inlineScroll.bounds.size.width);
    XCTAssertLessThanOrEqual(inlineScroll.contentOffset.x, maximum + 0.5);
    XCTAssertGreaterThanOrEqual(inlineScroll.contentOffset.x, -0.5);
}

- (void)testCandidateAccessibilityDescribesCodeExactnessAndRealShortcutsAcrossContexts {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0, 0, 320, 217.5)];
    UIView *host = [self hostForCandidateBar:bar width:320 height:217.5];
    NSArray<FSHCandidate *> *candidates = [self candidatesWithCount:12 code:@"ci"];
    bar.selectionContext = FSHCandidateSelectionContextLetters;
    [bar updateRawBuffer:@"ci" candidates:candidates exactCount:10 inlineLimit:10 moreLimit:12 hintText:nil];
    [host layoutIfNeeded];
    UIStackView *inlineStack = [bar valueForKey:@"candidateStack"];
    UIButton *first = (UIButton *)inlineStack.arrangedSubviews[0];
    UIButton *ninth = (UIButton *)inlineStack.arrangedSubviews[9];
    UIButton *raw = [bar valueForKey:@"rawButton"];
    UIButton *more = [bar valueForKey:@"moreButton"];
    XCTAssertEqualObjects(first.accessibilityLabel, candidates[0].value);
    XCTAssertEqualObjects(first.accessibilityValue, @"字碼 ci，完全符合");
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    XCTAssertTrue([ninth.accessibilityHint containsString:@"數字 9"]);
    XCTAssertFalse([ninth.accessibilityHint containsString:@"空白鍵"]);
    XCTAssertEqualObjects(raw.accessibilityLabel, @"ci");
    XCTAssertTrue([raw.accessibilityHint containsString:@"原始字碼"]);
    XCTAssertEqualObjects(more.accessibilityLabel, @"更多候選字");
    XCTAssertEqualObjects(more.accessibilityValue, @"已收合");

    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    [host layoutIfNeeded];
    XCTAssertEqualObjects(more.accessibilityValue, @"已展開");
    NSArray<UIButton *> *morePool = [bar valueForKey:@"moreButtonPool"];
    XCTAssertEqual(morePool.count, (NSUInteger)12);
    if (morePool.count < 12) { return; }
    UIButton *prefix = morePool[10];
    XCTAssertEqualObjects(prefix.accessibilityValue, @"字碼 ci，前綴候選");
    XCTAssertFalse([prefix.accessibilityHint containsString:@"數字"]);
    XCTAssertFalse([prefix.accessibilityHint containsString:@"空白鍵"]);

    bar.selectionContext = FSHCandidateSelectionContextSymbols;
    [bar updateRawBuffer:@"ci" candidates:candidates exactCount:10 inlineLimit:10 moreLimit:12 hintText:nil];
    XCTAssertEqual((UIButton *)inlineStack.arrangedSubviews[0], first);
    XCTAssertEqual(morePool[10], prefix);
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    bar.selectionContext = FSHCandidateSelectionContextReverseEntering;
    [bar updateRawBuffer:@"ci" candidates:candidates exactCount:10 inlineLimit:10 moreLimit:12 hintText:nil];
    XCTAssertTrue([first.accessibilityHint containsString:@"輸入候選字"],
                  @"A phrase base commits directly instead of opening homophones");
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    XCTAssertFalse([prefix.accessibilityHint containsString:@"數字"]);
    NSMutableArray<FSHCandidate *> *singleBaseCandidates = [candidates mutableCopy];
    singleBaseCandidates[0] = [[FSHCandidate alloc] initWithCode:@"ci" value:@"中"];
    [bar updateRawBuffer:@"ci" candidates:singleBaseCandidates exactCount:10 inlineLimit:10 moreLimit:12 hintText:nil];
    XCTAssertTrue([first.accessibilityHint containsString:@"查看同音字"]);
    bar.selectionContext = FSHCandidateSelectionContextReverseActive;
    [bar updateRawBuffer:@"ci" candidates:candidates exactCount:12 inlineLimit:10 moreLimit:12 hintText:nil];
    XCTAssertEqualObjects(first.accessibilityValue, @"讀音碼 ci，同音字候選");
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    XCTAssertFalse([prefix.accessibilityHint containsString:@"數字"], @"Indexes above 9 have no digit shortcut");
    [bar setExpanded:NO];
    XCTAssertEqualObjects(more.accessibilityValue, @"已收合");
}

- (void)testCandidateShortcutAnnouncementsMatchControllerDigitAndSpaceActions {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle mainBundle] error:&error], @"%@", error);
    [self.controller setValue:engine forKey:@"engine"];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    UIStackView *stack = [bar valueForKey:@"candidateStack"];

    [[self rawBuffer] setString:@"ci"];
    [self.controller refreshCandidatesAndUI];
    UIButton *first = (UIButton *)stack.arrangedSubviews.firstObject;
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"0"];
    XCTAssertEqualObjects(self.proxy.text, @"中");
    XCTAssertEqualObjects([self rawBuffer], @"");

    [[self rawBuffer] setString:@"ci"];
    [self.controller refreshCandidatesAndUI];
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeModeChange output:nil];
    XCTAssertEqual(self.keyboard.mode, FSHKeyboardModeSymbols);
    first = (UIButton *)stack.arrangedSubviews.firstObject;
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"1"];
    XCTAssertEqualObjects([self rawBuffer], @"ci1");
    XCTAssertEqualObjects(self.proxy.text, @"中");

    self.keyboard.mode = FSHKeyboardModeLetters;
    [[self rawBuffer] setString:@""];
    for (NSString *input in @[@"'", @"c", @"i"]) {
        [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:input];
    }
    XCTAssertEqualObjects([self rawBuffer], @"'ci");
    XCTAssertEqual([[self.controller valueForKey:@"reverseState"] integerValue], (NSInteger)1);
    first = (UIButton *)stack.arrangedSubviews.firstObject;
    XCTAssertTrue([first.accessibilityHint containsString:@"查看同音字"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"0"];
    XCTAssertEqual([[self.controller valueForKey:@"reverseState"] integerValue], (NSInteger)2);
    XCTAssertEqualObjects(self.proxy.text, @"中");
    first = (UIButton *)stack.arrangedSubviews.firstObject;
    NSArray<FSHCandidate *> *reverseCandidates = [self.controller valueForKey:@"candidates"];
    NSString *expectedPronunciationLabel = [NSString stringWithFormat:@"讀音碼 %@，同音字候選",
                                            reverseCandidates.firstObject.code];
    XCTAssertEqualObjects(first.accessibilityValue, expectedPronunciationLabel);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeSpace output:@" "];
    XCTAssertEqualObjects([self rawBuffer], @"");
    XCTAssertGreaterThan(self.proxy.text.length, (NSUInteger)1);
}

- (void)testCandidateShortcutAvailabilityRefreshesPooledMetadataWithoutChangingQueryOrScroll {
    FSHCandidateBarView *bar = [[FSHCandidateBarView alloc] initWithFrame:CGRectMake(0, 0, 320, 217.5)];
    UIView *host = [self hostForCandidateBar:bar width:320 height:217.5];
    NSArray<FSHCandidate *> *candidates = [self candidatesWithCount:50 code:@"ci"];
    bar.selectionContext = FSHCandidateSelectionContextLetters;
    [bar updateRawBuffer:@"ci" candidates:candidates exactCount:10 inlineLimit:10 moreLimit:50 hintText:nil];
    bar.expanded = YES;
    [host layoutIfNeeded];
    UIStackView *stack = [bar valueForKey:@"candidateStack"];
    UIButton *first = (UIButton *)stack.arrangedSubviews.firstObject;
    NSArray<UIButton *> *expandedPool = [bar valueForKey:@"moreButtonPool"];
    UIButton *expandedFirst = expandedPool.firstObject;
    UIScrollView *inlineScroll = [bar valueForKey:@"scrollView"];
    UIScrollView *expandedScroll = [bar valueForKey:@"moreScrollView"];
    inlineScroll.contentOffset = CGPointMake(12.0, 0.0);
    expandedScroll.contentOffset = CGPointMake(0.0, 18.0);
    NSArray *signature = [bar valueForKey:@"currentQuerySignature"];
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);

    [bar updateShortcutAvailabilityWithDigits:NO space:YES];
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    XCTAssertFalse([expandedFirst.accessibilityHint containsString:@"數字"]);
    [bar updateShortcutAvailabilityWithDigits:NO space:NO];
    XCTAssertFalse([first.accessibilityHint containsString:@"空白鍵"]);
    XCTAssertFalse([expandedFirst.accessibilityHint containsString:@"空白鍵"]);
    [bar updateShortcutAvailabilityWithDigits:YES space:YES];
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    XCTAssertTrue([expandedFirst.accessibilityHint containsString:@"空白鍵"]);
    XCTAssertEqual((UIButton *)stack.arrangedSubviews.firstObject, first);
    XCTAssertEqual(((NSArray *)[bar valueForKey:@"moreButtonPool"]).firstObject, expandedFirst);
    XCTAssertEqual([bar valueForKey:@"currentQuerySignature"], signature);
    XCTAssertEqualObjects(first.accessibilityIdentifier, @"candidate.inline.0");
    XCTAssertEqualObjects(expandedFirst.accessibilityIdentifier, @"candidate.expanded.0");
    XCTAssertEqualWithAccuracy(inlineScroll.contentOffset.x, 12.0, 0.5);
    XCTAssertEqualWithAccuracy(expandedScroll.contentOffset.y, 18.0, 0.5);
}

- (void)testCandidateDigitHintsRespectLetterNumberRowAvailability {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:NSBundle.mainBundle error:&error], @"%@", error);
    [self.controller setValue:engine forKey:@"engine"];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    UIStackView *stack = [bar valueForKey:@"candidateStack"];
    [[self rawBuffer] setString:@"ci"];
    self.keyboard.mode = FSHKeyboardModeLetters;
    self.keyboard.layout = FSHKeyboardLayoutStandard;
    self.keyboard.showNumberRow = YES;
    [self.controller refreshCandidatesAndUI];
    UIButton *first = (UIButton *)stack.arrangedSubviews.firstObject;
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    self.keyboard.showNumberRow = NO;
    [self.controller refreshCandidatesAndUI];
    XCTAssertEqual((UIButton *)stack.arrangedSubviews.firstObject, first);
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"]);
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
    self.keyboard.showNumberRow = YES;
    self.keyboard.layout = FSHKeyboardLayoutOriginalNoNumber;
    [self.controller refreshCandidatesAndUI];
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"]);
    self.keyboard.layout = FSHKeyboardLayoutStandard;
    [self.controller refreshCandidatesAndUI];
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"]);
    [self.controller setValue:@2 forKey:@"reverseState"];
    self.keyboard.mode = FSHKeyboardModeSymbols;
    [self.controller refreshCandidatesAndUI];
    XCTAssertTrue([first.accessibilityHint containsString:@"數字 0"],
                  @"Reverse-active Symbols still has reachable digit keys");
    self.keyboard.mode = FSHKeyboardModeEmoji;
    [self.controller refreshCandidatesAndUI];
    XCTAssertFalse([first.accessibilityHint containsString:@"數字"],
                   @"Emoji has no digit keys even while reverse selection is active");
    XCTAssertTrue([first.accessibilityHint containsString:@"空白鍵"]);
}

- (void)testProductionKeyboardViewsRenderInAttachedHostWindow {
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    XCTAssertNotNil(activeScene);
    if (!activeScene) {
        return;
    }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *candidate in activeScene.windows) {
        if (candidate.isKeyWindow) {
            oldKeyWindow = candidate;
            break;
        }
    }

    FSHTestInputController *controller = [[FSHTestInputController alloc] init];
    controller.fakeProxy = [[FSHFakeDocumentProxy alloc] init];
    [controller loadViewIfNeeded];
    UIViewController *host = [[UIViewController alloc] init];
    host.view.backgroundColor = [UIColor systemBackgroundColor];
    [host addChildViewController:controller];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    [host.view addSubview:controller.view];
    [controller didMoveToParentViewController:host];
    [NSLayoutConstraint activateConstraints:@[
        [controller.view.leadingAnchor constraintEqualToAnchor:host.view.leadingAnchor],
        [controller.view.trailingAnchor constraintEqualToAnchor:host.view.trailingAnchor],
        [controller.view.bottomAnchor constraintEqualToAnchor:host.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:activeScene];
    window.frame = activeScene.coordinateSpace.bounds;
    window.rootViewController = host;
    [window makeKeyAndVisible];
    XCTAssertTrue([self waitForView:controller.view toAttachToWindow:window],
                  @"The keyboard host view should attach to its scene-backed window");
    XCTAssertEqual(controller.view.window, window);

    // Preserve an unmodified UIButton transition as a control for title-change
    // snapshot timing; the production Shift path below suppresses animation.
    FSHKeyButton *baselineTitle = [FSHKeyButton buttonWithType:UIButtonTypeSystem];
    baselineTitle.frame = CGRectMake(100, 100, 100, 50);
    baselineTitle.backgroundColor = [UIColor systemGray5Color];
    [baselineTitle setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [baselineTitle setTitle:@"q" forState:UIControlStateNormal];
    [window addSubview:baselineTitle];
    [window layoutIfNeeded];
    NSPredicate *baselineInitialVisible = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        UIImage *frame = [self snapshotOfWindow:window];
        return [self titleContrastForButton:baselineTitle inWindow:window image:frame] >= 0.3;
    }];
    XCTNSPredicateExpectation *baselineInitial = [[XCTNSPredicateExpectation alloc] initWithPredicate:baselineInitialVisible
                                                                                                 object:baselineTitle];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[baselineInitial] timeout:2.0], XCTWaiterResultCompleted);
    UIImage *baselineBefore = [self snapshotOfWindow:window];
    XCTAttachment *baselineBeforeAttachment = [XCTAttachment attachmentWithImage:baselineBefore];
    baselineBeforeAttachment.name = @"Unmodified system button initial title visible";
    baselineBeforeAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:baselineBeforeAttachment];
    NSTimeInterval baselineMutationTime = [NSDate timeIntervalSinceReferenceDate];
    [baselineTitle setTitle:@"Q" forState:UIControlStateNormal];
    UIImage *baselineImmediate = [self snapshotOfWindow:window];
    CGFloat baselineImmediateContrast = [self titleContrastForButton:baselineTitle inWindow:window
                                                              image:baselineImmediate];
    CALayer *baselinePresentation = baselineTitle.titleLabel.layer.presentationLayer;
    NSLog(@"System UIButton title transition after %.3f sec: immediate contrast %.3f; model opacity %.2f; presentation %@; animations %@",
          [NSDate timeIntervalSinceReferenceDate] - baselineMutationTime,
          baselineImmediateContrast, baselineTitle.titleLabel.layer.opacity,
          baselinePresentation ? @(baselinePresentation.opacity) : @"uncommitted",
          baselineTitle.titleLabel.layer.animationKeys);
    XCTAttachment *baselineImmediateAttachment = [XCTAttachment attachmentWithImage:baselineImmediate];
    baselineImmediateAttachment.name = @"Unmodified system button title transition immediate";
    baselineImmediateAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:baselineImmediateAttachment];
    NSPredicate *baselineVisible = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        UIImage *frame = [self snapshotOfWindow:window];
        return [self titleContrastForButton:baselineTitle inWindow:window image:frame] >= 0.3;
    }];
    XCTNSPredicateExpectation *baselineSettled = [[XCTNSPredicateExpectation alloc] initWithPredicate:baselineVisible
                                                                                                 object:baselineTitle];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[baselineSettled] timeout:2.0], XCTWaiterResultCompleted);
    UIImage *baselineSettledImage = [self snapshotOfWindow:window];
    NSLog(@"System UIButton title settled after %.3f sec: contrast %.3f",
          [NSDate timeIntervalSinceReferenceDate] - baselineMutationTime,
          [self titleContrastForButton:baselineTitle inWindow:window image:baselineSettledImage]);
    XCTAttachment *baselineSettledAttachment = [XCTAttachment attachmentWithImage:baselineSettledImage];
    baselineSettledAttachment.name = @"Unmodified system button title transition settled";
    baselineSettledAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:baselineSettledAttachment];
    [baselineTitle removeFromSuperview];

    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle mainBundle] error:&error], @"%@", error);
    [controller setValue:engine forKey:@"engine"];
    [controller setValue:@1 forKey:@"engineLoadState"];
    NSMutableString *raw = [controller valueForKey:@"rawBuffer"];
    [raw setString:@"ci"];
    [controller refreshCandidatesAndUI];
    FSHKeyboardView *keyboard = [controller valueForKey:@"keyboardView"];
    keyboard.layout = FSHKeyboardLayoutStandard;
    keyboard.showNumberRow = YES;
    keyboard.showsGlobe = NO;
    FSHCandidateBarView *bar = [controller valueForKey:@"candidateBar"];
    UIStackView *candidateStack = [bar valueForKey:@"candidateStack"];
    UIButton *firstCandidate = (UIButton *)candidateStack.arrangedSubviews.firstObject;
    XCTAssertEqualObjects([firstCandidate titleForState:UIControlStateNormal], @"中");

    NSArray<NSDictionary<NSString *, id> *> *appearances = @[
        @{@"mode": @(FSHKeyboardModeLetters), @"shift": @NO, @"caps": @NO, @"name": @"letters lowercase"},
        @{@"mode": @(FSHKeyboardModeLetters), @"shift": @YES, @"caps": @NO, @"name": @"letters one-shot shift"},
        @{@"mode": @(FSHKeyboardModeLetters), @"shift": @NO, @"caps": @YES, @"name": @"letters caps lock"},
        @{@"mode": @(FSHKeyboardModeSymbolsShift), @"shift": @NO, @"caps": @NO, @"name": @"symbols second page"},
        @{@"mode": @(FSHKeyboardModeEmoji), @"shift": @NO, @"caps": @NO, @"name": @"emoji"},
    ];
    for (NSDictionary<NSString *, id> *appearance in appearances) {
        keyboard.mode = [appearance[@"mode"] integerValue];
        keyboard.shiftOn = [appearance[@"shift"] boolValue];
        keyboard.capsLockOn = [appearance[@"caps"] boolValue];
        for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
            window.overrideUserInterfaceStyle = style.integerValue;
            [window layoutIfNeeded];
            XCTAssertGreaterThan(keyboard.bounds.size.height, 0.0);
            XCTAssertEqual(keyboard.window, window);
            XCTAssertEqualWithAccuracy(CGRectGetMaxY(controller.view.frame),
                                       CGRectGetHeight(host.view.bounds) - host.view.safeAreaInsets.bottom, 1.0);
            NSArray<NSArray<FSHKeyButton *> *> *rows = [keyboard valueForKey:@"rowButtons"];
            for (NSArray<FSHKeyButton *> *row in rows) {
                for (FSHKeyButton *button in row) {
                    XCTAssertFalse(CGRectIsEmpty(button.frame));
                    XCTAssertGreaterThanOrEqual(CGRectGetMinX(button.frame), -0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxX(button.frame), CGRectGetWidth(keyboard.bounds) + 0.5);
                    XCTAssertLessThanOrEqual(CGRectGetMaxY(button.frame), CGRectGetHeight(keyboard.bounds) + 0.5);
                    if (keyboard.mode == FSHKeyboardModeLetters && button.output.length == 1) {
                        unichar ch = [button.output characterAtIndex:0];
                        if (ch >= 'a' && ch <= 'z') {
                            NSString *visibleLetter = (keyboard.shiftOn || keyboard.capsLockOn)
                                ? button.output.uppercaseString : button.output;
                            XCTAssertEqualObjects(button.currentTitle, visibleLetter);
                            XCTAssertEqualObjects(button.titleLabel.text, visibleLetter);
                            XCTAssertFalse(CGRectIsEmpty(button.titleLabel.frame));
                        }
                    }
                }
            }
            if (keyboard.mode == FSHKeyboardModeLetters) {
                FSHKeyButton *shiftKey = [keyboard valueForKey:@"shiftButton"];
                NSString *shiftTitle = keyboard.capsLockOn ? @"⇪" : @"⇧";
                XCTAssertEqualObjects(shiftKey.currentTitle, shiftTitle);
                XCTAssertEqualObjects(shiftKey.titleLabel.text, shiftTitle);
                XCTAssertFalse(CGRectIsEmpty(shiftKey.titleLabel.frame));
            }
            UIImage *snapshot = [self snapshotOfWindow:window];
            XCTAssertNotNil(snapshot);
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
            attachment.name = [NSString stringWithFormat:@"Production keyboard immediate %@ - %@",
                               appearance[@"name"], style.integerValue == UIUserInterfaceStyleDark ? @"dark" : @"light"];
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:attachment];
            if (keyboard.mode == FSHKeyboardModeLetters) {
                FSHKeyButton *q = [self keyWithOutput:@"q" inKeyboard:keyboard];
                CALayer *presentation = q.titleLabel.layer.presentationLayer;
                NSLog(@"Shift screenshot %@ %@: q model opacity %.2f, presentation %@, animations %@",
                      appearance[@"name"], style, q.titleLabel.layer.opacity,
                      presentation ? @(presentation.opacity) : @"uncommitted", q.titleLabel.layer.animationKeys);
                NSPredicate *visibleTitles = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                    [window layoutIfNeeded];
                    UIImage *frame = [self snapshotOfWindow:window];
                    for (NSArray<FSHKeyButton *> *row in rows) {
                        for (FSHKeyButton *button in row) {
                            if (button.output.length == 1) {
                                unichar ch = [button.output characterAtIndex:0];
                                if (ch >= 'a' && ch <= 'z' &&
                                    [self titleContrastForButton:button inWindow:window image:frame] < 0.3) {
                                    return NO;
                                }
                            }
                        }
                    }
                    FSHKeyButton *shiftKey = [keyboard valueForKey:@"shiftButton"];
                    return [self titleContrastForButton:shiftKey inWindow:window image:frame] >= 0.3;
                }];
                XCTNSPredicateExpectation *settled = [[XCTNSPredicateExpectation alloc] initWithPredicate:visibleTitles object:keyboard];
                XCTAssertEqual([XCTWaiter waitForExpectations:@[settled] timeout:2.0], XCTWaiterResultCompleted);
                UIImage *settledImage = [self snapshotOfWindow:window];
                XCTAttachment *settledAttachment = [XCTAttachment attachmentWithImage:settledImage];
                settledAttachment.name = [NSString stringWithFormat:@"Production keyboard settled %@ - %@",
                                          appearance[@"name"], style.integerValue == UIUserInterfaceStyleDark ? @"dark" : @"light"];
                settledAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
                [self addAttachment:settledAttachment];
                for (NSArray<FSHKeyButton *> *row in rows) {
                    for (FSHKeyButton *button in row) {
                        if (button.output.length == 1) {
                            unichar ch = [button.output characterAtIndex:0];
                            if (ch >= 'a' && ch <= 'z') {
                                XCTAssertGreaterThan([self titleContrastForButton:button inWindow:window image:snapshot],
                                                     0.3, @"Missing immediate title for %@ in %@", button.output, appearance[@"name"]);
                            }
                        }
                    }
                }
                FSHKeyButton *shiftKey = [keyboard valueForKey:@"shiftButton"];
                XCTAssertGreaterThan([self titleContrastForButton:shiftKey inWindow:window image:snapshot],
                                     0.3, @"Missing immediate Shift title in %@", appearance[@"name"]);
            }
        }
    }
    keyboard.mode = FSHKeyboardModeLetters;
    [controller keyboardView:keyboard didPressKeyCode:FSHKeyCodeSettings output:nil];
    UIButton *settingsHelp = [controller valueForKey:@"settingsHelpBanner"];
    XCTAssertFalse(settingsHelp.hidden);
    XCTAssertEqualObjects(raw, @"ci");
    XCTAssertEqual(candidateStack.arrangedSubviews.firstObject, firstCandidate);
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
        window.overrideUserInterfaceStyle = style.integerValue;
        [window layoutIfNeeded];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
        UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
        attachment.name = [NSString stringWithFormat:@"Settings help over active candidates - %@",
                           style.integerValue == UIUserInterfaceStyleDark ? @"dark" : @"light"];
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    }
    [settingsHelp sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(settingsHelp.hidden);
    window.frame = CGRectMake(0.0, 0.0, 320.0, 390.0);
    keyboard.mode = FSHKeyboardModeEmoji;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [window layoutIfNeeded];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(keyboard.bounds), 320.0, 1.0);
    UIGraphicsImageRenderer *compactRenderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    __block BOOL compactRendered = NO;
    UIImage *compactSnapshot = [compactRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        compactRendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    XCTAssertTrue(compactRendered);
    XCTAttachment *compactAttachment = [XCTAttachment attachmentWithImage:compactSnapshot];
    compactAttachment.name = @"Production keyboard host harness emoji - compact 320x390";
    compactAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:compactAttachment];
    [controller keyboardView:keyboard didPressKeyCode:FSHKeyCodeSettings output:nil];
    XCTAssertFalse(settingsHelp.hidden);
    XCTAssertEqualObjects(raw, @"ci");
    XCTAssertEqual(candidateStack.arrangedSubviews.firstObject, firstCandidate);
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
        window.overrideUserInterfaceStyle = style.integerValue;
        [window layoutIfNeeded];
        XCTAssertEqualWithAccuracy(CGRectGetWidth(settingsHelp.bounds), 320.0, 1.0);
        XCTAssertLessThanOrEqual(CGRectGetMaxY(settingsHelp.frame), CGRectGetMinY(keyboard.frame) + 0.5,
                                 @"Settings notice overlaps keyboard: notice %@, keyboard %@",
                                 NSStringFromCGRect(settingsHelp.frame), NSStringFromCGRect(keyboard.frame));
        XCTAssertLessThanOrEqual(CGRectGetHeight(settingsHelp.bounds), bar.barHeight + 0.5);
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
        __block BOOL rendered = NO;
        UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            rendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        XCTAssertTrue(rendered);
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
        attachment.name = [NSString stringWithFormat:@"Settings help with active candidates - compact 320 - %@",
                           style.integerValue == UIUserInterfaceStyleDark ? @"dark" : @"light"];
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    }
    [settingsHelp sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertTrue(settingsHelp.hidden);
    keyboard.mode = FSHKeyboardModeLetters;
    FSHKeyButton *returnKey = [keyboard valueForKey:@"enterButton"];
    for (NSNumber *type in @[@(UIReturnKeySearch), @(UIReturnKeyNext)]) {
        controller.fakeProxy.returnKeyType = type.integerValue;
        [controller textDidChange:nil];
        XCTAssertEqual([keyboard valueForKey:@"enterButton"], returnKey);
        XCTAssertEqualObjects(returnKey.currentTitle, type.integerValue == UIReturnKeyNext ? @"⇥" : @"搜尋");
        for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
            window.overrideUserInterfaceStyle = style.integerValue;
            [window layoutIfNeeded];
            XCTAssertFalse(CGRectIsEmpty(returnKey.titleLabel.frame));
            XCTAssertLessThanOrEqual(CGRectGetMaxX(returnKey.titleLabel.frame), CGRectGetWidth(returnKey.bounds) + 0.5);
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
            __block BOOL rendered = NO;
            UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                rendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
            }];
            XCTAssertTrue(rendered);
            XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
            attachment.name = [NSString stringWithFormat:@"Compact Return %@ - %@",
                               type.integerValue == UIReturnKeyNext ? @"Next" : @"Search",
                               style.integerValue == UIUserInterfaceStyleDark ? @"dark" : @"light"];
            attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:attachment];
        }
    }
    [window endEditing:YES];
    window.hidden = YES;
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testReverseLookupAndHintRecognizeOneComposedCharacter {
    FSHTestEngine *engine = [[FSHTestEngine alloc] init];
    [self.controller setValue:engine forKey:@"engine"];
    for (NSString *value in @[@"😀", @"☹️", @"é", @"👨‍👩‍👧‍👦", @"𠀀"]) {
        [self.controller setValue:@[[[FSHCandidate alloc] initWithCode:@"abcd" value:value]]
                          forKey:@"candidates"];
        NSUInteger previousCount = engine.reverseCallCount;
        [self.controller triggerReverseLookupWithBaseIndex:0];
        XCTAssertEqual(engine.reverseCallCount, previousCount + 1, @"Failed for %@", value);
        [self.controller updateHintForCommittedValue:value typedCodeLength:4 isReverse:NO];
        XCTAssertEqualObjects([self.controller valueForKey:@"shortestHint"], @"字根：A");
    }
    [self.controller updateHintForCommittedValue:@"ab" typedCodeLength:4 isReverse:NO];
    XCTAssertEqualObjects([self.controller valueForKey:@"shortestHint"], @"");
}

- (void)testAccessibleActivationDeletesExactlyOnce {
    [self.proxy.text setString:@"abc"];
    XCTAssertTrue([self.deleteButton accessibilityActivate]);
    XCTAssertEqualObjects(self.proxy.text, @"ab");
    XCTAssertNil([self.controller valueForKey:@"deleteRepeatTimer"]);
}

- (void)testDisappearanceAndKeyRebuildCancelRepeat {
    [self.proxy.text setString:@"abc"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self.controller beginAppearanceTransition:NO animated:NO];
    [self.controller endAppearanceTransition];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"ab");

    [self.controller beginAppearanceTransition:YES animated:NO];
    [self.controller endAppearanceTransition];
    self.deleteButton = [self.keyboard valueForKey:@"deleteButton"];
    [self.proxy.text setString:@"abc"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self.keyboard reloadKeys];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
}

- (void)testColdStartInputRemainsLiteralUntilSpaceAfterReady {
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects(self.proxy.text, @"a");
    XCTAssertEqualObjects([self rawBuffer], @"");
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    UILabel *hint = [[self.controller valueForKey:@"candidateBar"] valueForKey:@"hintLabel"];
    [self.controller refreshCandidatesAndUI];
    XCTAssertEqualObjects(hint.text, @"正在原文輸入，空白後恢復字碼");
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"b"];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
    XCTAssertEqualObjects([self rawBuffer], @"");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeSpace output:@" "];
    XCTAssertEqualObjects(self.proxy.text, @"ab ");
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"c"];
    XCTAssertEqualObjects(self.proxy.text, @"ab ");
    XCTAssertEqualObjects([self rawBuffer], @"c");
}

- (void)testLiteralFallbackEndsAtDocumentAndSessionBoundaries {
    NSUUID *firstDocument = self.proxy.documentIdentifier;
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    self.proxy.documentIdentifier = [NSUUID UUID];
    XCTAssertNotEqualObjects(self.proxy.documentIdentifier, firstDocument);
    [self.controller textDidChange:nil];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"b"];
    XCTAssertEqualObjects(self.proxy.text, @"a");
    XCTAssertEqualObjects([self rawBuffer], @"b");

    [[self rawBuffer] setString:@""];
    [self.controller setValue:@0 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"c"];
    self.proxy.secureTextEntry = YES;
    [self.controller setValue:@YES forKey:@"disableIMEInSensitive"];
    [self.controller textDidChange:nil];
    self.proxy.secureTextEntry = NO;
    [self.controller textDidChange:nil];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"d"];
    XCTAssertEqualObjects(self.proxy.text, @"ac");
    XCTAssertEqualObjects([self rawBuffer], @"d");

    [[self rawBuffer] setString:@""];
    [self.controller setValue:@0 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"e"];
    [self.controller beginAppearanceTransition:NO animated:NO];
    [self.controller endAppearanceTransition];
    [self.controller beginAppearanceTransition:YES animated:NO];
    [self.controller endAppearanceTransition];
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"f"];
    XCTAssertEqualObjects(self.proxy.text, @"ace");
    XCTAssertEqualObjects([self rawBuffer], @"f");
}

- (void)testStaleEngineCompletionCannotOverwriteNewerGeneration {
    NSUInteger oldGeneration = [self.controller beginEngineLoad];
    NSUInteger newGeneration = [self.controller beginEngineLoad];
    FSHTestEngine *oldEngine = [[FSHTestEngine alloc] init];
    FSHTestEngine *newEngine = [[FSHTestEngine alloc] init];
    [self.controller finishEngineLoad:oldEngine loaded:YES error:nil generation:oldGeneration];
    XCTAssertNil([self.controller valueForKey:@"engine"]);
    XCTAssertEqual([[self.controller valueForKey:@"engineLoadState"] integerValue], (NSInteger)0);
    [self.controller finishEngineLoad:newEngine loaded:YES error:nil generation:newGeneration];
    XCTAssertEqual([self.controller valueForKey:@"engine"], newEngine);
    XCTAssertEqual([[self.controller valueForKey:@"engineLoadState"] integerValue], (NSInteger)1);
    [self.controller finishEngineLoad:oldEngine loaded:YES error:nil generation:oldGeneration];
    XCTAssertEqual([self.controller valueForKey:@"engine"], newEngine);
    NSError *oldError = [NSError errorWithDomain:@"StaleLoad" code:1 userInfo:nil];
    [self.controller finishEngineLoad:nil loaded:NO error:oldError generation:oldGeneration];
    XCTAssertEqual([self.controller valueForKey:@"engine"], newEngine);
    XCTAssertEqual([[self.controller valueForKey:@"engineLoadState"] integerValue], (NSInteger)1);
    XCTAssertNil([self.controller valueForKey:@"engineLoadError"]);
}

- (void)testRealDictionaryCompletesAndPublishesEngine {
    FSHAsyncInputController *controller = [[FSHAsyncInputController alloc] init];
    controller.fakeProxy = [[FSHFakeDocumentProxy alloc] init];
    [controller loadViewIfNeeded];
    FSHKeyboardView *keyboard = [controller valueForKey:@"keyboardView"];
    [controller keyboardView:keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects(controller.fakeProxy.text, @"a");
    NSPredicate *completedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [[controller valueForKey:@"engineLoadState"] integerValue] != 0;
    }];
    XCTNSPredicateExpectation *completed = [[XCTNSPredicateExpectation alloc] initWithPredicate:completedPredicate object:controller];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[completed] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertEqual([[controller valueForKey:@"engineLoadState"] integerValue], (NSInteger)1);
    FSHShiamyEngine *engine = [controller valueForKey:@"engine"];
    XCTAssertTrue(engine.ready);
    XCTAssertNil([controller valueForKey:@"engineLoadError"]);
    [controller keyboardView:keyboard didPressKeyCode:0 output:@"b"];
    XCTAssertEqualObjects(controller.fakeProxy.text, @"ab");
    [controller keyboardView:keyboard didPressKeyCode:FSHKeyCodeSpace output:@" "];
    XCTAssertEqualObjects(controller.fakeProxy.text, @"ab ");
    [keyboard cancelActivePress];
}

- (void)testReloadPreservesCompositionAndTrailingSpaceOnFailure {
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [[self rawBuffer] setString:@"a"];
    [self.controller beginEngineLoad];
    XCTAssertEqualObjects([self rawBuffer], @"a");
    XCTAssertEqualObjects(self.proxy.text, @"");
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeSpace output:@" "];
    XCTAssertEqualObjects([self rawBuffer], @"a ");
    [self.controller setValue:@2 forKey:@"engineLoadState"];
    [self.controller refreshCandidatesAndUI];
    UILabel *hint = [[self.controller valueForKey:@"candidateBar"] valueForKey:@"hintLabel"];
    XCTAssertEqualObjects(hint.text, @"字庫載入失敗，暫以原文輸入");
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller refreshCandidatesAndUI];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarViewDidTapRawBuffer:bar];
    XCTAssertEqualObjects(self.proxy.text, @"a ");
    XCTAssertEqualObjects([self rawBuffer], @"");
}

- (void)testSensitiveFieldBlocksFirstKeyDeleteAndCandidateCommits {
    self.proxy.secureTextEntry = YES;
    [self.controller setValue:@YES forKey:@"disableIMEInSensitive"];
    [self.proxy.text setString:@"host"];
    [[self rawBuffer] setString:@"ab"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"host");
    XCTAssertEqualObjects([self rawBuffer], @"");

    [[self rawBuffer] setString:@"ab"];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarViewDidTapRawBuffer:bar];
    XCTAssertEqualObjects(self.proxy.text, @"host");
    XCTAssertEqualObjects([self rawBuffer], @"");

    [[self rawBuffer] setString:@"ab"];
    [self.controller setValue:@[[[FSHCandidate alloc] initWithCode:@"ab" value:@"secret"]]
                      forKey:@"candidates"];
    [self.controller candidateBarView:bar didSelectCandidateAtIndex:0];
    XCTAssertEqualObjects(self.proxy.text, @"host");
    XCTAssertEqualObjects([self rawBuffer], @"");

    NSUInteger advancesBeforeGlobe = self.controller.inputModeAdvanceCount;
    NSUInteger dismissalsBeforeGlobe = self.controller.dismissCount;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeGlobe output:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBeforeGlobe + 1);
    XCTAssertEqual(self.controller.dismissCount, dismissalsBeforeGlobe);
    NSUInteger advancesBeforeCancel = self.controller.inputModeAdvanceCount;
    NSUInteger dismissalsBeforeCancel = self.controller.dismissCount;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeCancel output:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBeforeCancel);
    XCTAssertEqual(self.controller.dismissCount, dismissalsBeforeCancel + 1);
    XCTAssertEqualObjects(self.proxy.text, @"host");
}

- (void)testConnectedSecureTransitionSwitchesAndDismissesOnlyOnce {
    [self.controller setValue:@YES forKey:@"disableIMEInSensitive"];
    [self.proxy.text setString:@"host"];
    [self.controller textDidChange:nil];
    NSUInteger initialAdvances = self.controller.inputModeAdvanceCount;
    NSUInteger initialDismissals = self.controller.dismissCount;

    self.proxy.secureTextEntry = YES;
    [self.controller textDidChange:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, initialAdvances + 1);
    XCTAssertEqual(self.controller.dismissCount, initialDismissals + 1);
    XCTAssertEqualObjects(self.proxy.text, @"host");
    [self.controller textWillChange:nil];
    [self.controller selectionDidChange:nil];
    [self.controller textDidChange:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, initialAdvances + 1);
    XCTAssertEqual(self.controller.dismissCount, initialDismissals + 1);

    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects(self.proxy.text, @"host");
    NSUInteger advancesBeforeGlobe = self.controller.inputModeAdvanceCount;
    NSUInteger dismissalsBeforeGlobe = self.controller.dismissCount;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeGlobe output:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBeforeGlobe + 1);
    XCTAssertEqual(self.controller.dismissCount, dismissalsBeforeGlobe);
    NSUInteger advancesBeforeCancel = self.controller.inputModeAdvanceCount;
    NSUInteger dismissalsBeforeCancel = self.controller.dismissCount;
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeCancel output:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, advancesBeforeCancel);
    XCTAssertEqual(self.controller.dismissCount, dismissalsBeforeCancel + 1);
    XCTAssertEqualObjects(self.proxy.text, @"host");
}

- (void)testSensitiveTransitionStopsHeldDeleteAndOrdinaryInputResumes {
    [self.proxy.text setString:@"abcdef"];
    [self.controller setValue:@YES forKey:@"disableIMEInSensitive"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    XCTAssertEqualObjects(self.proxy.text, @"abcde");
    self.proxy.secureTextEntry = YES;
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"abcde");
    XCTAssertNil([self.controller valueForKey:@"deleteRepeatTimer"]);
    [self.controller textDidChange:nil];
    self.proxy.secureTextEntry = NO;
    [self.controller textDidChange:nil];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self tapDelete];
    XCTAssertEqualObjects(self.proxy.text, @"abcd");
}

- (void)testSensitiveTraitMatrixMatchesSettingsExplanation {
    NSArray<NSDictionary *> *cases = @[
        @{@"type": [NSNull null], @"protected": @NO},
        @{@"type": UITextContentTypeUsername, @"protected": @NO},
        @{@"type": UITextContentTypeEmailAddress, @"protected": @NO},
        @{@"type": UITextContentTypePassword, @"protected": @YES},
        @{@"type": UITextContentTypeNewPassword, @"protected": @YES},
        @{@"type": UITextContentTypeOneTimeCode, @"protected": @YES},
    ];
    for (NSNumber *master in @[@NO, @YES]) {
        for (NSNumber *optional in @[@NO, @YES]) {
            for (NSDictionary *fixture in cases) {
                FSHFakeDocumentProxy *proxy = [[FSHFakeDocumentProxy alloc] init];
                if (fixture[@"type"] != [NSNull null]) {
                    proxy.textContentType = fixture[@"type"];
                }
                FSHTestInputController *controller = [[FSHTestInputController alloc] init];
                controller.fakeProxy = proxy;
                [controller loadViewIfNeeded];
                [controller setValue:master forKey:@"disableIMEInSensitive"];
                [controller setValue:optional forKey:@"sensitiveIncludeNoPersonalized"];
                FSHKeyboardView *keyboard = [controller valueForKey:@"keyboardView"];
                [controller keyboardView:keyboard didPressKeyCode:0 output:@"a"];
                BOOL blocked = master.boolValue && optional.boolValue && [fixture[@"protected"] boolValue];
                XCTAssertEqualObjects(proxy.text, blocked ? @"" : @"a",
                                      @"master %@ optional %@ content type %@", master, optional, fixture[@"type"]);
            }
            FSHFakeDocumentProxy *secureProxy = [[FSHFakeDocumentProxy alloc] init];
            secureProxy.secureTextEntry = YES;
            FSHTestInputController *secureController = [[FSHTestInputController alloc] init];
            secureController.fakeProxy = secureProxy;
            [secureController loadViewIfNeeded];
            [secureController setValue:master forKey:@"disableIMEInSensitive"];
            [secureController setValue:optional forKey:@"sensitiveIncludeNoPersonalized"];
            [secureController keyboardView:[secureController valueForKey:@"keyboardView"] didPressKeyCode:0 output:@"a"];
            XCTAssertEqualObjects(secureProxy.text, master.boolValue ? @"" : @"a");
        }
    }

    FSHNoContentTypeProxy *missingTrait = [[FSHNoContentTypeProxy alloc] init];
    FSHTestInputController *controller = [[FSHTestInputController alloc] init];
    controller.fakeProxy = missingTrait;
    [controller loadViewIfNeeded];
    [controller setValue:@YES forKey:@"disableIMEInSensitive"];
    [controller setValue:@YES forKey:@"sensitiveIncludeNoPersonalized"];
    [controller keyboardView:[controller valueForKey:@"keyboardView"] didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects(missingTrait.text, @"a");
}

- (void)testSensitiveSettingsLabelsDescribeActualTraitGuard {
    SettingsViewController *settings = [[SettingsViewController alloc] init];
    [settings loadViewIfNeeded];
    UISwitch *master = [settings valueForKey:@"sensitiveSwitch"];
    UISwitch *optional = [settings valueForKey:@"noLearningSwitch"];
    XCTAssertEqualObjects(master.accessibilityLabel, @"安全輸入欄位停用輸入法");
    XCTAssertEqualObjects(optional.accessibilityLabel, @"包含密碼與一次性驗證碼欄位");
    XCTAssertEqual(optional.enabled, master.isOn);
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:settings.view];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if ([view isKindOfClass:[UILabel class]]) {
            [texts addObject:((UILabel *)view).text ?: @""];
        }
    }
    NSString *allText = [texts componentsJoinedByString:@" "];
    XCTAssertTrue([allText containsString:@"無法辨識所有敏感內容"]);
    XCTAssertFalse([allText containsString:@"No Personalized Learning"]);
}

- (void)testCandidateFromPreviousDocumentCannotCommitAfterFocusChange {
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    XCTAssertEqualObjects([self rawBuffer], @"a");
    [self.controller setValue:@[[[FSHCandidate alloc] initWithCode:@"a" value:@"old field"]]
                      forKey:@"candidates"];
    [self.controller setValue:@"old hint" forKey:@"shortestHint"];
    self.proxy.documentIdentifier = [NSUUID UUID];
    [self.controller textDidChange:nil];
    XCTAssertEqualObjects([self rawBuffer], @"");
    XCTAssertEqualObjects([self.controller valueForKey:@"candidates"], @[]);
    XCTAssertEqualObjects([self.controller valueForKey:@"shortestHint"], @"");
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarView:bar didSelectCandidateAtIndex:0];
    XCTAssertEqualObjects(self.proxy.text, @"");

    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"b"];
    [self.controller textDidChange:nil];
    XCTAssertEqualObjects([self rawBuffer], @"b");
}

- (void)testCandidateTapChecksDocumentEvenWithoutHostNotification {
    [self.controller setValue:@1 forKey:@"engineLoadState"];
    [self.controller keyboardView:self.keyboard didPressKeyCode:0 output:@"a"];
    [self.controller setValue:@[[[FSHCandidate alloc] initWithCode:@"a" value:@"old field"]]
                      forKey:@"candidates"];
    self.proxy.documentIdentifier = [NSUUID UUID];
    FSHCandidateBarView *bar = [self.controller valueForKey:@"candidateBar"];
    [self.controller candidateBarView:bar didSelectCandidateAtIndex:0];
    XCTAssertEqualObjects(self.proxy.text, @"");
    XCTAssertEqualObjects([self rawBuffer], @"");
}

- (void)testParserRemovesTrailingCommentButPreservesLiteralHashValue {
    NSString *fixture = @"#jp6 汶\nj03 腕 # non official\na #\nx A#B\n";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.cin", [NSUUID UUID].UUIDString]];
    NSError *error = nil;
    XCTAssertTrue([fixture writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    XCTAssertNil(error);
    NSArray<FSHCandidate *> *entries = [FSHCinParser parseCinAtPath:path error:&error];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    XCTAssertNil(error);
    XCTAssertEqual(entries.count, (NSUInteger)3);
    XCTAssertEqualObjects(entries[0].value, @"腕");
    XCTAssertEqualObjects(entries[1].value, @"#");
    XCTAssertEqualObjects(entries[2].value, @"A#B");
}

- (void)testShippedSpellCorpusDoesNotLeakInlineCommentIntoCandidate {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle bundleForClass:[self class]] error:&error], @"%@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects([engine spellForValue:@"腕"], @"j03");
    NSArray<FSHCandidate *> *candidates = [engine reverseLookupCandidatesForBaseValue:@"腕"];
    XCTAssertTrue(candidates.count > 0);
    BOOL foundWrist = NO;
    for (FSHCandidate *candidate in candidates) {
        foundWrist |= [candidate.value isEqualToString:@"腕"];
        XCTAssertEqual([candidate.value rangeOfString:@"non official"].location, NSNotFound);
    }
    XCTAssertTrue(foundWrist);
}

- (void)testAllPronunciationsContributeStableDeduplicatedHomophones {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle bundleForClass:[self class]] error:&error]);
    XCTAssertNil(error);
    NSArray<NSString *> *walkingReadings = @[@"c;4", @"c;6", @"vu/4", @"vu/6"];
    NSArray<NSString *> *musicReadings = @[@"m,4", @"ul4", @"xk4", @"xl4"];
    XCTAssertEqualObjects([engine spellsForValue:@"行"], walkingReadings);
    XCTAssertEqualObjects([engine spellsForValue:@"樂"], musicReadings);
    XCTAssertEqualObjects([engine spellForValue:@"行"], walkingReadings.firstObject);
    XCTAssertEqualObjects([engine spellForValue:@"樂"], musicReadings.firstObject);

    for (NSString *base in @[@"行", @"樂"]) {
        NSArray<NSString *> *readings = [engine spellsForValue:base];
        NSArray<FSHCandidate *> *candidates = [engine reverseLookupCandidatesForBaseValue:base];
        NSMutableSet<NSString *> *seenValues = [NSMutableSet set];
        NSMutableArray<NSString *> *seenReadings = [NSMutableArray array];
        for (FSHCandidate *candidate in candidates) {
            XCTAssertFalse([seenValues containsObject:candidate.value], @"Duplicate %@ for %@", candidate.value, base);
            [seenValues addObject:candidate.value];
            if (![seenReadings containsObject:candidate.code]) {
                [seenReadings addObject:candidate.code];
            }
        }
        XCTAssertEqualObjects(seenReadings, readings);
        XCTAssertTrue([seenValues containsObject:base]);
    }
    NSArray<FSHCandidate *> *walking = [engine reverseLookupCandidatesForBaseValue:@"行"];
    XCTAssertTrue(walking.count >= 4);
    XCTAssertEqualObjects([walking[0] value], @"行");
    XCTAssertEqualObjects([walking[1] value], @"沆");
    XCTAssertEqualObjects([walking[2] value], @"桁");
    XCTAssertEqualObjects([walking[3] value], @"苀");
}

- (void)testExactDuplicateCodesAreRemovedWithoutDroppingAlternativeCodes {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle bundleForClass:[self class]] error:&error]);
    XCTAssertNil(error);
    NSDictionary<NSString *, NSArray<FSHCandidate *> *> *buckets = [engine valueForKey:@"firstCharIndex"];
    NSUInteger indexedEntries = 0;
    for (NSArray<FSHCandidate *> *bucket in buckets.allValues) {
        indexedEntries += bucket.count;
    }
    XCTAssertEqual(indexedEntries, (NSUInteger)26286); // 26,288 corpus rows, two exact duplicates.

    NSDictionary<NSString *, NSNumber *> *expectedPrefixCounts = @{@",": @663, @".": @20};
    NSDictionary<NSString *, NSString *> *expectedExactValues = @{@",": @"，", @".": @"。"};
    for (NSString *code in @[@",", @"."]) {
        NSUInteger exactCount = 0;
        NSArray<FSHCandidate *> *matches = [engine prefixCandidatesForCode:code exactCount:&exactCount];
        XCTAssertEqual(exactCount, (NSUInteger)1);
        XCTAssertEqual(matches.count, expectedPrefixCounts[code].unsignedIntegerValue);
        XCTAssertEqualObjects(matches.firstObject.code, code);
        XCTAssertEqualObjects(matches.firstObject.value, expectedExactValues[code]);
    }
    for (NSString *code in @[@"ci", @"cj", @"cjv"]) {
        NSArray<FSHCandidate *> *matches = [engine prefixCandidatesForCode:code exactCount:NULL];
        BOOL found = NO;
        for (FSHCandidate *candidate in matches) {
            found |= [candidate.code isEqualToString:code] && [candidate.value isEqualToString:@"中"];
        }
        XCTAssertTrue(found, @"Missing alternate code %@", code);
    }
}

- (void)testAllShiamyCodesForCharacterPreserveShortestAndAlternatives {
    FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
    NSError *error = nil;
    XCTAssertTrue([engine loadFromBundle:[NSBundle bundleForClass:[self class]] error:&error], @"%@", error);
    XCTAssertEqualObjects([engine allCodesForValue:@"行"], (@[@"mv", @"miri"]));
    XCTAssertEqualObjects([engine allCodesForValue:@"中"], (@[@"ci", @"cj", @"cjv"]));
    XCTAssertEqualObjects([engine shortestCodeForValue:@"行"], @"mv");
    XCTAssertEqualObjects([engine shortestCodeForValue:@"中"], @"ci");
    XCTAssertEqualObjects([engine allCodesForValue:@"😀"], @[]);

    FSHFixtureEngine *fixture = [[FSHFixtureEngine alloc] init];
    fixture.mainPath = @"/missing-main.cin";
    fixture.spellPath = @"/missing-spell.cin";
    XCTAssertFalse([fixture loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertEqualObjects([fixture allCodesForValue:@"中"], @[]);
}

- (void)testHostCodeSearchLoadsOfflineAndFormatsMultipleCharacters {
    CodeSearchViewController *search = [[CodeSearchViewController alloc] init];
    [search loadViewIfNeeded];
    UITextField *queryField = [search valueForKey:@"queryField"];
    UILabel *resultsView = [search valueForKey:@"resultsLabel"];
    XCTAssertEqualObjects(queryField.accessibilityIdentifier, @"codeSearch.query");
    XCTAssertEqualObjects(resultsView.accessibilityIdentifier, @"codeSearch.results");
    queryField.text = @"行中😀";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    NSPredicate *loadedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"engine"] != nil || [search valueForKey:@"loadErrorDescription"] != nil;
    }];
    XCTNSPredicateExpectation *completed = [[XCTNSPredicateExpectation alloc] initWithPredicate:loadedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[completed] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertNil([search valueForKey:@"loadErrorDescription"]);
    XCTAssertEqualObjects(resultsView.text, @"行：最短 MV；其他 MIRI\n中：最短 CI；其他 CJ、CJV\n😀：查無字碼");
    queryField.text = @"行 中";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(resultsView.text, @"行：最短 MV；其他 MIRI\n中：最短 CI；其他 CJ、CJV");
    queryField.text = @"";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(resultsView.text, @"輸入一個或多個字開始查詢。");
}

- (void)testCodeSearchFailureRetryUsesLatestQueryAndKeepsInput {
    FSHCodeSearchFixtureController *search = [[FSHCodeSearchFixtureController alloc] init];
    search.failNextLoad = YES;
    [search loadViewIfNeeded];
    UITextField *queryField = [search valueForKey:@"queryField"];
    UILabel *resultsLabel = [search valueForKey:@"resultsLabel"];
    queryField.text = @"行";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    NSPredicate *failedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"loadErrorDescription"] != nil;
    }];
    XCTNSPredicateExpectation *failed = [[XCTNSPredicateExpectation alloc] initWithPredicate:failedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[failed] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertEqualObjects(queryField.text, @"行");
    XCTAssertTrue([resultsLabel.text hasPrefix:@"字庫載入失敗"]);
    UIBarButtonItem *retry = search.navigationItem.rightBarButtonItem;
    XCTAssertNotNil(retry);
    search.failNextLoad = NO;
    XCTAssertTrue([[UIApplication sharedApplication] sendAction:retry.action to:retry.target from:retry forEvent:nil]);
    queryField.text = @"中";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    NSPredicate *loadedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"engine"] != nil;
    }];
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc] initWithPredicate:loadedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[loaded] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertEqualObjects(queryField.text, @"中");
    XCTAssertEqualObjects(resultsLabel.text, @"中：最短 CI；其他 CJ、CJV");
    XCTAssertNil(search.navigationItem.rightBarButtonItem);
}

- (void)testCodeSearchCapsQueryAt64ComposedCharacters {
    CodeSearchViewController *search = [[CodeSearchViewController alloc] init];
    [search loadViewIfNeeded];
    NSPredicate *loadedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"engine"] != nil;
    }];
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc] initWithPredicate:loadedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[loaded] timeout:20.0], XCTWaiterResultCompleted);
    UITextField *queryField = [search valueForKey:@"queryField"];
    UILabel *resultsLabel = [search valueForKey:@"resultsLabel"];
    NSMutableString *query = [NSMutableString string];
    for (NSUInteger index = 0; index < 64; index++) {
        [query appendString:@"😀"];
    }
    queryField.text = query;
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqual([resultsLabel.text componentsSeparatedByString:@"\n"].count, (NSUInteger)64);
    XCTAssertFalse([resultsLabel.text containsString:@"最多查詢"]);
    [query appendString:@"😀"];
    queryField.text = query;
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    NSArray<NSString *> *lines = [resultsLabel.text componentsSeparatedByString:@"\n"];
    XCTAssertEqual(lines.count, (NSUInteger)65);
    XCTAssertEqualObjects(lines.lastObject, @"一次最多查詢 64 個字，請縮短輸入。");
}

- (void)testHostCodeSearchRendersInAttachedWindow {
    CodeSearchViewController *search = [[CodeSearchViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:search];
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    XCTAssertNotNil(activeScene);
    if (!activeScene) {
        return;
    }
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *sceneWindow in activeScene.windows) {
        if (sceneWindow.isKeyWindow) {
            oldKeyWindow = sceneWindow;
            break;
        }
    }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:activeScene];
    window.frame = activeScene.coordinateSpace.bounds;
    window.rootViewController = navigation;
    [window makeKeyAndVisible];
    [search loadViewIfNeeded];
    XCTAssertTrue([self waitForView:search.view toAttachToWindow:window],
                  @"The code-search view should attach to its scene-backed window");
    XCTAssertEqual(search.view.window, window);
    NSPredicate *loadedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"engine"] != nil || [search valueForKey:@"loadErrorDescription"] != nil;
    }];
    XCTNSPredicateExpectation *completed = [[XCTNSPredicateExpectation alloc] initWithPredicate:loadedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[completed] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertNil([search valueForKey:@"loadErrorDescription"]);
    UITextField *queryField = [search valueForKey:@"queryField"];
    UILabel *resultsView = [search valueForKey:@"resultsLabel"];
    queryField.text = @"行中";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    [window layoutIfNeeded];
    XCTAssertGreaterThan(queryField.bounds.size.height, 0.0);
    XCTAssertFalse(CGRectIsEmpty(resultsView.frame));
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
        window.overrideUserInterfaceStyle = style.integerValue;
        [window layoutIfNeeded];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
        __block BOOL rendered = NO;
        UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            rendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        XCTAssertTrue(rendered);
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
        attachment.name = style.integerValue == UIUserInterfaceStyleLight ? @"Host code search - light" : @"Host code search - dark";
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    }
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    XCTAssertTrue([queryField becomeFirstResponder]);
    NSPredicate *keyboardVisiblePredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        CGRect keyboardFrame = search.view.keyboardLayoutGuide.layoutFrame;
        return keyboardFrame.size.height > search.view.safeAreaInsets.bottom + 100.0 &&
               CGRectGetMinY(keyboardFrame) < CGRectGetHeight(search.view.bounds) - 100.0;
    }];
    XCTNSPredicateExpectation *keyboardVisible = [[XCTNSPredicateExpectation alloc] initWithPredicate:keyboardVisiblePredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[keyboardVisible] timeout:10.0], XCTWaiterResultCompleted,
                   @"The scene-backed test must actually observe keyboard occlusion");
    [window layoutIfNeeded];
    UIScrollView *scrollView = [search valueForKey:@"scrollView"];
    CGRect fullSceneQuery = [queryField convertRect:queryField.bounds toView:scrollView];
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(fullSceneQuery), scrollView.contentOffset.y - 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(fullSceneQuery),
                             scrollView.contentOffset.y + scrollView.bounds.size.height + 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(scrollView.frame),
                             CGRectGetMinY(search.view.keyboardLayoutGuide.layoutFrame) + 1.0);
    UIGraphicsImageRenderer *focusedRenderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    __block BOOL focusedRendered = NO;
    UIImage *focusedSnapshot = [focusedRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        focusedRendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    XCTAssertTrue(focusedRendered);
    XCTAttachment *focusedAttachment = [XCTAttachment attachmentWithImage:focusedSnapshot];
    focusedAttachment.name = @"Host search - focused with keyboard occlusion";
    focusedAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:focusedAttachment];
    [queryField resignFirstResponder];

    UITraitCollection *largeText = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityMedium];
    [navigation setOverrideTraitCollection:largeText forChildViewController:search];
    window.frame = CGRectMake(0.0, 0.0, 320.0, 390.0);
    XCTAssertTrue([queryField becomeFirstResponder]);
    NSPredicate *compactReadyPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        [window layoutIfNeeded];
        CGRect query = [queryField convertRect:queryField.bounds toView:scrollView];
        CGFloat top = scrollView.contentOffset.y;
        CGFloat bottom = top + CGRectGetHeight(scrollView.bounds);
        return search.view.window == window && queryField.isFirstResponder &&
               fabs(CGRectGetWidth(window.bounds) - 320.0) < 0.5 &&
               fabs(CGRectGetHeight(window.bounds) - 390.0) < 0.5 &&
               [search.traitCollection.preferredContentSizeCategory isEqualToString:UIContentSizeCategoryAccessibilityMedium] &&
               !CGRectIsEmpty(queryField.bounds) && !CGRectIsEmpty(scrollView.bounds) &&
               CGRectGetMinY(query) >= top - 1.0 && CGRectGetMaxY(query) <= bottom + 1.0;
    }];
    XCTNSPredicateExpectation *compactReady = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:compactReadyPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[compactReady] timeout:10.0], XCTWaiterResultCompleted,
                   @"Compact scene must attach, adopt its trait, and show the focused field before capture");
    [window layoutIfNeeded];
    CGRect queryInScroll = [queryField convertRect:queryField.bounds toView:scrollView];
    CGFloat visibleTop = scrollView.contentOffset.y;
    CGFloat visibleBottom = visibleTop + scrollView.bounds.size.height;
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(queryInScroll), visibleTop - 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(queryInScroll), visibleBottom + 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(scrollView.frame),
                             CGRectGetMinY(search.view.keyboardLayoutGuide.layoutFrame) + 1.0);
    UIGraphicsImageRenderer *compactRenderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    __block BOOL compactRendered = NO;
    UIImage *compactSnapshot = [compactRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        compactRendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    XCTAssertTrue(compactRendered);
    XCTAttachment *compactAttachment = [XCTAttachment attachmentWithImage:compactSnapshot];
    compactAttachment.name = @"Host search - focused compact window and accessibility text";
    compactAttachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:compactAttachment];
    [queryField resignFirstResponder];
    [window endEditing:YES];
    window.hidden = YES;
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testHostCodeSearchDoesNotChangeTestInputFields {
    ViewController *panel = [[ViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:panel];
    [panel loadViewIfNeeded];
    UITextField *singleLine = [panel valueForKey:@"singleLineField"];
    UITextView *multiLine = [panel valueForKey:@"multiLineView"];
    singleLine.text = @"原有單行文字";
    multiLine.text = @"原有多行文字";
    [panel openCodeSearch];
    XCTAssertTrue([navigation.topViewController isKindOfClass:[CodeSearchViewController class]]);
    CodeSearchViewController *search = (CodeSearchViewController *)navigation.topViewController;
    [search loadViewIfNeeded];
    UITextField *queryField = [search valueForKey:@"queryField"];
    queryField.text = @"行";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(singleLine.text, @"原有單行文字");
    XCTAssertEqualObjects(multiLine.text, @"原有多行文字");
}

- (void)testHostPanelScrollsFocusedFieldsAboveSceneBackedKeyboard {
    ViewController *panel = [[ViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:panel];
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    XCTAssertNotNil(activeScene);
    if (!activeScene) return;
    UIWindow *oldKeyWindow = nil;
    for (UIWindow *sceneWindow in activeScene.windows) {
        if (sceneWindow.isKeyWindow) oldKeyWindow = sceneWindow;
    }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:activeScene];
    window.frame = activeScene.coordinateSpace.bounds;
    window.rootViewController = navigation;
    [window makeKeyAndVisible];
    [panel loadViewIfNeeded];
    XCTAssertTrue([self waitForView:panel.view toAttachToWindow:window]);
    XCTAssertEqual(panel.view.window, window);
    UITextField *single = [panel valueForKey:@"singleLineField"];
    UITextView *multi = [panel valueForKey:@"multiLineView"];
    UIScrollView *scroll = [panel valueForKey:@"scrollView"];
    single.text = @"保留單行";
    multi.text = @"保留多行";
    XCTAssertTrue([single becomeFirstResponder]);
    NSPredicate *visibleKeyboard = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        CGRect keyboardFrame = panel.view.keyboardLayoutGuide.layoutFrame;
        return keyboardFrame.size.height > panel.view.safeAreaInsets.bottom + 100.0 &&
               CGRectGetMinY(keyboardFrame) < CGRectGetHeight(panel.view.bounds) - 100.0;
    }];
    XCTNSPredicateExpectation *keyboardVisible = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:visibleKeyboard object:panel];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[keyboardVisible] timeout:10.0], XCTWaiterResultCompleted);
    [window layoutIfNeeded];
    CGRect singleRect = [single convertRect:single.bounds toView:scroll];
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(singleRect), scroll.contentOffset.y - 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(singleRect), scroll.contentOffset.y + scroll.bounds.size.height + 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(scroll.frame),
                             CGRectGetMinY(panel.view.keyboardLayoutGuide.layoutFrame) + 1.0);
    XCTAttachment *singleSnapshot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
    singleSnapshot.name = @"Host panel focused single-line field above keyboard";
    singleSnapshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:singleSnapshot];

    XCTAssertFalse([panel textFieldShouldReturn:single]);
    XCTAssertTrue(multi.isFirstResponder);
    [window layoutIfNeeded];
    NSPredicate *caretAvailable = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return multi.selectedTextRange.end != nil;
    }];
    XCTNSPredicateExpectation *caretReady = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:caretAvailable object:multi];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[caretReady] timeout:5.0], XCTWaiterResultCompleted);
    UITextPosition *caret = multi.selectedTextRange.end;
    XCTAssertNotNil(caret);
    CGRect caretRect = caret ? [multi convertRect:[multi caretRectForPosition:caret] toView:scroll] : CGRectZero;
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(caretRect), scroll.contentOffset.y - 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(caretRect), scroll.contentOffset.y + scroll.bounds.size.height + 1.0);
    XCTAssertEqualObjects(single.text, @"保留單行");
    XCTAssertEqualObjects(multi.text, @"保留多行");
    XCTAttachment *multilineSnapshot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
    multilineSnapshot.name = @"Host panel focused multiline caret above keyboard";
    multilineSnapshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:multilineSnapshot];

    UIStackView *stack = nil;
    for (UIView *child in scroll.subviews) {
        if ([child isKindOfClass:UIStackView.class]) {
            stack = (UIStackView *)child;
            break;
        }
    }
    XCTAssertNotNil(stack);
    UIButton *settingsButton = nil;
    UIButton *clearButton = nil;
    for (UIView *child in stack.arrangedSubviews) {
        if ([child.accessibilityIdentifier isEqualToString:@"smoke.appSettings"]) settingsButton = (UIButton *)child;
        if ([child.accessibilityIdentifier isEqualToString:@"smoke.clearFields"]) clearButton = (UIButton *)child;
    }
    XCTAssertNotNil(settingsButton);
    XCTAssertNotNil(clearButton);
    if (settingsButton && clearButton) {
        for (UIButton *action in @[settingsButton, clearButton]) {
            CGRect actionRect = [action convertRect:action.bounds toView:scroll];
            [scroll scrollRectToVisible:actionRect animated:NO];
            CGFloat chosenOffset = scroll.contentOffset.y;
            [window layoutIfNeeded];
            XCTAssertEqualWithAccuracy(scroll.contentOffset.y, chosenOffset, 0.5,
                                       @"Focused input should not fight manual scrolling to an action");
            XCTAssertGreaterThanOrEqual(CGRectGetMinY(actionRect), scroll.contentOffset.y - 1.0);
            XCTAssertLessThanOrEqual(CGRectGetMaxY(actionRect), scroll.contentOffset.y + scroll.bounds.size.height + 1.0);
            XCTAttachment *actionSnapshot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
            actionSnapshot.name = [NSString stringWithFormat:@"Host panel focused input with %@ reachable",
                                   action.accessibilityIdentifier];
            actionSnapshot.lifetime = XCTAttachmentLifetimeKeepAlways;
            [self addAttachment:actionSnapshot];
        }
    }
    XCTAssertEqualObjects(single.text, @"保留單行");
    XCTAssertEqualObjects(multi.text, @"保留多行");

    [single becomeFirstResponder];
    [window layoutIfNeeded];
    singleRect = [single convertRect:single.bounds toView:scroll];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(singleRect), scroll.contentOffset.y + scroll.bounds.size.height + 1.0);

    [multi becomeFirstResponder];
    window.frame = CGRectMake(0, 0, 320, 390);
    // Resizing this window within a portrait scene does not rotate the
    // simulator keyboard. Validate compact-window caret/layout geometry here;
    // the installed UI rotation test must prove real keyboard occlusion.
    NSPredicate *compactCaretVisible = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        [window layoutIfNeeded];
        CGRect guide = panel.view.keyboardLayoutGuide.layoutFrame;
        if (fabs(CGRectGetWidth(window.bounds) - 320.0) > 0.5 ||
            fabs(CGRectGetHeight(window.bounds) - 390.0) > 0.5 ||
            fabs(CGRectGetWidth(panel.view.bounds) - 320.0) > 0.5 ||
            CGRectGetHeight(panel.view.bounds) > 391.0) return NO;
        UITextPosition *currentCaret = multi.selectedTextRange.end;
        if (!multi.isFirstResponder || !currentCaret || CGRectIsEmpty(scroll.bounds)) return NO;
        CGRect currentRect = [multi convertRect:[multi caretRectForPosition:currentCaret] toView:scroll];
        return CGRectGetMinY(currentRect) >= scroll.contentOffset.y - 1.0 &&
               CGRectGetMaxY(currentRect) <= scroll.contentOffset.y + CGRectGetHeight(scroll.bounds) + 1.0 &&
               CGRectGetMaxY(scroll.frame) <= CGRectGetMinY(guide) + 1.0;
    }];
    XCTNSPredicateExpectation *compactReady = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:compactCaretVisible object:multi];
    XCTWaiterResult compactResult = [XCTWaiter waitForExpectations:@[compactReady] timeout:8.0];
    XCTAttachment *compactShot = [XCTAttachment attachmentWithImage:[self snapshotOfWindow:window]];
    compactShot.name = @"Synthetic compact host-window caret layout";
    compactShot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:compactShot];
    caret = multi.selectedTextRange.end;
    XCTAssertNotNil(caret);
    caretRect = caret ? [multi convertRect:[multi caretRectForPosition:caret] toView:scroll] : CGRectZero;
    XCTAttachment *compactGeometry = [XCTAttachment attachmentWithString:
        [NSString stringWithFormat:@"caret=%@ viewport=%@ offset=%@ keyboardGuide=%@ window=%@ panel=%@ responder=%d",
         NSStringFromCGRect(caretRect), NSStringFromCGRect(scroll.bounds),
         NSStringFromCGPoint(scroll.contentOffset),
         NSStringFromCGRect(panel.view.keyboardLayoutGuide.layoutFrame), NSStringFromCGRect(window.bounds),
         NSStringFromCGRect(panel.view.bounds), multi.isFirstResponder]];
    compactGeometry.name = @"Synthetic compact host-window caret and keyboard-guide geometry";
    compactGeometry.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:compactGeometry];
    XCTAssertEqual(compactResult, XCTWaiterResultCompleted,
                   @"Focused caret must settle inside the actual compact viewport");
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(caretRect), scroll.contentOffset.y - 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(caretRect), scroll.contentOffset.y + scroll.bounds.size.height + 1.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(scroll.frame),
                             CGRectGetMinY(panel.view.keyboardLayoutGuide.layoutFrame) + 1.0);
    XCTAssertEqualObjects(single.text, @"保留單行");
    XCTAssertEqualObjects(multi.text, @"保留多行");

    [window endEditing:YES];
    window.hidden = YES;
    [oldKeyWindow makeKeyAndVisible];
}

- (void)testEngineRequiresBothReadableNonemptyDictionaries {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:directory
                                             withIntermediateDirectories:YES attributes:nil error:&error]);
    NSString *mainPath = [directory stringByAppendingPathComponent:@"main.cin"];
    NSString *spellPath = [directory stringByAppendingPathComponent:@"spell.cin"];
    XCTAssertTrue([@"a 中\n" writeToFile:mainPath atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    XCTAssertTrue([@"z 中\n" writeToFile:spellPath atomically:YES encoding:NSUTF8StringEncoding error:&error]);

    FSHFixtureEngine *engine = [[FSHFixtureEngine alloc] init];
    engine.mainPath = mainPath;
    engine.spellPath = spellPath;
    XCTAssertTrue([engine loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertTrue(engine.ready);
    XCTAssertEqual([engine prefixCandidatesForCode:@"a" exactCount:NULL].count, (NSUInteger)1);

    engine.spellPath = nil;
    error = nil;
    XCTAssertFalse([engine loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse(engine.ready);
    XCTAssertEqual([engine prefixCandidatesForCode:@"a" exactCount:NULL].count, (NSUInteger)0);
    XCTAssertEqual([engine reverseLookupCandidatesForBaseValue:@"中"].count, (NSUInteger)0);
    XCTAssertNil([engine shortestCodeForValue:@"中"]);
    XCTAssertNil([engine spellForValue:@"中"]);
    XCTAssertEqual([engine spellsForValue:@"中"].count, (NSUInteger)0);

    engine.spellPath = [directory stringByAppendingPathComponent:@"missing.cin"];
    error = nil;
    XCTAssertFalse([engine loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse(engine.ready);

    engine.spellPath = spellPath;
    XCTAssertTrue([@"" writeToFile:mainPath atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    error = nil;
    XCTAssertFalse([engine loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse(engine.ready);

    XCTAssertTrue([@"a 中\n" writeToFile:mainPath atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    XCTAssertTrue([@"" writeToFile:spellPath atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    error = nil;
    XCTAssertFalse([engine loadFromBundle:[NSBundle mainBundle] error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse(engine.ready);
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

@end
