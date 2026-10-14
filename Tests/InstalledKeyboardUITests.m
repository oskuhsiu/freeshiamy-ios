#import <XCTest/XCTest.h>

// Black-box test: this bundle contains no keyboard production classes and never
// calls the extension controller or a fake text proxy. It drives installed UI.
@interface InstalledKeyboardUITests : XCTestCase
@end

@implementation InstalledKeyboardUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
}

- (void)capture:(NSString *)stage application:(XCUIApplication *)application {
    [XCTContext runActivityNamed:stage block:^(id<XCTActivity> activity) {
        XCTAttachment *screen = [XCTAttachment attachmentWithScreenshot:[XCUIScreen mainScreen].screenshot];
        screen.name = [stage stringByAppendingString:@" — full screen"];
        screen.lifetime = XCTAttachmentLifetimeKeepAlways;
        [activity addAttachment:screen];
        XCTAttachment *tree = [XCTAttachment attachmentWithString:application.debugDescription];
        tree.name = [stage stringByAppendingString:@" — accessibility hierarchy"];
        tree.lifetime = XCTAttachmentLifetimeKeepAlways;
        [activity addAttachment:tree];
    }];
}

- (XCUIElement *)requireUnique:(XCUIElementQuery *)query
                         stage:(NSString *)stage
                   application:(XCUIApplication *)application {
    XCUIElement *first = query.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return query.count == 1 && first.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
                                             initWithPredicate:ready object:first];
    BOOL appeared = ([XCTWaiter waitForExpectations:@[expectation] timeout:20.0] == XCTWaiterResultCompleted);
    if (!appeared) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:application];
        XCTFail(@"%@: expected one visible, hittable control; found %lu", stage, (unsigned long)query.count);
        return nil;
    }
    [self capture:stage application:application];
    return first;
}

- (XCUIElement *)settingsControl:(XCUIElementQuery *)query
                          stage:(NSString *)stage
                    application:(XCUIApplication *)settings {
    XCUIElement *first = query.firstMatch;
    // Settings lists are scrollable, and rows vary by simulator screen size.
    // Walk the public UI rather than changing Settings preferences directly.
    for (NSUInteger scroll = 0; scroll <= 8; scroll++) {
        NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return query.count == 1 && first.isHittable;
        }];
        XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
                                                 initWithPredicate:ready object:first];
        if ([XCTWaiter waitForExpectations:@[expectation] timeout:2.0] == XCTWaiterResultCompleted) {
            [self capture:stage application:settings];
            return first;
        }
        if (scroll < 8) [settings swipeUp];
    }
    [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:settings];
    XCTFail(@"%@: expected one visible, hittable Settings control; found %lu", stage, (unsigned long)query.count);
    return nil;
}

- (XCUIElement *)settingsRowWithLabels:(NSArray<NSString *> *)labels
                           identifier:(NSString *)identifier
                                stage:(NSString *)stage
                          application:(XCUIApplication *)settings {
    NSPredicate *label = [NSPredicate predicateWithFormat:@"label IN %@", labels];
    // Settings sometimes puts the semantic label on a button inside an
    // unlabeled cell (as it does for General on iOS 26.2). Restrict button
    // matches to rows so a navigation-bar button cannot masquerade as one.
    XCUIElementQuery *buttons = identifier
        ? [settings.buttons matchingIdentifier:identifier]
        : [settings.cells.buttons matchingPredicate:label];
    XCUIElementQuery *cells = identifier ? nil : [settings.cells matchingPredicate:label];
    for (NSUInteger scroll = 0; scroll <= 8; scroll++) {
        __block XCUIElement *target = nil;
        NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            NSUInteger buttonCount = buttons.count;
            NSUInteger cellCount = cells ? cells.count : 0;
            if (buttonCount > 1 || cellCount > 1) return NO;
            XCUIElement *button = buttonCount == 1 ? buttons.firstMatch : nil;
            XCUIElement *cell = cellCount == 1 ? cells.firstMatch : nil;
            // If both expose the label, they must be the same physical row.
            if (button && cell && !CGRectIntersectsRect(button.frame, cell.frame)) return NO;
            target = button.isHittable ? button : (cell.isHittable ? cell : nil);
            return target != nil;
        }];
        XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
                                                 initWithPredicate:ready object:settings];
        if ([XCTWaiter waitForExpectations:@[expectation] timeout:2.0] == XCTWaiterResultCompleted) {
            [self capture:stage application:settings];
            return target;
        }
        if (scroll < 8) [settings swipeUp];
    }
    [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:settings];
    XCTFail(@"%@: expected one visible, hittable semantic row; found %lu buttons and %lu cells",
            stage, (unsigned long)buttons.count, (unsigned long)(cells ? cells.count : 0));
    return nil;
}

- (BOOL)tapSettingsRow:(NSString *)title inSettings:(XCUIApplication *)settings {
    NSString *identifier = [title isEqualToString:@"General"] ? @"com.apple.settings.general" : nil;
    XCUIElement *row = [self settingsRowWithLabels:@[title] identifier:identifier
                                            stage:[@"Settings row: " stringByAppendingString:title]
                                      application:settings];
    if (!row) return NO;
    [row tap];
    [self capture:[@"Opened Settings row: " stringByAppendingString:title] application:settings];
    return YES;
}

- (XCUIElement *)keyboardControl:(NSString *)identifier application:(XCUIApplication *)application {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier == %@", identifier];
    return [self requireUnique:[application.buttons matchingPredicate:predicate]
                         stage:[@"Extension control: " stringByAppendingString:identifier]
                   application:application];
}

- (BOOL)tapKeyboardControl:(NSString *)identifier application:(XCUIApplication *)application {
    XCUIElement *control = [self keyboardControl:identifier application:application];
    if (!control) return NO;
    [control tap];
    return YES;
}

- (BOOL)expectValue:(NSString *)expected of:(XCUIElement *)element
              stage:(NSString *)stage application:(XCUIApplication *)application {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value == %@", expected];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:element];
    XCTWaiterResult waitResult = [XCTWaiter waitForExpectations:@[expectation] timeout:15.0];
    if (waitResult != XCTWaiterResultCompleted || ![element.value isEqual:expected]) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:application];
        XCTFail(@"%@: expected value '%@', observed '%@'", stage, expected, element.value);
        return NO;
    }
    [self capture:stage application:application];
    return YES;
}

- (BOOL)composeAndCommitMiddleCharacterIn:(XCUIApplication *)application
                                     field:(XCUIElement *)field {
    if (![self tapKeyboardControl:@"key.letter.c" application:application]) return NO;
    if (![self tapKeyboardControl:@"key.letter.i" application:application]) return NO;
    XCUIElement *raw = [self keyboardControl:@"candidate.raw" application:application];
    if (!raw) return NO;
    if (![raw.label isEqualToString:@"ci"]) {
        [self capture:@"Raw composition ci — first boundary failure" application:application];
        XCTFail(@"Expected raw composition ci, observed %@", raw.label);
        return NO;
    }
    [self capture:@"Raw composition ci" application:application];
    XCUIElement *first = [self keyboardControl:@"candidate.inline.0" application:application];
    if (!first) return NO;
    if ([first.label rangeOfString:@"中"].location == NSNotFound) {
        [self capture:@"First candidate must be 中 — first boundary failure" application:application];
        XCTFail(@"First ci candidate is '%@', expected 中", first.label);
        return NO;
    }
    [first tap];
    return [self expectValue:@"中" of:field stage:@"Candidate inserted by extension" application:application];
}

- (void)testInstalledKeyboardWithFullAccessOff {
    XCUIApplication *host = [[XCUIApplication alloc] initWithBundleIdentifier:@"osku.me.freeshiamyios"];
    [host launch]; // XCTest installs the containing app and embedded extension.
    [self capture:@"Host app installed and launched" application:host];

    XCUIApplication *settings = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.Preferences"];
    [settings launch];
    [self capture:@"Settings opened at public UI" application:settings];
    if (![self tapSettingsRow:@"General" inSettings:settings]) return;
    if (![self tapSettingsRow:@"Keyboard" inSettings:settings]) return;
    if (![self tapSettingsRow:@"Keyboards" inSettings:settings]) return;
    XCUIElement *add = [self settingsRowWithLabels:@[@"Add New Keyboard", @"Add New Keyboard…", @"Add New Keyboard..."]
                                        identifier:nil stage:@"Settings row: Add New Keyboard"
                                      application:settings];
    if (!add) return;
    [add tap];
    [self capture:@"Opened Add New Keyboard" application:settings];
    NSArray<NSString *> *extensionNames = @[@"FreeShiamy", @"freeshiamy-ios"];
    XCUIElement *registration = [self settingsRowWithLabels:extensionNames identifier:nil
                                                     stage:@"Installed FreeShiamy listing"
                                               application:settings];
    if (!registration) return;
    [registration tap];
    [self capture:@"FreeShiamy registered through Settings" application:settings];
    XCUIElement *configuration = [self settingsRowWithLabels:extensionNames identifier:nil
                                                      stage:@"Enabled FreeShiamy settings row"
                                                application:settings];
    if (!configuration) return;
    [configuration tap];
    NSPredicate *fullAccessLabel = [NSPredicate predicateWithFormat:@"label == %@", @"Allow Full Access"];
    XCUIElement *fullAccess = [self settingsControl:[settings.switches matchingPredicate:fullAccessLabel]
                                          stage:@"Allow Full Access switch observed"
                                    application:settings];
    if (!fullAccess) return;
    NSString *fullAccessValue = [fullAccess.value description];
    if (![@[@"0", @"Off"] containsObject:fullAccessValue]) {
        [self capture:@"Full Access must remain off — first boundary failure" application:settings];
        XCTFail(@"Allow Full Access is '%@'; expected off. Test never changes it.", fullAccessValue);
        return;
    }
    [self capture:@"Full Access observed OFF; never touched" application:settings];

    [host activate];
    [self capture:@"Returned to host app" application:host];
    XCUIElement *single = [self requireUnique:[host.textFields matchingIdentifier:@"smoke.singleLine"]
                                       stage:@"Single-line host field" application:host];
    XCUIElement *multi = [self requireUnique:[host.textViews matchingIdentifier:@"smoke.multiLine"]
                                      stage:@"Multiline host field" application:host];
    if (!single || !multi) return;
    [single tap];
    [self capture:@"Focused host field and opened system keyboard" application:host];

    // The first activation may show the system keyboard. Only the real system
    // input-mode picker may select the installed keyboard.
    XCUIElement *letter = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    if (![letter waitForExistenceWithTimeout:5.0]) {
        XCUIElement *systemGlobe = [self requireUnique:[host.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"Next keyboard", @"Globe"]]
                                                    stage:@"System keyboard switcher" application:host];
        if (!systemGlobe) return;
        [systemGlobe pressForDuration:1.2];
        [self capture:@"System input-mode picker open" application:host];
        XCUIElement *choice = [self requireUnique:[host.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"FreeShiamy"]]
                                              stage:@"FreeShiamy in system picker" application:host];
        if (!choice) return;
        [choice tap];
    }
    if (![self keyboardControl:@"key.letter.c" application:host]) return;
    if (![self keyboardControl:@"key.globe" application:host]) return;
    [self capture:@"Installed extension selected; extension-only controls visible" application:host];

    // A cold extension loads its dictionary asynchronously. While loading, the
    // real keyboard deliberately inserts raw Latin letters, so wait for the
    // production status label to disappear before testing candidate conversion.
    XCUIElement *dictionaryStatus = [host.staticTexts matchingIdentifier:@"candidate.status"].firstMatch;
    NSPredicate *loaded = [NSPredicate predicateWithFormat:@"exists == NO"];
    XCTNSPredicateExpectation *loadedExpectation = [[XCTNSPredicateExpectation alloc]
                                                  initWithPredicate:loaded object:dictionaryStatus];
    if ([XCTWaiter waitForExpectations:@[loadedExpectation] timeout:30.0] != XCTWaiterResultCompleted) {
        [self capture:@"Dictionary load — first boundary failure" application:host];
        XCTFail(@"Dictionary status remains visible: %@", dictionaryStatus.label);
        return;
    }
    [self capture:@"Dictionary ready in installed extension" application:host];

    if (![self composeAndCommitMiddleCharacterIn:host field:single]) return;
    if (![self tapKeyboardControl:@"key.delete" application:host]) return;
    if (![self expectValue:@"" of:single stage:@"Delete removed committed character" application:host]) return;
    if (![self composeAndCommitMiddleCharacterIn:host field:single]) return;
    XCUIElement *next = [self keyboardControl:@"key.return" application:host];
    if (!next) return;
    if (![next.label isEqualToString:@"下一個欄位"]) {
        [self capture:@"Next key trait — first boundary failure" application:host];
        XCTFail(@"Expected Next trait, got '%@'", next.label);
        return;
    }
    [next tap];
    [self capture:@"Tapped real extension Next key" application:host];
    if (![self tapKeyboardControl:@"key.digit.1" application:host]) return;
    if (![self expectValue:@"中" of:single stage:@"Single-line value preserved after Next" application:host]) return;
    if (![self expectValue:@"1" of:multi stage:@"Next focused multiline through host" application:host]) return;
    if (![self tapKeyboardControl:@"key.return" application:host]) return;
    if (![self expectValue:@"1\n" of:multi stage:@"Multiline Return inserted newline" application:host]) return;

    XCUIElement *extensionGlobe = [self keyboardControl:@"key.globe" application:host];
    if (!extensionGlobe) return;
    [extensionGlobe pressForDuration:1.2];
    [self capture:@"Extension system input-mode picker open" application:host];
    XCUIElement *other = [self requireUnique:[host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"English"]]
                                        stage:@"System English keyboard in picker" application:host];
    if (!other) return;
    [other tap];
    [self capture:@"Switched away via system picker" application:host];
    XCUIElement *extensionKey = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    XCTNSPredicateExpectation *gone = [[XCTNSPredicateExpectation alloc]
                                      initWithPredicate:[NSPredicate predicateWithFormat:@"exists == NO"]
                                              object:extensionKey];
    if ([XCTWaiter waitForExpectations:@[gone] timeout:10.0] != XCTWaiterResultCompleted) {
        [self capture:@"Extension must disappear after switch — first boundary failure" application:host];
        XCTFail(@"Extension key remained after switching to English");
        return;
    }
    XCUIElement *systemKey = [self requireUnique:[host.keys matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"q", @"Q"]]
                                             stage:@"System keyboard visible after switch" application:host];
    if (!systemKey) return;
    if (![self expectValue:@"中" of:single stage:@"Single-line preserved on switch away" application:host]) return;
    if (![self expectValue:@"1\n" of:multi stage:@"Multiline preserved on switch away" application:host]) return;
    [self capture:@"Installed-extension smoke complete" application:host];
}

@end
