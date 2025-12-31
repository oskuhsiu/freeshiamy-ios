#import "SettingsViewController.h"
#import "FSHSettings.h"

@interface SettingsViewController ()

@property (nonatomic, strong) UILabel *heightValueLabel;
@property (nonatomic, strong) UISlider *heightSlider;
@property (nonatomic, strong) UISegmentedControl *layoutSegment;
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
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [scrollView addSubview:stack];

    UILabel *heightLabel = [[UILabel alloc] init];
    heightLabel.text = @"鍵盤高度 (%)";
    [stack addArrangedSubview:heightLabel];

    self.heightValueLabel = [[UILabel alloc] init];
    self.heightValueLabel.font = [UIFont systemFontOfSize:14.0];
    [stack addArrangedSubview:self.heightValueLabel];

    self.heightSlider = [[UISlider alloc] init];
    self.heightSlider.minimumValue = 90;
    self.heightSlider.maximumValue = 220;
    [self.heightSlider addTarget:self action:@selector(heightChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.heightSlider];

    UILabel *layoutLabel = [[UILabel alloc] init];
    layoutLabel.text = @"鍵盤排版";
    [stack addArrangedSubview:layoutLabel];

    self.layoutSegment = [[UISegmentedControl alloc] initWithItems:@[@"標準", @"間距", @"原始"]];
    [self.layoutSegment addTarget:self action:@selector(layoutChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.layoutSegment];

    self.numberRowSwitch = [self addSwitchRowWithTitle:@"顯示數字列" toStack:stack selector:@selector(numberRowChanged:)];
    self.labelTopSwitch = [self addSwitchRowWithTitle:@"文字靠上" toStack:stack selector:@selector(labelTopChanged:)];
    self.leftShiftSwitch = [self addSwitchRowWithTitle:@"QAZ 左移半格＋Del 加寬" toStack:stack selector:@selector(leftShiftChanged:)];

    UILabel *inlineLabel = [[UILabel alloc] init];
    inlineLabel.text = @"候選列顯示筆數";
    [stack addArrangedSubview:inlineLabel];

    self.inlineValueLabel = [[UILabel alloc] init];
    self.inlineValueLabel.font = [UIFont systemFontOfSize:14.0];
    [stack addArrangedSubview:self.inlineValueLabel];

    self.inlineStepper = [[UIStepper alloc] init];
    self.inlineStepper.minimumValue = 5;
    self.inlineStepper.maximumValue = 20;
    self.inlineStepper.stepValue = 1;
    [self.inlineStepper addTarget:self action:@selector(inlineChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.inlineStepper];

    UILabel *moreLabel = [[UILabel alloc] init];
    moreLabel.text = @"更多候選最大筆數";
    [stack addArrangedSubview:moreLabel];

    self.moreValueLabel = [[UILabel alloc] init];
    self.moreValueLabel.font = [UIFont systemFontOfSize:14.0];
    [stack addArrangedSubview:self.moreValueLabel];

    self.moreStepper = [[UIStepper alloc] init];
    self.moreStepper.minimumValue = 50;
    self.moreStepper.maximumValue = 500;
    self.moreStepper.stepValue = 10;
    [self.moreStepper addTarget:self action:@selector(moreChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.moreStepper];

    self.hintSwitch = [self addSwitchRowWithTitle:@"顯示字根提示" toStack:stack selector:@selector(hintChanged:)];
    self.sensitiveSwitch = [self addSwitchRowWithTitle:@"敏感欄位停用輸入法" toStack:stack selector:@selector(sensitiveChanged:)];
    self.noLearningSwitch = [self addSwitchRowWithTitle:@"將 No Personalized Learning 視為敏感" toStack:stack selector:@selector(noLearningChanged:)];

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

- (UISwitch *)addSwitchRowWithTitle:(NSString *)title toStack:(UIStackView *)stack selector:(SEL)selector {
    UIView *container = [[UIView alloc] init];
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [toggle addTarget:self action:selector forControlEvents:UIControlEventValueChanged];

    [container addSubview:label];
    [container addSubview:toggle];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [toggle.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-12.0],
        [container.heightAnchor constraintEqualToConstant:32.0],
    ]];

    [stack addArrangedSubview:container];
    return toggle;
}

- (void)refreshUI {
    NSInteger height = [FSHSettings keyboardHeightPercent];
    self.heightSlider.value = height;
    self.heightValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)height];

    NSString *layout = [FSHSettings keyboardLayout];
    if ([layout isEqualToString:@"original_no_number"]) {
        [FSHSettings setKeyboardLayout:@"original"];
        [FSHSettings setShowNumberRow:NO];
        layout = @"original";
    }
    BOOL legacyLabelTop = [layout isEqualToString:@"standard_label_top"];
    if ([layout isEqualToString:@"standard_spacious"]) {
        self.layoutSegment.selectedSegmentIndex = 1;
    } else if ([layout isEqualToString:@"original"]) {
        self.layoutSegment.selectedSegmentIndex = 2;
    } else {
        self.layoutSegment.selectedSegmentIndex = 0;
    }

    self.numberRowSwitch.on = [FSHSettings showNumberRow];
    self.labelTopSwitch.on = legacyLabelTop ? YES : [FSHSettings keyboardLabelTop];
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
    self.leftShiftSwitch.enabled = ([value isEqualToString:@"standard"] || [value isEqualToString:@"standard_spacious"]);
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
}

- (void)noLearningChanged:(UISwitch *)toggle {
    [FSHSettings setSensitiveIncludeNoPersonalizedLearning:toggle.isOn];
}

@end
