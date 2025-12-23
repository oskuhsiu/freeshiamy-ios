#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"
#import "FSHCandidate.h"

@interface FSHShiamyEngine ()

@property (nonatomic, assign, readwrite) BOOL ready;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<FSHCandidate *> *> *firstCharIndex;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *shortestCodeByValue;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *spellByValue;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *valuesBySpell;

@end

@implementation FSHShiamyEngine

- (BOOL)loadFromBundle:(NSBundle *)bundle error:(NSError **)error {
    NSString *cinPath = [self pathForResource:@"freeshiamy" type:@"cin" inBundle:bundle];
    NSString *spellPath = [self pathForResource:@"cht_spells" type:@"cin" inBundle:bundle];
    if (!cinPath || !spellPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"FSHShiamyEngine" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Missing cin resources"}];
        }
        self.ready = NO;
        return NO;
    }

    NSError *parseError = nil;
    NSArray<FSHCandidate *> *cinEntries = [FSHCinParser parseCinAtPath:cinPath error:&parseError];
    if (parseError && error) {
        *error = parseError;
    }

    NSArray<FSHCandidate *> *spellEntries = [FSHCinParser parseCinAtPath:spellPath error:nil];

    [self buildIndexesWithCinEntries:cinEntries spellEntries:spellEntries];
    self.ready = YES;
    return YES;
}

- (NSArray<FSHCandidate *> *)prefixCandidatesForCode:(NSString *)code exactCount:(NSUInteger *)exactCount {
    if (exactCount) {
        *exactCount = 0;
    }
    if (!self.ready) {
        return @[];
    }
    NSString *normalized = [self normalizedCode:code];
    if (normalized.length == 0) {
        return @[];
    }
    NSString *firstChar = [normalized substringToIndex:1];
    NSArray<FSHCandidate *> *bucket = self.firstCharIndex[firstChar];
    if (bucket.count == 0) {
        return @[];
    }

    NSArray<FSHCandidate *> *candidates = bucket;
    if (normalized.length > 1) {
        NSMutableArray<FSHCandidate *> *filtered = [NSMutableArray array];
        for (FSHCandidate *candidate in bucket) {
            if ([candidate.code hasPrefix:normalized]) {
                [filtered addObject:candidate];
            }
        }
        candidates = filtered;
    }

    if (exactCount) {
        NSUInteger count = 0;
        for (FSHCandidate *candidate in candidates) {
            if (candidate.code.length == normalized.length) {
                count += 1;
            } else {
                break;
            }
        }
        *exactCount = count;
    }

    return candidates;
}

- (NSArray<FSHCandidate *> *)reverseLookupCandidatesForBaseValue:(NSString *)baseValue {
    if (!self.ready || baseValue.length == 0) {
        return @[];
    }
    NSString *spell = self.spellByValue[baseValue];
    NSArray<NSString *> *values = spell ? self.valuesBySpell[spell] : nil;
    if (values.count == 0) {
        NSString *fallbackSpell = spell ?: @"";
        return @[[[FSHCandidate alloc] initWithCode:fallbackSpell value:baseValue]];
    }
    NSMutableArray<FSHCandidate *> *results = [NSMutableArray arrayWithCapacity:values.count];
    for (NSString *value in values) {
        [results addObject:[[FSHCandidate alloc] initWithCode:spell value:value]];
    }
    return results;
}

- (NSString *)shortestCodeForValue:(NSString *)value {
    return self.shortestCodeByValue[value];
}

- (NSString *)spellForValue:(NSString *)value {
    return self.spellByValue[value];
}

- (NSString *)normalizedCode:(NSString *)code {
    return [[code ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

- (NSString *)pathForResource:(NSString *)name type:(NSString *)type inBundle:(NSBundle *)bundle {
    NSString *path = [bundle pathForResource:name ofType:type];
    if (path) {
        return path;
    }
    return [bundle pathForResource:name ofType:type inDirectory:@"Resources"];
}

- (void)buildIndexesWithCinEntries:(NSArray<FSHCandidate *> *)cinEntries
                       spellEntries:(NSArray<FSHCandidate *> *)spellEntries {
    NSMutableDictionary<NSString *, NSMutableArray<FSHCandidate *> *> *firstCharIndex = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *shortestCodeByValue = [NSMutableDictionary dictionary];

    for (FSHCandidate *candidate in cinEntries) {
        NSString *normalizedCode = [self normalizedCode:candidate.code];
        if (normalizedCode.length == 0) {
            continue;
        }
        if (!shortestCodeByValue[candidate.value]) {
            shortestCodeByValue[candidate.value] = normalizedCode;
        }
        NSString *firstChar = [normalizedCode substringToIndex:1];
        NSMutableArray<FSHCandidate *> *bucket = firstCharIndex[firstChar];
        if (!bucket) {
            bucket = [NSMutableArray array];
            firstCharIndex[firstChar] = bucket;
        }
        [bucket addObject:[[FSHCandidate alloc] initWithCode:normalizedCode value:candidate.value]];
    }

    NSMutableDictionary<NSString *, NSString *> *spellByValue = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *valuesBySpell = [NSMutableDictionary dictionary];

    for (FSHCandidate *candidate in spellEntries) {
        NSString *spell = candidate.code;
        NSString *value = candidate.value;
        if (spell.length == 0 || value.length == 0) {
            continue;
        }
        if (!spellByValue[value]) {
            spellByValue[value] = spell;
        }
        NSMutableArray<NSString *> *values = valuesBySpell[spell];
        if (!values) {
            values = [NSMutableArray array];
            valuesBySpell[spell] = values;
        }
        [values addObject:value];
    }

    NSMutableDictionary<NSString *, NSArray<FSHCandidate *> *> *finalIndex = [NSMutableDictionary dictionaryWithCapacity:firstCharIndex.count];
    [firstCharIndex enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableArray<FSHCandidate *> * _Nonnull obj, BOOL * _Nonnull stop) {
        finalIndex[key] = [obj copy];
    }];

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *finalSpellIndex = [NSMutableDictionary dictionaryWithCapacity:valuesBySpell.count];
    [valuesBySpell enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableArray<NSString *> * _Nonnull obj, BOOL * _Nonnull stop) {
        finalSpellIndex[key] = [obj copy];
    }];

    self.firstCharIndex = finalIndex;
    self.shortestCodeByValue = [shortestCodeByValue copy];
    self.spellByValue = [spellByValue copy];
    self.valuesBySpell = finalSpellIndex;
}

@end
