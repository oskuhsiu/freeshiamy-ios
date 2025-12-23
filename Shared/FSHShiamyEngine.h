#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FSHCandidate;

@interface FSHShiamyEngine : NSObject

@property (nonatomic, assign, readonly) BOOL ready;

- (BOOL)loadFromBundle:(NSBundle *)bundle error:(NSError * _Nullable * _Nullable)error;

- (NSArray<FSHCandidate *> *)prefixCandidatesForCode:(NSString *)code exactCount:(NSUInteger * _Nullable)exactCount;
- (NSArray<FSHCandidate *> *)reverseLookupCandidatesForBaseValue:(NSString *)baseValue;
- (nullable NSString *)shortestCodeForValue:(NSString *)value;
- (nullable NSString *)spellForValue:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
