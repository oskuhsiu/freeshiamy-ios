#import "FSHSettings.h"

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
    return [[self sharedDefaults] integerForKey:kFSHKeyKeyboardHeightPercent];
}

+ (void)setKeyboardHeightPercent:(NSInteger)value {
    [[self sharedDefaults] setInteger:value forKey:kFSHKeyKeyboardHeightPercent];
}

+ (NSString *)keyboardLayout {
    NSString *value = [[self sharedDefaults] stringForKey:kFSHKeyKeyboardLayout];
    return value.length > 0 ? value : @"standard";
}

+ (void)setKeyboardLayout:(NSString *)value {
    if (value.length == 0) {
        value = @"standard";
    }
    [[self sharedDefaults] setObject:value forKey:kFSHKeyKeyboardLayout];
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
    NSInteger value = [[self sharedDefaults] integerForKey:kFSHKeyCandidateInlineLimit];
    return value > 0 ? value : 10;
}

+ (void)setCandidateInlineLimit:(NSInteger)value {
    [[self sharedDefaults] setInteger:value forKey:kFSHKeyCandidateInlineLimit];
}

+ (NSInteger)candidateMoreLimit {
    NSInteger value = [[self sharedDefaults] integerForKey:kFSHKeyCandidateMoreLimit];
    return value > 0 ? value : 200;
}

+ (void)setCandidateMoreLimit:(NSInteger)value {
    [[self sharedDefaults] setInteger:value forKey:kFSHKeyCandidateMoreLimit];
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
