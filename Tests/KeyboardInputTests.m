#import <XCTest/XCTest.h>
#import "InputViewController.h"
#import "FSHKeyboardView.h"
#import "FSHKeyButton.h"
#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"
#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"

@interface InputViewController (KeyboardInputTests)
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView;
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didPressKeyCode:(NSInteger)keyCode output:(NSString *)output;
- (void)triggerReverseLookupWithBaseIndex:(NSUInteger)index;
- (void)updateHintForCommittedValue:(NSString *)value typedCodeLength:(NSUInteger)typedCodeLength isReverse:(BOOL)isReverse;
@end

@interface FSHTestEngine : FSHShiamyEngine
@property (nonatomic, assign) NSUInteger reverseCallCount;
@end

@implementation FSHTestEngine
- (NSArray<FSHCandidate *> *)reverseLookupCandidatesForBaseValue:(NSString *)baseValue {
    self.reverseCallCount++;
    return @[[[FSHCandidate alloc] initWithCode:@"reading" value:baseValue]];
}
- (NSString *)shortestCodeForValue:(NSString *)value {
    return @"a";
}
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
    self.keyboard = [self.controller valueForKey:@"keyboardView"];
    self.deleteButton = [self.keyboard valueForKey:@"deleteButton"];
    XCTAssertNotNil(self.deleteButton);
}

- (void)tearDown {
    [self.controller viewWillDisappear:NO];
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
    [self.controller viewWillDisappear:NO];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"ab");

    [self.proxy.text setString:@"abc"];
    [self.deleteButton sendActionsForControlEvents:UIControlEventTouchDown];
    [self.keyboard reloadKeys];
    [self waitForSeconds:0.55];
    XCTAssertEqualObjects(self.proxy.text, @"ab");
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
