#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class FSHCandidate;
@class FSHCandidateBarView;

typedef NS_ENUM(NSInteger, FSHCandidateSelectionContext) {
    FSHCandidateSelectionContextLetters,
    FSHCandidateSelectionContextSymbols,
    FSHCandidateSelectionContextReverseEntering,
    FSHCandidateSelectionContextReverseActive,
};

@protocol FSHCandidateBarViewDelegate <NSObject>
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView;
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index;
- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded;
@optional
- (void)candidateBarView:(FSHCandidateBarView *)barView didReceiveInputModeEvent:(nullable UIEvent *)event fromView:(UIView *)view;
- (void)candidateBarViewDidActivateCompactGlobe:(FSHCandidateBarView *)barView;
@end

@interface FSHCandidateBarView : UIView

@property (nonatomic, weak) id<FSHCandidateBarViewDelegate> delegate;
@property (nonatomic, assign, readonly) CGFloat barHeight;
@property (nonatomic, assign, readonly) CGFloat expandedHeight;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;
@property (nonatomic, assign) FSHCandidateSelectionContext selectionContext;
@property (nonatomic, assign) BOOL showsCompactGlobe;

// Only advertise shortcuts backed by keys currently reachable in the keyboard.
// Changes refresh accessibility metadata on pooled candidate views in place.
- (void)updateShortcutAvailabilityWithDigits:(BOOL)digits space:(BOOL)space;

// Applies the height actually assigned by the host without changing the
// preferred expansion size or candidate query/scroll state.
- (void)applyAvailableHeight:(CGFloat)height;

- (void)updateRawBuffer:(NSString *)rawBuffer
             candidates:(NSArray<FSHCandidate *> *)candidates
             exactCount:(NSUInteger)exactCount
            inlineLimit:(NSUInteger)inlineLimit
              moreLimit:(NSUInteger)moreLimit
               hintText:(nullable NSString *)hintText;

@end

NS_ASSUME_NONNULL_END
