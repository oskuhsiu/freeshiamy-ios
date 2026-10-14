#import "FSHKeyButton.h"

@implementation FSHKeyButton

- (BOOL)accessibilityActivate {
    if (self.accessibilityActivationHandler) {
        self.accessibilityActivationHandler();
        return YES;
    }
    return [super accessibilityActivate];
}

@end
