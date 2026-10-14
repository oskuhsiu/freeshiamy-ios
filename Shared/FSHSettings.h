#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSHSettings : NSObject

+ (NSUserDefaults *)sharedDefaults;
+ (void)registerDefaults;
// Call from the containing app at launch, before registering defaults. The
// extension only reads shared settings and never performs this migration.
+ (void)migrateLegacySettings;
+ (void)migrateLegacySettingsFromDefaults:(NSUserDefaults *)legacyDefaults
                               suiteName:(NSString *)legacySuiteName
                              toDefaults:(NSUserDefaults *)sharedDefaults
                               suiteName:(NSString *)sharedSuiteName;
+ (BOOL)hasPersistedSettingForKey:(NSString *)key;

+ (NSInteger)keyboardHeightPercent;
+ (void)setKeyboardHeightPercent:(NSInteger)value;

+ (NSString *)keyboardLayout;
+ (void)setKeyboardLayout:(NSString *)value;

+ (BOOL)showNumberRow;
+ (BOOL)effectiveShowNumberRow;
+ (void)setShowNumberRow:(BOOL)value;

+ (BOOL)keyboardLabelTop;
+ (BOOL)effectiveKeyboardLabelTop;
+ (void)setKeyboardLabelTop:(BOOL)value;

+ (BOOL)keyboardLeftShift;
+ (void)setKeyboardLeftShift:(BOOL)value;

+ (NSInteger)candidateInlineLimit;
+ (void)setCandidateInlineLimit:(NSInteger)value;

+ (NSInteger)candidateMoreLimit;
+ (void)setCandidateMoreLimit:(NSInteger)value;

+ (BOOL)showShortestCodeHint;
+ (void)setShowShortestCodeHint:(BOOL)value;

+ (BOOL)disableImeInSensitiveFields;
+ (void)setDisableImeInSensitiveFields:(BOOL)value;

+ (BOOL)sensitiveIncludeNoPersonalizedLearning;
+ (void)setSensitiveIncludeNoPersonalizedLearning:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
