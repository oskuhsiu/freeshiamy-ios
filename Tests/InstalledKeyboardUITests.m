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
    if ([title isEqualToString:@"General"]) {
        // On iPad Settings can open with General already selected in the
        // sidebar and its detail pane visible. In run 17, querying that
        // selected button's hittability failed with an invalid activation
        // point. Verify the detail state instead.
        XCUIElementQuery *sidebar = [settings.buttons matchingIdentifier:@"com.apple.settings.general"];
        if (sidebar.count == 1 && sidebar.firstMatch.isSelected) {
            XCUIElementQuery *detailBars = [settings.navigationBars matchingIdentifier:@"General"];
            XCUIElementQuery *keyboardRows = [settings.cells matchingIdentifier:@"Keyboard"];
            XCUIElement *keyboardRow = keyboardRows.firstMatch;
            NSPredicate *detailReady = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return sidebar.count == 1 && sidebar.firstMatch.isSelected &&
                       detailBars.count == 1 && keyboardRows.count == 1 &&
                       [self isOnScreen:keyboardRow application:settings];
            }];
            XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
                initWithPredicate:detailReady object:settings];
            if ([XCTWaiter waitForExpectations:@[expectation] timeout:5.0] != XCTWaiterResultCompleted) {
                [self capture:@"Selected General detail — first boundary failure" application:settings];
                XCTFail(@"General sidebar is selected without one visible General detail and Keyboard row");
                return NO;
            }
            [self capture:@"General already open in Settings detail pane" application:settings];
            return YES;
        }
    }
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

- (void)testInstalledAccessibilityMoreAndOffscreenCandidate {
    XCUIApplication *host = [[XCUIApplication alloc] initWithBundleIdentifier:@"osku.me.freeshiamyios"];
    NSString *runID = [NSUUID UUID].UUIDString;
    host.launchEnvironment = @{@"FSH_INSTALLED_SMOKE_RUN_ID": runID};
    [host launch];
    XCTAttachment *runMarker = [XCTAttachment attachmentWithString:runID];
    runMarker.name = @"Installed AX More host run ID";
    runMarker.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:runMarker];
    [self capture:@"AX host launched at public content size" application:host];

    XCUIElementQuery *fields = [host.textFields matchingIdentifier:@"smoke.singleLine"];
    XCUIElement *single = fields.firstMatch;
    XCUIElementQuery *scrolls = [host.scrollViews matchingIdentifier:@"host.testPanel.scroll"];
    XCUIElement *hostScroll = scrolls.firstMatch;
    BOOL focused = NO;
    for (NSUInteger attempt = 0; attempt <= 5; attempt++) {
        if (fields.count == 1 && [self isOnScreen:single application:host] && single.isHittable) {
            [single tap];
            focused = YES;
            break;
        }
        if (attempt < 5 && scrolls.count == 1 && [self isOnScreen:hostScroll application:host] && hostScroll.isHittable) {
            [hostScroll swipeUp];
        }
    }
    if (!focused) {
        [self capture:@"AX single-line focus — first boundary failure" application:host];
        XCTFail(@"Expected one visible single-line field and containing host scroll view; found %lu fields, %lu scroll views",
                (unsigned long)fields.count, (unsigned long)scrolls.count);
        return;
    }
    [self capture:@"AX host field focused" application:host];

    XCUIElement *letter = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    if (![letter waitForExistenceWithTimeout:5.0]) {
        XCUIElementQuery *switchers = [host.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"Next keyboard", @"Globe"]];
        XCUIElement *switcher = [self requireUnique:switchers stage:@"AX system keyboard switcher" application:host];
        if (!switcher) return;
        [switcher pressForDuration:1.2];
        [self capture:@"AX real system input-mode picker" application:host];
        XCUIElement *choice = [self observedInputSwitcherCell:@"FreeShiamy — freeshiamy-ios, Chinese"
                                                       stage:@"AX FreeShiamy picker choice" application:host];
        if (!choice) return;
        [choice tap];
    }
    if (![self keyboardControl:@"key.letter.c" application:host]) return;
    XCUIElement *dictionaryStatus = [host.staticTexts matchingIdentifier:@"candidate.status"].firstMatch;
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] object:dictionaryStatus];
    if ([XCTWaiter waitForExpectations:@[loaded] timeout:30.0] != XCTWaiterResultCompleted) {
        [self capture:@"AX dictionary load — first boundary failure" application:host];
        XCTFail(@"Dictionary did not become ready in the installed extension");
        return;
    }
    [self capture:@"AX installed extension ready" application:host];

    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    XCUIElement *raw = [self keyboardControl:@"candidate.raw" application:host];
    if (!raw || ![raw.label isEqualToString:@"c"]) {
        [self capture:@"AX raw c — first boundary failure" application:host];
        XCTFail(@"Expected raw c before opening More, observed %@", raw.label);
        return;
    }
    XCUIElement *more = [self keyboardControl:@"candidate.more" application:host];
    if (!more || ![more.value isEqual:@"已收合"]) {
        [self capture:@"AX More collapsed — first boundary failure" application:host];
        XCTFail(@"Expected collapsed More before opening, observed %@", more.value);
        return;
    }
    [more tap];
    more = [self keyboardControl:@"candidate.more" application:host];
    XCUIElement *first = [self keyboardControl:@"candidate.expanded.0" application:host];
    if (!more || ![more.value isEqual:@"已展開"] || !first || ![first.label isEqualToString:@"七"]) {
        [self capture:@"AX More opened — first boundary failure" application:host];
        XCTFail(@"Expected expanded More with first candidate 七; More %@, first %@", more.value, first.label);
        return;
    }
    [self capture:@"AX More expanded before scroll" application:host];

    XCUIElementQuery *moreScrolls = [host.scrollViews matchingIdentifier:@"candidate.expandedList"];
    XCUIElement *moreScroll = moreScrolls.firstMatch;
    XCUIElementQuery *targets = [host.buttons matchingIdentifier:@"candidate.expanded.79"];
    XCUIElement *target = targets.firstMatch;
    NSUInteger initialTargetCount = targets.count;
    BOOL targetInitiallyVisible = moreScrolls.count == 1 && initialTargetCount == 1 &&
        !CGRectIsEmpty(target.frame) && CGRectIntersectsRect(target.frame, moreScroll.frame);
    if (moreScrolls.count != 1 || ![self isOnScreen:moreScroll application:host] ||
        !moreScroll.isHittable || initialTargetCount > 1 ||
        (initialTargetCount == 1 && ![target.label isEqualToString:@"蟻"]) ||
        targetInitiallyVisible) {
        [self capture:@"AX offscreen candidate precondition — first boundary failure" application:host];
        XCTFail(@"Expected candidate 79 蟻 outside one visible More viewport or absent from its initial AX snapshot; scroll %@ count %lu target %@ label %@",
                moreScrolls.count == 1 ? NSStringFromCGRect(moreScroll.frame) : @"not exposed",
                (unsigned long)initialTargetCount,
                initialTargetCount == 1 ? NSStringFromCGRect(target.frame) : @"not exposed",
                initialTargetCount == 1 ? target.label : @"not exposed");
        return;
    }
    [self capture:@"AX candidate 79 initially offscreen" application:host];
    BOOL reached = NO;
    for (NSUInteger swipe = 0; swipe < 16; swipe++) {
        CGRect viewport = moreScroll.frame;
        NSUInteger count = targets.count;
        if (count > 1) break;
        if (count == 1) {
            CGRect item = target.frame;
            if (![target.label isEqualToString:@"蟻"]) break;
            if (!CGRectIsEmpty(viewport) && !CGRectIsEmpty(item) &&
                CGRectContainsRect(viewport, item) && CGRectContainsRect(host.frame, item) &&
                target.isHittable) {
                reached = YES;
                break;
            }
            if (!CGRectIsEmpty(item) && CGRectGetMinY(item) < CGRectGetMinY(viewport)) {
                [moreScroll swipeDown];
                continue;
            }
        }
        [moreScroll swipeUp];
    }
    if (!reached) {
        [self capture:@"AX offscreen candidate scroll — first boundary failure" application:host];
        XCTFail(@"Candidate 79 did not become fully visible and hittable after bounded More-viewport swipes; scroll %@ count %lu target %@",
                NSStringFromCGRect(moreScroll.frame), (unsigned long)targets.count,
                targets.count == 1 ? NSStringFromCGRect(target.frame) : @"not exposed");
        return;
    }
    [self capture:@"AX offscreen candidate 79 visible after scroll" application:host];
    [target tap];
    if (![self expectValue:@"蟻" of:single stage:@"AX offscreen candidate committed" application:host]) return;
    if (![self keyboardControl:@"key.letter.c" application:host]) return;

    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    raw = [self keyboardControl:@"candidate.raw" application:host];
    if (!raw || ![raw.label isEqualToString:@"c"]) {
        [self capture:@"AX second raw c — first boundary failure" application:host];
        XCTFail(@"Expected second raw c, observed %@", raw.label);
        return;
    }
    more = [self keyboardControl:@"candidate.more" application:host];
    if (!more) return;
    [more tap];
    [self capture:@"AX More reopened" application:host];
    more = [self keyboardControl:@"candidate.more" application:host];
    if (!more || ![more.value isEqual:@"已展開"]) {
        [self capture:@"AX More reopen — first boundary failure" application:host];
        XCTFail(@"Expected expanded More after reopening, observed %@", more.value);
        return;
    }
    [more tap];
    [self capture:@"AX More collapsed again" application:host];
    raw = [self keyboardControl:@"candidate.raw" application:host];
    more = [self keyboardControl:@"candidate.more" application:host];
    if (!raw || ![raw.label isEqualToString:@"c"] || !more || ![more.value isEqual:@"已收合"]) {
        [self capture:@"AX collapse composition — first boundary failure" application:host];
        XCTFail(@"More collapse lost raw composition c or collapsed state");
        return;
    }
    if (![self keyboardControl:@"key.letter.c" application:host]) return;
    XCUIElement *inlineFirst = [self keyboardControl:@"candidate.inline.0" application:host];
    if (!inlineFirst || ![inlineFirst.label isEqualToString:@"七"]) {
        [self capture:@"AX inline candidate — first boundary failure" application:host];
        XCTFail(@"Expected inline 七 after collapse, observed %@", inlineFirst.label);
        return;
    }
    [inlineFirst tap];
    if (![self expectValue:@"蟻七" of:single stage:@"AX collapsed inline candidate committed" application:host]) return;
    if (![self tapKeyboardControl:@"key.delete" application:host]) return;
    if (![self expectValue:@"蟻" of:single stage:@"AX Delete after More collapse" application:host]) return;
    XCUIElementQuery *multilineFields = [host.textViews matchingIdentifier:@"smoke.multiLine"];
    XCUIElement *multi = multilineFields.firstMatch;
    if (multilineFields.count != 1 || ![multi.value isEqual:@""]) {
        [self capture:@"AX multiline preservation — first boundary failure" application:host];
        XCTFail(@"Expected one untouched empty multiline field; found %lu, value %@",
                (unsigned long)multilineFields.count, multilineFields.count == 1 ? multi.value : @"absent");
        return;
    }
    [self capture:@"AX installed More test complete" application:host];
}

@end
