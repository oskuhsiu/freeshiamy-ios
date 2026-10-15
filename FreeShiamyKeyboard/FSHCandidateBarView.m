#import "FSHCandidateBarView.h"
#import "FSHCandidate.h"
#import "FSHKeyboardMetrics.h"
#import "FSHKeyButton.h"

static const CGFloat kFSHCandidateMoreHeight = 180.0;
static const NSUInteger kFSHCandidateMoreColumns = 5;

@interface FSHCandidateBarView ()

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *rawButton;
@property (nonatomic, strong) UIView *candidateArea;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *candidateStack;
@property (nonatomic, strong) NSMutableArray<UIButton *> *inlineButtonPool;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) FSHKeyButton *compactGlobeButton;
@property (nonatomic, strong) UILabel *hintLabel;

@property (nonatomic, strong) UIView *moreContainer;
@property (nonatomic, strong) UIScrollView *moreScrollView;
@property (nonatomic, strong) UIView *moreContentView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *moreButtonPool;

@property (nonatomic, strong) NSLayoutConstraint *moreHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *topBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *moreButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *moreContentHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *scrollTrailingWithMore;
@property (nonatomic, strong) NSLayoutConstraint *scrollTrailingWithoutMore;
@property (nonatomic, strong) NSLayoutConstraint *candidateTrailingWithGlobe;
@property (nonatomic, strong) NSLayoutConstraint *candidateTrailingWithoutGlobe;

@property (nonatomic, copy) NSArray<FSHCandidate *> *currentCandidates;
@property (nonatomic, assign) NSUInteger currentExactCount;
@property (nonatomic, assign) NSUInteger currentInlineLimit;
@property (nonatomic, assign) NSUInteger currentMoreLimit;
@property (nonatomic, copy) NSArray *currentQuerySignature;
@property (nonatomic, assign) BOOL digitShortcutsAvailable;
@property (nonatomic, assign) BOOL spaceShortcutAvailable;
#if DEBUG
@property (nonatomic, assign) NSUInteger morePanChangedLogCount;
#endif

@end

@implementation FSHCandidateBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _digitShortcutsAvailable = YES;
        _spaceShortcutAvailable = YES;
        [self setupViews];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _digitShortcutsAvailable = YES;
        _spaceShortcutAvailable = YES;
        [self setupViews];
    }
    return self;
}

- (CGFloat)barHeight {
    return FSHCandidateBarDesiredHeight(self.traitCollection);
}

- (CGFloat)expandedHeight {
    return kFSHCandidateMoreHeight;
}

- (void)updateShortcutAvailabilityWithDigits:(BOOL)digits space:(BOOL)space {
    if (self.digitShortcutsAvailable == digits && self.spaceShortcutAvailable == space) {
        return;
    }
    self.digitShortcutsAvailable = digits;
    self.spaceShortcutAvailable = space;
    [UIView performWithoutAnimation:^{
        for (UIButton *button in self.candidateStack.arrangedSubviews) {
            NSUInteger index = (NSUInteger)button.tag;
            if (index < self.currentCandidates.count) {
                [self configureCandidateButton:button index:index candidate:self.currentCandidates[index]
                                    exactCount:self.currentExactCount];
            }
        }
        for (UIButton *button in self.moreButtonPool) {
            NSUInteger index = (NSUInteger)button.tag;
            if (button.superview == self.moreContentView && index < self.currentCandidates.count) {
                [self configureCandidateButton:button index:index candidate:self.currentCandidates[index]
                                    exactCount:self.currentExactCount];
            }
        }
    }];
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
    self.moreButton.accessibilityLabel = expanded ? @"收起更多候選字" : @"更多候選字";
    self.moreButton.accessibilityValue = expanded ? @"已展開" : @"已收合";
    self.moreButton.accessibilityHint = expanded ? @"點兩下收合候選字" : @"點兩下展開候選字";
    self.moreButton.accessibilityTraits = UIAccessibilityTraitButton | (expanded ? UIAccessibilityTraitSelected : 0);
    // Request the full list when standalone; the controller can budget it down.
    self.moreHeightConstraint.constant = expanded ? self.expandedHeight : 0.0;
    if ([self.delegate respondsToSelector:@selector(candidateBarView:didToggleExpanded:)]) {
        [self.delegate candidateBarView:self didToggleExpanded:expanded];
    }
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            [self layoutIfNeeded];
        }];
    } else {
        [self setNeedsLayout];
    }
}

- (void)setShowsCompactGlobe:(BOOL)showsCompactGlobe {
    if (_showsCompactGlobe == showsCompactGlobe) { return; }
    _showsCompactGlobe = showsCompactGlobe;
    self.compactGlobeButton.hidden = !showsCompactGlobe;
    self.candidateTrailingWithoutGlobe.active = NO;
    self.candidateTrailingWithGlobe.active = NO;
    if (showsCompactGlobe) {
        self.candidateTrailingWithGlobe.active = YES;
    } else {
        self.candidateTrailingWithoutGlobe.active = YES;
    }
    [self setNeedsLayout];
}

- (void)applyAvailableHeight:(CGFloat)height {
    CGFloat available = FSHNonnegativeFinite(height);
    CGFloat top = MIN(self.barHeight, available);
    CGFloat more = self.isExpanded ? MAX(0.0, available - top) : 0.0;
    if (fabs(self.topBarHeightConstraint.constant - top) > 0.5 ||
        fabs(self.moreButtonHeightConstraint.constant - top) > 0.5 ||
        fabs(self.moreHeightConstraint.constant - more) > 0.5) {
        self.topBarHeightConstraint.constant = top;
        self.moreButtonHeightConstraint.constant = top;
        self.moreHeightConstraint.constant = more;
        [self setNeedsLayout];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection ||
        [previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) {
        return;
    }
    UIFont *font = [self candidateFont];
    self.rawButton.titleLabel.font = font;
    self.moreButton.titleLabel.font = font;
    self.compactGlobeButton.titleLabel.font = font;
    self.hintLabel.font = font;
    for (UIButton *button in self.inlineButtonPool) { button.titleLabel.font = font; }
    for (UIButton *button in self.moreButtonPool) { button.titleLabel.font = font; }
    [self applyAvailableHeight:CGRectGetHeight(self.bounds)];
    [self setNeedsLayout];
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
        self.rawButton.accessibilityLabel = rawText;
        self.rawButton.accessibilityHint = @"點兩下輸入原始字碼";
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
    self.rawButton.titleLabel.minimumScaleFactor = 0.75;
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

    self.compactGlobeButton = [FSHKeyButton buttonWithType:UIButtonTypeSystem];
    self.compactGlobeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.compactGlobeButton.hidden = YES;
    self.compactGlobeButton.accessibilityLabel = @"切換鍵盤";
    self.compactGlobeButton.accessibilityIdentifier = @"candidate.compactGlobe";
    self.compactGlobeButton.titleLabel.font = [self candidateFont];
    [self.compactGlobeButton setTitle:@"🌐" forState:UIControlStateNormal];
    [self.compactGlobeButton addTarget:self action:@selector(handleCompactGlobeEvent:forEvent:)
                     forControlEvents:UIControlEventAllTouchEvents];
    __weak typeof(self) weakSelf = self;
    self.compactGlobeButton.accessibilityActivationHandler = ^{
        typeof(self) strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(candidateBarViewDidActivateCompactGlobe:)]) {
            [strongSelf.delegate candidateBarViewDidActivateCompactGlobe:strongSelf];
        }
    };
    [self.topBar addSubview:self.compactGlobeButton];

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
    self.moreButton.accessibilityLabel = @"更多候選字";
    self.moreButton.accessibilityIdentifier = @"candidate.more";
    self.moreButton.accessibilityValue = @"已收合";
    self.moreButton.accessibilityHint = @"點兩下展開候選字";
    [self.moreButton addTarget:self action:@selector(handleMoreTap) forControlEvents:UIControlEventTouchUpInside];
    [self.candidateArea addSubview:self.moreButton];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.accessibilityIdentifier = @"candidate.status";
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.font = [self candidateFont];
    self.hintLabel.adjustsFontSizeToFitWidth = YES;
    self.hintLabel.minimumScaleFactor = 0.75;
    self.hintLabel.textAlignment = NSTextAlignmentRight;
    self.hintLabel.textColor = [UIColor secondaryLabelColor];
    [self.topBar addSubview:self.hintLabel];

    self.moreContainer = [[UIView alloc] init];
    self.moreContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreContainer.hidden = YES;
    [self addSubview:self.moreContainer];

    self.moreScrollView = [[UIScrollView alloc] init];
    self.moreScrollView.accessibilityIdentifier = @"candidate.expandedList";
    self.moreScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.moreScrollView.showsVerticalScrollIndicator = YES;
#if DEBUG
    [self.moreScrollView.panGestureRecognizer addTarget:self action:@selector(observeMorePan:)];
#endif
    [self.moreContainer addSubview:self.moreScrollView];

    self.moreContentView = [[UIView alloc] init];
    self.moreContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.moreScrollView addSubview:self.moreContentView];
    self.moreButtonPool = [NSMutableArray array];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.topBar.topAnchor constraintEqualToAnchor:self.topAnchor],

        [self.rawButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:4.0],
        [self.rawButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.rawButton.widthAnchor constraintLessThanOrEqualToAnchor:self.topBar.widthAnchor multiplier:0.35],

        [self.candidateArea.leadingAnchor constraintEqualToAnchor:self.rawButton.trailingAnchor constant:4.0],
        [self.candidateArea.topAnchor constraintEqualToAnchor:self.topBar.topAnchor],
        [self.candidateArea.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],

        [self.compactGlobeButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-4.0],
        [self.compactGlobeButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.compactGlobeButton.widthAnchor constraintEqualToConstant:44.0],

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

        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.rawButton.trailingAnchor constant:8.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-8.0],
        [self.hintLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],

        [self.moreContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.moreContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.moreContainer.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.moreContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.topBarHeightConstraint = [self.topBar.heightAnchor constraintEqualToConstant:self.barHeight];
    // These are sizing requests, not a minimum input-view height. A host can
    // shrink between layout passes while the previous expanded More height is
    // still installed; required child heights would force the host back up.
    self.topBarHeightConstraint.priority = UILayoutPriorityDefaultHigh;
    self.topBarHeightConstraint.active = YES;
    self.moreButtonHeightConstraint = [self.moreButton.heightAnchor constraintEqualToConstant:self.barHeight];
    self.moreButtonHeightConstraint.active = YES;
    [self.compactGlobeButton.heightAnchor constraintEqualToAnchor:self.topBar.heightAnchor].active = YES;
    self.candidateTrailingWithoutGlobe = [self.candidateArea.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-4.0];
    self.candidateTrailingWithGlobe = [self.candidateArea.trailingAnchor constraintEqualToAnchor:self.compactGlobeButton.leadingAnchor constant:-4.0];
    self.candidateTrailingWithoutGlobe.active = YES;

    self.scrollTrailingWithMore = [self.scrollView.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-4.0];
    self.scrollTrailingWithoutMore = [self.scrollView.trailingAnchor constraintEqualToAnchor:self.candidateArea.trailingAnchor];
    self.scrollTrailingWithMore.active = YES;

    self.moreHeightConstraint = [self.moreContainer.heightAnchor constraintEqualToConstant:0.0];
    self.moreHeightConstraint.priority = UILayoutPriorityDefaultHigh;
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
    UIFont *base = [UIFont systemFontOfSize:18.0 weight:UIFontWeightRegular];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:base maximumPointSize:27.0 compatibleWithTraitCollection:self.traitCollection];
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
    CGFloat buttonWidth = MAX(0.0, (totalWidth - gap * (kFSHCandidateMoreColumns - 1)) / kFSHCandidateMoreColumns);
    CGFloat rowHeight = FSHCandidateRowDesiredHeight(self.traitCollection);

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger row = index / kFSHCandidateMoreColumns;
        NSUInteger col = index % kFSHCandidateMoreColumns;
        CGFloat x = (buttonWidth + gap) * col;
        CGFloat y = (rowHeight + gap) * row;

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
        button.frame = CGRectMake(x, y, buttonWidth, rowHeight);
        if (button.superview != self.moreContentView) {
            [self.moreContentView addSubview:button];
        }
    }

    CGFloat rows = ceil((double)count / (double)kFSHCandidateMoreColumns);
    CGFloat contentHeight = rows * rowHeight + (rows - 1) * gap;
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
    button.titleLabel.minimumScaleFactor = 0.75;
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
    button.accessibilityLabel = candidate.value;
    BOOL exact = index < exactCount;
    NSString *status = exact ? @"完全符合" : @"前綴候選";
    if (self.selectionContext == FSHCandidateSelectionContextReverseActive) {
        status = @"同音字候選";
    }
    NSString *codeLabel = self.selectionContext == FSHCandidateSelectionContextReverseActive ? @"讀音碼" : @"字碼";
    button.accessibilityValue = [NSString stringWithFormat:@"%@ %@，%@", codeLabel, candidate.code, status];
    BOOL digitShortcut = self.digitShortcutsAvailable && index < 10 &&
        ((self.selectionContext == FSHCandidateSelectionContextLetters && exact) ||
         (self.selectionContext == FSHCandidateSelectionContextReverseEntering && exact) ||
         self.selectionContext == FSHCandidateSelectionContextReverseActive);
    BOOL spaceShortcut = self.spaceShortcutAvailable && index == 0 &&
        (exact || self.selectionContext == FSHCandidateSelectionContextReverseActive);
    BOOL canExploreHomophones = self.selectionContext == FSHCandidateSelectionContextReverseEntering &&
        exact && candidate.value.length > 0 &&
        NSMaxRange([candidate.value rangeOfComposedCharacterSequenceAtIndex:0]) == candidate.value.length;
    NSString *action = canExploreHomophones
        ? @"點兩下查看同音字" : @"點兩下輸入候選字";
    NSMutableArray<NSString *> *shortcuts = [NSMutableArray array];
    if (digitShortcut) {
        [shortcuts addObject:[NSString stringWithFormat:@"數字 %lu", (unsigned long)index]];
    }
    if (spaceShortcut) {
        [shortcuts addObject:@"空白鍵"];
    }
    if (shortcuts.count > 0) {
        button.accessibilityHint = [NSString stringWithFormat:@"%@；也可按%@", action,
                                    [shortcuts componentsJoinedByString:@"或"]];
    } else {
        button.accessibilityHint = action;
    }
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
#if DEBUG
    UIScrollView *scroll = self.moreScrollView;
    UIPanGestureRecognizer *pan = scroll.panGestureRecognizer;
    NSLog(@"[MoreGesture] candidate action area=%@ index=%lu expanded=%d pan=%ld translation=%@ offset=%@ bounds=%@ contentSize=%@ dragging=%d decelerating=%d",
          sender.superview == self.moreContentView ? @"expanded" : @"inline",
          (unsigned long)sender.tag, self.isExpanded, (long)pan.state,
          NSStringFromCGPoint([pan translationInView:scroll]), NSStringFromCGPoint(scroll.contentOffset),
          NSStringFromCGRect(scroll.bounds), NSStringFromCGSize(scroll.contentSize),
          scroll.isDragging, scroll.isDecelerating);
#endif
    if ([self.delegate respondsToSelector:@selector(candidateBarView:didSelectCandidateAtIndex:)]) {
        [self.delegate candidateBarView:self didSelectCandidateAtIndex:sender.tag];
    }
}

#if DEBUG
- (void)observeMorePan:(UIPanGestureRecognizer *)pan {
    UIGestureRecognizerState state = pan.state;
    if (state == UIGestureRecognizerStateBegan) self.morePanChangedLogCount = 0;
    // Log transitions and only the first few changed samples per gesture.
    if (state == UIGestureRecognizerStateChanged && self.morePanChangedLogCount++ >= 3) return;
    UIScrollView *scroll = self.moreScrollView;
    NSLog(@"[MoreGesture] pan state=%ld translation=%@ offset=%@ bounds=%@ contentSize=%@ dragging=%d decelerating=%d",
          (long)state, NSStringFromCGPoint([pan translationInView:scroll]),
          NSStringFromCGPoint(scroll.contentOffset), NSStringFromCGRect(scroll.bounds),
          NSStringFromCGSize(scroll.contentSize), scroll.isDragging, scroll.isDecelerating);
}
#endif

- (void)handleMoreTap {
    [self setExpanded:!self.isExpanded animated:YES];
    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:self.currentMoreLimit];
    }
}

- (void)handleCompactGlobeEvent:(FSHKeyButton *)sender forEvent:(UIEvent *)event {
    if ([self.delegate respondsToSelector:@selector(candidateBarView:didReceiveInputModeEvent:fromView:)]) {
        [self.delegate candidateBarView:self didReceiveInputModeEvent:event fromView:sender];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = FSHNonnegativeFinite(CGRectGetHeight(self.bounds));
    CGFloat top = MIN(self.barHeight, height);
    CGFloat more = self.isExpanded ? MAX(0.0, height - top) : 0.0;
    if (fabs(self.topBarHeightConstraint.constant - top) > 0.5 ||
        fabs(self.moreHeightConstraint.constant - more) > 0.5) {
        [self applyAvailableHeight:height];
    }
    if (self.isExpanded) {
        [self rebuildMoreCandidatesWithLimit:self.currentMoreLimit];
    }
    [self clampScrollOffsets];
}

@end
