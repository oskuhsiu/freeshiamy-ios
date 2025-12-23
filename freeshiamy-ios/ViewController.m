#import "ViewController.h"
#import "FSHSettings.h"
#import "SettingsViewController.h"

@interface ViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextField *singleLineField;
@property (nonatomic, strong) UITextView *multiLineView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"FreeShiamy Test Panel";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [FSHSettings registerDefaults];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [scrollView addSubview:stack];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [stack addArrangedSubview:self.statusLabel];

    UILabel *singleLabel = [[UILabel alloc] init];
    singleLabel.text = @"單行測試區";
    [stack addArrangedSubview:singleLabel];

    self.singleLineField = [[UITextField alloc] init];
    self.singleLineField.borderStyle = UITextBorderStyleRoundedRect;
    self.singleLineField.delegate = self;
    self.singleLineField.returnKeyType = UIReturnKeyNext;
    [stack addArrangedSubview:self.singleLineField];

    UILabel *multiLabel = [[UILabel alloc] init];
    multiLabel.text = @"多行測試區";
    [stack addArrangedSubview:multiLabel];

    self.multiLineView = [[UITextView alloc] init];
    self.multiLineView.layer.borderColor = [UIColor systemGray4Color].CGColor;
    self.multiLineView.layer.borderWidth = 1.0;
    self.multiLineView.layer.cornerRadius = 8.0;
    self.multiLineView.font = [UIFont systemFontOfSize:16.0];
    self.multiLineView.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    [stack addArrangedSubview:self.multiLineView];

    UIButton *openSettingsButton = [self actionButtonWithTitle:@"開啟 App 設定" selector:@selector(openSettings)];
    UIButton *openKeyboardSettingsButton = [self actionButtonWithTitle:@"開啟系統設定（鍵盤）" selector:@selector(openSystemSettings)];
    UIButton *focusSingleButton = [self actionButtonWithTitle:@"聚焦單行並顯示鍵盤" selector:@selector(focusSingleLine)];
    UIButton *clearButton = [self actionButtonWithTitle:@"清空兩個輸入框" selector:@selector(clearFields)];
    UIButton *refreshButton = [self actionButtonWithTitle:@"刷新狀態" selector:@selector(refreshStatus)];

    [stack addArrangedSubview:openSettingsButton];
    [stack addArrangedSubview:openKeyboardSettingsButton];
    [stack addArrangedSubview:focusSingleButton];
    [stack addArrangedSubview:clearButton];
    [stack addArrangedSubview:refreshButton];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:16.0],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-16.0],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-32.0],

        [self.multiLineView.heightAnchor constraintEqualToConstant:140.0],
    ]];

    [self refreshStatus];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.layer.cornerRadius = 8.0;
    button.backgroundColor = [UIColor systemGray5Color];
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)refreshStatus {
    NSArray<UITextInputMode *> *modes = [UITextInputMode activeInputModes];
    NSMutableArray<NSString *> *languages = [NSMutableArray array];
    for (UITextInputMode *mode in modes) {
        if (mode.primaryLanguage.length > 0) {
            [languages addObject:mode.primaryLanguage];
        }
    }
    NSString *languageList = [languages componentsJoinedByString:@", "];
    self.statusLabel.text = [NSString stringWithFormat:@"IME 狀態：iOS 無法直接判斷啟用/預設鍵盤。\n已啟用語言：%@\n請至 系統設定 > 鍵盤 確認 FreeShiamy 已啟用。", languageList];
}

- (void)openSettings {
    SettingsViewController *settings = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settings animated:YES];
}

- (void)openSystemSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)focusSingleLine {
    [self.singleLineField becomeFirstResponder];
}

- (void)clearFields {
    self.singleLineField.text = @"";
    self.multiLineView.text = @"";
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.multiLineView becomeFirstResponder];
    return NO;
}

@end
