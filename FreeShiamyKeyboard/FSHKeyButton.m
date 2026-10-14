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
    [self updateAlternateHintTypography];
    [self setNeedsLayout];
}

- (void)updateAlternateHintTypography {
    if (!self.alternateHintLabel) { return; }
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat cap = (isfinite(height) && height > 0.0) ? MAX(8.0, MIN(14.0, height * 0.27)) : 10.0;
    UIFont *base = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
    UIFont *font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
        scaledFontForFont:base maximumPointSize:cap compatibleWithTraitCollection:self.traitCollection];
    if (fabs(self.alternateHintLabel.font.pointSize - font.pointSize) > 0.1) {
        self.alternateHintLabel.font = font;
    }
    if (isfinite(height) && height > 0.0) {
        CGFloat availableTitleLine = height - font.lineHeight - 3.0;
        UIFont *titleFont = self.titleLabel.font;
        if (availableTitleLine > 0.0 && titleFont.lineHeight > availableTitleLine) {
            CGFloat fittedPointSize = MAX(8.0, titleFont.pointSize * availableTitleLine / titleFont.lineHeight - 0.5);
            if (fittedPointSize < titleFont.pointSize - 0.1) {
                self.titleLabel.font = [titleFont fontWithSize:fittedPointSize];
            }
        }
        BOOL showHint = self.titleLabel.font.lineHeight + font.lineHeight + 3.0 <= height;
        self.alternateHintLabel.hidden = !showHint;
        if (showHint) {
            self.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
            self.contentEdgeInsets = UIEdgeInsetsMake(0.0, 1.0, MIN(2.0, height * 0.05), 1.0);
        } else {
            // No two-line treatment fits: give the one visible primary glyph
            // the whole row rather than leaving it at the two-line minimum.
            UIFont *base = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
            UIFont *single = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
                scaledFontForFont:base maximumPointSize:MAX(8.0, MIN(30.0, height * 0.62))
                compatibleWithTraitCollection:self.traitCollection];
            if (single.lineHeight > height - 2.0) {
                single = [single fontWithSize:MAX(8.0, single.pointSize * (height - 2.0) / single.lineHeight - 0.5)];
            }
            self.titleLabel.font = single;
            self.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
            self.contentEdgeInsets = UIEdgeInsetsMake(0.0, 1.0, 0.0, 1.0);
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection ||
        [previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        return;
    }
    [self updateAlternateHintTypography];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.alternateHintLabel) {
        [self updateAlternateHintTypography];
        [super layoutSubviews];
        // At a host-constrained height the primary label takes priority; the
        // alternate accessibility action remains available even without hint.
        CGFloat width = MIN(MAX(16.0, self.alternateHintLabel.font.pointSize + 4.0), MAX(0.0, CGRectGetWidth(self.bounds) - 2.0));
        self.alternateHintLabel.frame = CGRectMake(MAX(0.0, CGRectGetWidth(self.bounds) - width - 2.0),
                                                   1.0, width, MIN(self.alternateHintLabel.font.lineHeight, CGRectGetHeight(self.bounds)));
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
