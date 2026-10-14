#import "FSHSettings.h"
#import <math.h>

static NSString *const kFSHAppGroup = @"group.osku.me.freeshiamy_ios";
static NSString *const kFSHLegacyAppGroup = @"group.osku.me.freeshiamy";

static NSString *const kFSHKeyKeyboardHeightPercent = @"keyboard_height_percent";
static NSString *const kFSHKeyKeyboardLayout = @"keyboard_layout";
static NSString *const kFSHKeyShowNumberRow = @"show_number_row";
static NSString *const kFSHKeyKeyboardLabelTop = @"keyboard_label_top";
static NSString *const kFSHKeyKeyboardLeftShift = @"keyboard_left_shift";
static NSString *const kFSHKeyCandidateInlineLimit = @"candidate_inline_limit";
static NSString *const kFSHKeyCandidateMoreLimit = @"candidate_more_limit";
static NSString *const kFSHKeyShowShortestCodeHint = @"show_shortest_code_hint";
static NSString *const kFSHKeyDisableImeSensitive = @"disable_ime_in_sensitive_fields";
static NSString *const kFSHKeySensitiveNoPersonalized = @"sensitive_field_include_no_personalized_learning";

static NSInteger FSHBoundedInteger(id value, NSInteger fallback, NSInteger minimum, NSInteger maximum) {
    // The application writes NSNumbers. Do not let NSUserDefaults coerce a corrupt
    // string, collection, fractional value, or non-finite number into a setting.
    if (![value isKindOfClass:[NSNumber class]]) {
        return fallback;
    }
    double number = [value doubleValue];
    if (!isfinite(number) || trunc(number) != number) {
        return fallback;
    }
    if (number <= (double)minimum) {
        return minimum;
    }
    if (number >= (double)maximum) {
        return maximum;
    }
    return [value integerValue];
}

static BOOL FSHStoredBoolean(id value, BOOL fallback) {
    if (![value isKindOfClass:NSNumber.class]) {
        return fallback;
    }
    double number = [value doubleValue];
    return (number == 0.0 || number == 1.0) ? [value boolValue] : fallback;
}

static NSString *FSHValidLayout(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"standard";
    }
    static NSSet<NSString *> *layouts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        layouts = [NSSet setWithArray:@[@"standard", @"standard_spacious", @"original",
                                        @"original_no_number", @"standard_label_top"]];
    });
    return [layouts containsObject:value] ? value : @"standard";
}

static BOOL FSHValidMigratedValue(NSString *key, id value) {
    if ([key isEqualToString:kFSHKeyKeyboardLayout]) {
        return [value isKindOfClass:NSString.class] &&
            [FSHValidLayout(value) isEqualToString:value];
    }
    if (![value isKindOfClass:NSNumber.class]) {
        return NO;
    }
    double number = [value doubleValue];
    if (!isfinite(number) || trunc(number) != number) {
        return NO;
    }
    if ([key isEqualToString:kFSHKeyKeyboardHeightPercent] ||
        [key isEqualToString:kFSHKeyCandidateInlineLimit] ||
        [key isEqualToString:kFSHKeyCandidateMoreLimit]) {
        return YES; // Range sanitation remains in the normal getter.
    }
    return number == 0.0 || number == 1.0;
}

@implementation FSHSettings

+ (void)migrateLegacySettings {
    NSUserDefaults *legacy = [[NSUserDefaults alloc] initWithSuiteName:kFSHLegacyAppGroup];
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:kFSHAppGroup];
    if (!legacy || !shared) {
        return;
    }
    [self migrateLegacySettingsFromDefaults:legacy suiteName:kFSHLegacyAppGroup
                                toDefaults:shared suiteName:kFSHAppGroup];
}

+ (void)migrateLegacySettingsFromDefaults:(NSUserDefaults *)legacyDefaults
                               suiteName:(NSString *)legacySuiteName
                              toDefaults:(NSUserDefaults *)sharedDefaults
                               suiteName:(NSString *)sharedSuiteName {
    // objectForKey: also sees registration defaults. Migrate only values the
    // user actually persisted, and never replace an existing destination key.
    NSDictionary<NSString *, id> *source = [legacyDefaults persistentDomainForName:legacySuiteName] ?: @{};
    NSDictionary<NSString *, id> *destination = [sharedDefaults persistentDomainForName:sharedSuiteName] ?: @{};
    NSArray<NSString *> *keys = @[
        kFSHKeyKeyboardHeightPercent, kFSHKeyKeyboardLayout, kFSHKeyShowNumberRow,
        kFSHKeyKeyboardLabelTop, kFSHKeyKeyboardLeftShift, kFSHKeyCandidateInlineLimit,
        kFSHKeyCandidateMoreLimit, kFSHKeyShowShortestCodeHint,
        kFSHKeyDisableImeSensitive, kFSHKeySensitiveNoPersonalized,
    ];
    for (NSString *key in keys) {
        id value = source[key];
        if (value && !destination[key] && FSHValidMigratedValue(key, value)) {
            [sharedDefaults setObject:value forKey:key];
        }
    }
    if (!destination[kFSHKeyKeyboardLayout]) {
        NSString *legacyLayout = source[kFSHKeyKeyboardLayout];
        if ([legacyLayout isKindOfClass:NSString.class]) {
            if ([legacyLayout isEqualToString:@"standard_label_top"]) {
                [sharedDefaults setObject:@"standard" forKey:kFSHKeyKeyboardLayout];
                if (!destination[kFSHKeyKeyboardLabelTop] &&
                    !FSHValidMigratedValue(kFSHKeyKeyboardLabelTop, source[kFSHKeyKeyboardLabelTop])) {
                    [sharedDefaults setBool:YES forKey:kFSHKeyKeyboardLabelTop];
                }
            } else if ([legacyLayout isEqualToString:@"original_no_number"]) {
                [sharedDefaults setObject:@"original" forKey:kFSHKeyKeyboardLayout];
                if (!destination[kFSHKeyShowNumberRow] &&
                    !FSHValidMigratedValue(kFSHKeyShowNumberRow, source[kFSHKeyShowNumberRow])) {
                    [sharedDefaults setBool:NO forKey:kFSHKeyShowNumberRow];
                }
            }
        }
    }
}

+ (NSUserDefaults *)sharedDefaults {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kFSHAppGroup];
    return defaults ?: [NSUserDefaults standardUserDefaults];
}

+ (BOOL)hasPersistedSettingForKey:(NSString *)key {
    NSDictionary *persisted = [[self sharedDefaults] persistentDomainForName:kFSHAppGroup];
    return persisted[key] != nil;
}

+ (void)registerDefaults {
    NSDictionary *defaults = @{
        kFSHKeyKeyboardHeightPercent: @100,
        kFSHKeyKeyboardLayout: @"standard",
        kFSHKeyShowNumberRow: @YES,
        kFSHKeyKeyboardLabelTop: @NO,
        kFSHKeyKeyboardLeftShift: @YES,
        kFSHKeyCandidateInlineLimit: @10,
        kFSHKeyCandidateMoreLimit: @200,
        kFSHKeyShowShortestCodeHint: @YES,
        kFSHKeyDisableImeSensitive: @YES,
        kFSHKeySensitiveNoPersonalized: @NO,
    };
    [[self sharedDefaults] registerDefaults:defaults];
}

+ (NSInteger)keyboardHeightPercent {
    return FSHBoundedInteger([[self sharedDefaults] objectForKey:kFSHKeyKeyboardHeightPercent], 100, 90, 220);
}

+ (void)setKeyboardHeightPercent:(NSInteger)value {
    [[self sharedDefaults] setInteger:MAX(90, MIN(value, 220)) forKey:kFSHKeyKeyboardHeightPercent];
}

+ (NSString *)keyboardLayout {
    return FSHValidLayout([[self sharedDefaults] objectForKey:kFSHKeyKeyboardLayout]);
}

+ (void)setKeyboardLayout:(NSString *)value {
    [[self sharedDefaults] setObject:FSHValidLayout(value) forKey:kFSHKeyKeyboardLayout];
}

+ (BOOL)showNumberRow {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeyShowNumberRow], YES);
}

+ (BOOL)effectiveShowNumberRow {
    if ([[self keyboardLayout] isEqualToString:@"original_no_number"] &&
        ![self hasPersistedSettingForKey:kFSHKeyShowNumberRow]) {
        return NO;
    }
    return [self showNumberRow];
}

+ (void)setShowNumberRow:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyShowNumberRow];
}

+ (BOOL)keyboardLabelTop {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeyKeyboardLabelTop], NO);
}

+ (BOOL)effectiveKeyboardLabelTop {
    if ([[self keyboardLayout] isEqualToString:@"standard_label_top"] &&
        ![self hasPersistedSettingForKey:kFSHKeyKeyboardLabelTop]) {
        return YES;
    }
    return [self keyboardLabelTop];
}

+ (void)setKeyboardLabelTop:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyKeyboardLabelTop];
}

+ (BOOL)keyboardLeftShift {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeyKeyboardLeftShift], YES);
}

+ (void)setKeyboardLeftShift:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyKeyboardLeftShift];
}

+ (NSInteger)candidateInlineLimit {
    return FSHBoundedInteger([[self sharedDefaults] objectForKey:kFSHKeyCandidateInlineLimit], 10, 5, 20);
}

+ (void)setCandidateInlineLimit:(NSInteger)value {
    [[self sharedDefaults] setInteger:MAX(5, MIN(value, 20)) forKey:kFSHKeyCandidateInlineLimit];
}

+ (NSInteger)candidateMoreLimit {
    return FSHBoundedInteger([[self sharedDefaults] objectForKey:kFSHKeyCandidateMoreLimit], 200, 50, 500);
}

+ (void)setCandidateMoreLimit:(NSInteger)value {
    [[self sharedDefaults] setInteger:MAX(50, MIN(value, 500)) forKey:kFSHKeyCandidateMoreLimit];
}

+ (BOOL)showShortestCodeHint {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeyShowShortestCodeHint], YES);
}

+ (void)setShowShortestCodeHint:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyShowShortestCodeHint];
}

+ (BOOL)disableImeInSensitiveFields {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeyDisableImeSensitive], YES);
}

+ (void)setDisableImeInSensitiveFields:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyDisableImeSensitive];
}

+ (BOOL)sensitiveIncludeNoPersonalizedLearning {
    return FSHStoredBoolean([[self sharedDefaults] objectForKey:kFSHKeySensitiveNoPersonalized], NO);
}

+ (void)setSensitiveIncludeNoPersonalizedLearning:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeySensitiveNoPersonalized];
}

@end
