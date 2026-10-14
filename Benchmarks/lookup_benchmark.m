#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <sys/resource.h>
#import <time.h>
#import <stdio.h>
#import <stdint.h>
#import <string.h>
#import "FSHShiamyEngine.h"
#import "FSHCinParser.h"
#import "FSHCandidate.h"

static double nowMilliseconds(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1000000.0;
}

static uint64_t residentBytes(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                     (task_info_t)&info, &count);
    return result == KERN_SUCCESS ? (uint64_t)info.resident_size : 0;
}

static uint64_t peakResidentBytes(void) {
    struct rusage usage;
    return getrusage(RUSAGE_SELF, &usage) == 0 ? (uint64_t)usage.ru_maxrss : 0;
}

static void writeInteger(FILE *file, uint64_t value) {
    for (NSUInteger index = 0; index < 8; index++) {
        fputc((int)((value >> (index * 8)) & 0xff), file);
    }
}

static void writeString(FILE *file, NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    writeInteger(file, data.length);
    fwrite(data.bytes, 1, data.length, file);
}

static NSArray<NSString *> *queriesForEntries(NSArray<FSHCandidate *> *entries) {
    NSMutableOrderedSet<NSString *> *queries = [NSMutableOrderedSet orderedSet];
    [queries addObject:@""];
    [queries addObject:@"  "];
    [queries addObject:@"zzzzzz"];
    [queries addObject:@"a!"];
    [queries addObject:@"["];
    [queries addObject:@";"];
    for (FSHCandidate *candidate in entries) {
        NSString *code = candidate.code.lowercaseString;
        for (NSUInteger length = 1; length <= code.length; length++) {
            [queries addObject:[code substringToIndex:length]];
        }
    }
    // Exercise normalization without allowing spelling-data differences to
    // influence the prefix comparison.
    for (NSString *code in [queries.array copy]) {
        if (code.length > 0 && code.length <= 3) {
            [queries addObject:code.uppercaseString];
            [queries addObject:[NSString stringWithFormat:@" %@\n", code]];
        }
    }
    return queries.array;
}

static NSArray<NSString *> *repeatedBatch(NSArray<NSString *> *queries) {
    if (queries.count == 0) return queries;
    NSUInteger repetitions = MAX((NSUInteger)1, ((NSUInteger)4000 + queries.count - 1) / queries.count);
    NSMutableArray<NSString *> *batch = [NSMutableArray arrayWithCapacity:queries.count * repetitions];
    for (NSUInteger index = 0; index < repetitions; index++) {
        [batch addObjectsFromArray:queries];
    }
    return batch;
}

static uint64_t runQueries(FSHShiamyEngine *engine, NSArray<NSString *> *queries) {
    uint64_t checksum = 0;
    for (NSUInteger start = 0; start < queries.count; start += 128) {
        @autoreleasepool {
            NSUInteger end = MIN(start + 128, queries.count);
            for (NSUInteger index = start; index < end; index++) {
                NSString *query = queries[index];
                NSUInteger exactCount = 0;
                NSArray<FSHCandidate *> *results = [engine prefixCandidatesForCode:query exactCount:&exactCount];
                checksum += results.count * 17 + exactCount * 31;
                if (results.count) {
                    checksum += results.firstObject.code.length + results.lastObject.value.length;
                }
            }
        }
    }
    return checksum;
}

static void dumpOrderedResults(FSHShiamyEngine *engine, NSArray<NSString *> *queries, FILE *file) {
    writeInteger(file, queries.count);
    for (NSString *query in queries) {
        @autoreleasepool {
            NSUInteger exactCount = 0;
            NSArray<FSHCandidate *> *results = [engine prefixCandidatesForCode:query exactCount:&exactCount];
            writeString(file, query);
            writeInteger(file, exactCount);
            writeInteger(file, results.count);
            for (FSHCandidate *candidate in results) {
                writeString(file, candidate.code);
                writeString(file, candidate.value);
            }
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL verify = argc == 4 && strcmp(argv[2], "--verify") == 0;
        if (!((argc == 3 && strcmp(argv[2], "--measure") == 0) || verify)) {
            fprintf(stderr, "usage: lookup_benchmark RESOURCE.bundle --measure | --verify ordered-results.bin\n");
            return 2;
        }
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        if (!bundle) {
            fprintf(stderr, "cannot open resource bundle\n");
            return 2;
        }
        FSHShiamyEngine *engine = [[FSHShiamyEngine alloc] init];
        __block double loadMilliseconds = 0;
        @autoreleasepool {
            NSError *loadError = nil;
            double start = nowMilliseconds();
            BOOL loaded = [engine loadFromBundle:bundle error:&loadError];
            loadMilliseconds = nowMilliseconds() - start;
            if (!loaded) {
                fprintf(stderr, "engine load failed: %s\n", loadError.description.UTF8String);
                return 2;
            }
        }
        uint64_t residentAfterLoad = residentBytes();
        uint64_t peakAfterLoad = peakResidentBytes();
        NSString *cinPath = [bundle pathForResource:@"freeshiamy" ofType:@"cin"];
        if (!cinPath) cinPath = [bundle pathForResource:@"freeshiamy" ofType:@"cin" inDirectory:@"Resources"];
        __block NSArray<NSString *> *queries;
        __block NSUInteger entryCount = 0;
        @autoreleasepool {
            NSError *parseError = nil;
            NSArray<FSHCandidate *> *entries = [FSHCinParser parseCinAtPath:cinPath error:&parseError];
            if (!entries || parseError) {
                fprintf(stderr, "query corpus parse failed: %s\n", parseError.description.UTF8String);
                return 2;
            }
            entryCount = entries.count;
            queries = queriesForEntries(entries);
        }
        if (verify) {
            FILE *dump = fopen(argv[3], "wb");
            if (!dump) {
                perror("result dump");
                return 2;
            }
            dumpOrderedResults(engine, queries, dump);
            BOOL wroteEverything = ferror(dump) == 0;
            int closeResult = fclose(dump);
            if (!wroteEverything || closeResult != 0) {
                fprintf(stderr, "result dump write failed\n");
                return 2;
            }
            printf("verification_queries\t%llu\n", (unsigned long long)queries.count);
            return 0;
        }

        NSMutableArray<NSString *> *one = [NSMutableArray array];
        NSMutableArray<NSString *> *two = [NSMutableArray array];
        NSMutableArray<NSString *> *deep = [NSMutableArray array];
        for (NSString *query in queries) {
            NSUInteger normalizedLength = [[query stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString].length;
            if (normalizedLength == 1) [one addObject:query];
            else if (normalizedLength == 2) [two addObject:query];
            else if (normalizedLength > 2) [deep addObject:query];
        }
        // Time a deterministic, corpus-wide deep-prefix sample. Verification
        // still compares every real prefix and normalization probe exactly.
        NSMutableArray<NSString *> *deepSample = [NSMutableArray array];
        NSUInteger deepStride = MAX((NSUInteger)1, (deep.count + 4095) / 4096);
        for (NSUInteger index = 0; index < deep.count; index += deepStride) {
            [deepSample addObject:deep[index]];
        }
        NSDictionary<NSString *, NSArray<NSString *> *> *batches = @{
            @"one": repeatedBatch(one), @"two": repeatedBatch(two),
            @"deep": deepSample
        };
        printf("load_ms\t%.6f\n", loadMilliseconds);
        printf("resident_after_load_bytes\t%llu\n", (unsigned long long)residentAfterLoad);
        printf("peak_after_load_bytes\t%llu\n", (unsigned long long)peakAfterLoad);
        printf("query_count\t%llu\n", (unsigned long long)queries.count);
        printf("raw_entry_count\t%llu\n", (unsigned long long)entryCount);
        printf("deep_sample_stride\t%llu\n", (unsigned long long)deepStride);
        uint64_t checksum = 0;
        for (NSString *name in @[@"one", @"two", @"deep"]) {
            NSArray<NSString *> *batch = batches[name];
            checksum += runQueries(engine, batch); // untimed warmup
            printf("batch_count_%s\t%llu\n", name.UTF8String, (unsigned long long)batch.count);
            for (NSUInteger sample = 0; sample < 7; sample++) {
                @autoreleasepool {
                    double start = nowMilliseconds();
                    checksum += runQueries(engine, batch);
                    double elapsed = nowMilliseconds() - start;
                    printf("sample_ms_%s\t%.6f\n", name.UTF8String, elapsed);
                }
            }
        }
        printf("checksum\t%llu\n", (unsigned long long)checksum);
        printf("resident_final_bytes\t%llu\n", (unsigned long long)residentBytes());
        printf("peak_final_bytes\t%llu\n", (unsigned long long)peakResidentBytes());
        return 0;
    }
}
