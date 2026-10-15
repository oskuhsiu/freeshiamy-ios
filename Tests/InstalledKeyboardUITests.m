#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import <math.h>

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
    if ([title isEqualToString:@"Keyboard"]) {
        // Run 20's retained iPad hierarchy exposes this exact actionable
        // button inside a cell. Do not resolve unrelated rows or a nav Back.
        XCUIElementQuery *rows = [settings.cells.buttons matchingIdentifier:@"Keyboard"];
        XCUIElement *row = rows.firstMatch;
        NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
            return rows.count == 1 && [row.label isEqualToString:@"Keyboard"] &&
                   [self isOnScreen:row application:settings] && row.isHittable;
        }];
        XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
            initWithPredicate:ready object:row];
        if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
            [self capture:@"Settings row: Keyboard — first boundary failure" application:settings];
            XCTFail(@"Expected one on-screen hittable cell button with identifier/label Keyboard; found %lu, label %@",
                    (unsigned long)rows.count, rows.count == 1 ? row.label : @"not unique");
            return NO;
        }
        [self capture:@"Settings row: Keyboard" application:settings];
        [row tap];
        [self capture:@"Opened Settings row: Keyboard" application:settings];
        return YES;
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

- (XCUIElement *)requireVisibleUnique:(XCUIElementQuery *)query
                                stage:(NSString *)stage
                          application:(XCUIApplication *)application {
    XCUIElement *element = query.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return query.count == 1 && [self isOnScreen:element application:application] && element.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:element];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:application];
        XCTFail(@"%@: expected one on-screen, hittable control; found %lu", stage, (unsigned long)query.count);
        return nil;
    }
    [self capture:stage application:application];
    return element;
}

- (XCUIElement *)hostControlByScrolling:(XCUIElementQuery *)query
                                  stage:(NSString *)stage
                            application:(XCUIApplication *)host {
    XCUIElement *element = query.firstMatch;
    if (![element waitForExistenceWithTimeout:5.0] || query.count != 1) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: expected one observed host control before scrolling; found %lu", stage, (unsigned long)query.count);
        return nil;
    }
    XCUIElementQuery *scrolls = [host.scrollViews matchingIdentifier:@"host.testPanel.scroll"];
    XCUIElement *scroll = scrolls.firstMatch;
    for (NSUInteger swipe = 0; swipe <= 8; swipe++) {
        CGRect item = element.frame;
        CGRect viewport = scroll.frame;
        if (query.count != 1 || scrolls.count != 1 || CGRectIsEmpty(item) || CGRectIsEmpty(viewport)) break;
        if (CGRectContainsRect(viewport, item) && [self isOnScreen:element application:host] && element.isHittable) {
            [self capture:stage application:host];
            return element;
        }
        if (swipe == 8 || ![self isOnScreen:scroll application:host] || !scroll.isHittable) break;
        if (CGRectGetMinY(item) < CGRectGetMinY(viewport)) {
            [scroll swipeDown];
        } else if (CGRectGetMaxY(item) > CGRectGetMaxY(viewport)) {
            [scroll swipeUp];
        } else {
            break;
        }
    }
    [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
    XCTFail(@"%@: host control did not become fully visible after bounded observed-frame host-panel scrolling", stage);
    return nil;
}

- (BOOL)requireHeightComposition:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElement *raw = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"candidate.raw"]
                                           stage:stage application:host];
    if (!raw) return NO;
    if (![raw.label isEqualToString:@"c"]) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: expected raw c, observed %@", stage, raw.label);
        return NO;
    }
    return YES;
}

- (BOOL)verifyHeightMoreOrientation:(UIDeviceOrientation)orientation
                           landscape:(BOOL)landscape
                               field:(XCUIElement *)field
                         application:(XCUIApplication *)host
                               stage:(NSString *)stage {
    [XCUIDevice sharedDevice].orientation = orientation;
    XCUIElementQuery *raws = [host.buttons matchingIdentifier:@"candidate.raw"];
    XCUIElementQuery *mores = [host.buttons matchingIdentifier:@"candidate.more"];
    XCUIElementQuery *lists = [host.scrollViews matchingIdentifier:@"candidate.expandedList"];
    XCUIElement *raw = raws.firstMatch;
    XCUIElement *more = mores.firstMatch;
    XCUIElement *list = lists.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        CGRect scene = host.frame;
        BOOL rotated = landscape ? CGRectGetWidth(scene) > CGRectGetHeight(scene) + 20.0
                                 : CGRectGetHeight(scene) > CGRectGetWidth(scene) + 20.0;
        return rotated && raws.count == 1 && [raw.label isEqualToString:@"c"] &&
               [self isOnScreen:raw application:host] && raw.isHittable &&
               mores.count == 1 && [more.value isEqual:@"已展開"] &&
               [self isOnScreen:more application:host] && more.isHittable &&
               lists.count == 1 && [self isOnScreen:list application:host] && list.isHittable &&
               [self isOnScreen:field application:host] && field.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:host];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: missing actual orientation, preserved raw c, expanded More viewport or focused multiline field", stage);
        return NO;
    }
    [self capture:stage application:host];
    return YES;
}

- (BOOL)requireHeightCollapsedKeys:(XCUIApplication *)host
                   withComposition:(BOOL)withComposition
                             stage:(NSString *)stage {
    XCUIElementQuery *keys = [host.buttons matchingIdentifier:@"key.letter.c"];
    XCUIElementQuery *lists = [host.scrollViews matchingIdentifier:@"candidate.expandedList"];
    XCUIElementQuery *mores = [host.buttons matchingIdentifier:@"candidate.more"];
    XCUIElementQuery *raws = [host.buttons matchingIdentifier:@"candidate.raw"];
    XCUIElement *key = keys.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        BOOL collapsed = lists.count == 0 && mores.count <= 1 &&
            (mores.count == 0 || [mores.firstMatch.value isEqual:@"已收合"]);
        if (withComposition) {
            collapsed = collapsed && mores.count == 1 &&
                [self isOnScreen:mores.firstMatch application:host] && mores.firstMatch.isHittable &&
                raws.count == 1 && [raws.firstMatch.label isEqualToString:@"c"] &&
                [self isOnScreen:raws.firstMatch application:host] && raws.firstMatch.isHittable;
        }
        return collapsed && keys.count == 1 && [self isOnScreen:key application:host] && key.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:host];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: expected restored visible letter keys, collapsed More and required composition", stage);
        return NO;
    }
    [self capture:stage application:host];
    return YES;
}

- (void)runInstalledHeightScenario:(NSInteger)percent normalizedPosition:(CGFloat)position {
    NSString *prefix = [NSString stringWithFormat:@"Height %ld%%", (long)percent];
    [XCUIDevice sharedDevice].orientation = UIDeviceOrientationPortrait;
    XCUIApplication *host = [[XCUIApplication alloc] initWithBundleIdentifier:@"osku.me.freeshiamyios"];
    NSString *runID = [NSUUID UUID].UUIDString;
    host.launchEnvironment = @{@"FSH_INSTALLED_SMOKE_RUN_ID": runID};
    [host launch];
    XCTAttachment *runMarker = [XCTAttachment attachmentWithString:runID];
    runMarker.name = @"Installed smoke host-geometry run ID";
    runMarker.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:runMarker];
    [self capture:[prefix stringByAppendingString:@" host launched"] application:host];

    XCUIElement *settingsButton = [self hostControlByScrolling:[host.buttons matchingIdentifier:@"smoke.appSettings"]
        stage:[prefix stringByAppendingString:@" actual app Settings action"] application:host];
    if (!settingsButton) return;
    [settingsButton tap];
    XCUIElement *settingsBar = [self requireVisibleUnique:[host.navigationBars matchingIdentifier:@"設定"]
        stage:[prefix stringByAppendingString:@" Settings navigation bar"] application:host];
    XCUIElement *slider = [self requireVisibleUnique:[host.sliders matchingIdentifier:@"settings.height.slider"]
        stage:[prefix stringByAppendingString:@" Settings height slider"] application:host];
    XCUIElement *value = [self requireVisibleUnique:[host.staticTexts matchingIdentifier:@"settings.height.value"]
        stage:[prefix stringByAppendingString:@" Settings height value"] application:host];
    if (!settingsBar || !slider || !value) return;
    [slider adjustToNormalizedSliderPosition:position];
    NSString *expectedLabel = [NSString stringWithFormat:@"%ld%%", (long)percent];
    NSString *initialLabel = value.label;
    CGFloat actualPosition = slider.normalizedSliderPosition;
    CGRect sliderFrame = slider.frame;
    NSLog(@"[HeightSliderEndpoint] target=%ld initialLabel=%@ normalizedPosition=%.6f sliderFrame=%@",
          (long)percent, initialLabel, actualPosition, NSStringFromCGRect(sliderFrame));
    [self capture:[prefix stringByAppendingString:@" initial actual slider endpoint feedback"] application:host];
    if (![initialLabel isEqualToString:expectedLabel]) {
        BOOL nearEndpoint = isfinite(actualPosition) &&
            ((percent == 220 && [initialLabel isEqualToString:@"219%"] && actualPosition >= 0.98 && actualPosition < 1.0) ||
             (percent == 90 && [initialLabel isEqualToString:@"91%"] && actualPosition > 0.0 && actualPosition <= 0.02));
        XCUIElementQuery *sliders = [host.sliders matchingIdentifier:@"settings.height.slider"];
        CGRect hostFrame = host.frame;
        BOOL finiteBounds = isfinite(sliderFrame.origin.x) && isfinite(sliderFrame.origin.y) &&
            isfinite(sliderFrame.size.width) && isfinite(sliderFrame.size.height) &&
            isfinite(hostFrame.origin.x) && isfinite(hostFrame.origin.y) &&
            isfinite(hostFrame.size.width) && isfinite(hostFrame.size.height) &&
            sliderFrame.size.width > 0 && sliderFrame.size.height > 0 && hostFrame.size.width > 0 && hostFrame.size.height > 0;
        BOOL visibleSlider = finiteBounds && sliders.count == 1 && slider.exists && slider.isHittable &&
            CGRectGetMinX(sliderFrame) >= CGRectGetMinX(hostFrame) && CGRectGetMaxX(sliderFrame) <= CGRectGetMaxX(hostFrame) &&
            CGRectGetMinY(sliderFrame) >= CGRectGetMinY(hostFrame) && CGRectGetMaxY(sliderFrame) <= CGRectGetMaxY(hostFrame);
        if (nearEndpoint && visibleSlider) {
            // Value-space to thumb-start mapping is a bounded near-edge
            // hypothesis, not a guarantee about UISlider's track geometry.
            XCUICoordinate *start = [slider coordinateWithNormalizedOffset:CGVectorMake(actualPosition, 0.5)];
            XCUICoordinate *end = [slider coordinateWithNormalizedOffset:CGVectorMake(position, 0.5)];
            CGPoint startPoint = start.screenPoint;
            CGPoint endPoint = end.screenPoint;
            BOOL safePoints = YES;
            for (NSValue *pointValue in @[[NSValue valueWithCGPoint:startPoint], [NSValue valueWithCGPoint:endPoint]]) {
                CGPoint point = pointValue.CGPointValue;
                // Closed edge bounds intentionally include the requested 0/1 endpoint.
                safePoints = safePoints && isfinite(point.x) && isfinite(point.y) &&
                    point.x >= CGRectGetMinX(sliderFrame) && point.x <= CGRectGetMaxX(sliderFrame) &&
                    point.y >= CGRectGetMinY(sliderFrame) && point.y <= CGRectGetMaxY(sliderFrame) &&
                    point.x >= CGRectGetMinX(hostFrame) && point.x <= CGRectGetMaxX(hostFrame) &&
                    point.y >= CGRectGetMinY(hostFrame) && point.y <= CGRectGetMaxY(hostFrame);
            }
            NSLog(@"[HeightSliderEndpoint] oneCorrectionAllowed=%@ start=%@ end=%@ hostFrame=%@",
                  safePoints ? @"YES" : @"NO", NSStringFromCGPoint(startPoint), NSStringFromCGPoint(endPoint), NSStringFromCGRect(hostFrame));
            if (safePoints) {
                [start pressForDuration:0.1 thenDragToCoordinate:end];
                [self capture:[prefix stringByAppendingString:@" after one feedback-gated slider-edge drag"] application:host];
            } else {
                [self capture:[prefix stringByAppendingString:@" unsafe slider-edge points — first boundary failure"] application:host];
                XCTFail(@"Slider endpoint correction points must lie inside actual visible host and slider-edge bounds");
                return;
            }
        } else {
            [self capture:[prefix stringByAppendingString:@" contradictory slider feedback — first boundary failure"] application:host];
            XCTFail(@"Endpoint correction requires exact near-endpoint label/position and one fully visible hittable slider; observed %@ at %.6f",
                    initialLabel, actualPosition);
            return;
        }
    }
    NSPredicate *chosen = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [value.label isEqualToString:expectedLabel] && [self isOnScreen:value application:host] && value.isHittable;
    }];
    XCTNSPredicateExpectation *chosenExpectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:chosen object:value];
    if ([XCTWaiter waitForExpectations:@[chosenExpectation] timeout:10.0] != XCTWaiterResultCompleted) {
        [self capture:[prefix stringByAppendingString:@" slider value — first boundary failure"] application:host];
        XCTFail(@"Expected actual Settings slider label %@, observed %@", expectedLabel, value.label);
        return;
    }
    [self capture:[prefix stringByAppendingString:@" chosen through Settings slider"] application:host];
    XCUIElement *back = [self requireVisibleUnique:settingsBar.buttons
        stage:[prefix stringByAppendingString:@" unique Settings back action"] application:host];
    if (!back) return;
    [self capture:[NSString stringWithFormat:@"%@ Settings back label: %@", prefix, back.label] application:host];
    [back tap];
    [self capture:[prefix stringByAppendingString:@" returned from Settings"] application:host];

    XCUIElement *multi = [self hostControlByScrolling:[host.textViews matchingIdentifier:@"smoke.multiLine"]
        stage:[prefix stringByAppendingString:@" multiline field before focus"] application:host];
    if (!multi) return;
    if (![self expectValue:@"" of:multi stage:[prefix stringByAppendingString:@" initial multiline empty"] application:host]) return;
    [multi tap];
    [self capture:[prefix stringByAppendingString:@" multiline focused"] application:host];
    XCUIElement *letter = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    if (![letter waitForExistenceWithTimeout:5.0]) {
        XCUIElementQuery *switchers = [host.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"Next keyboard", @"Globe"]];
        XCUIElement *switcher = [self requireVisibleUnique:switchers
            stage:[prefix stringByAppendingString:@" observed system switcher"] application:host];
        if (!switcher) return;
        [switcher pressForDuration:1.2];
        [self capture:[prefix stringByAppendingString:@" real input-mode picker"] application:host];
        XCUIElement *choice = [self observedInputSwitcherCell:@"FreeShiamy — freeshiamy-ios, Chinese"
            stage:[prefix stringByAppendingString:@" FreeShiamy picker choice"] application:host];
        if (!choice) return;
        [choice tap];
    }
    if (![self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.letter.c"]
        stage:[prefix stringByAppendingString:@" installed letter key"] application:host]) return;
    XCUIElement *dictionaryStatus = [host.staticTexts matchingIdentifier:@"candidate.status"].firstMatch;
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] object:dictionaryStatus];
    if ([XCTWaiter waitForExpectations:@[loaded] timeout:30.0] != XCTWaiterResultCompleted) {
        [self capture:[prefix stringByAppendingString:@" dictionary — first boundary failure"] application:host];
        XCTFail(@"Dictionary did not become ready in installed height scenario");
        return;
    }
    if (![self verifyInstalledOrientation:UIDeviceOrientationPortrait landscape:NO field:multi
        application:host stage:[prefix stringByAppendingString:@" portrait collapsed before composition"]]) return;
    if (![self tapKeyboardControl:@"key.digit.1" application:host]) return;
    if (![self expectValue:@"1" of:multi stage:[prefix stringByAppendingString:@" digit inserted"] application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    if (![self requireHeightComposition:host stage:[prefix stringByAppendingString:@" initial raw c"]]) return;
    XCUIElement *more = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"candidate.more"]
        stage:[prefix stringByAppendingString:@" collapsed More before opening"] application:host];
    if (!more) return;
    if (![more.value isEqual:@"已收合"]) {
        [self capture:[prefix stringByAppendingString:@" initial More state — first boundary failure"] application:host];
        XCTFail(@"Expected collapsed More, observed %@", more.value);
        return;
    }
    [more tap];
    if (![self verifyHeightMoreOrientation:UIDeviceOrientationPortrait landscape:NO field:multi
        application:host stage:@"Height expanded portrait before rotation"]) return;
    if (![self verifyHeightMoreOrientation:UIDeviceOrientationLandscapeLeft landscape:YES field:multi
        application:host stage:@"Height expanded landscape"]) return;
    if (![self expectValue:@"1" of:multi stage:[prefix stringByAppendingString:@" landscape preserves multiline"] application:host]) return;
    if (![self requireHeightComposition:host stage:[prefix stringByAppendingString:@" landscape raw c preserved"]]) return;

    XCUIElement *list = [self requireVisibleUnique:[host.scrollViews matchingIdentifier:@"candidate.expandedList"]
        stage:[prefix stringByAppendingString:@" landscape More viewport before scrolling"] application:host];
    if (!list) return;
    XCUIElementQuery *targets = [host.buttons matchingIdentifier:@"candidate.expanded.79"];
    XCUIElement *target = targets.firstMatch;
    BOOL initiallyVisible = targets.count == 1 && !CGRectIsEmpty(target.frame) &&
        CGRectContainsRect(list.frame, target.frame) && CGRectContainsRect(host.frame, target.frame) && target.isHittable;
    [self capture:[prefix stringByAppendingString:initiallyVisible
        ? @" candidate 79 initially fully visible" : @" candidate 79 not initially fully visible"] application:host];
    XCUIElementQuery *lists = [host.scrollViews matchingIdentifier:@"candidate.expandedList"];
    XCUIElementQuery *mores = [host.buttons matchingIdentifier:@"candidate.more"];
    XCUIElementQuery *raws = [host.buttons matchingIdentifier:@"candidate.raw"];
    BOOL reached = NO;
    for (NSUInteger swipe = 0; swipe <= 16; swipe++) {
        CGRect viewport = list.frame;
        NSUInteger count = targets.count;
        BOOL swipeDown = NO;
        if (count > 1) break;
        if (count == 1) {
            CGRect item = target.frame;
            if (![target.label isEqualToString:@"蟻"]) break;
            if (!CGRectIsEmpty(viewport) && !CGRectIsEmpty(item) &&
                CGRectContainsRect(viewport, item) && CGRectContainsRect(host.frame, item) && target.isHittable) {
                reached = YES;
                break;
            }
            if (!CGRectIsEmpty(item) && CGRectGetMinY(item) < CGRectGetMinY(viewport)) {
                swipeDown = YES;
            }
        }
        if (swipe == 16 || ![self isOnScreen:list application:host] || !list.isHittable) break;
        if (swipeDown) [list swipeDown];
        else [list swipeUp];

        // Check the first unsafe boundary before asking for another stale list frame.
        NSUInteger listCount = lists.count;
        NSUInteger moreCount = mores.count;
        NSUInteger rawCount = raws.count;
        id moreValue = moreCount == 1 ? mores.firstMatch.value : nil;
        NSString *rawLabel = rawCount == 1 ? raws.firstMatch.label : nil;
        id hostValue = multi.value;
        if (listCount != 1 || moreCount != 1 || ![moreValue isEqual:@"已展開"] ||
            rawCount != 1 || ![rawLabel isEqualToString:@"c"] || ![hostValue isEqual:@"1"]) {
            [self capture:[NSString stringWithFormat:@"%@ swipe %lu — first boundary failure",
                prefix, (unsigned long)(swipe + 1)] application:host];
            XCTFail(@"%@ swipe %lu changed More/composition/host before candidate 79: viewport count %lu, More %@, raw %@, host %@",
                    prefix, (unsigned long)(swipe + 1), (unsigned long)listCount,
                    moreValue ?: @"absent", rawLabel ?: @"absent", hostValue ?: @"absent");
            return;
        }
    }
    if (!reached) {
        [self capture:[prefix stringByAppendingString:@" candidate scroll — first boundary failure"] application:host];
        XCTFail(@"Expected unique candidate 79 蟻 fully contained and hittable after at most 16 More-viewport swipes");
        return;
    }
    [self capture:[prefix stringByAppendingString:@" candidate 79 visible before commit"] application:host];
    [target tap];
    if (![self expectValue:@"1蟻" of:multi stage:[prefix stringByAppendingString:@" landscape candidate committed"] application:host]) return;
    if (![self requireHeightCollapsedKeys:host withComposition:NO
        stage:[prefix stringByAppendingString:@" landscape collapsed keys restored"]]) return;
    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    if (![self requireHeightCollapsedKeys:host withComposition:YES
        stage:[prefix stringByAppendingString:@" landscape collapsed raw c before reopening"]]) return;
    more = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"candidate.more"]
        stage:[prefix stringByAppendingString:@" landscape More reopen control"] application:host];
    if (!more) return;
    [more tap];
    if (![self verifyHeightMoreOrientation:UIDeviceOrientationLandscapeLeft landscape:YES field:multi
        application:host stage:[prefix stringByAppendingString:@" landscape expanded again"]]) return;
    if (![self verifyHeightMoreOrientation:UIDeviceOrientationPortrait landscape:NO field:multi
        application:host stage:@"Height expanded portrait after rotation"]) return;
    if (![self expectValue:@"1蟻" of:multi stage:[prefix stringByAppendingString:@" portrait preserves multiline"] application:host]) return;
    more = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"candidate.more"]
        stage:[prefix stringByAppendingString:@" portrait More collapse control"] application:host];
    if (!more) return;
    [more tap];
    if (![self requireHeightCollapsedKeys:host withComposition:YES
        stage:[prefix stringByAppendingString:@" portrait collapsed composition preserved"]]) return;
    XCUIElement *first = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"candidate.inline.0"]
        stage:[prefix stringByAppendingString:@" inline first candidate"] application:host];
    if (!first) return;
    if (![first.label isEqualToString:@"七"]) {
        [self capture:[prefix stringByAppendingString:@" inline candidate — first boundary failure"] application:host];
        XCTFail(@"Expected inline 七, observed %@", first.label);
        return;
    }
    [first tap];
    if (![self expectValue:@"1蟻七" of:multi stage:[prefix stringByAppendingString:@" inline candidate committed"] application:host]) return;
    if (![self tapKeyboardControl:@"key.delete" application:host]) return;
    if (![self expectValue:@"1蟻" of:multi stage:[prefix stringByAppendingString:@" Delete after More"] application:host]) return;
    if (![self tapKeyboardControl:@"key.return" application:host]) return;
    if (![self expectValue:@"1蟻\n" of:multi stage:[prefix stringByAppendingString:@" multiline Return after More"] application:host]) return;
    [self capture:[prefix stringByAppendingString:@" installed scenario complete"] application:host];
}

- (void)testInstalledHeight90ExtraSmallLight {
    [self runInstalledHeightScenario:90 normalizedPosition:0.0];
}

- (void)testInstalledHeight220AccessibilityDark {
    [self runInstalledHeightScenario:220 normalizedPosition:1.0];
}

- (XCUIApplication *)launchInstalledActionHost:(NSString *)stage {
    [XCUIDevice sharedDevice].orientation = UIDeviceOrientationPortrait;
    XCUIApplication *host = [[XCUIApplication alloc] initWithBundleIdentifier:@"osku.me.freeshiamyios"];
    NSString *runID = [NSUUID UUID].UUIDString;
    host.launchEnvironment = @{@"FSH_INSTALLED_SMOKE_RUN_ID": runID};
    [host launch];
    XCTAttachment *marker = [XCTAttachment attachmentWithString:runID];
    marker.name = @"Installed smoke host-geometry run ID";
    marker.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:marker];
    [self capture:stage application:host];
    return host;
}

// 1 means a real extension was normalized, 0 means no extension control is
// visible, and -1 means an observed extension state failed its boundary.
- (NSInteger)normalizeInstalledActionKeyboardMode:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElementQuery *modes = [host.buttons matchingIdentifier:@"key.mode"];
    if (modes.count > 1) {
        [self capture:[stage stringByAppendingString:@" ambiguous extension mode — first boundary failure"] application:host];
        XCTFail(@"%@: expected one extension mode control, found %lu", stage, (unsigned long)modes.count);
        return -1;
    }
    if (modes.count == 1) {
        XCUIElement *mode = [self requireVisibleUnique:modes
            stage:[stage stringByAppendingString:@" actual extension mode"] application:host];
        if (!mode) return -1;
        if ([mode.label isEqualToString:@"切換至字母鍵盤"]) {
            [mode tap];
            [self capture:[stage stringByAppendingString:@" changed actual extension to letters"] application:host];
        } else if (![mode.label isEqualToString:@"切換至符號鍵盤"]) {
            [self capture:[stage stringByAppendingString:@" unknown extension mode — first boundary failure"] application:host];
            XCTFail(@"%@: unrecognized actual extension mode label %@", stage, mode.label);
            return -1;
        }
        return [self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.letter.c"]
            stage:[stage stringByAppendingString:@" actual letters after mode normalization"] application:host] ? 1 : -1;
    }
    XCUIElementQuery *extensionControls = [host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", @"key.", @"candidate."]];
    for (XCUIElement *control in extensionControls.allElementsBoundByIndex) {
        if ([self isOnScreen:control application:host] && control.isHittable) {
            [self capture:[stage stringByAppendingString:@" extension without mode — first boundary failure"] application:host];
            XCTFail(@"%@: visible extension control %@ without a unique known mode", stage, control.identifier);
            return -1;
        }
    }
    return 0;
}

- (BOOL)readyInstalledActionKeyboard:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElement *letter = [host.buttons matchingIdentifier:@"key.letter.c"].firstMatch;
    [letter waitForExistenceWithTimeout:5.0];
    NSInteger normalized = [self normalizeInstalledActionKeyboardMode:host stage:stage];
    if (normalized < 0) return NO;
    if (normalized == 0) {
        XCUIElementQuery *switchers = [host.buttons matchingPredicate:
            [NSPredicate predicateWithFormat:@"label == %@ OR label == %@", @"Next keyboard", @"Globe"]];
        XCUIElement *switcher = [self requireVisibleUnique:switchers
            stage:[stage stringByAppendingString:@" observed system switcher"] application:host];
        if (!switcher) return NO;
        [switcher pressForDuration:1.2];
        [self capture:[stage stringByAppendingString:@" actual input-mode picker"] application:host];
        XCUIElement *choice = [self observedInputSwitcherCell:@"FreeShiamy — freeshiamy-ios, Chinese"
            stage:[stage stringByAppendingString:@" FreeShiamy picker choice"] application:host];
        if (!choice) return NO;
        [choice tap];
        if (![self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.mode"]
            stage:[stage stringByAppendingString:@" extension mode after picker"] application:host]) return NO;
        normalized = [self normalizeInstalledActionKeyboardMode:host
            stage:[stage stringByAppendingString:@" after real picker selection"]];
        if (normalized < 0) return NO;
        if (normalized == 0) {
            [self capture:[stage stringByAppendingString:@" selected extension missing — first boundary failure"] application:host];
            XCTFail(@"%@: selected extension exposes no actual mode control", stage);
            return NO;
        }
    }
    if (![self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.letter.c"]
        stage:[stage stringByAppendingString:@" installed letters visible"] application:host]) return NO;
    XCUIElement *status = [host.staticTexts matchingIdentifier:@"candidate.status"].firstMatch;
    XCTNSPredicateExpectation *loaded = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] object:status];
    if ([XCTWaiter waitForExpectations:@[loaded] timeout:30.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" dictionary — first boundary failure"] application:host];
        XCTFail(@"%@: installed dictionary did not become ready", stage);
        return NO;
    }
    [self capture:[stage stringByAppendingString:@" dictionary ready"] application:host];
    return YES;
}

- (BOOL)expectActionRaw:(NSString *)expected allowEmpty:(BOOL)allowEmpty
            application:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElementQuery *raws = [host.buttons matchingIdentifier:@"candidate.raw"];
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        if (!expected) {
            return raws.count == 0 || (allowEmpty && raws.count == 1 && raws.firstMatch.label.length == 0);
        }
        return raws.count == 1 && [raws.firstMatch.label isEqualToString:expected] &&
            [self isOnScreen:raws.firstMatch application:host] && raws.firstMatch.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:host];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: expected raw %@, found %lu controls and label %@", stage, expected ?: @"absent",
                (unsigned long)raws.count, raws.count == 1 ? raws.firstMatch.label : @"not unique");
        return NO;
    }
    [self capture:stage application:host];
    return YES;
}

- (XCUIElement *)requireActionLabel:(NSString *)label query:(XCUIElementQuery *)query
                              stage:(NSString *)stage application:(XCUIApplication *)host {
    XCUIElement *element = query.firstMatch;
    NSPredicate *ready = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return query.count == 1 && [element.label isEqualToString:label] &&
            [self isOnScreen:element application:host] && element.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:ready object:element];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:20.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: expected unique visible label %@, found %lu and %@", stage, label,
                (unsigned long)query.count, query.count == 1 ? element.label : @"not unique");
        return nil;
    }
    [self capture:stage application:host];
    return element;
}

- (BOOL)expectCodeSearchEmptyQuery:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElementQuery *queries = [host.textFields matchingIdentifier:@"codeSearch.query"];
    XCUIElementQuery *results = [host.staticTexts matchingIdentifier:@"codeSearch.results"];
    XCUIElement *query = queries.firstMatch;
    XCUIElement *result = results.firstMatch;
    NSString *placeholder = @"輸入要查的字";
    NSPredicate *empty = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        if (queries.count != 1 || results.count != 1) return NO;
        id value = query.value;
        BOOL emptyValue = value == nil || ([value isKindOfClass:NSString.class] &&
            ([(NSString *)value isEqualToString:@""] || [(NSString *)value isEqualToString:placeholder]));
        return emptyValue &&
            [query.placeholderValue isEqualToString:placeholder] &&
            [result.label isEqualToString:@"輸入一個或多個字開始查詢。"] &&
            [self isOnScreen:query application:host] && query.isHittable &&
            [self isOnScreen:result application:host] && result.isHittable;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:empty object:host];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:20.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        NSUInteger queryCount = queries.count;
        NSUInteger resultsCount = results.count;
        id observedValue = queryCount == 1 ? query.value : @"query not unique";
        NSString *valueClass = queryCount == 1
            ? (observedValue ? NSStringFromClass([observedValue class]) : @"nil") : @"query not unique";
        NSString *observedPlaceholder = queryCount == 1 ? query.placeholderValue : @"query not unique";
        NSLog(@"[CodeSearchEmptyQuery] stage=%@ queryCount=%lu resultsCount=%lu valueClass=%@ value=%@ placeholder=%@",
              stage, (unsigned long)queryCount, (unsigned long)resultsCount,
              valueClass, observedValue, observedPlaceholder);
        XCTFail(@"%@: expected unique visible empty CodeSearch placeholder/query and dictionary-ready empty results", stage);
        return NO;
    }
    [self capture:stage application:host];
    return YES;
}

- (BOOL)requireActionKeyboardDismissed:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElementQuery *letters = [host.buttons matchingIdentifier:@"key.letter.c"];
    XCUIElementQuery *returns = [host.buttons matchingIdentifier:@"key.return"];
    NSPredicate *gone = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return letters.count == 0 && returns.count == 0 && host.keyboards.count == 0;
    }];
    XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:gone object:host];
    if ([XCTWaiter waitForExpectations:@[expectation] timeout:15.0] != XCTWaiterResultCompleted) {
        [self capture:[stage stringByAppendingString:@" — first boundary failure"] application:host];
        XCTFail(@"%@: actual keyboard did not dismiss after host Search", stage);
        return NO;
    }
    [self capture:stage application:host];
    return YES;
}

- (BOOL)requireInstalledActionHeight100:(XCUIApplication *)host stage:(NSString *)stage {
    XCUIElement *settings = [self hostControlByScrolling:[host.buttons matchingIdentifier:@"smoke.appSettings"]
        stage:[stage stringByAppendingString:@" actual Settings action"] application:host];
    if (!settings) return NO;
    [settings tap];
    XCUIElement *bar = [self requireVisibleUnique:[host.navigationBars matchingIdentifier:@"設定"]
        stage:[stage stringByAppendingString:@" actual Settings navigation"] application:host];
    XCUIElement *slider = [self requireVisibleUnique:[host.sliders matchingIdentifier:@"settings.height.slider"]
        stage:[stage stringByAppendingString:@" actual height slider"] application:host];
    if (!bar || !slider) return NO;
    if (![self requireActionLabel:@"100%" query:[host.staticTexts matchingIdentifier:@"settings.height.value"]
        stage:[stage stringByAppendingString:@" observed height exactly 100%"] application:host]) return NO;
    XCUIElement *back = [self requireVisibleUnique:bar.buttons
        stage:[stage stringByAppendingString:@" unique Settings Back"] application:host];
    if (!back) return NO;
    [self capture:[NSString stringWithFormat:@"%@ Settings Back label: %@", stage, back.label] application:host];
    [back tap];
    [self capture:[stage stringByAppendingString:@" returned from Settings without changing height"] application:host];
    return YES;
}

- (void)testInstalledBracketRootsUseRealLongPressAndLiteralSymbols {
    XCUIApplication *host = [self launchInstalledActionHost:@"Bracket roots fresh portrait host"];
    if (![self requireInstalledActionHeight100:host stage:@"Bracket roots baseline settings"]) return;
    XCUIElement *multi = [self hostControlByScrolling:[host.textViews matchingIdentifier:@"smoke.multiLine"]
        stage:@"Bracket roots initially empty multiline field" application:host];
    if (!multi) return;
    if (![self expectValue:@"" of:multi stage:@"Bracket roots initial host empty" application:host]) return;
    [multi tap];
    if (![self readyInstalledActionKeyboard:host stage:@"Bracket roots activation"]) return;
    if (![self expectActionRaw:nil allowEmpty:YES application:host stage:@"Bracket roots initial composition empty"]) return;

    XCUIElement *open = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.root.open"]
        stage:@"Opening root before real long press" application:host];
    if (!open) return;
    [open pressForDuration:0.6];
    if (![self expectActionRaw:@"[" allowEmpty:NO application:host stage:@"Opening root after real long press"]) return;
    if (![self expectValue:@"" of:multi stage:@"Opening root inserted no primary comma" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.f" application:host]) return;
    if (![self expectActionRaw:@"[f" allowEmpty:NO application:host stage:@"Opening root f composition"]) return;
    XCUIElement *first = [self requireActionLabel:@"【" query:[host.buttons matchingIdentifier:@"candidate.inline.0"]
        stage:@"Opening bracket exact first candidate" application:host];
    if (!first) return;
    [first tap];
    if (![self expectValue:@"【" of:multi stage:@"Opening bracket candidate committed" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"Opening bracket composition cleared"]) return;

    XCUIElement *close = [self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.root.close"]
        stage:@"Closing root before real long press" application:host];
    if (!close) return;
    [close pressForDuration:0.6];
    if (![self expectActionRaw:@"]" allowEmpty:NO application:host stage:@"Closing root after real long press"]) return;
    if (![self expectValue:@"【" of:multi stage:@"Closing root inserted no primary period" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.f" application:host]) return;
    if (![self expectActionRaw:@"]f" allowEmpty:NO application:host stage:@"Closing root f composition"]) return;
    first = [self requireActionLabel:@"】" query:[host.buttons matchingIdentifier:@"candidate.inline.0"]
        stage:@"Closing bracket exact first candidate" application:host];
    if (!first) return;
    [first tap];
    if (![self expectValue:@"【】" of:multi stage:@"Closing bracket candidate committed" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"Closing bracket composition cleared"]) return;

    if (![self tapKeyboardControl:@"key.mode" application:host]) return;
    XCUIElement *page = [self requireVisibleUnique:[host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@", @"符號頁面"]]
        stage:@"Literal brackets actual symbol page" application:host];
    if (!page) return;
    if (![page.value isEqual:@"第一頁"]) {
        [self capture:@"Literal bracket symbol page — first boundary failure" application:host];
        XCTFail(@"Expected actual symbol page 第一頁, observed %@", page.value);
        return;
    }
    XCUIElement *literal = [self requireActionLabel:@"[" query:[host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@", @"["]]
        stage:@"Literal opening bracket on symbols" application:host];
    if (!literal) return;
    [literal tap];
    if (![self expectValue:@"【】[" of:multi stage:@"Symbols inserted literal opening bracket" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"Literal opening bracket has no raw composition"]) return;
    literal = [self requireActionLabel:@"]" query:[host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@", @"]"]]
        stage:@"Literal closing bracket on symbols" application:host];
    if (!literal) return;
    [literal tap];
    if (![self expectValue:@"【】[]" of:multi stage:@"Symbols inserted both literal brackets exactly" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"Literal closing bracket has no raw composition"]) return;
    [self capture:@"Installed bracket-root and symbol gestures complete" application:host];
}

- (void)testInstalledCodeSearchReturnCommitsThenDismisses {
    XCUIApplication *host = [self launchInstalledActionHost:@"CodeSearch fresh portrait host"];
    if (![self requireInstalledActionHeight100:host stage:@"CodeSearch baseline settings"]) return;
    XCUIElement *action = [self hostControlByScrolling:[host.buttons matchingPredicate:
        [NSPredicate predicateWithFormat:@"label == %@", @"查嘸蝦米字根"]]
        stage:@"CodeSearch actual main-panel action" application:host];
    if (!action) return;
    [action tap];
    XCUIElement *query = [self requireVisibleUnique:[host.textFields matchingIdentifier:@"codeSearch.query"]
        stage:@"CodeSearch actual query field" application:host];
    XCUIElement *results = [self requireVisibleUnique:[host.staticTexts matchingIdentifier:@"codeSearch.results"]
        stage:@"CodeSearch actual results view" application:host];
    if (!query || !results) return;
    if (![self expectCodeSearchEmptyQuery:host stage:@"CodeSearch query initially empty"]) return;
    [query tap];
    if (![self readyInstalledActionKeyboard:host stage:@"CodeSearch activation"]) return;
    if (![self requireActionLabel:@"搜尋" query:[host.buttons matchingIdentifier:@"key.return"]
        stage:@"CodeSearch installed Search trait" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.i" application:host]) return;
    if (![self expectActionRaw:@"ci" allowEmpty:NO application:host stage:@"CodeSearch live ci composition"]) return;
    if (![self expectCodeSearchEmptyQuery:host stage:@"CodeSearch composition keeps host query empty"]) return;
    if (![self tapKeyboardControl:@"key.return" application:host]) return;
    if (![self expectValue:@"ci" of:query stage:@"First Search commits literal ci" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"First Search clears raw composition"]) return;
    if (![self requireVisibleUnique:[host.buttons matchingIdentifier:@"key.letter.c"]
        stage:@"First Search leaves installed keyboard active" application:host]) return;
    if (![self requireActionLabel:@"搜尋" query:[host.buttons matchingIdentifier:@"key.return"]
        stage:@"First Search preserves Search label" application:host]) return;
    if (![self tapKeyboardControl:@"key.return" application:host]) return;
    if (![self requireActionKeyboardDismissed:host stage:@"Second Search dismisses through CodeSearch host"]) return;
    if (![self expectValue:@"ci" of:query stage:@"Second Search adds no newline to query" application:host]) return;

    query = [self requireVisibleUnique:[host.textFields matchingIdentifier:@"codeSearch.query"]
        stage:@"CodeSearch query before refocus" application:host];
    if (!query) return;
    [query tap];
    if (![self readyInstalledActionKeyboard:host stage:@"CodeSearch refocus activation"]) return;
    if (![self tapKeyboardControl:@"key.delete" application:host]) return;
    if (![self expectValue:@"c" of:query stage:@"First Delete removes i from actual query" application:host]) return;
    if (![self tapKeyboardControl:@"key.delete" application:host]) return;
    if (![self expectCodeSearchEmptyQuery:host stage:@"Second Delete empties actual query"]) return;
    if (![self tapKeyboardControl:@"key.letter.c" application:host]) return;
    if (![self tapKeyboardControl:@"key.letter.i" application:host]) return;
    if (![self expectActionRaw:@"ci" allowEmpty:NO application:host stage:@"CodeSearch recomposed ci"]) return;
    XCUIElement *middle = [self requireActionLabel:@"中" query:[host.buttons matchingIdentifier:@"candidate.inline.0"]
        stage:@"CodeSearch actual 中 candidate" application:host];
    if (!middle) return;
    [middle tap];
    if (![self expectValue:@"中" of:query stage:@"CodeSearch 中 candidate committed" application:host]) return;
    if (![self expectActionRaw:nil allowEmpty:NO application:host stage:@"CodeSearch 中 composition cleared"]) return;
    NSString *expectedResults = @"中：最短 CI；其他 CJ、CJV";
    if (![self requireActionLabel:expectedResults query:[host.staticTexts matchingIdentifier:@"codeSearch.results"]
        stage:@"CodeSearch exact native code-search results" application:host]) return;
    if (![self requireActionLabel:@"搜尋" query:[host.buttons matchingIdentifier:@"key.return"]
        stage:@"CodeSearch Search before final dismissal" application:host]) return;
    if (![self tapKeyboardControl:@"key.return" application:host]) return;
    if (![self requireActionKeyboardDismissed:host stage:@"Search dismisses with 中 results"]) return;
    if (![self expectValue:@"中" of:query stage:@"Search preserves committed 中 query" application:host]) return;
    if (![self requireActionLabel:expectedResults query:[host.staticTexts matchingIdentifier:@"codeSearch.results"]
        stage:@"Search preserves exact 中 results" application:host]) return;
    [self capture:@"Installed CodeSearch Return behavior complete" application:host];
}

@end
