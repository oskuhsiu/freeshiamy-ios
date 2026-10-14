#import "FSHSettings.h"
#import <math.h>

static NSString *const kFSHAppGroup = @"group.osku.me.freeshiamy";

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

@implementation FSHSettings

+ (NSUserDefaults *)sharedDefaults {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kFSHAppGroup];
    return defaults ?: [NSUserDefaults standardUserDefaults];
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
    return [[self sharedDefaults] boolForKey:kFSHKeyShowNumberRow];
}

+ (void)setShowNumberRow:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyShowNumberRow];
}

+ (BOOL)keyboardLabelTop {
    return [[self sharedDefaults] boolForKey:kFSHKeyKeyboardLabelTop];
}

+ (void)setKeyboardLabelTop:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyKeyboardLabelTop];
}

+ (BOOL)keyboardLeftShift {
    return [[self sharedDefaults] boolForKey:kFSHKeyKeyboardLeftShift];
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
    return [[self sharedDefaults] boolForKey:kFSHKeyShowShortestCodeHint];
}

+ (void)setShowShortestCodeHint:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyShowShortestCodeHint];
}

+ (BOOL)disableImeInSensitiveFields {
    return [[self sharedDefaults] boolForKey:kFSHKeyDisableImeSensitive];
}

+ (void)setDisableImeInSensitiveFields:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeyDisableImeSensitive];
}

+ (BOOL)sensitiveIncludeNoPersonalizedLearning {
    return [[self sharedDefaults] boolForKey:kFSHKeySensitiveNoPersonalized];
}

+ (void)setSensitiveIncludeNoPersonalizedLearning:(BOOL)value {
    [[self sharedDefaults] setBool:value forKey:kFSHKeySensitiveNoPersonalized];
}

@end
