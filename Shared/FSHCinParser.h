#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FSHCandidate;

@interface FSHCinParser : NSObject

+ (NSArray<FSHCandidate *> *)parseCinAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
