#import "SettingsViewController.h"
#import "FSHSettings.h"

@interface SettingsViewController ()

@property (nonatomic, strong) UILabel *heightValueLabel;
@property (nonatomic, strong) UISlider *heightSlider;
@property (nonatomic, strong) UISegmentedControl *layoutSegment;
@property (nonatomic, strong) NSLayoutConstraint *layoutSegmentHeightConstraint;
@property (nonatomic, assign) CGFloat lastSegmentFontSize;
@property (nonatomic, strong) UISwitch *numberRowSwitch;
@property (nonatomic, strong) UISwitch *labelTopSwitch;
@property (nonatomic, strong) UISwitch *leftShiftSwitch;
@property (nonatomic, strong) UIStepper *inlineStepper;
@property (nonatomic, strong) UILabel *inlineValueLabel;
@property (nonatomic, strong) UIStepper *moreStepper;
@property (nonatomic, strong) UILabel *moreValueLabel;
@property (nonatomic, strong) UISwitch *hintSwitch;
@property (nonatomic, strong) UISwitch *sensitiveSwitch;
@property (nonatomic, strong) UISwitch *noLearningSwitch;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"設定";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [FSHSettings registerDefaults];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.accessibilityIdentifier = @"settings.scroll";
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [scrollView addSubview:stack];

    UILabel *heightLabel = [[UILabel alloc] init];
    heightLabel.text = @"鍵盤高度 (%)";
    [self styleBodyLabel:heightLabel];
    [stack addArrangedSubview:heightLabel];

    self.heightValueLabel = [[UILabel alloc] init];
    self.heightValueLabel.accessibilityIdentifier = @"settings.height.value";
    [self styleValueLabel:self.heightValueLabel];
    [stack addArrangedSubview:self.heightValueLabel];

    self.heightSlider = [[UISlider alloc] init];
    self.heightSlider.accessibilityIdentifier = @"settings.height.slider";
    self.heightSlider.accessibilityLabel = @"鍵盤高度";
    self.heightSlider.minimumValue = 90;
    self.heightSlider.maximumValue = 220;
    [self.heightSlider addTarget:self action:@selector(heightChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.heightSlider];

    UILabel *layoutLabel = [[UILabel alloc] init];
    layoutLabel.text = @"鍵盤排版";
    [self styleBodyLabel:layoutLabel];
    [stack addArrangedSubview:layoutLabel];

    self.layoutSegment = [[UISegmentedControl alloc] initWithItems:@[@"標準", @"間距", @"原始"]];
    self.layoutSegmentHeightConstraint = [self.layoutSegment.heightAnchor constraintGreaterThanOrEqualToConstant:44.0];
    self.layoutSegmentHeightConstraint.active = YES;
    [self updateSegmentTypography];
    [self.layoutSegment addTarget:self action:@selector(layoutChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.layoutSegment];

    self.numberRowSwitch = [self addSwitchRowWithTitle:@"顯示數字列" toStack:stack selector:@selector(numberRowChanged:)];
    self.labelTopSwitch = [self addSwitchRowWithTitle:@"文字靠上" toStack:stack selector:@selector(labelTopChanged:)];
    self.leftShiftSwitch = [self addSwitchRowWithTitle:@"QAZ 左移半格＋Del 加寬" toStack:stack selector:@selector(leftShiftChanged:)];

    UILabel *inlineLabel = [[UILabel alloc] init];
    inlineLabel.text = @"候選列顯示筆數";
    [self styleBodyLabel:inlineLabel];
    [stack addArrangedSubview:inlineLabel];

    self.inlineValueLabel = [[UILabel alloc] init];
    [self styleValueLabel:self.inlineValueLabel];
    [stack addArrangedSubview:self.inlineValueLabel];

    self.inlineStepper = [[UIStepper alloc] init];
    self.inlineStepper.minimumValue = 5;
    self.inlineStepper.maximumValue = 20;
    self.inlineStepper.stepValue = 1;
    [self.inlineStepper addTarget:self action:@selector(inlineChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.inlineStepper];

    UILabel *moreLabel = [[UILabel alloc] init];
    moreLabel.text = @"更多候選最大筆數";
    [self styleBodyLabel:moreLabel];
    [stack addArrangedSubview:moreLabel];

    self.moreValueLabel = [[UILabel alloc] init];
    [self styleValueLabel:self.moreValueLabel];
    [stack addArrangedSubview:self.moreValueLabel];

    self.moreStepper = [[UIStepper alloc] init];
    self.moreStepper.minimumValue = 50;
    self.moreStepper.maximumValue = 500;
    self.moreStepper.stepValue = 10;
    [self.moreStepper addTarget:self action:@selector(moreChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.moreStepper];

    self.hintSwitch = [self addSwitchRowWithTitle:@"顯示字根提示" toStack:stack selector:@selector(hintChanged:)];
    self.sensitiveSwitch = [self addSwitchRowWithTitle:@"安全輸入欄位停用輸入法" toStack:stack selector:@selector(sensitiveChanged:)];
    self.noLearningSwitch = [self addSwitchRowWithTitle:@"包含密碼與一次性驗證碼欄位" toStack:stack selector:@selector(noLearningChanged:)];
    UILabel *sensitiveExplanation = [[UILabel alloc] init];
    sensitiveExplanation.text = @"啟用後會檢查安全輸入欄位；開啟「包含密碼與一次性驗證碼欄位」時，另會檢查 App 提供的密碼、新密碼及一次性驗證碼欄位類型。無法辨識所有敏感內容。";
    sensitiveExplanation.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    sensitiveExplanation.adjustsFontForContentSizeCategory = YES;
    sensitiveExplanation.textColor = [UIColor secondaryLabelColor];
    sensitiveExplanation.numberOfLines = 0;
    [stack addArrangedSubview:sensitiveExplanation];

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
    ]];

    [self refreshUI];
}

- (void)styleBodyLabel:(UILabel *)label {
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
}

- (void)styleValueLabel:(UILabel *)label {
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
}

- (void)updateSegmentTypography {
    UIFont *preferred = [UIFont preferredFontForTextStyle:UIFontTextStyleBody
                             compatibleWithTraitCollection:self.traitCollection];
    CGFloat width = CGRectGetWidth(self.layoutSegment.bounds);
    if (width <= 0.0) { width = MAX(0.0, CGRectGetWidth(self.view.bounds) - 32.0); }
    if (width <= 0.0) { width = 288.0; }
    CGFloat labelWidth = MAX(1.0, width / 3.0 - 16.0);
    CGFloat pointSize = preferred.pointSize;
    for (NSString *title in @[@"標準", @"間距", @"原始"]) {
        CGFloat measured = [title sizeWithAttributes:@{NSFontAttributeName: preferred}].width;
        if (measured > labelWidth) {
            pointSize = MIN(pointSize, preferred.pointSize * labelWidth / measured);
        }
    }
    pointSize = MAX(12.0, MIN(preferred.pointSize, pointSize));
    if (fabs(self.lastSegmentFontSize - pointSize) <= 0.25) { return; }
    self.lastSegmentFontSize = pointSize;
    UIFont *font = [preferred fontWithSize:pointSize];
    [self.layoutSegment setTitleTextAttributes:@{NSFontAttributeName: font} forState:UIControlStateNormal];
    self.layoutSegmentHeightConstraint.constant = MAX(44.0, ceil(font.lineHeight + 16.0));
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateSegmentTypography];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !previousTraitCollection ||
        [previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        return;
    }
    [self updateSegmentTypography];
}

- (UISwitch *)addSwitchRowWithTitle:(NSString *)title toStack:(UIStackView *)stack selector:(SEL)selector {
    UIView *container = [[UIView alloc] init];
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.accessibilityLabel = title;
    [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [toggle addTarget:self action:selector forControlEvents:UIControlEventValueChanged];

    [container addSubview:label];
    [container addSubview:toggle];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:container.topAnchor constant:8.0],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-8.0],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [toggle.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-12.0],
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];

    [stack addArrangedSubview:container];
    return toggle;
}

- (void)refreshUI {
    NSInteger height = [FSHSettings keyboardHeightPercent];
    self.heightSlider.value = height;
    self.heightValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)height];

    NSString *layout = [FSHSettings keyboardLayout];
    BOOL legacyNoNumber = [layout isEqualToString:@"original_no_number"];
    if ([layout isEqualToString:@"standard_spacious"]) {
        self.layoutSegment.selectedSegmentIndex = 1;
    } else if ([layout isEqualToString:@"original"] || legacyNoNumber) {
        self.layoutSegment.selectedSegmentIndex = 2;
    } else {
        self.layoutSegment.selectedSegmentIndex = 0;
    }

    self.numberRowSwitch.on = [FSHSettings effectiveShowNumberRow];
    self.labelTopSwitch.on = [FSHSettings effectiveKeyboardLabelTop];
    self.leftShiftSwitch.on = [FSHSettings keyboardLeftShift];
    BOOL leftShiftApplicable = ([layout isEqualToString:@"standard"] || [layout isEqualToString:@"standard_spacious"] || [layout isEqualToString:@"standard_label_top"]);
    self.leftShiftSwitch.enabled = leftShiftApplicable;

    NSInteger inlineLimit = [FSHSettings candidateInlineLimit];
    self.inlineStepper.value = inlineLimit;
    self.inlineValueLabel.text = [NSString stringWithFormat:@"%ld", (long)inlineLimit];

    NSInteger moreLimit = [FSHSettings candidateMoreLimit];
    self.moreStepper.value = moreLimit;
    self.moreValueLabel.text = [NSString stringWithFormat:@"%ld", (long)moreLimit];

    self.hintSwitch.on = [FSHSettings showShortestCodeHint];
    self.sensitiveSwitch.on = [FSHSettings disableImeInSensitiveFields];
    self.noLearningSwitch.on = [FSHSettings sensitiveIncludeNoPersonalizedLearning];
    self.noLearningSwitch.enabled = self.sensitiveSwitch.isOn;
}

- (void)heightChanged:(UISlider *)slider {
    NSInteger value = (NSInteger)round(slider.value);
    [FSHSettings setKeyboardHeightPercent:value];
    self.heightValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)value];
}

- (void)layoutChanged:(UISegmentedControl *)segment {
    NSString *value = @"standard";
    switch (segment.selectedSegmentIndex) {
        case 1: value = @"standard_spacious"; break;
        case 2: value = @"original"; break;
        default: value = @"standard"; break;
    }
    [FSHSettings setKeyboardLayout:value];
    [self refreshUI];
}

- (void)numberRowChanged:(UISwitch *)toggle {
    [FSHSettings setShowNumberRow:toggle.isOn];
}

- (void)labelTopChanged:(UISwitch *)toggle {
    [FSHSettings setKeyboardLabelTop:toggle.isOn];
}

- (void)leftShiftChanged:(UISwitch *)toggle {
    [FSHSettings setKeyboardLeftShift:toggle.isOn];
}

- (void)inlineChanged:(UIStepper *)stepper {
    NSInteger value = (NSInteger)stepper.value;
    [FSHSettings setCandidateInlineLimit:value];
    self.inlineValueLabel.text = [NSString stringWithFormat:@"%ld", (long)value];
}

- (void)moreChanged:(UIStepper *)stepper {
    NSInteger value = (NSInteger)stepper.value;
    [FSHSettings setCandidateMoreLimit:value];
    self.moreValueLabel.text = [NSString stringWithFormat:@"%ld", (long)value];
}

- (void)hintChanged:(UISwitch *)toggle {
    [FSHSettings setShowShortestCodeHint:toggle.isOn];
}

- (void)sensitiveChanged:(UISwitch *)toggle {
    [FSHSettings setDisableImeInSensitiveFields:toggle.isOn];
    self.noLearningSwitch.enabled = toggle.isOn;
}

- (void)noLearningChanged:(UISwitch *)toggle {
    [FSHSettings setSensitiveIncludeNoPersonalizedLearning:toggle.isOn];
}

@end
