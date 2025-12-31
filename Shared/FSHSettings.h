#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSHSettings : NSObject

+ (NSUserDefaults *)sharedDefaults;
+ (void)registerDefaults;

+ (NSInteger)keyboardHeightPercent;
+ (void)setKeyboardHeightPercent:(NSInteger)value;

+ (NSString *)keyboardLayout;
+ (void)setKeyboardLayout:(NSString *)value;

+ (BOOL)showNumberRow;
+ (void)setShowNumberRow:(BOOL)value;

+ (BOOL)keyboardLabelTop;
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
