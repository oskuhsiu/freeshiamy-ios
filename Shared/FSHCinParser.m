#import "FSHCinParser.h"
#import "FSHCandidate.h"

@implementation FSHCinParser

+ (NSArray<FSHCandidate *> *)parseCinAtPath:(NSString *)path error:(NSError **)error {
    if (path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"FSHCinParser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Missing cin path"}];
        }
        return @[];
    }

    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!content) {
        return @[];
    }

    NSMutableArray<FSHCandidate *> *results = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    [content enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:whitespace];
        if (trimmed.length == 0) {
            return;
        }
        unichar firstChar = [trimmed characterAtIndex:0];
        if (firstChar == '#' || firstChar == '%') {
            return;
        }
        NSRange splitRange = [trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (splitRange.location == NSNotFound) {
            return;
        }
        NSString *code = [trimmed substringToIndex:splitRange.location];
        NSString *value = [[trimmed substringFromIndex:splitRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (code.length == 0 || value.length == 0) {
            return;
        }
        FSHCandidate *candidate = [[FSHCandidate alloc] initWithCode:code value:value];
        [results addObject:candidate];
    }];

    return results;
}

@end
