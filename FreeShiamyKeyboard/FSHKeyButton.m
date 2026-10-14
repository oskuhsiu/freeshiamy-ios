#import "FSHKeyButton.h"
#import <math.h>
#import <float.h>

@interface FSHKeyButton ()
@property (nonatomic, strong) UILabel *alternateHintLabel;
@end

@implementation FSHKeyButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectIsEmpty(self.bounds) || !isfinite(CGRectGetWidth(self.bounds)) ||
        !isfinite(CGRectGetHeight(self.bounds)) || !isfinite(point.x) || !isfinite(point.y)) {
        return NO;
    }
    CGRect hitBounds = CGRectMake(-self.hitAreaOutsets.left, -self.hitAreaOutsets.top,
                                  CGRectGetWidth(self.bounds) + self.hitAreaOutsets.left + self.hitAreaOutsets.right,
                                  CGRectGetHeight(self.bounds) + self.hitAreaOutsets.top + self.hitAreaOutsets.bottom);
    // The nominal hit rectangles meet exactly at each gap midpoint. UIKit's
    // parent-to-child conversion can round that shared edge one ULP away from
    // both rectangles. Include only a scale-relative floating-point guard at
    // the edge; the control uses this same predicate for tracking after hitTest.
    CGFloat scale = MAX(1.0, MAX(fabs(point.x), MAX(fabs(point.y),
        MAX(fabs(CGRectGetMaxX(hitBounds)), fabs(CGRectGetMaxY(hitBounds))))));
    CGFloat epsilon = 64.0 * DBL_EPSILON * scale;
    return point.x >= CGRectGetMinX(hitBounds) - epsilon &&
           point.x <= CGRectGetMaxX(hitBounds) + epsilon &&
           point.y >= CGRectGetMinY(hitBounds) - epsilon &&
           point.y <= CGRectGetMaxY(hitBounds) + epsilon;
}

- (void)setAlternateHint:(NSString *)alternateHint {
    _alternateHint = [alternateHint copy];
    if (_alternateHint.length == 0) {
        [self.alternateHintLabel removeFromSuperview];
        self.alternateHintLabel = nil;
        return;
    }
    if (!self.alternateHintLabel) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
        label.textColor = [UIColor secondaryLabelColor];
        label.textAlignment = NSTextAlignmentRight;
        label.isAccessibilityElement = NO;
        self.alternateHintLabel = label;
        [self addSubview:label];
    }
    self.alternateHintLabel.text = _alternateHint;
    self.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.8;
    self.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
    self.contentEdgeInsets = UIEdgeInsetsMake(0.0, 1.0, 2.0, 1.0);
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.alternateHintLabel) {
        CGFloat width = MIN(16.0, MAX(0.0, CGRectGetWidth(self.bounds) - 2.0));
        self.alternateHintLabel.frame = CGRectMake(MAX(0.0, CGRectGetWidth(self.bounds) - width - 2.0),
                                                   1.0, width, MIN(12.0, CGRectGetHeight(self.bounds)));
    }
}

- (BOOL)accessibilityActivate {
    if (self.accessibilityActivationHandler) {
        self.accessibilityActivationHandler();
        return YES;
    }
    return [super accessibilityActivate];
}

@end
