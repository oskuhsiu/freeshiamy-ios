#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"

static const CGFloat kFSHCandidateBarHeight = 38.0;
static const CGFloat kFSHCandidateMoreHeight = 180.0;
static const CGFloat kFSHCandidateButtonHeight = 38.0;
static const NSUInteger kFSHCandidateMoreColumns = 5;

@interface FSHCandidateBarView ()

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *rawButton;
@property (nonatomic, strong) UIView *candidateArea;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *candidateStack;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *hintLabel;

@property (nonatomic, strong) UIView *moreContainer;
@property (nonatomic, strong) UIScrollView *moreScrollView;
@property (nonatomic, strong) UIView *moreContentView;

@property (nonatomic, strong) NSLayoutConstraint *moreHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *moreContentHeightConstraint;

@property (nonatomic, copy) NSArray<FSHCandidate *> *currentCandidates;
@property (nonatomic, assign) NSUInteger currentExactCount;

@end

@implementation FSHCandidateBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (CGFloat)barHeight {
    return kFSHCandidateBarHeight;
}

- (CGFloat)expandedHeight {
    return kFSHCandidateMoreHeight;
}

- (void)setExpanded:(BOOL)expanded {
    [self setExpanded:expanded animated:NO];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _expanded = expanded;
    self.moreContainer.hidden = !expanded;
    self.moreHeightConstraint.constant = expanded ? kFSHCandidateMoreHeight : 0.0;
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            [self layoutIfNeeded];
        }];
    } else {
        [self setNeedsLayout];
    }
    if ([self.delegate respondsToSelector:@selector(candidateBarView:didToggleExpanded:)]) {
        [self.delegate candidateBarView:self didToggleExpanded:expanded];
    }
}

- (void)updateRawBuffer:(NSString *)rawBuffer
             candidates:(NSArray<FSHCandidate *> *)candidates
             exactCount:(NSUInteger)exactCount
            inlineLimit:(NSUInteger)inlineLimit
              moreLimit:(NSUInteger)moreLimit
               hintText:(NSString *)hintText {
    self.currentCandidates = candidates ?: @[];
    self.currentExactCount = exactCount;

    NSString *rawText = rawBuffer ?: @"";
    [self.rawButton setTitle:rawText forState:UIControlStateNormal];
    self.rawButton.hidden = (rawText.length == 0);

    BOOL showHint = (rawText.length == 0 && hintText.length > 0);
    self.hintLabel.text = hintText ?: @"";
    self.hintLabel.hidden = !showHint;
    self.candidateArea.hidden = showHint;

    if (showHint) {
        [self setExpanded:NO animated:NO];
        return;
    }

    [self rebuildInlineCandidatesWithLimit:inlineLimit];

    BOOL showMoreButton = (self.currentCandidates.count > inlineLimit);
    self.moreButton.hidden = !showMoreButton;
    if (!showMoreButton) {
        [self setExpanded:NO animated:NO];
    }

    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:moreLimit];
    }
}

- (void)setupViews {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.topBar];

    self.rawButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.rawButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.rawButton.titleLabel.font = [self candidateFont];
    self.rawButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.rawButton.titleLabel.minimumScaleFactor = 12.0 / 18.0;
    self.rawButton.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
    self.rawButton.layer.cornerRadius = 6.0;
    self.rawButton.backgroundColor = [UIColor systemGray5Color];
    [self.rawButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [self.rawButton setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.rawButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.rawButton addTarget:self action:@selector(handleRawTap) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.rawButton];

    self.candidateArea = [[UIView alloc] init];
    self.candidateArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.candidateArea];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    [self.candidateArea addSubview:self.scrollView];

    self.candidateStack = [[UIStackView alloc] init];
    self.candidateStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.candidateStack.axis = UILayoutConstraintAxisHorizontal;
    self.candidateStack.alignment = UIStackViewAlignmentCenter;
    self.candidateStack.spacing = 2.0;
    [self.scrollView addSubview:self.candidateStack];

    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreButton.titleLabel.font = [self candidateFont];
    [self.moreButton setTitle:@"⋯" forState:UIControlStateNormal];
    [self.moreButton addTarget:self action:@selector(handleMoreTap) forControlEvents:UIControlEventTouchUpInside];
    [self.candidateArea addSubview:self.moreButton];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.font = [self candidateFont];
    self.hintLabel.adjustsFontSizeToFitWidth = YES;
    self.hintLabel.minimumScaleFactor = 12.0 / 18.0;
    self.hintLabel.textAlignment = NSTextAlignmentRight;
    self.hintLabel.textColor = [UIColor secondaryLabelColor];
    [self.topBar addSubview:self.hintLabel];

    self.moreContainer = [[UIView alloc] init];
    self.moreContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreContainer.hidden = YES;
    [self addSubview:self.moreContainer];

    self.moreScrollView = [[UIScrollView alloc] init];
    self.moreScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreScrollView.showsVerticalScrollIndicator = YES;
    [self.moreContainer addSubview:self.moreScrollView];

    self.moreContentView = [[UIView alloc] init];
    self.moreContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreScrollView addSubview:self.moreContentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.topBar.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:kFSHCandidateBarHeight],

        [self.rawButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:4.0],
        [self.rawButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.rawButton.widthAnchor constraintLessThanOrEqualToAnchor:self.topBar.widthAnchor multiplier:0.35],

        [self.candidateArea.leadingAnchor constraintEqualToAnchor:self.rawButton.trailingAnchor constant:4.0],
        [self.candidateArea.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-4.0],
        [self.candidateArea.topAnchor constraintEqualToAnchor:self.topBar.topAnchor],
        [self.candidateArea.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],

        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.candidateArea.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-4.0],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.candidateArea.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.candidateArea.bottomAnchor],

        [self.candidateStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.candidateStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.candidateStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.candidateStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.candidateStack.heightAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.heightAnchor],

        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.candidateArea.trailingAnchor],
        [self.moreButton.centerYAnchor constraintEqualToAnchor:self.candidateArea.centerYAnchor],
        [self.moreButton.widthAnchor constraintEqualToConstant:32.0],
        [self.moreButton.heightAnchor constraintEqualToConstant:28.0],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.rawButton.trailingAnchor constant:8.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-8.0],
        [self.hintLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],

        [self.moreContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.moreContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.moreContainer.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.moreContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    self.moreHeightConstraint = [self.moreContainer.heightAnchor constraintEqualToConstant:0.0];
    self.moreHeightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.moreScrollView.leadingAnchor constraintEqualToAnchor:self.moreContainer.leadingAnchor],
        [self.moreScrollView.trailingAnchor constraintEqualToAnchor:self.moreContainer.trailingAnchor],
        [self.moreScrollView.topAnchor constraintEqualToAnchor:self.moreContainer.topAnchor],
        [self.moreScrollView.bottomAnchor constraintEqualToAnchor:self.moreContainer.bottomAnchor],

        [self.moreContentView.leadingAnchor constraintEqualToAnchor:self.moreScrollView.contentLayoutGuide.leadingAnchor],
        [self.moreContentView.trailingAnchor constraintEqualToAnchor:self.moreScrollView.contentLayoutGuide.trailingAnchor],
        [self.moreContentView.topAnchor constraintEqualToAnchor:self.moreScrollView.contentLayoutGuide.topAnchor],
        [self.moreContentView.bottomAnchor constraintEqualToAnchor:self.moreScrollView.contentLayoutGuide.bottomAnchor],
        [self.moreContentView.widthAnchor constraintEqualToAnchor:self.moreScrollView.frameLayoutGuide.widthAnchor],
    ]];
    self.moreContentHeightConstraint = [self.moreContentView.heightAnchor constraintEqualToConstant:0.0];
    self.moreContentHeightConstraint.active = YES;
}

- (UIFont *)candidateFont {
    return [UIFont systemFontOfSize:18.0 weight:UIFontWeightRegular];
}

- (void)rebuildInlineCandidatesWithLimit:(NSUInteger)inlineLimit {
    for (UIView *view in self.candidateStack.arrangedSubviews) {
        [self.candidateStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSUInteger limit = inlineLimit == 0 ? self.currentCandidates.count : inlineLimit;
    NSUInteger count = MIN(self.currentCandidates.count, limit);
    for (NSUInteger index = 0; index < count; index++) {
        FSHCandidate *candidate = self.currentCandidates[index];
        UIButton *button = [self candidateButtonForIndex:index candidate:candidate exactCount:self.currentExactCount];
        [self.candidateStack addArrangedSubview:button];
    }
}

- (void)rebuildMoreCandidatesWithLimit:(NSUInteger)moreLimit {
    for (UIView *view in self.moreContentView.subviews) {
        [view removeFromSuperview];
    }

    NSUInteger limit = moreLimit == 0 ? self.currentCandidates.count : moreLimit;
    NSUInteger count = MIN(self.currentCandidates.count, limit);
    if (count == 0) {
        return;
    }

    CGFloat gap = 2.0;
    CGFloat totalWidth = self.bounds.size.width;
    if (totalWidth <= 0) {
        [self setNeedsLayout];
        return;
    }
    CGFloat buttonWidth = (totalWidth - gap * (kFSHCandidateMoreColumns - 1)) / kFSHCandidateMoreColumns;

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger row = index / kFSHCandidateMoreColumns;
        NSUInteger col = index % kFSHCandidateMoreColumns;
        CGFloat x = (buttonWidth + gap) * col;
        CGFloat y = (kFSHCandidateButtonHeight + gap) * row;

        FSHCandidate *candidate = self.currentCandidates[index];
        UIButton *button = [self candidateButtonForIndex:index candidate:candidate exactCount:self.currentExactCount];
        button.frame = CGRectMake(x, y, buttonWidth, kFSHCandidateButtonHeight);
        [self.moreContentView addSubview:button];
    }

    CGFloat rows = ceil((double)count / (double)kFSHCandidateMoreColumns);
    CGFloat contentHeight = rows * kFSHCandidateButtonHeight + (rows - 1) * gap;
    self.moreContentHeightConstraint.constant = contentHeight;
    self.moreScrollView.contentSize = CGSizeMake(totalWidth, contentHeight);
}

- (UIButton *)candidateButtonForIndex:(NSUInteger)index
                             candidate:(FSHCandidate *)candidate
                            exactCount:(NSUInteger)exactCount {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = index;
    button.titleLabel.font = [self candidateFont];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 12.0 / 18.0;
    button.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
    button.layer.cornerRadius = 6.0;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor systemGray4Color].CGColor;
    [button setTitle:candidate.value forState:UIControlStateNormal];
    UIColor *titleColor = [self candidateColorForIndex:index exactCount:exactCount];
    [button setTitleColor:titleColor forState:UIControlStateNormal];
    [button addTarget:self action:@selector(handleCandidateTap:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIColor *)candidateColorForIndex:(NSUInteger)index exactCount:(NSUInteger)exactCount {
    if (index < exactCount) {
        if (index == 0) {
            return [UIColor systemBlueColor];
        }
        return [UIColor labelColor];
    }
    return [UIColor secondaryLabelColor];
}

- (void)handleRawTap {
    if ([self.delegate respondsToSelector:@selector(candidateBarViewDidTapRawBuffer:)]) {
        [self.delegate candidateBarViewDidTapRawBuffer:self];
    }
}

- (void)handleCandidateTap:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(candidateBarView:didSelectCandidateAtIndex:)]) {
        [self.delegate candidateBarView:self didSelectCandidateAtIndex:sender.tag];
    }
}

- (void)handleMoreTap {
    [self setExpanded:!self.isExpanded animated:YES];
    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:0];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:0];
    }
}

@end
