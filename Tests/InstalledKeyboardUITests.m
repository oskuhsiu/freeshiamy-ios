#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

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
            return query.count == 1 && [self isOnScreen:first application:settings] && first.isHittable;
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

- (BOOL)isOnScreen:(XCUIElement *)element application:(XCUIApplication *)application {
    if (!element || !element.exists) return NO;
    CGRect frame = element.frame;
    return !CGRectIsEmpty(frame) && CGRectIntersectsRect(frame, application.frame);
}

- (XCUIElement *)observedSettingsStaticText:(NSString *)identifier
                                      stage:(NSString *)stage
                                application:(XCUIApplication *)settings {
    XCUIElementQuery *query = [settings.staticTexts matchingIdentifier:identifier];
    XCUIElement *first = query.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return query.count == 1 && [self isOnScreen:first application:settings] && first.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:first];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:5.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:settings];
        XCTFail(@"%@: expected one visible, hittable Settings StaticText %@; found %lu",
                stage, identifier, (unsigned long)query.count);
        return nil;
    }
    [self capture:stage application:settings];
    return first;
}

- (XCUIElement *)observedInputSwitcherCell:(NSString *)exactLabel
                                     stage:(NSString *)stage
                               application:(XCUIApplication *)application {
    XCUIElementQuery *tables = [application.tables matchingIdentifier:@"InputSwitcherTable"];
    XCUIElementQuery *cells = [tables.cells matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@", exactLabel]];
    XCUIElement *cell = cells.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return tables.count == 1 && cells.count == 1 &&
               [self isOnScreen:cell application:application] && cell.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:cell];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:5.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:application];
        XCTFail(@"%@: expected one visible, hittable %@ cell in InputSwitcherTable; found %lu tables, %lu cells",
                stage, exactLabel, (unsigned long)tables.count, (unsigned long)cells.count);
        return nil;
    }
    [self capture:stage application:application];
    return cell;
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
    XCUIElementQuery *labeledCells = identifier ? nil : [settings.cells matchingPredicate:label];
    NSPredicate *exactText = [NSPredicate predicateWithFormat:@"elementType == %ld AND label IN %@",
                              (long)XCUIElementTypeStaticText, labels];
    XCUIElementQuery *containingCells = identifier ? nil : [settings.cells containingPredicate:exactText];
    for (NSUInteger scroll = 0; scroll <= 8; scroll++) {
        __block XCUIElement *target = nil;
        NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            NSUInteger buttonCount = buttons.count;
            NSUInteger labeledCount = labeledCells ? labeledCells.count : 0;
            NSUInteger containingCount = containingCells ? containingCells.count : 0;
            if (buttonCount > 1 || labeledCount > 1 || containingCount > 1) return NO;
            XCUIElement *button = buttonCount == 1 ? buttons.firstMatch : nil;
            XCUIElement *labeledCell = labeledCount == 1 ? labeledCells.firstMatch : nil;
            XCUIElement *containingCell = containingCount == 1 ? containingCells.firstMatch : nil;
            if (labeledCell && containingCell && !CGRectEqualToRect(labeledCell.frame, containingCell.frame)) return NO;
            XCUIElement *cell = labeledCell ?: containingCell;
            // A child button may have CGRectZero even when its cell is
            // hittable. Check structural containment instead of geometry.
            if (button && cell && [cell.buttons matchingPredicate:label].count != 1) return NO;
            target = ([self isOnScreen:button application:settings] && button.isHittable)
                ? button : (([self isOnScreen:cell application:settings] && cell.isHittable) ? cell : nil);
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
    XCTFail(@"%@: expected one visible, hittable semantic row; found %lu buttons, %lu labeled cells, %lu containing cells",
            stage, (unsigned long)buttons.count, (unsigned long)(labeledCells ? labeledCells.count : 0),
            (unsigned long)(containingCells ? containingCells.count : 0));
    return nil;
}

- (BOOL)tapSettingsRow:(NSString *)title inSettings:(XCUIApplication *)settings {
    if ([title isEqualToString:@"Keyboards"]) {
        // iOS 26.2 exposes this composite row as "Keyboards, 2". Its stable
        // identifier belongs to the actionable cell; the nested button is
        // zero-sized in the retained simulator hierarchy.
        XCUIElement *row = [self settingsControl:[settings.cells matchingIdentifier:@"KEYBOARDS"]
                                         stage:@"Settings row: Keyboards" application:settings];
        if (!row) return NO;
        [row tap];
        [self capture:@"Opened Settings row: Keyboards" application:settings];
        return YES;
    }
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

- (BOOL)verifyInstalledOrientation:(UIDeviceOrientation)orientation
                          landscape:(BOOL)landscape
                               field:(XCUIElement *)field
                         application:(XCUIApplication *)application
                               stage:(NSString *)stage {
    [XCUIDevice sharedDevice].orientation = orientation;
    XCUIElementQuery *keys = [application.buttons matchingIdentifier:@"key.letter.c"];
    XCUIElement *key = keys.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        CGRect scene = application.frame;
        BOOL sceneRotated = landscape ? CGRectGetWidth(scene) > CGRectGetHeight(scene) + 20.0
                                      : CGRectGetHeight(scene) > CGRectGetWidth(scene) + 20.0;
        return sceneRotated && keys.count == 1 && [self isOnScreen:key application:application] &&
               key.isHittable && [self isOnScreen:field application:application] && field.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:application];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:application];
        XCTFail(@"%@: expected rotated scene, visible installed key and focused host field; app %@ key %@ field %@",
                stage, NSStringFromCGRect(application.frame),
                key.exists ? NSStringFromCGRect(key.frame) : @"absent",
                field.exists ? NSStringFromCGRect(field.frame) : @"absent");
        return NO;
    }
    [self capture:stage application:application];
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
    NSString *smokeRunID = [NSUUID UUID].UUIDString;
    host.launchEnvironment = @{@"FSH_INSTALLED_SMOKE_RUN_ID": smokeRunID};
    [host launch]; // XCTest installs the containing app and embedded extension.
    XCTAttachment *runMarker = [XCTAttachment attachmentWithString:smokeRunID];
    runMarker.name = @"Installed smoke host-geometry run ID";
    runMarker.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:runMarker];
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
    // The retained Add New Keyboard hierarchy exposes this exact visible
    // StaticText within a row whose cell reports non-hittable. Validate the
    // semantic child without scrolling the observed row away.
    XCUIElement *registration = [self observedSettingsStaticText:@"osku.me.freeshiamyios"
                                                           stage:@"Installed FreeShiamy listing"
                                                     application:settings];
    if (!registration) return;
    [registration tap];
    [self capture:@"FreeShiamy registered through Settings" application:settings];
    // After enrollment, iOS 26.2 exposes the enabled extension under this
    // exact identifier and the composite label "FreeShiamy — freeshiamy-ios".
    XCUIElement *configuration = [self observedSettingsStaticText:@"osku.me.freeshiamyios.keyboard"
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
    NSString *observedSystemSwitcherIdentifier = nil;
    NSString *observedSystemSwitcherLabel = nil;
    XCUIElementQuery *publicSystemSwitchers = [host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"Next keyboard", @"Globe"]];
    XCUIElement *initialSwitcher = publicSystemSwitchers.firstMatch;
    if (publicSystemSwitchers.count == 1 && [self isOnScreen:initialSwitcher application:host] && initialSwitcher.isHittable) {
        observedSystemSwitcherIdentifier = [initialSwitcher.identifier copy];
        observedSystemSwitcherLabel = [initialSwitcher.label copy];
        [self capture:@"Observed public system input-mode switcher" application:host];
    }
    XCUIElement *letter = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    if (![letter waitForExistenceWithTimeout:5.0]) {
        XCUIElement *systemGlobe = [self requireUnique:publicSystemSwitchers
                                               stage:@"System keyboard switcher" application:host];
        if (!systemGlobe) return;
        observedSystemSwitcherIdentifier = [systemGlobe.identifier copy];
        observedSystemSwitcherLabel = [systemGlobe.label copy];
        [systemGlobe pressForDuration:1.2];
        [self capture:@"System input-mode picker open" application:host];
        XCUIElement *choice = [self observedInputSwitcherCell:@"FreeShiamy — freeshiamy-ios, Chinese"
                                                       stage:@"FreeShiamy in system picker" application:host];
        if (!choice) return;
        [choice tap];
    }
    if (![self keyboardControl:@"key.letter.c" application:host]) return;
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

    // Exercise the installed extension in a genuinely rotated scene while a
    // multiline host field is focused. The host's DEBUG geometry log records
    // the keyboard guide and caret in window coordinates for this same stage.
    if (![self verifyInstalledOrientation:UIDeviceOrientationPortrait landscape:NO field:multi
                               application:host stage:@"Installed extension portrait before rotation"]) return;
    if (![self verifyInstalledOrientation:UIDeviceOrientationLandscapeLeft landscape:YES field:multi
                               application:host stage:@"Installed extension live landscape"]) return;
    if (![self expectValue:@"中" of:single stage:@"Single-line preserved in landscape" application:host]) return;
    if (![self expectValue:@"1\n" of:multi stage:@"Multiline preserved in landscape" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.i" application:host]) return;
    XCUIElement *rotatedRaw = [self keyboardControl:@"candidate.raw" application:host];
    if (!rotatedRaw) return;
    if (![rotatedRaw.label isEqualToString:@"ci"]) {
        [self capture:@"Landscape raw composition — first boundary failure" application:host];
        XCTFail(@"Expected raw composition ci in landscape, observed %@", rotatedRaw.label);
        return;
    }
    [self capture:@"Live ci composition in landscape" application:host];
    if (![self verifyInstalledOrientation:UIDeviceOrientationPortrait landscape:NO field:multi
                               application:host stage:@"Installed extension returned to portrait"]) return;
    rotatedRaw = [self keyboardControl:@"candidate.raw" application:host];
    if (!rotatedRaw || ![rotatedRaw.label isEqualToString:@"ci"]) {
        [self capture:@"Composition after rotation — first boundary failure" application:host];
        XCTFail(@"Raw ci composition did not survive rotation");
        return;
    }
    XCUIElement *rotatedCandidate = [self keyboardControl:@"candidate.inline.0" application:host];
    if (!rotatedCandidate) return;
    if ([rotatedCandidate.label rangeOfString:@"中"].location == NSNotFound) {
        [self capture:@"Rotated candidate — first boundary failure" application:host];
        XCTFail(@"Expected 中 after rotation, observed %@", rotatedCandidate.label);
        return;
    }
    [rotatedCandidate tap];
    if (![self expectValue:@"1\n中" of:multi stage:@"Committed preserved rotated composition" application:host]) return;

    // On Face ID iPhones, iOS supplies its own Globe below the extension and
    // needsInputModeSwitchKey can be false. Use the extension key only if it
    // is actually visible; otherwise reuse the observed system switcher.
    XCUIElementQuery *extensionSwitchers = [host.buttons matchingIdentifier:@"key.globe"];
    if (extensionSwitchers.count > 1) {
        [self capture:@"Ambiguous extension switcher — first boundary failure" application:host];
        XCTFail(@"Expected at most one extension Globe, found %lu", (unsigned long)extensionSwitchers.count);
        return;
    }
    XCUIElement *switcher = extensionSwitchers.firstMatch;
    NSString *switcherOwnership = @"extension-owned";
    if (extensionSwitchers.count != 1 || ![self isOnScreen:switcher application:host] || !switcher.isHittable) {
        switcher = nil;
        switcherOwnership = @"system-owned";
        if (observedSystemSwitcherIdentifier.length > 0 || observedSystemSwitcherLabel.length > 0) {
            NSPredicate *observed = observedSystemSwitcherIdentifier.length > 0
                ? [NSPredicate predicateWithFormat:@"identifier == %@", observedSystemSwitcherIdentifier]
                : [NSPredicate predicateWithFormat:@"label == %@", observedSystemSwitcherLabel];
            XCUIElementQuery *systemSwitchers = [host.buttons matchingPredicate:observed];
            XCUIElement *candidate = systemSwitchers.firstMatch;
            NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return systemSwitchers.count == 1 && [self isOnScreen:candidate application:host] && candidate.isHittable;
            }];
            XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:ready object:candidate];
            if ([XCTWaiter waitForExpectations:@[expectation] timeout:5.0] == XCTWaiterResultCompleted) {
                switcher = candidate;
            }
        }
    }
    if (!switcher) {
        [self capture:@"Observed input-mode switcher — first boundary failure" application:host];
        XCTFail(@"Neither a visible extension Globe nor the previously observed system switcher is available");
        return;
    }
    [self capture:[NSString stringWithFormat:@"Observed %@ input-mode switcher", switcherOwnership]
        application:host];
    [switcher pressForDuration:1.2];
    [self capture:@"Extension system input-mode picker open" application:host];
    XCUIElement *other = [self observedInputSwitcherCell:@"English (US)"
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
    if (![self expectValue:@"1\n中" of:multi stage:@"Multiline preserved on switch away" application:host]) return;
    [self capture:@"Installed-extension smoke complete" application:host];
}

@end
