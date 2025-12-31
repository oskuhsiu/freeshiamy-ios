#import "FSHKeyboardView.h"
#import "FSHKeyButton.h"

@interface FSHKeyDescriptor : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, assign) NSInteger keyCode;
@property (nonatomic, assign) CGFloat weight;
@property (nonatomic, assign) BOOL isSpecial;
@end

@implementation FSHKeyDescriptor
@end

@interface FSHKeyboardView ()

@property (nonatomic, strong) NSMutableArray<NSArray<FSHKeyButton *> *> *rowButtons;
@property (nonatomic, strong) FSHKeyButton *shiftButton;
@property (nonatomic, strong) FSHKeyButton *deleteButton;
@property (nonatomic, strong) FSHKeyButton *modeButton;
@property (nonatomic, strong) FSHKeyButton *emojiButton;

@end

@implementation FSHKeyboardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _rowButtons = [NSMutableArray array];
        _layout = FSHKeyboardLayoutStandard;
        _mode = FSHKeyboardModeLetters;
        _showNumberRow = YES;
        _showsGlobe = NO;
        _labelTop = NO;
        _leftShift = YES;
        self.backgroundColor = [UIColor systemGray5Color];
        [self reloadKeys];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _rowButtons = [NSMutableArray array];
        _layout = FSHKeyboardLayoutStandard;
        _mode = FSHKeyboardModeLetters;
        _showNumberRow = YES;
        _showsGlobe = NO;
        _labelTop = NO;
        _leftShift = YES;
        self.backgroundColor = [UIColor systemGray5Color];
        [self reloadKeys];
    }
    return self;
}

- (void)setMode:(FSHKeyboardMode)mode {
    if (_mode == mode) {
        return;
    }
    _mode = mode;
    [self reloadKeys];
}

- (void)setLayout:(FSHKeyboardLayout)layout {
    if (layout == FSHKeyboardLayoutStandardLabelTop) {
        self.labelTop = YES;
        layout = FSHKeyboardLayoutStandard;
    }
    if (_layout == layout) {
        return;
    }
    _layout = layout;
    [self reloadKeys];
}

- (void)setShowNumberRow:(BOOL)showNumberRow {
    if (_showNumberRow == showNumberRow) {
        return;
    }
    _showNumberRow = showNumberRow;
    [self reloadKeys];
}

- (void)setShowsGlobe:(BOOL)showsGlobe {
    if (_showsGlobe == showsGlobe) {
        return;
    }
    _showsGlobe = showsGlobe;
    [self reloadKeys];
}

- (void)setLabelTop:(BOOL)labelTop {
    if (_labelTop == labelTop) {
        return;
    }
    _labelTop = labelTop;
    [self reloadKeys];
}

- (void)setLeftShift:(BOOL)leftShift {
    if (_leftShift == leftShift) {
        return;
    }
    _leftShift = leftShift;
    [self setNeedsLayout];
}

- (void)setShiftOn:(BOOL)shiftOn {
    _shiftOn = shiftOn;
    [self updateShiftAppearance];
}

- (void)setCapsLockOn:(BOOL)capsLockOn {
    _capsLockOn = capsLockOn;
    [self updateShiftAppearance];
}

- (void)reloadKeys {
    for (NSArray<FSHKeyButton *> *row in self.rowButtons) {
        for (FSHKeyButton *button in row) {
            [button removeFromSuperview];
        }
    }
    [self.rowButtons removeAllObjects];
    self.shiftButton = nil;
    self.deleteButton = nil;
    self.modeButton = nil;
    self.emojiButton = nil;

    NSArray<NSArray<FSHKeyDescriptor *> *> *rows = [self keyDescriptorsForMode:self.mode];
    for (NSArray<FSHKeyDescriptor *> *row in rows) {
        NSMutableArray<FSHKeyButton *> *buttons = [NSMutableArray arrayWithCapacity:row.count];
        for (FSHKeyDescriptor *descriptor in row) {
            FSHKeyButton *button = [self buildButtonWithDescriptor:descriptor];
            [self addSubview:button];
            [buttons addObject:button];
        }
        [self.rowButtons addObject:buttons];
    }
    [self updateShiftAppearance];
    [self setNeedsLayout];
}

- (NSArray<NSArray<FSHKeyDescriptor *> *> *)keyDescriptorsForMode:(FSHKeyboardMode)mode {
    switch (mode) {
        case FSHKeyboardModeLetters:
            return [self letterRows];
        case FSHKeyboardModeSymbols:
            return [self symbolRows:NO];
        case FSHKeyboardModeSymbolsShift:
            return [self symbolRows:YES];
        case FSHKeyboardModeEmoji:
            return [self emojiRows];
    }
}

- (NSArray<NSArray<FSHKeyDescriptor *> *> *)letterRows {
    NSMutableArray<NSArray<FSHKeyDescriptor *> *> *rows = [NSMutableArray array];

    BOOL isOriginal = (self.layout == FSHKeyboardLayoutOriginal || self.layout == FSHKeyboardLayoutOriginalNoNumber);
    BOOL showNumbers = self.showNumberRow && self.layout != FSHKeyboardLayoutOriginalNoNumber;
    if (showNumbers) {
        NSMutableArray<FSHKeyDescriptor *> *numbers = [NSMutableArray array];
        for (NSString *digit in @[ @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0" ]) {
            [numbers addObject:[self key:digit output:digit code:0 weight:1.0 special:NO]];
        }
        [rows addObject:numbers];
    }

    NSArray<NSString *> *qRow = @[ @"Q", @"W", @"E", @"R", @"T", @"Y", @"U", @"I", @"O", @"P" ];
    NSMutableArray<FSHKeyDescriptor *> *row1 = [NSMutableArray array];
    for (NSString *letter in qRow) {
        [row1 addObject:[self key:letter output:letter.lowercaseString code:0 weight:1.0 special:NO]];
    }
    [rows addObject:row1];

    NSArray<NSString *> *aRow = @[ @"A", @"S", @"D", @"F", @"G", @"H", @"J", @"K", @"L" ];
    NSMutableArray<FSHKeyDescriptor *> *row2 = [NSMutableArray array];
    for (NSString *letter in aRow) {
        [row2 addObject:[self key:letter output:letter.lowercaseString code:0 weight:1.0 special:NO]];
    }
    if (isOriginal) {
        [row2 addObject:[self key:@"'" output:@"'" code:0 weight:1.0 special:NO]];
    } else {
        [row2 addObject:[self key:@"⌫" output:nil code:FSHKeyCodeDelete weight:1.4 special:YES]];
    }
    [rows addObject:row2];

    NSArray<NSString *> *zRow = @[ @"Z", @"X", @"C", @"V", @"B", @"N", @"M", @",", @"." ];
    NSMutableArray<FSHKeyDescriptor *> *row3 = [NSMutableArray array];
    CGFloat shiftWeight = isOriginal ? 1.0 : 1.4;
    [row3 addObject:[self key:@"⇧" output:nil code:FSHKeyCodeShift weight:shiftWeight special:YES]];
    for (NSString *letter in zRow) {
        [row3 addObject:[self key:letter output:letter.lowercaseString code:0 weight:1.0 special:NO]];
    }
    [rows addObject:row3];

    NSMutableArray<FSHKeyDescriptor *> *row4 = [NSMutableArray array];
    if (isOriginal) {
        [row4 addObject:[self key:@"Done" output:nil code:FSHKeyCodeCancel weight:1.5 special:YES]];
        CGFloat modeWeight = 1.5;
        [row4 addObject:[self key:@"123" output:nil code:FSHKeyCodeModeChange weight:modeWeight special:YES]];
        [row4 addObject:[self key:@"Space" output:@" " code:FSHKeyCodeSpace weight:4.0 special:YES]];
        [row4 addObject:[self key:@"⌫" output:nil code:FSHKeyCodeDelete weight:1.5 special:YES]];
        [row4 addObject:[self key:@"Enter" output:nil code:FSHKeyCodeEnter weight:1.5 special:YES]];
    } else {
        [row4 addObject:[self key:@"Done" output:nil code:FSHKeyCodeCancel weight:1.5 special:YES]];
        CGFloat modeWeight = 1.5;
        [row4 addObject:[self key:@"123" output:nil code:FSHKeyCodeModeChange weight:modeWeight special:YES]];
        if (self.showsGlobe) {
            [row4 addObject:[self key:@"🌐" output:nil code:FSHKeyCodeGlobe weight:1.0 special:YES]];
        }
        [row4 addObject:[self key:@"Space" output:@" " code:FSHKeyCodeSpace weight:4.0 special:YES]];
        [row4 addObject:[self key:@"'" output:@"'" code:0 weight:1.0 special:NO]];
        CGFloat enterWeight = self.showsGlobe ? 1.0 : 2.0;
        [row4 addObject:[self key:@"Enter" output:nil code:FSHKeyCodeEnter weight:enterWeight special:YES]];
    }
    [rows addObject:row4];

    return rows;
}

- (NSArray<NSArray<FSHKeyDescriptor *> *> *)symbolRows:(BOOL)shifted {
    NSMutableArray<NSArray<FSHKeyDescriptor *> *> *rows = [NSMutableArray array];

    NSArray<NSString *> *row0 = @[ @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0" ];
    NSMutableArray<FSHKeyDescriptor *> *numbers = [NSMutableArray array];
    for (NSString *digit in row0) {
        [numbers addObject:[self key:digit output:digit code:0 weight:1.0 special:NO]];
    }
    [rows addObject:numbers];

    NSArray<NSString *> *row1 = shifted ? @[ @"_", @"\\", @"|", @"~", @"<", @">", @"€", @"£", @"¥", @"•" ]
                                     : @[ @"-", @"/", @":", @";", @"(", @")", @"$", @"&", @"@", @"'" ];
    NSMutableArray<FSHKeyDescriptor *> *symbols1 = [NSMutableArray array];
    for (NSString *symbol in row1) {
        [symbols1 addObject:[self key:symbol output:symbol code:0 weight:1.0 special:NO]];
    }
    [rows addObject:symbols1];

    NSArray<NSString *> *row2 = shifted ? @[ @"±", @"×", @"÷", @"…", @"=", @"+", @"•", @"°", @"^" ]
                                     : @[ @"[", @"]", @"{", @"}", @"#", @"%", @"^", @"*", @"+" ];
    NSMutableArray<FSHKeyDescriptor *> *symbols2 = [NSMutableArray array];
    [symbols2 addObject:[self key:shifted ? @"123" : @"#+=" output:nil code:FSHKeyCodeShift weight:1.4 special:YES]];
    for (NSString *symbol in row2) {
        [symbols2 addObject:[self key:symbol output:symbol code:0 weight:1.0 special:NO]];
    }
    [symbols2 addObject:[self key:@"⌫" output:nil code:FSHKeyCodeDelete weight:1.2 special:YES]];
    [rows addObject:symbols2];

    NSMutableArray<FSHKeyDescriptor *> *bottom = [NSMutableArray array];
    [bottom addObject:[self key:@"Done" output:nil code:FSHKeyCodeCancel weight:1.0 special:YES]];
    CGFloat modeWeight = 1.5;
    [bottom addObject:[self key:@"ABC" output:nil code:FSHKeyCodeModeChange weight:modeWeight special:YES]];
    if (self.showsGlobe) {
        [bottom addObject:[self key:@"🌐" output:nil code:FSHKeyCodeGlobe weight:1.0 special:YES]];
    }
    [bottom addObject:[self key:@"Space" output:@" " code:FSHKeyCodeSpace weight:4.0 special:YES]];
    if (shifted) {
        [bottom addObject:[self key:@"…" output:@"…" code:0 weight:0.75 special:NO]];
    } else {
        [bottom addObject:[self key:@"," output:@"," code:0 weight:0.75 special:NO]];
    }
    [bottom addObject:[self key:@"." output:@"." code:0 weight:0.75 special:NO]];
    CGFloat enterWeight = self.showsGlobe ? 1.0 : 2.0;
    [bottom addObject:[self key:@"Enter" output:nil code:FSHKeyCodeEnter weight:enterWeight special:YES]];
    [rows addObject:bottom];

    return rows;
}

- (NSArray<NSArray<FSHKeyDescriptor *> *> *)emojiRows {
    NSArray<NSString *> *emoji = @[ @"😀", @"😃", @"😄", @"😁", @"😆", @"😅", @"😂", @"🤣", @"😊", @"😇",
                                   @"🙂", @"🙃", @"😉", @"😌", @"😍", @"🥰", @"😘", @"😗", @"😙", @"😚",
                                   @"😋", @"😛", @"😝", @"😜", @"🤪", @"🤨", @"🧐", @"🤓", @"😎", @"🤩",
                                   @"🥳", @"😏", @"😒", @"😞", @"😔", @"😟", @"😕", @"🙁", @"☹️", @"😣" ];

    NSMutableArray<NSArray<FSHKeyDescriptor *> *> *rows = [NSMutableArray array];
    NSUInteger perRow = 10;
    for (NSUInteger i = 0; i < emoji.count; i += perRow) {
        NSRange range = NSMakeRange(i, MIN(perRow, emoji.count - i));
        NSArray<NSString *> *slice = [emoji subarrayWithRange:range];
        NSMutableArray<FSHKeyDescriptor *> *row = [NSMutableArray array];
        for (NSString *symbol in slice) {
            [row addObject:[self key:symbol output:symbol code:0 weight:1.0 special:NO]];
        }
        [rows addObject:row];
    }

    NSMutableArray<FSHKeyDescriptor *> *bottom = [NSMutableArray array];
    [bottom addObject:[self key:@"Done" output:nil code:FSHKeyCodeCancel weight:1.0 special:YES]];
    CGFloat modeWeight = 1.5;
    [bottom addObject:[self key:@"ABC" output:nil code:FSHKeyCodeModeChange weight:modeWeight special:YES]];
    if (self.showsGlobe) {
        [bottom addObject:[self key:@"🌐" output:nil code:FSHKeyCodeGlobe weight:1.0 special:YES]];
    }
    [bottom addObject:[self key:@"Space" output:@" " code:FSHKeyCodeSpace weight:4.0 special:YES]];
    [bottom addObject:[self key:@"," output:@"," code:0 weight:0.75 special:NO]];
    [bottom addObject:[self key:@"." output:@"." code:0 weight:0.75 special:NO]];
    CGFloat enterWeight = self.showsGlobe ? 1.0 : 2.0;
    [bottom addObject:[self key:@"Enter" output:nil code:FSHKeyCodeEnter weight:enterWeight special:YES]];
    [rows addObject:bottom];

    return rows;
}

- (FSHKeyDescriptor *)key:(NSString *)label output:(NSString *)output code:(NSInteger)code weight:(CGFloat)weight special:(BOOL)special {
    FSHKeyDescriptor *descriptor = [[FSHKeyDescriptor alloc] init];
    descriptor.label = label;
    descriptor.output = output;
    descriptor.keyCode = code;
    descriptor.weight = weight;
    descriptor.isSpecial = special;
    return descriptor;
}

- (FSHKeyButton *)buildButtonWithDescriptor:(FSHKeyDescriptor *)descriptor {
    FSHKeyButton *button = [FSHKeyButton buttonWithType:UIButtonTypeSystem];
    button.keyCode = descriptor.keyCode;
    button.output = descriptor.output;
    button.isSpecial = descriptor.isSpecial;
    button.weight = descriptor.weight;
    button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightRegular];
    [button setTitle:descriptor.label forState:UIControlStateNormal];
    button.layer.cornerRadius = 6.0;
    button.backgroundColor = descriptor.isSpecial ? [UIColor systemGray4Color] : [UIColor whiteColor];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(handleKeyPress:) forControlEvents:UIControlEventTouchUpInside];

    if (descriptor.keyCode == FSHKeyCodeDelete) {
        [button addTarget:self action:@selector(handleKeyDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(handleKeyUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        self.deleteButton = button;
    }
    if (descriptor.keyCode == FSHKeyCodeModeChange) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleModeLongPress:)];
        longPress.minimumPressDuration = 0.4;
        [button addGestureRecognizer:longPress];
        self.modeButton = button;
    }
    if (descriptor.keyCode == FSHKeyCodeCancel) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoneLongPress:)];
        longPress.minimumPressDuration = 0.4;
        [button addGestureRecognizer:longPress];
    }
    if (descriptor.keyCode == FSHKeyCodeShift) {
        self.shiftButton = button;
    }
    if (descriptor.keyCode == FSHKeyCodeEmoji) {
        self.emojiButton = button;
    }

    if (self.labelTop && !descriptor.isSpecial && descriptor.label.length > 0) {
        button.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
        button.contentEdgeInsets = UIEdgeInsetsMake(6, 0, 0, 0);
    }
    return button;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.rowButtons.count == 0) {
        return;
    }
    CGFloat totalHeight = self.bounds.size.height;
    CGFloat totalWidth = self.bounds.size.width;
    NSUInteger rowsCount = self.rowButtons.count;
    CGFloat rowGap = 6.0;
    CGFloat rowHeight = (totalHeight - rowGap * (rowsCount - 1)) / rowsCount;

    CGFloat hGap = 4.0;
    CGFloat sideInset = 4.0;
    if (self.layout == FSHKeyboardLayoutStandardSpacious) {
        hGap = totalWidth * 0.015;
        sideInset = totalWidth * 0.0575;
    } else if (self.layout == FSHKeyboardLayoutOriginal || self.layout == FSHKeyboardLayoutOriginalNoNumber) {
        hGap = 1.0;
        sideInset = 0.0;
        rowGap = 1.0;
    }

    for (NSUInteger rowIndex = 0; rowIndex < rowsCount; rowIndex++) {
        NSArray<FSHKeyButton *> *row = self.rowButtons[rowIndex];
        CGFloat rowInsetUnitsLeft = 0.0;
        CGFloat rowInsetUnitsRight = 0.0;
        BOOL shrinkDeleteHalf = NO;
        if (self.mode == FSHKeyboardModeLetters && self.leftShift && self.layout != FSHKeyboardLayoutOriginal && self.layout != FSHKeyboardLayoutOriginalNoNumber) {
            FSHKeyButton *first = row.firstObject;
            NSString *label = [first titleForState:UIControlStateNormal];
            if ([label isEqualToString:@"1"] || [label isEqualToString:@"Q"]) {
                rowInsetUnitsLeft = 0.5;
                rowInsetUnitsRight = 0.5;
            } else if ([label isEqualToString:@"A"]) {
                rowInsetUnitsLeft = 1.0;
                shrinkDeleteHalf = YES;
            }
        }
        CGFloat totalWeight = 0.0;
        for (FSHKeyButton *button in row) {
            CGFloat weight = button.weight;
            if (shrinkDeleteHalf && button.keyCode == FSHKeyCodeDelete) {
                weight = MAX(0.5, weight - 0.5);
            }
            totalWeight += weight;
        }
        CGFloat availableWidth = totalWidth - sideInset * 2 - hGap * (row.count - 1);
        CGFloat unitWidth = totalWeight > 0 ? (availableWidth / (totalWeight + rowInsetUnitsLeft + rowInsetUnitsRight)) : 0.0;
        CGFloat rowInsetLeft = unitWidth * rowInsetUnitsLeft;
        CGFloat rowInsetRight = unitWidth * rowInsetUnitsRight;
        CGFloat adjustedAvailableWidth = availableWidth - rowInsetLeft - rowInsetRight;
        CGFloat adjustedUnitWidth = totalWeight > 0 ? (adjustedAvailableWidth / totalWeight) : 0.0;
        CGFloat x = sideInset + rowInsetLeft;
        CGFloat y = (rowHeight + rowGap) * rowIndex;
        for (FSHKeyButton *button in row) {
            CGFloat weight = button.weight;
            if (shrinkDeleteHalf && button.keyCode == FSHKeyCodeDelete) {
                weight = MAX(0.5, weight - 0.5);
            }
            CGFloat width = (totalWeight > 0) ? adjustedUnitWidth * weight : 0;
            button.frame = CGRectMake(x, y, width, rowHeight);
            x += width + hGap;
        }
    }
}

- (void)handleKeyPress:(FSHKeyButton *)sender {
    if ([self.delegate respondsToSelector:@selector(keyboardView:didPressKeyCode:output:)]) {
        [self.delegate keyboardView:self didPressKeyCode:sender.keyCode output:sender.output];
    }
}

- (void)handleKeyDown:(FSHKeyButton *)sender {
    if ([self.delegate respondsToSelector:@selector(keyboardView:didBeginPressKeyCode:output:)]) {
        [self.delegate keyboardView:self didBeginPressKeyCode:sender.keyCode output:sender.output];
    }
}

- (void)handleKeyUp:(FSHKeyButton *)sender {
    if ([self.delegate respondsToSelector:@selector(keyboardView:didEndPressKeyCode:output:)]) {
        [self.delegate keyboardView:self didEndPressKeyCode:sender.keyCode output:sender.output];
    }
}

- (void)handleModeLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([self.delegate respondsToSelector:@selector(keyboardView:didPressKeyCode:output:)]) {
            [self.delegate keyboardView:self didPressKeyCode:FSHKeyCodeEmoji output:nil];
        }
    }
}

- (void)handleDoneLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([self.delegate respondsToSelector:@selector(keyboardView:didPressKeyCode:output:)]) {
            [self.delegate keyboardView:self didPressKeyCode:FSHKeyCodeSettings output:nil];
        }
    }
}

- (void)updateShiftAppearance {
    if (!self.shiftButton) {
        return;
    }
    if (self.capsLockOn) {
        self.shiftButton.backgroundColor = [UIColor systemBlueColor];
        [self.shiftButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else if (self.shiftOn) {
        self.shiftButton.backgroundColor = [UIColor systemBlueColor];
        [self.shiftButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        self.shiftButton.backgroundColor = [UIColor systemGray4Color];
        [self.shiftButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }
}

@end
