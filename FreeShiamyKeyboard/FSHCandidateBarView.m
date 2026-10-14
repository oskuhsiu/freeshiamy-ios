#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"

static const CGFloat kFSHCandidateBarHeight = 37.5;
static const CGFloat kFSHCandidateMoreHeight = 180.0;
static const CGFloat kFSHCandidateButtonHeight = 37.5;
static const NSUInteger kFSHCandidateMoreColumns = 5;

@interface FSHCandidateBarView ()

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *rawButton;
@property (nonatomic, strong) UIView *candidateArea;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *candidateStack;
@property (nonatomic, strong) NSMutableArray<UIButton *> *inlineButtonPool;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *hintLabel;

@property (nonatomic, strong) UIView *moreContainer;
@property (nonatomic, strong) UIScrollView *moreScrollView;
@property (nonatomic, strong) UIView *moreContentView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *moreButtonPool;

@property (nonatomic, strong) NSLayoutConstraint *moreHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *moreContentHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *scrollTrailingWithMore;
@property (nonatomic, strong) NSLayoutConstraint *scrollTrailingWithoutMore;

@property (nonatomic, copy) NSArray<FSHCandidate *> *currentCandidates;
@property (nonatomic, assign) NSUInteger currentExactCount;
@property (nonatomic, assign) NSUInteger currentInlineLimit;
@property (nonatomic, assign) NSUInteger currentMoreLimit;
@property (nonatomic, copy) NSArray *currentQuerySignature;

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
    if (_expanded == expanded) {
        return;
    }
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
    [UIView performWithoutAnimation:^{
        BOOL canLayoutNow = (self.window && self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0);
        NSString *rawText = [rawBuffer copy] ?: @"";
        NSArray<FSHCandidate *> *nextCandidates = candidates ?: @[];
        NSMutableArray *candidateValues = [NSMutableArray arrayWithCapacity:nextCandidates.count];
        for (FSHCandidate *candidate in nextCandidates) {
            [candidateValues addObject:@[candidate.code ?: @"", candidate.value ?: @""]];
        }
        NSArray *querySignature = @[rawText, candidateValues];
        BOOL queryChanged = ![self.currentQuerySignature isEqual:querySignature];
        if (queryChanged) {
            for (UIButton *button in self.candidateStack.arrangedSubviews) {
                [button cancelTrackingWithEvent:nil];
                button.highlighted = NO;
            }
            for (UIButton *button in self.moreContentView.subviews) {
                [button cancelTrackingWithEvent:nil];
                button.highlighted = NO;
            }
            self.scrollView.contentOffset = CGPointZero;
            self.moreScrollView.contentOffset = CGPointZero;
        }
        self.currentQuerySignature = querySignature;
        self.currentCandidates = candidates ?: @[];
        self.currentExactCount = exactCount;
        self.currentInlineLimit = inlineLimit;
        self.currentMoreLimit = moreLimit;

        [self.rawButton setTitle:rawText forState:UIControlStateNormal];
        self.rawButton.hidden = (rawText.length == 0);

        BOOL showHint = (hintText.length > 0 && self.currentCandidates.count == 0);
        self.hintLabel.text = hintText ?: @"";
        self.hintLabel.hidden = !showHint;
        self.candidateArea.hidden = showHint;

        BOOL hasContent = (rawText.length > 0 || self.currentCandidates.count > 0 || showHint);
        self.topBar.hidden = !hasContent;
        self.topBar.userInteractionEnabled = hasContent;

        if (showHint || !hasContent) {
            [self setExpanded:NO animated:NO];
            if (self.currentCandidates.count == 0) {
                [self rebuildMoreCandidatesWithLimit:0];
            }
            if (canLayoutNow) {
                [self layoutIfNeeded];
            } else {
                [self setNeedsLayout];
            }
            return;
        }

        [self rebuildInlineCandidatesWithLimit:inlineLimit];

        NSUInteger visibleInlineLimit = inlineLimit == 0 ? 20 : MIN(inlineLimit, 20);
        BOOL showMoreButton = (self.currentCandidates.count > visibleInlineLimit);
        self.moreButton.hidden = !showMoreButton;
        if (showMoreButton) {
            self.scrollTrailingWithoutMore.active = NO;
            self.scrollTrailingWithMore.active = YES;
        } else {
            self.scrollTrailingWithMore.active = NO;
            self.scrollTrailingWithoutMore.active = YES;
        }
        if (!showMoreButton) {
            [self setExpanded:NO animated:NO];
        }

        if (self.currentCandidates.count == 0) {
            [self rebuildMoreCandidatesWithLimit:0];
        }

        if (self.isExpanded) {
            [self rebuildMoreCandidatesWithLimit:self.currentMoreLimit];
        }
        if (canLayoutNow) {
            [self layoutIfNeeded];
        } else {
            [self setNeedsLayout];
        }
        if (queryChanged) {
            self.scrollView.contentOffset = CGPointZero;
            self.moreScrollView.contentOffset = CGPointZero;
        }
    }];
}

- (void)clampScrollOffsets {
    CGFloat inlineMaximum = MAX(0.0, self.scrollView.contentSize.width - CGRectGetWidth(self.scrollView.bounds));
    CGFloat moreMaximum = MAX(0.0, self.moreScrollView.contentSize.height - CGRectGetHeight(self.moreScrollView.bounds));
    self.scrollView.contentOffset = CGPointMake(MIN(MAX(self.scrollView.contentOffset.x, 0.0), inlineMaximum), 0.0);
    self.moreScrollView.contentOffset = CGPointMake(0.0, MIN(MAX(self.moreScrollView.contentOffset.y, 0.0), moreMaximum));
}

- (void)setupViews {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.topBar];

    self.rawButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.rawButton.accessibilityIdentifier = @"candidate.raw";
    self.rawButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.rawButton.titleLabel.font = [self candidateFont];
    self.rawButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.rawButton.titleLabel.minimumScaleFactor = 12.0 / 18.0;
    self.rawButton.contentEdgeInsets = UIEdgeInsetsMake(1, 7, 1, 7);
    self.rawButton.layer.cornerRadius = 6.0;
    self.rawButton.backgroundColor = [UIColor systemGray5Color];
    [self.rawButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [self.rawButton setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
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
    self.candidateStack.spacing = 1.0;
    [self.scrollView addSubview:self.candidateStack];
    self.inlineButtonPool = [NSMutableArray array];

    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreButton.titleLabel.font = [self candidateFont];
    [self.moreButton setTitle:@"⋯" forState:UIControlStateNormal];
    [self.moreButton addTarget:self action:@selector(handleMoreTap) forControlEvents:UIControlEventTouchUpInside];
    [self.candidateArea addSubview:self.moreButton];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.accessibilityIdentifier = @"candidate.status";
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
    self.moreButtonPool = [NSMutableArray array];

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
        [self.scrollView.topAnchor constraintEqualToAnchor:self.candidateArea.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.candidateArea.bottomAnchor],

        [self.candidateStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.candidateStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.candidateStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.candidateStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.candidateStack.heightAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.heightAnchor],

        [self.moreButton.trailingAnchor constraintEqualToAnchor:self.candidateArea.trailingAnchor],
        [self.moreButton.centerYAnchor constraintEqualToAnchor:self.candidateArea.centerYAnchor],
        [self.moreButton.widthAnchor constraintEqualToConstant:44.0],
        [self.moreButton.heightAnchor constraintEqualToConstant:kFSHCandidateBarHeight],

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.rawButton.trailingAnchor constant:8.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-8.0],
        [self.hintLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],

        [self.moreContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.moreContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.moreContainer.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.moreContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    self.scrollTrailingWithMore = [self.scrollView.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-4.0];
    self.scrollTrailingWithoutMore = [self.scrollView.trailingAnchor constraintEqualToAnchor:self.candidateArea.trailingAnchor];
    self.scrollTrailingWithMore.active = YES;

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
    NSUInteger limit = inlineLimit == 0 ? 20 : MIN(inlineLimit, 20);
    NSUInteger count = MIN(self.currentCandidates.count, limit);
    while (self.candidateStack.arrangedSubviews.count > count) {
        UIButton *button = (UIButton *)self.candidateStack.arrangedSubviews.lastObject;
        [button cancelTrackingWithEvent:nil];
        button.highlighted = NO;
        [self.candidateStack removeArrangedSubview:button];
        [button removeFromSuperview];
    }
    for (NSUInteger index = 0; index < count; index++) {
        FSHCandidate *candidate = self.currentCandidates[index];
        UIButton *button;
        if (index < self.inlineButtonPool.count) {
            button = self.inlineButtonPool[index];
            [self configureCandidateButton:button index:index candidate:candidate exactCount:self.currentExactCount];
        } else {
            button = [self candidateButtonForIndex:index candidate:candidate exactCount:self.currentExactCount];
            [self.inlineButtonPool addObject:button];
        }
        button.accessibilityIdentifier = [NSString stringWithFormat:@"candidate.inline.%lu", (unsigned long)index];
        if (button.superview != self.candidateStack) {
            [self.candidateStack addArrangedSubview:button];
        }
    }
}

- (void)rebuildMoreCandidatesWithLimit:(NSUInteger)moreLimit {
    NSUInteger limit = moreLimit == 0 ? 500 : MIN(moreLimit, 500);
    NSUInteger count = MIN(self.currentCandidates.count, limit);
    for (NSUInteger index = count; index < self.moreButtonPool.count; index++) {
        UIButton *button = self.moreButtonPool[index];
        if (button.superview == self.moreContentView) {
            [button cancelTrackingWithEvent:nil];
            button.highlighted = NO;
            [button removeFromSuperview];
        }
    }
    if (count == 0) {
        if (self.moreContentHeightConstraint.constant != 0.0) {
            self.moreContentHeightConstraint.constant = 0.0;
        }
        if (!CGSizeEqualToSize(self.moreScrollView.contentSize, CGSizeZero)) {
            self.moreScrollView.contentSize = CGSizeZero;
        }
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
        UIButton *button;
        if (index < self.moreButtonPool.count) {
            button = self.moreButtonPool[index];
            [self configureCandidateButton:button index:index candidate:candidate exactCount:self.currentExactCount];
        } else {
            button = [self candidateButtonForIndex:index candidate:candidate exactCount:self.currentExactCount];
            [self.moreButtonPool addObject:button];
        }
        button.accessibilityIdentifier = [NSString stringWithFormat:@"candidate.expanded.%lu", (unsigned long)index];
        button.frame = CGRectMake(x, y, buttonWidth, kFSHCandidateButtonHeight);
        if (button.superview != self.moreContentView) {
            [self.moreContentView addSubview:button];
        }
    }

    CGFloat rows = ceil((double)count / (double)kFSHCandidateMoreColumns);
    CGFloat contentHeight = rows * kFSHCandidateButtonHeight + (rows - 1) * gap;
    if (self.moreContentHeightConstraint.constant != contentHeight) {
        self.moreContentHeightConstraint.constant = contentHeight;
    }
    CGSize contentSize = CGSizeMake(totalWidth, contentHeight);
    if (!CGSizeEqualToSize(self.moreScrollView.contentSize, contentSize)) {
        self.moreScrollView.contentSize = contentSize;
    }
}

- (UIButton *)candidateButtonForIndex:(NSUInteger)index
                             candidate:(FSHCandidate *)candidate
                            exactCount:(NSUInteger)exactCount {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = index;
    button.titleLabel.font = [self candidateFont];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 12.0 / 18.0;
    button.contentEdgeInsets = UIEdgeInsetsMake(1, 7, 1, 7);
    button.layer.cornerRadius = 6.0;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor systemGray4Color].CGColor;
    [button addTarget:self action:@selector(handleCandidateTap:) forControlEvents:UIControlEventTouchUpInside];
    [self configureCandidateButton:button index:index candidate:candidate exactCount:exactCount];
    return button;
}

- (void)configureCandidateButton:(UIButton *)button
                           index:(NSUInteger)index
                       candidate:(FSHCandidate *)candidate
                      exactCount:(NSUInteger)exactCount {
    if (button.tag != (NSInteger)index || ![[button titleForState:UIControlStateNormal] isEqualToString:candidate.value]) {
        [button cancelTrackingWithEvent:nil];
        button.highlighted = NO;
    }
    button.tag = index;
    [button setTitle:candidate.value forState:UIControlStateNormal];
    [button setTitleColor:[self candidateColorForIndex:index exactCount:exactCount] forState:UIControlStateNormal];
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
        [self rebuildMoreCandidatesWithLimit:self.currentMoreLimit];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:self.currentMoreLimit];
    }
    [self clampScrollOffsets];
}

@end
