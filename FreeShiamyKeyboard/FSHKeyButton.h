#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSHKeyButton : UIButton

@property (nonatomic, assign) NSInteger keyCode;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, assign) BOOL isSpecial;
@property (nonatomic, assign) CGFloat weight;

@end

NS_ASSUME_NONNULL_END
