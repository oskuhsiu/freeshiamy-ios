#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class FSHCandidate;
@class FSHCandidateBarView;

@protocol FSHCandidateBarViewDelegate <NSObject>
- (void)candidateBarViewDidTapRawBuffer:(FSHCandidateBarView *)barView;
- (void)candidateBarView:(FSHCandidateBarView *)barView didSelectCandidateAtIndex:(NSUInteger)index;
- (void)candidateBarView:(FSHCandidateBarView *)barView didToggleExpanded:(BOOL)expanded;
@end

@interface FSHCandidateBarView : UIView

@property (nonatomic, weak) id<FSHCandidateBarViewDelegate> delegate;
@property (nonatomic, assign, readonly) CGFloat barHeight;
@property (nonatomic, assign, readonly) CGFloat expandedHeight;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;

- (void)updateRawBuffer:(NSString *)rawBuffer
             candidates:(NSArray<FSHCandidate *> *)candidates
             exactCount:(NSUInteger)exactCount
            inlineLimit:(NSUInteger)inlineLimit
              moreLimit:(NSUInteger)moreLimit
               hintText:(nullable NSString *)hintText;

@end

NS_ASSUME_NONNULL_END
