#import <UIKit/UIKit.h>
#import <math.h>

// Shared candidate geometry.  These are desired sizes; the host can assign a
// smaller input-view height, in which case the expanded list becomes a viewport.
static inline CGFloat FSHCandidateBarDesiredHeight(UITraitCollection *traits) {
    UIFont *base = [UIFont systemFontOfSize:18.0];
    UIFont *scaled = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:base maximumPointSize:27.0 compatibleWithTraitCollection:traits];
    return MAX(37.5, MIN(56.0, ceil(scaled.lineHeight + 13.0)));
}

static inline CGFloat FSHCandidateRowDesiredHeight(UITraitCollection *traits) {
    UIFont *base = [UIFont systemFontOfSize:18.0];
    UIFont *scaled = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:base maximumPointSize:27.0 compatibleWithTraitCollection:traits];
    return MAX(37.5, MIN(54.0, ceil(scaled.lineHeight + 12.0)));
}

static inline CGFloat FSHNonnegativeFinite(CGFloat value) {
    return isfinite(value) ? MAX(0.0, value) : 0.0;
}

static inline CGFloat FSHSceneKeyboardHeightLimit(CGFloat sceneHeight, CGFloat safeTop, CGFloat safeBottom) {
    CGFloat usable = MAX(0.0, FSHNonnegativeFinite(sceneHeight) - FSHNonnegativeFinite(safeTop)
                          - FSHNonnegativeFinite(safeBottom));
    return MAX(0.0, MIN(usable * 0.60, usable - 44.0));
}
