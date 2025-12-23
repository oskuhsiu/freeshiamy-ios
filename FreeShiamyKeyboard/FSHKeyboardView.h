#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class FSHKeyboardView;

typedef NS_ENUM(NSInteger, FSHKeyboardMode) {
    FSHKeyboardModeLetters,
    FSHKeyboardModeSymbols,
    FSHKeyboardModeSymbolsShift,
    FSHKeyboardModeEmoji,
};

typedef NS_ENUM(NSInteger, FSHKeyboardLayout) {
    FSHKeyboardLayoutStandard,
    FSHKeyboardLayoutStandardSpacious,
    FSHKeyboardLayoutStandardLabelTop,
    FSHKeyboardLayoutOriginal,
};

static const NSInteger FSHKeyCodeDelete = -5;
static const NSInteger FSHKeyCodeShift = -1;
static const NSInteger FSHKeyCodeModeChange = -2;
static const NSInteger FSHKeyCodeCancel = -3;
static const NSInteger FSHKeyCodeSettings = -100;
static const NSInteger FSHKeyCodeGlobe = -101;
static const NSInteger FSHKeyCodeEmoji = -102;
static const NSInteger FSHKeyCodeSpace = 32;
static const NSInteger FSHKeyCodeEnter = 10;

@protocol FSHKeyboardViewDelegate <NSObject>
- (void)keyboardView:(FSHKeyboardView *)keyboardView didPressKeyCode:(NSInteger)keyCode output:(nullable NSString *)output;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didBeginPressKeyCode:(NSInteger)keyCode output:(nullable NSString *)output;
- (void)keyboardView:(FSHKeyboardView *)keyboardView didEndPressKeyCode:(NSInteger)keyCode output:(nullable NSString *)output;
@end

@interface FSHKeyboardView : UIView

@property (nonatomic, weak) id<FSHKeyboardViewDelegate> delegate;
@property (nonatomic, assign) FSHKeyboardMode mode;
@property (nonatomic, assign) FSHKeyboardLayout layout;
@property (nonatomic, assign) BOOL showNumberRow;
@property (nonatomic, assign) BOOL showsGlobe;
@property (nonatomic, assign) BOOL shiftOn;
@property (nonatomic, assign) BOOL capsLockOn;

- (void)reloadKeys;

@end

NS_ASSUME_NONNULL_END
