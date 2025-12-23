#import "FSHCandidate.h"

@implementation FSHCandidate

- (instancetype)initWithCode:(NSString *)code value:(NSString *)value {
    self = [super init];
    if (self) {
        _code = [code copy];
        _value = [value copy];
    }
    return self;
}

@end
