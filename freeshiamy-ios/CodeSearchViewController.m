#import "CodeSearchViewController.h"
#import "FSHShiamyEngine.h"

@interface CodeSearchViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *queryField;
@property (nonatomic, strong) UILabel *resultsLabel;
@property (nonatomic, strong) FSHShiamyEngine *engine;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, copy) NSString *loadErrorDescription;

@end

@implementation CodeSearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"查字根";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;

    UILabel *instructions = [[UILabel alloc] init];
    instructions.text = @"輸入中文字，查詢最短與其他嘸蝦米字碼；多個字會逐字查詢。";
    instructions.numberOfLines = 0;
    instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    instructions.adjustsFontForContentSizeCategory = YES;

    self.queryField = [[UITextField alloc] init];
    self.queryField.borderStyle = UITextBorderStyleRoundedRect;
    self.queryField.placeholder = @"輸入要查的字";
    self.queryField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.queryField.returnKeyType = UIReturnKeySearch;
    self.queryField.delegate = self;
    self.queryField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.queryField.adjustsFontForContentSizeCategory = YES;
    self.queryField.accessibilityIdentifier = @"codeSearch.query";
    [self.queryField addTarget:self action:@selector(queryChanged:) forControlEvents:UIControlEventEditingChanged];

    self.resultsLabel = [[UILabel alloc] init];
    self.resultsLabel.numberOfLines = 0;
    self.resultsLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.resultsLabel.layer.cornerRadius = 8.0;
    self.resultsLabel.layer.masksToBounds = YES;
    self.resultsLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.resultsLabel.adjustsFontForContentSizeCategory = YES;
    self.resultsLabel.accessibilityIdentifier = @"codeSearch.results";

    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:stack];
    [stack addArrangedSubview:instructions];
    [stack addArrangedSubview:self.queryField];
    [stack addArrangedSubview:self.resultsLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-16.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32.0],
        [self.queryField.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];

    [self loadDictionaryAsync];
}

- (void)loadDictionaryAsync {
    self.loadGeneration++;
    NSUInteger generation = self.loadGeneration;
    self.engine = nil;
    self.loadErrorDescription = nil;
    self.navigationItem.rightBarButtonItem = nil;
    [self renderResults];
    FSHShiamyEngine *engine = [self newDictionaryEngine];
    NSBundle *bundle = [self dictionaryBundle];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL loaded = [engine loadFromBundle:bundle error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            CodeSearchViewController *strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.loadGeneration) {
                return;
            }
            strongSelf.engine = loaded ? engine : nil;
            strongSelf.loadErrorDescription = loaded ? nil : (error.localizedDescription ?: @"無法讀取字庫");
            strongSelf.navigationItem.rightBarButtonItem = loaded ? nil :
                [[UIBarButtonItem alloc] initWithTitle:@"重試" style:UIBarButtonItemStylePlain
                                             target:strongSelf action:@selector(loadDictionaryAsync)];
            [strongSelf renderResults];
        });
    });
}

- (FSHShiamyEngine *)newDictionaryEngine {
    return [[FSHShiamyEngine alloc] init];
}

- (NSBundle *)dictionaryBundle {
    return [NSBundle mainBundle];
}

- (void)queryChanged:(UITextField *)field {
    if (field.markedTextRange) {
        return;
    }
    [self renderResults];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self scrollQueryIntoView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.queryField.isFirstResponder) {
        [self scrollQueryIntoView];
    }
}

- (void)scrollQueryIntoView {
    CGRect queryRect = [self.queryField convertRect:self.queryField.bounds toView:self.scrollView];
    [self.scrollView scrollRectToVisible:CGRectInset(queryRect, 0.0, -8.0) animated:NO];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

- (void)renderResults {
    if (!self.engine) {
        self.resultsLabel.text = self.loadErrorDescription.length > 0
            ? [NSString stringWithFormat:@"字庫載入失敗：%@", self.loadErrorDescription]
            : @"字庫載入中…";
        return;
    }
    NSString *query = [self.queryField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.resultsLabel.text = @"輸入一個或多個字開始查詢。";
        return;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    __block NSUInteger count = 0;
    [query enumerateSubstringsInRange:NSMakeRange(0, query.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString * _Nullable character, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        if (character.length == 0 ||
            [character rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
            return;
        }
        if (count == 64) {
            [lines addObject:@"一次最多查詢 64 個字，請縮短輸入。"];
            *stop = YES;
            return;
        }
        count++;
        NSArray<NSString *> *codes = [self.engine allCodesForValue:character];
        if (codes.count == 0) {
            [lines addObject:[NSString stringWithFormat:@"%@：查無字碼", character]];
            return;
        }
        NSString *shortest = codes.firstObject.uppercaseString;
        if (codes.count == 1) {
            [lines addObject:[NSString stringWithFormat:@"%@：最短 %@", character, shortest]];
            return;
        }
        NSMutableArray<NSString *> *alternatives = [NSMutableArray arrayWithCapacity:codes.count - 1];
        for (NSUInteger index = 1; index < codes.count; index++) {
            [alternatives addObject:codes[index].uppercaseString];
        }
        [lines addObject:[NSString stringWithFormat:@"%@：最短 %@；其他 %@", character, shortest,
                          [alternatives componentsJoinedByString:@"、"]]];
    }];
    self.resultsLabel.text = [lines componentsJoinedByString:@"\n"];
}

@end
