#import "ViewController.h"
#import "FSHSettings.h"
#import "SettingsViewController.h"
#import "CodeSearchViewController.h"
#import <math.h>
#import <unistd.h>

@interface ViewController () <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) CGSize lastScrollViewportSize;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextField *singleLineField;
@property (nonatomic, strong) UITextView *multiLineView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *actionButtons;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *actionButtonHeights;
#if DEBUG
@property (nonatomic, copy) NSString *lastLoggedHostGeometry;
- (void)logHostGeometryIfChanged;
#endif

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"FreeShiamy Test Panel";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [FSHSettings registerDefaults];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [self.scrollView addSubview:stack];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:self.statusLabel];

    UILabel *singleLabel = [[UILabel alloc] init];
    singleLabel.text = @"單行測試區";
    singleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    singleLabel.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:singleLabel];

    self.singleLineField = [[UITextField alloc] init];
    self.singleLineField.accessibilityIdentifier = @"smoke.singleLine";
    self.singleLineField.borderStyle = UITextBorderStyleRoundedRect;
    self.singleLineField.delegate = self;
    self.singleLineField.returnKeyType = UIReturnKeyNext;
    self.singleLineField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.singleLineField.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:self.singleLineField];

    UILabel *multiLabel = [[UILabel alloc] init];
    multiLabel.text = @"多行測試區";
    multiLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    multiLabel.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:multiLabel];

    self.multiLineView = [[UITextView alloc] init];
    self.multiLineView.accessibilityIdentifier = @"smoke.multiLine";
    self.multiLineView.layer.borderColor = [UIColor systemGray4Color].CGColor;
    self.multiLineView.layer.borderWidth = 1.0;
    self.multiLineView.layer.cornerRadius = 8.0;
    self.multiLineView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.multiLineView.adjustsFontForContentSizeCategory = YES;
    self.multiLineView.delegate = self;
    self.multiLineView.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    [stack addArrangedSubview:self.multiLineView];

    UIButton *openSettingsButton = [self actionButtonWithTitle:@"開啟 App 設定" selector:@selector(openSettings)];
    openSettingsButton.accessibilityIdentifier = @"smoke.appSettings";
    UIButton *codeSearchButton = [self actionButtonWithTitle:@"查嘸蝦米字根" selector:@selector(openCodeSearch)];
    UIButton *openKeyboardSettingsButton = [self actionButtonWithTitle:@"開啟系統設定（鍵盤）" selector:@selector(openSystemSettings)];
    openKeyboardSettingsButton.accessibilityIdentifier = @"smoke.keyboardSettings";
    UIButton *showPickerButton = [self actionButtonWithTitle:@"顯示鍵盤選擇器" selector:@selector(showKeyboardPickerHint)];
    UIButton *focusSingleButton = [self actionButtonWithTitle:@"聚焦單行並顯示鍵盤" selector:@selector(focusSingleLine)];
    UIButton *clearButton = [self actionButtonWithTitle:@"清空兩個輸入框" selector:@selector(clearFields)];
    clearButton.accessibilityIdentifier = @"smoke.clearFields";
    UIButton *refreshButton = [self actionButtonWithTitle:@"刷新狀態" selector:@selector(refreshStatus)];

    [stack addArrangedSubview:codeSearchButton];
    [stack addArrangedSubview:openSettingsButton];
    [stack addArrangedSubview:openKeyboardSettingsButton];
    [stack addArrangedSubview:showPickerButton];
    [stack addArrangedSubview:focusSingleButton];
    [stack addArrangedSubview:clearButton];
    [stack addArrangedSubview:refreshButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-16.0],
        [stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32.0],

        [self.singleLineField.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [self.multiLineView.heightAnchor constraintGreaterThanOrEqualToConstant:140.0],
    ]];

    [self refreshStatus];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self refreshActionButtonHeights];
    CGSize viewport = self.scrollView.bounds.size;
    if (!CGSizeEqualToSize(viewport, self.lastScrollViewportSize)) {
        self.lastScrollViewportSize = viewport;
        if (!self.scrollView.isDragging && !self.scrollView.isDecelerating) {
            [self scrollFocusedInputIntoView];
        }
    }
#if DEBUG
    [self logHostGeometryIfChanged];
#endif
}

#if DEBUG
- (void)logHostGeometryIfChanged {
    UIWindow *window = self.view.window;
    NSString *runID = NSProcessInfo.processInfo.environment[@"FSH_INSTALLED_SMOKE_RUN_ID"];
    if (!window || runID.length == 0) return;
    CGRect guide = [self.view convertRect:self.view.keyboardLayoutGuide.layoutFrame toView:window];
    CGRect viewport = [self.scrollView convertRect:self.scrollView.bounds toView:window];
    CGRect caret = CGRectNull;
    NSString *responder = @"none";
    if (self.multiLineView.isFirstResponder) {
        responder = @"multiline";
        UITextPosition *position = self.multiLineView.selectedTextRange.end;
        if (position) {
            caret = [self.multiLineView convertRect:[self.multiLineView caretRectForPosition:position]
                                              toView:window];
        }
    } else if (self.singleLineField.isFirstResponder) {
        responder = @"singleline";
        caret = [self.singleLineField convertRect:self.singleLineField.bounds toView:window];
    }
    NSString *geometry = [NSString stringWithFormat:@"scene=%@ window=%@ viewport=%@ guide=%@ caret=%@ responder=%@",
                          NSStringFromCGSize(window.windowScene.coordinateSpace.bounds.size),
                          NSStringFromCGRect(window.bounds), NSStringFromCGRect(viewport),
                          NSStringFromCGRect(guide), NSStringFromCGRect(caret), responder];
    if ([geometry isEqualToString:self.lastLoggedHostGeometry]) return;
    self.lastLoggedHostGeometry = geometry;
    NSLog(@"[HostGeometry] run=%@ pid=%d %@", runID, getpid(), geometry);
}
#endif

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    __weak typeof(self) weakSelf = self;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [weakSelf scrollFocusedInputIntoView];
    }];
}

- (void)scrollFocusedInputIntoView {
    if (CGRectIsEmpty(self.scrollView.bounds) ||
        self.scrollView.isDragging || self.scrollView.isDecelerating) {
        return;
    }
    CGRect target;
    if (self.singleLineField.isFirstResponder) {
        target = [self.singleLineField convertRect:self.singleLineField.bounds toView:self.scrollView];
    } else if (self.multiLineView.isFirstResponder) {
        if (self.multiLineView.selectedRange.location != NSNotFound) {
            [self.multiLineView scrollRangeToVisible:self.multiLineView.selectedRange];
        }
        UITextPosition *caret = self.multiLineView.selectedTextRange.end;
        CGRect caretRect = caret ? [self.multiLineView caretRectForPosition:caret] : self.multiLineView.bounds;
        target = [self.multiLineView convertRect:caretRect toView:self.scrollView];
    } else {
        return;
    }
    [self.scrollView scrollRectToVisible:CGRectInset(target, 0.0, -8.0) animated:NO];
#if DEBUG
    [self logHostGeometryIfChanged];
#endif
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection ||
        [previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.isViewLoaded &&
            [strongSelf respondsToSelector:@selector(scrollFocusedInputIntoView)]) {
            [strongSelf refreshActionButtonHeights];
            [strongSelf.view layoutIfNeeded];
            [strongSelf scrollFocusedInputIntoView];
        }
    });
}

- (void)refreshActionButtonHeights {
    UIFont *bodyFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody
                              compatibleWithTraitCollection:self.traitCollection];
    for (NSUInteger index = 0; index < self.actionButtons.count; index++) {
        UIButton *button = self.actionButtons[index];
        BOOL changed = NO;
        if (![button.titleLabel.font isEqual:bodyFont]) {
            button.titleLabel.font = bodyFont;
            changed = YES;
        }
        CGFloat textWidth = CGRectGetWidth(button.bounds) - button.contentEdgeInsets.left - button.contentEdgeInsets.right;
        if (textWidth <= 0.0) { continue; }
        if (fabs(button.titleLabel.preferredMaxLayoutWidth - textWidth) > 0.5) {
            button.titleLabel.preferredMaxLayoutWidth = textWidth;
            changed = YES;
        }
        NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
        CGRect textRect = [title boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                          attributes:@{NSFontAttributeName: button.titleLabel.font}
                                             context:nil];
        CGFloat minimum = MAX(44.0, ceil(CGRectGetHeight(textRect)) + button.contentEdgeInsets.top + button.contentEdgeInsets.bottom);
        NSLayoutConstraint *height = self.actionButtonHeights[index];
        if (fabs(height.constant - minimum) > 0.5) {
            height.constant = minimum;
            changed = YES;
        }
        if (changed) { [button invalidateIntrinsicContentSize]; }
    }
}

- (UIButton *)actionButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.layer.cornerRadius = 8.0;
    button.backgroundColor = [UIColor systemGray5Color];
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    NSLayoutConstraint *minimumHeight = [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0];
    minimumHeight.active = YES;
    if (!self.actionButtons) {
        self.actionButtons = [NSMutableArray array];
        self.actionButtonHeights = [NSMutableArray array];
    }
    [self.actionButtons addObject:button];
    [self.actionButtonHeights addObject:minimumHeight];
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

- (void)openCodeSearch {
    [self.navigationController pushViewController:[[CodeSearchViewController alloc] init] animated:YES];
}

- (void)openSystemSettings {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)showKeyboardPickerHint {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"鍵盤選擇器"
                                                                   message:@"iOS 需要在鍵盤上長按 🌐 才能切換輸入法。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)focusSingleLine {
    [self.singleLineField becomeFirstResponder];
    [self scrollFocusedInputIntoView];
}

- (void)clearFields {
    self.singleLineField.text = @"";
    self.multiLineView.text = @"";
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self scrollFocusedInputIntoView];
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    [self scrollFocusedInputIntoView];
}

- (void)textViewDidChangeSelection:(UITextView *)textView {
    [self scrollFocusedInputIntoView];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.multiLineView becomeFirstResponder];
    [self scrollFocusedInputIntoView];
    return NO;
}

@end
