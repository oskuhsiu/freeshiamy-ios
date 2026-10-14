#import <XCTest/XCTest.h>
#import "InputViewController.h"
#import "FSHKeyboardView.h"
#import "FSHKeyButton.h"
#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"
#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"
#import "CodeSearchViewController.h"
#import "ViewController.h"

@interface ViewController (CodeSearchTests)
- (void)openCodeSearch;
@end

@class FSHFakeDocumentProxy;

@interface InputViewController (KeyboardInputTests)
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView;
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didPressKeyCode:(NSInteger)keyCode output:(NSString *)output;
- (void)triggerReverseLookupWithBaseIndex:(NSUInteger)index;
- (void)updateHintForCommittedValue:(NSString *)value typedCodeLength:(NSUInteger)typedCodeLength isReverse:(BOOL)isReverse;
- (NSUInteger)beginEngineLoad;
- (void)refreshCandidatesAndUI;
- (void)finishEngineLoad:(FSHShiamyEngine *)loadedEngine loaded:(BOOL)loaded error:(NSError *)error generation:(NSUInteger)generation;
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

@interface FSHFakeDocumentProxy : NSObject
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, assign, getter=isSecureTextEntry) BOOL secureTextEntry;
@property (nonatomic, copy) NSUUID *documentIdentifier;
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

- (void)waitForSeconds:(NSTimeInterval)seconds {
    XCTestExpectation *elapsed = [self expectationWithDescription:@"Timer elapsed"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [elapsed fulfill];
    });
    [self waitForExpectations:@[elapsed] timeout:seconds + 1.0];
}

- (void)testTapDeletesHostExactlyOnce {
    [self.proxy.text setString:@"abc"];
    [self tapDelete];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
    XCTAssertNil([self.controller valueForKey:@"deleteRepeatTimer"]);
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

    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeGlobe output:nil];
    XCTAssertEqual(self.controller.inputModeAdvanceCount, (NSUInteger)1);
    [self.controller keyboardView:self.keyboard didPressKeyCode:FSHKeyCodeCancel output:nil];
    XCTAssertEqual(self.controller.dismissCount, (NSUInteger)1);
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
    UITextView *resultsView = [search valueForKey:@"resultsView"];
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
    queryField.text = @"";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    XCTAssertEqualObjects(resultsView.text, @"輸入一個或多個字開始查詢。");
}

- (void)testHostCodeSearchRendersInAttachedWindow {
    CodeSearchViewController *search = [[CodeSearchViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:search];
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.rootViewController = navigation;
    [window makeKeyAndVisible];
    [search loadViewIfNeeded];
    NSPredicate *loadedPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [search valueForKey:@"engine"] != nil || [search valueForKey:@"loadErrorDescription"] != nil;
    }];
    XCTNSPredicateExpectation *completed = [[XCTNSPredicateExpectation alloc] initWithPredicate:loadedPredicate object:search];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[completed] timeout:20.0], XCTWaiterResultCompleted);
    XCTAssertNil([search valueForKey:@"loadErrorDescription"]);
    UITextField *queryField = [search valueForKey:@"queryField"];
    UITextView *resultsView = [search valueForKey:@"resultsView"];
    queryField.text = @"行中";
    [queryField sendActionsForControlEvents:UIControlEventEditingChanged];
    [window layoutIfNeeded];
    XCTAssertFalse(CGRectIsEmpty(resultsView.frame));
    XCTAssertTrue(CGRectContainsRect(window.bounds, [resultsView convertRect:resultsView.bounds toView:window]));
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
        window.overrideUserInterfaceStyle = style.integerValue;
        [window layoutIfNeeded];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
        UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot];
        attachment.name = style.integerValue == UIUserInterfaceStyleLight ? @"Host code search - light" : @"Host code search - dark";
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
        [self addAttachment:attachment];
    }
    window.hidden = YES;
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
