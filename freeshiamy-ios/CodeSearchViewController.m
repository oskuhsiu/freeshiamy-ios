#import "CodeSearchViewController.h"
#import "FSHShiamyEngine.h"

@interface CodeSearchViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UITextField *queryField;
@property (nonatomic, strong) UITextView *resultsView;
@property (nonatomic, strong) FSHShiamyEngine *engine;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, copy) NSString *loadErrorDescription;

@end

@implementation CodeSearchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"查字根";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UILabel *instructions = [[UILabel alloc] init];
    instructions.translatesAutoresizingMaskIntoConstraints = NO;
    instructions.text = @"輸入中文字，查詢最短與其他嘸蝦米字碼；多個字會逐字查詢。";
    instructions.numberOfLines = 0;
    instructions.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    instructions.adjustsFontForContentSizeCategory = YES;

    self.queryField = [[UITextField alloc] init];
    self.queryField.translatesAutoresizingMaskIntoConstraints = NO;
    self.queryField.borderStyle = UITextBorderStyleRoundedRect;
    self.queryField.placeholder = @"輸入要查的字";
    self.queryField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.queryField.returnKeyType = UIReturnKeySearch;
    self.queryField.delegate = self;
    self.queryField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.queryField.adjustsFontForContentSizeCategory = YES;
    self.queryField.accessibilityIdentifier = @"codeSearch.query";
    [self.queryField addTarget:self action:@selector(queryChanged:) forControlEvents:UIControlEventEditingChanged];

    self.resultsView = [[UITextView alloc] init];
    self.resultsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultsView.editable = NO;
    self.resultsView.selectable = YES;
    self.resultsView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.resultsView.layer.cornerRadius = 8.0;
    self.resultsView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.resultsView.adjustsFontForContentSizeCategory = YES;
    self.resultsView.accessibilityIdentifier = @"codeSearch.results";

    [self.view addSubview:instructions];
    [self.view addSubview:self.queryField];
    [self.view addSubview:self.resultsView];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [instructions.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [instructions.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [instructions.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [self.queryField.topAnchor constraintEqualToAnchor:instructions.bottomAnchor constant:12.0],
        [self.queryField.leadingAnchor constraintEqualToAnchor:instructions.leadingAnchor],
        [self.queryField.trailingAnchor constraintEqualToAnchor:instructions.trailingAnchor],
        [self.queryField.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [self.resultsView.topAnchor constraintEqualToAnchor:self.queryField.bottomAnchor constant:12.0],
        [self.resultsView.leadingAnchor constraintEqualToAnchor:instructions.leadingAnchor],
        [self.resultsView.trailingAnchor constraintEqualToAnchor:instructions.trailingAnchor],
    ]];
    NSLayoutConstraint *minimumResultsHeight = [self.resultsView.heightAnchor constraintGreaterThanOrEqualToConstant:100.0];
    minimumResultsHeight.priority = UILayoutPriorityDefaultLow;
    minimumResultsHeight.active = YES;
    NSLayoutConstraint *resultsBottom = [self.resultsView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-16.0];
    resultsBottom.priority = UILayoutPriorityDefaultHigh;
    resultsBottom.active = YES;

    [self loadDictionaryAsync];
}

- (void)loadDictionaryAsync {
    self.loadGeneration++;
    NSUInteger generation = self.loadGeneration;
    self.engine = nil;
    self.loadErrorDescription = nil;
    self.navigationItem.rightBarButtonItem = nil;
    [self renderResults];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
        NSError *error = nil;
        BOOL loaded = [engine loadFromBundle:[NSBundle mainBundle] error:&error];
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

- (void)queryChanged:(UITextField *)field {
    [self renderResults];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

- (void)renderResults {
    if (!self.engine) {
        self.resultsView.text = self.loadErrorDescription.length > 0
            ? [NSString stringWithFormat:@"字庫載入失敗：%@", self.loadErrorDescription]
            : @"字庫載入中…";
        return;
    }
    NSString *query = [self.queryField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.resultsView.text = @"輸入一個或多個字開始查詢。";
        return;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    __block NSUInteger count = 0;
    [query enumerateSubstringsInRange:NSMakeRange(0, query.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString * _Nullable character, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
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
    self.resultsView.text = [lines componentsJoinedByString:@"\n"];
}

@end
