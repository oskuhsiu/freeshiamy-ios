#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"
#import "FSHCandidate.h"

@interface FSHShiamyEngine ()

@property (nonatomic, assign, readwrite) BOOL ready;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<FSHCandidate *> *> *firstCharIndex;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *shortestCodeByValue;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *spellsByValue;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *valuesBySpell;

@end

@implementation FSHShiamyEngine

- (BOOL)loadFromBundle:(NSBundle *)bundle error:(NSError **)error {
    self.ready = NO;
    self.firstCharIndex = nil;
    self.shortestCodeByValue = nil;
    self.spellsByValue = nil;
    self.valuesBySpell = nil;

    NSString *cinPath = [self pathForResource:@"freeshiamy" type:@"cin" inBundle:bundle];
    NSString *spellPath = [self pathForResource:@"cht_spells" type:@"cin" inBundle:bundle];
    if (!cinPath || !spellPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"FSHShiamyEngine" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Missing cin resources"}];
        }
        return NO;
    }

    NSError *parseError = nil;
    NSArray<FSHCandidate *> *cinEntries = [FSHCinParser parseCinAtPath:cinPath error:&parseError];
    if (parseError || cinEntries.count == 0) {
        if (error) {
            *error = parseError ?: [NSError errorWithDomain:@"FSHShiamyEngine" code:3
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Main cin dictionary is empty"}];
        }
        return NO;
    }

    parseError = nil;
    NSArray<FSHCandidate *> *spellEntries = [FSHCinParser parseCinAtPath:spellPath error:&parseError];
    if (parseError || spellEntries.count == 0) {
        if (error) {
            *error = parseError ?: [NSError errorWithDomain:@"FSHShiamyEngine" code:4
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Spelling cin dictionary is empty"}];
        }
        return NO;
    }

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
    NSArray<NSString *> *spells = self.spellsByValue[baseValue];
    NSMutableArray<FSHCandidate *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seenValues = [NSMutableSet set];
    for (NSString *spell in spells) {
        for (NSString *value in self.valuesBySpell[spell]) {
            if (![seenValues containsObject:value]) {
                [seenValues addObject:value];
                [results addObject:[[FSHCandidate alloc] initWithCode:spell value:value]];
            }
        }
    }
    if (results.count == 0) {
        return @[[[FSHCandidate alloc] initWithCode:spells.firstObject ?: @"" value:baseValue]];
    }
    return results;
}

- (NSString *)shortestCodeForValue:(NSString *)value {
    return self.shortestCodeByValue[value];
}

- (NSString *)spellForValue:(NSString *)value {
    return self.spellsByValue[value].firstObject;
}

- (NSArray<NSString *> *)spellsForValue:(NSString *)value {
    return self.spellsByValue[value] ?: @[];
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

    NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *spellsByValue = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *valuesBySpell = [NSMutableDictionary dictionary];

    for (FSHCandidate *candidate in spellEntries) {
        NSString *spell = candidate.code;
        NSString *value = candidate.value;
        if (spell.length == 0 || value.length == 0) {
            continue;
        }
        NSMutableOrderedSet<NSString *> *spells = spellsByValue[value];
        if (!spells) {
            spells = [NSMutableOrderedSet orderedSet];
            spellsByValue[value] = spells;
        }
        [spells addObject:spell];
        NSMutableOrderedSet<NSString *> *values = valuesBySpell[spell];
        if (!values) {
            values = [NSMutableOrderedSet orderedSet];
            valuesBySpell[spell] = values;
        }
        [values addObject:value];
    }

    NSMutableDictionary<NSString *, NSArray<FSHCandidate *> *> *finalIndex = [NSMutableDictionary dictionaryWithCapacity:firstCharIndex.count];
    [firstCharIndex enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableArray<FSHCandidate *> * _Nonnull obj, BOOL * _Nonnull stop) {
        finalIndex[key] = [obj copy];
    }];

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *finalSpellsByValue = [NSMutableDictionary dictionaryWithCapacity:spellsByValue.count];
    [spellsByValue enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableOrderedSet<NSString *> * _Nonnull obj, BOOL * _Nonnull stop) {
        finalSpellsByValue[key] = obj.array;
    }];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *finalSpellIndex = [NSMutableDictionary dictionaryWithCapacity:valuesBySpell.count];
    [valuesBySpell enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSMutableOrderedSet<NSString *> * _Nonnull obj, BOOL * _Nonnull stop) {
        finalSpellIndex[key] = obj.array;
    }];

    self.firstCharIndex = finalIndex;
    self.shortestCodeByValue = [shortestCodeByValue copy];
    self.spellsByValue = [finalSpellsByValue copy];
    self.valuesBySpell = finalSpellIndex;
}

@end
