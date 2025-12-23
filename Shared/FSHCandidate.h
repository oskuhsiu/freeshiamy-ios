#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSHCandidate : NSObject

@property (nonatomic, copy, readonly) NSString *code;
@property (nonatomic, copy, readonly) NSString *value;

- (instancetype)initWithCode:(NSString *)code value:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
