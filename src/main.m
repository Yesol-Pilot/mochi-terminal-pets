#import <Cocoa/Cocoa.h>

static NSString *const CmuxPathPrefix = @"PATH=\"$HOME/bin:$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH\"; ";
static NSTimeInterval const EndedPetVisibleSeconds = 14.0;
static CGFloat const DefaultPetMinSize = 28.0;
static CGFloat const DefaultPetMaxSize = 36.0;
static CGFloat const DefaultOverlayBandHeight = 220.0;
static double const DefaultWorkingCpuThreshold = 1.0;
static double const DefaultWorkingCpuExitThreshold = 0.6;

static NSString *ProjectRootPath(void) {
    NSString *exe = NSProcessInfo.processInfo.arguments.firstObject ?: @"";
    if (![exe hasPrefix:@"/"]) {
        exe = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:exe];
    }
    exe = exe.stringByStandardizingPath;
    return [[exe stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
}

static NSString *LocalizedStr(NSString *key) {
    static BOOL isKorean = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *lang = [NSLocale preferredLanguages].firstObject;
        isKorean = [lang hasPrefix:@"ko"];
    });

    if (isKorean) {
        if ([key isEqualToString:@"prework"]) return @"시작전";
        if ([key isEqualToString:@"working"]) return @"작업중";
        if ([key isEqualToString:@"done"]) return @"완료(실패)";
        if ([key isEqualToString:@"expired"]) return @"실패 (만료)";
        if ([key isEqualToString:@"approval"]) return @"허가 대기";
        if ([key isEqualToString:@"input"]) return @"입력 대기";
        if ([key isEqualToString:@"ended"]) return @"종료";
        if ([key isEqualToString:@"completed"]) return @"완료";
    } else {
        if ([key isEqualToString:@"prework"]) return @"Ready";
        if ([key isEqualToString:@"working"]) return @"Working";
        if ([key isEqualToString:@"done"]) return @"Done";
        if ([key isEqualToString:@"expired"]) return @"Fainted (Expired)";
        if ([key isEqualToString:@"approval"]) return @"Approval Needed";
        if ([key isEqualToString:@"input"]) return @"Input Needed";
        if ([key isEqualToString:@"ended"]) return @"Ended";
        if ([key isEqualToString:@"completed"]) return @"Completed";
    }
    return key;
}

@interface OverlayConfig : NSObject
@property(nonatomic) double workingCpuThreshold;
@property(nonatomic) double workingCpuExitThreshold;
@property(nonatomic) CGFloat petMinSize;
@property(nonatomic) CGFloat petMaxSize;
@property(nonatomic) CGFloat overlayBandHeight;
@property(nonatomic) CGFloat fpsActive;
@property(nonatomic) CGFloat fpsIdle;
@property(nonatomic) CGFloat fpsQuiet;
@property(nonatomic) CGFloat pollIntervalSeconds;
@property(nonatomic) CGFloat preworkAreaRatio;
@property(nonatomic) CGFloat workingAreaRatio;
@property(nonatomic) BOOL clickNameplateOnly;
@property(nonatomic) BOOL showStateRail;
@property(nonatomic) BOOL showShellTabs;
@property(nonatomic) BOOL petDraggingEnabled;
@property(nonatomic) BOOL dragPetBodyEnabled;
@property(nonatomic) BOOL soundEffectsEnabled;
@property(nonatomic) CGFloat soundEffectsVolume;
@property(nonatomic) CGFloat soundEffectsCooldownSeconds;
@property(nonatomic, copy) NSString *dragStartSoundName;
@property(nonatomic, copy) NSString *dragDropSoundName;
@property(nonatomic, copy) NSString *focusSoundName;
@property(nonatomic, copy) NSString *completionSoundName;
@property(nonatomic) BOOL completionVoiceEnabled;
@property(nonatomic) CGFloat completionVoiceVolume;
@property(nonatomic) CGFloat completionVoiceCooldownSeconds;
@property(nonatomic, copy) NSString *completionVoicePath;
@property(nonatomic, copy) NSArray<NSString *> *excludedTitleContains;
@property(nonatomic, copy) NSString *monitorMode;
+ (instancetype)sharedConfig;
@end

@implementation OverlayConfig

+ (instancetype)sharedConfig {
    static OverlayConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[OverlayConfig alloc] init];
    });
    return config;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _workingCpuThreshold = DefaultWorkingCpuThreshold;
        _workingCpuExitThreshold = DefaultWorkingCpuExitThreshold;
        _petMinSize = DefaultPetMinSize;
        _petMaxSize = DefaultPetMaxSize;
        _overlayBandHeight = DefaultOverlayBandHeight;
        _fpsActive = 60.0;
        _fpsIdle = 60.0;
        _fpsQuiet = 12.0;
        _pollIntervalSeconds = 2.5;
        _preworkAreaRatio = 0.46;
        _workingAreaRatio = 0.46;
        _clickNameplateOnly = YES;
        _showStateRail = YES;
        _showShellTabs = NO;
        _petDraggingEnabled = YES;
        _dragPetBodyEnabled = YES;
        _soundEffectsEnabled = YES;
        _soundEffectsVolume = 0.34;
        _soundEffectsCooldownSeconds = 0.08;
        _dragStartSoundName = @"Pop";
        _dragDropSoundName = @"Tink";
        _focusSoundName = @"Glass";
        _completionSoundName = @"Hero";
        _completionVoiceEnabled = YES;
        _completionVoiceVolume = 0.58;
        _completionVoiceCooldownSeconds = 1.2;
        _completionVoicePath = @"";
        _excludedTitleContains = @[];
        _monitorMode = @"auto";
        [self loadFromDisk];
    }
    return self;
}

- (double)numberForKey:(NSString *)key
          inDictionary:(NSDictionary *)dictionary
          defaultValue:(double)defaultValue
                   min:(double)minValue
                   max:(double)maxValue {
    id value = dictionary[key];
    if (![value respondsToSelector:@selector(doubleValue)]) {
        return defaultValue;
    }
    double number = [value doubleValue];
    if (!isfinite(number)) {
        return defaultValue;
    }
    return MIN(MAX(number, minValue), maxValue);
}

- (BOOL)boolForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary defaultValue:(BOOL)defaultValue {
    id value = dictionary[key];
    if (![value respondsToSelector:@selector(boolValue)]) {
        return defaultValue;
    }
    return [value boolValue];
}

- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary {
    id value = dictionary[key];
    if (![value isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *trimmed = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            [strings addObject:trimmed.lowercaseString];
        }
    }
    return strings;
}

- (NSString *)stringForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary defaultValue:(NSString *)defaultValue {
    id value = dictionary[key];
    if (![value isKindOfClass:NSString.class]) {
        return defaultValue;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed : defaultValue;
}

- (void)loadFromDisk {
    NSString *path = [ProjectRootPath() stringByAppendingPathComponent:@"config.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return;
    }

    NSDictionary *dictionary = (NSDictionary *)json;
    self.workingCpuThreshold = [self numberForKey:@"workingCpuThreshold" inDictionary:dictionary defaultValue:self.workingCpuThreshold min:0.0 max:100.0];
    self.workingCpuExitThreshold = [self numberForKey:@"workingCpuExitThreshold"
                                         inDictionary:dictionary
                                         defaultValue:self.workingCpuExitThreshold
                                                  min:0.0
                                                  max:self.workingCpuThreshold];
    self.petMinSize = [self numberForKey:@"petMinSize" inDictionary:dictionary defaultValue:self.petMinSize min:5.0 max:80.0];
    self.petMaxSize = [self numberForKey:@"petMaxSize" inDictionary:dictionary defaultValue:self.petMaxSize min:self.petMinSize max:96.0];
    self.overlayBandHeight = [self numberForKey:@"overlayBandHeight" inDictionary:dictionary defaultValue:self.overlayBandHeight min:96.0 max:800.0];
    self.fpsActive = [self numberForKey:@"fpsActive" inDictionary:dictionary defaultValue:self.fpsActive min:12.0 max:90.0];
    self.fpsIdle = [self numberForKey:@"fpsIdle" inDictionary:dictionary defaultValue:self.fpsIdle min:8.0 max:self.fpsActive];
    self.fpsQuiet = [self numberForKey:@"fpsQuiet" inDictionary:dictionary defaultValue:self.fpsQuiet min:4.0 max:self.fpsIdle];
    self.pollIntervalSeconds = [self numberForKey:@"pollIntervalSeconds" inDictionary:dictionary defaultValue:self.pollIntervalSeconds min:1.0 max:15.0];
    self.preworkAreaRatio = [self numberForKey:@"preworkAreaRatio" inDictionary:dictionary defaultValue:self.preworkAreaRatio min:0.20 max:0.70];
    self.workingAreaRatio = [self numberForKey:@"workingAreaRatio" inDictionary:dictionary defaultValue:self.workingAreaRatio min:0.20 max:0.70];
    self.clickNameplateOnly = [self boolForKey:@"clickNameplateOnly" inDictionary:dictionary defaultValue:self.clickNameplateOnly];
    self.showStateRail = [self boolForKey:@"showStateRail" inDictionary:dictionary defaultValue:self.showStateRail];
    self.showShellTabs = [self boolForKey:@"showShellTabs" inDictionary:dictionary defaultValue:self.showShellTabs];
    self.petDraggingEnabled = [self boolForKey:@"petDraggingEnabled" inDictionary:dictionary defaultValue:self.petDraggingEnabled];
    self.dragPetBodyEnabled = [self boolForKey:@"dragPetBodyEnabled" inDictionary:dictionary defaultValue:self.dragPetBodyEnabled];
    self.soundEffectsEnabled = [self boolForKey:@"soundEffectsEnabled" inDictionary:dictionary defaultValue:self.soundEffectsEnabled];
    self.soundEffectsVolume = [self numberForKey:@"soundEffectsVolume" inDictionary:dictionary defaultValue:self.soundEffectsVolume min:0.0 max:1.0];
    self.soundEffectsCooldownSeconds = [self numberForKey:@"soundEffectsCooldownSeconds"
                                              inDictionary:dictionary
                                              defaultValue:self.soundEffectsCooldownSeconds
                                                       min:0.0
                                                       max:1.0];
    self.dragStartSoundName = [self stringForKey:@"dragStartSoundName" inDictionary:dictionary defaultValue:self.dragStartSoundName];
    self.dragDropSoundName = [self stringForKey:@"dragDropSoundName" inDictionary:dictionary defaultValue:self.dragDropSoundName];
    self.focusSoundName = [self stringForKey:@"focusSoundName" inDictionary:dictionary defaultValue:self.focusSoundName];
    self.completionSoundName = [self stringForKey:@"completionSoundName" inDictionary:dictionary defaultValue:self.completionSoundName];
    self.completionVoiceEnabled = [self boolForKey:@"completionVoiceEnabled" inDictionary:dictionary defaultValue:self.completionVoiceEnabled];
    self.completionVoiceVolume = [self numberForKey:@"completionVoiceVolume" inDictionary:dictionary defaultValue:self.completionVoiceVolume min:0.0 max:1.0];
    self.completionVoiceCooldownSeconds = [self numberForKey:@"completionVoiceCooldownSeconds"
                                                 inDictionary:dictionary
                                                 defaultValue:self.completionVoiceCooldownSeconds
                                                          min:0.0
                                                          max:10.0];
    self.completionVoicePath = [self stringForKey:@"completionVoicePath" inDictionary:dictionary defaultValue:self.completionVoicePath];
    self.excludedTitleContains = [self stringArrayForKey:@"excludedTitleContains" inDictionary:dictionary];
    self.monitorMode = [self stringForKey:@"monitorMode" inDictionary:dictionary defaultValue:self.monitorMode];
}

@end

static OverlayConfig *SharedConfig(void) {
    return [OverlayConfig sharedConfig];
}

static NSString *ProjectResolvedPath(NSString *path) {
    NSString *value = path.length > 0 ? path : @"";
    if ([value hasPrefix:@"/"]) {
        return value.stringByStandardizingPath;
    }
    return [[ProjectRootPath() stringByAppendingPathComponent:value] stringByStandardizingPath];
}

static NSSound *SoundFromNameOrPath(NSString *nameOrPath) {
    NSString *trimmed = [nameOrPath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    NSSound *namedSound = [NSSound soundNamed:trimmed];
    if (namedSound) {
        return namedSound;
    }

    NSString *resolvedPath = ProjectResolvedPath(trimmed);
    if (![NSFileManager.defaultManager fileExistsAtPath:resolvedPath]) {
        return nil;
    }
    return [[NSSound alloc] initWithContentsOfFile:resolvedPath byReference:YES];
}

static BOOL PlayNamedSystemSound(NSString *name, CGFloat volume, NSTimeInterval waitSeconds) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return NO;
    }

    NSSound *sound = SoundFromNameOrPath(trimmed);
    if (!sound) {
        return NO;
    }

    sound.volume = MIN(MAX(volume, 0.0), 1.0);
    if (sound.isPlaying) {
        [sound stop];
    }
    BOOL played = [sound play];
    if (played && waitSeconds > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:waitSeconds]];
    }
    return played;
}

static BOOL TextContainsConfiguredExclusion(NSString *text) {
    NSString *lower = (text ?: @"").lowercaseString;
    if (lower.length == 0) {
        return NO;
    }
    for (NSString *needle in SharedConfig().excludedTitleContains) {
        if (needle.length > 0 && [lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static NSString *ManualPetPositionsPath(void) {
    return [ProjectRootPath() stringByAppendingPathComponent:@".build/pet-positions.json"];
}

@interface SessionInfo : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *provider;
@property(nonatomic, copy) NSString *surfaceRef;
@property(nonatomic, copy) NSString *paneRef;
@property(nonatomic, copy) NSString *workspaceRef;
@property(nonatomic, copy) NSString *windowRef;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) double cpu;
@property(nonatomic) double memoryBytes;
@property(nonatomic) BOOL tokenExpired;
@property(nonatomic) NSInteger processCount;
@property(nonatomic) NSTimeInterval seenAt;
@property(nonatomic) BOOL focused;
@property(nonatomic, copy) NSArray<NSString *> *processNames;
@property(nonatomic, copy) NSString *lastNotification;
@property(nonatomic) BOOL lastNotificationIsUnread;
@property(nonatomic) NSInteger contextPercentage;
@property(nonatomic, copy) NSString *contextText;
@end

@implementation SessionInfo
@end

@interface AlertInfo : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *body;
@property(nonatomic, copy) NSString *provider;
@property(nonatomic, copy) NSString *kind;
@property(nonatomic, copy) NSString *surfaceKey;
@property(nonatomic, copy) NSString *paneRef;
@property(nonatomic, copy) NSString *workspaceRef;
@property(nonatomic, copy) NSString *windowRef;
@property(nonatomic) NSTimeInterval createdAt;
@end

@implementation AlertInfo
@end

@interface PetInfo : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *provider;
@property(nonatomic, copy) NSString *paneRef;
@property(nonatomic, copy) NSString *workspaceRef;
@property(nonatomic, copy) NSString *windowRef;
@property(nonatomic) NSPoint position;
@property(nonatomic) NSPoint velocity;
@property(nonatomic) CGFloat size;
@property(nonatomic) CGFloat facing;
@property(nonatomic) CGFloat bobPhase;
@property(nonatomic) double cpu;
@property(nonatomic) CGFloat homeX;
@property(nonatomic) CGFloat homeY;
@property(nonatomic) CGFloat laneWidth;
@property(nonatomic) NSUInteger slotIndex;
@property(nonatomic) NSTimeInterval nextTurnAt;
@property(nonatomic) BOOL alerting;
@property(nonatomic) BOOL focused;
@property(nonatomic) BOOL manuallyPlaced;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSString *state;
@property(nonatomic) NSTimeInterval endedAt;
@property(nonatomic) NSTimeInterval alertUntil;
@property(nonatomic, strong) NSImage *nameplateImage;
@property(nonatomic, copy) NSString *nameplateSignature;
@property(nonatomic) NSSize nameplateSize;
@property(nonatomic) NSTimeInterval lastActiveAt;
@property(nonatomic) double memoryBytes;
@property(nonatomic) BOOL tokenExpired;
@property(nonatomic, copy) NSArray<NSString *> *processNames;
@property(nonatomic, copy) NSString *lastNotification;
@property(nonatomic) BOOL lastNotificationIsUnread;
@property(nonatomic) NSInteger contextPercentage;
@property(nonatomic, copy) NSString *contextText;
@end

@implementation PetInfo
@end

@interface PSProcess : NSObject
@property(nonatomic) NSInteger pid;
@property(nonatomic) NSInteger ppid;
@property(nonatomic) double cpu;
@property(nonatomic) double rss;
@property(nonatomic, strong) NSString *comm;
@end

@implementation PSProcess
@end

@interface CmuxStateReader : NSObject
@property(nonatomic) BOOL notificationBaselineReady;
@property(nonatomic) BOOL sessionBaselineReady;
@property(nonatomic, strong) NSMutableSet<NSString *> *knownNotifications;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SessionInfo *> *lastSessionsByKey;
- (NSArray<SessionInfo *> *)readSessions;
- (NSDictionary<NSString *, NSString *> *)readFocusedRefs;
- (NSArray<AlertInfo *> *)readNewAlerts;
- (NSArray<AlertInfo *> *)trackEndedSessionsFromActiveSessions:(NSArray<SessionInfo *> *)sessions;
- (NSArray<SessionInfo *> *)readLocalSystemSessions;
- (void)collectDescendantsOfPid:(NSInteger)parentPid fromMap:(NSDictionary<NSNumber *, PSProcess *> *)processes intoArray:(NSMutableArray<PSProcess *> *)array;
- (NSInteger)parsePercentageFromString:(NSString *)str;
- (void)extractContextInfoForSession:(SessionInfo *)info workspaceContexts:(NSDictionary *)workspaceContexts workspaceNames:(NSDictionary *)workspaceNames;
@end

@implementation CmuxStateReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _knownNotifications = [NSMutableSet set];
        _lastSessionsByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSInteger)parsePercentageFromString:(NSString *)str {
    if (str.length == 0) return -1;
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s*%" options:0 error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
    if (match && match.numberOfRanges > 1) {
        NSString *pctStr = [str substringWithRange:[match rangeAtIndex:1]];
        return pctStr.integerValue;
    }
    
    NSRegularExpression *decRegex = [NSRegularExpression regularExpressionWithPattern:@"\\b(0\\.\\d+)\\b" options:0 error:&error];
    NSTextCheckingResult *decMatch = [decRegex firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
    if (decMatch && decMatch.numberOfRanges > 1) {
        NSString *decStr = [str substringWithRange:[decMatch rangeAtIndex:1]];
        double val = decStr.doubleValue;
        return (NSInteger)(val * 100.0);
    }
    
    NSString *trimmed = [str stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger intVal = 0;
    if ([scanner scanInteger:&intVal] && [scanner isAtEnd]) {
        if (intVal >= 0 && intVal <= 100) {
            return intVal;
        }
    }
    
    return -1;
}

- (void)extractContextInfoForSession:(SessionInfo *)info workspaceContexts:(NSDictionary *)workspaceContexts workspaceNames:(NSDictionary *)workspaceNames {
    NSInteger pct = -1;
    NSString *text = nil;
    
    // 1. Try workspace tag first
    NSString *wsRef = info.workspaceRef;
    NSString *tagVal = workspaceContexts[wsRef];
    if (tagVal.length > 0) {
        pct = [self parsePercentageFromString:tagVal];
        text = tagVal;
    }
    
    // 2. Try workspace title
    NSString *wsName = workspaceNames[wsRef] ?: @"";
    if (pct == -1 && wsName.length > 0) {
        pct = [self parsePercentageFromString:wsName];
        if (pct >= 0) {
            text = [NSString stringWithFormat:@"%ld%%", (long)pct];
        }
    }
    
    // 3. Try surface title
    if (pct == -1 && info.title.length > 0) {
        pct = [self parsePercentageFromString:info.title];
        if (pct >= 0) {
            text = [NSString stringWithFormat:@"%ld%%", (long)pct];
        }
    }
    
    // 4. If Codex, read latest rollout log file to get actual tokens and window size!
    if (pct == -1 && [info.provider isEqualToString:@"codex"]) {
        NSString *profileDir = nil;
        if ([info.key.lowercaseString containsString:@"sol"]) {
            profileDir = [NSHomeDirectory() stringByAppendingPathComponent:@".codex-sol"];
        } else if ([info.key.lowercaseString containsString:@"et"]) {
            profileDir = [NSHomeDirectory() stringByAppendingPathComponent:@".codex-et"];
        } else {
            profileDir = [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
        }
        
        NSString *sessionsDir = [profileDir stringByAppendingPathComponent:@"sessions"];
        // Find latest jsonl
        NSString *findCmd = [NSString stringWithFormat:@"find \"%@\" -name \"rollout-*.jsonl\" -type f -print0 2>/dev/null | xargs -0 stat -f '%%m %%N' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-", sessionsDir];
        NSString *latestLog = [self runShell:findCmd];
        latestLog = [latestLog stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        
        if (latestLog.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:latestLog]) {
            NSString *tailCmd = [NSString stringWithFormat:@"tail -n 35 \"%@\"", latestLog];
            NSString *tailContent = [self runShell:tailCmd];
            
            NSError *error = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"total_tokens\":\\s*(\\d+)[^}]*\"model_context_window\":\\s*(\\d+)" options:0 error:&error];
            NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:tailContent options:0 range:NSMakeRange(0, tailContent.length)];
            if (matches.count > 0) {
                NSTextCheckingResult *lastMatch = matches.lastObject;
                NSString *tokensStr = [tailContent substringWithRange:[lastMatch rangeAtIndex:1]];
                NSString *windowStr = [tailContent substringWithRange:[lastMatch rangeAtIndex:2]];
                long long totalTokens = tokensStr.longLongValue;
                long long window = windowStr.longLongValue;
                if (window > 0) {
                    pct = (NSInteger)((totalTokens * 100) / window);
                    NSString *tokensK = [NSString stringWithFormat:@"%.0fk", (double)totalTokens / 1000.0];
                    NSString *windowK = [NSString stringWithFormat:@"%.0fk", (double)window / 1000.0];
                    text = [NSString stringWithFormat:@"%ld%% (%@/%@)", (long)pct, tokensK, windowK];
                }
            }
        }
    }
    
    // 5. Try cmux read-screen as fallback or primary for non-codex agents to get actual tokens!
    if (text == nil && info.key.length > 0 && ![info.provider isEqualToString:@"shell"]) {
        NSString *screenCmd = [NSString stringWithFormat:@"cmux read-screen --surface %@ --lines 40 2>/dev/null", info.key];
        NSString *screenContent = [self runShell:screenCmd];
        if (screenContent.length > 0) {
            NSError *error = nil;
            // Search for token counts: e.g. "367.3k tokens"
            NSRegularExpression *tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"([\\d,]+(?:\\.\\d+)?[kM]?)\\s*(?:tokens|t\\b)" options:NSRegularExpressionCaseInsensitive error:&error];
            NSArray<NSTextCheckingResult *> *matches = [tokenRegex matchesInString:screenContent options:0 range:NSMakeRange(0, screenContent.length)];
            if (matches.count > 0) {
                NSTextCheckingResult *lastMatch = matches.lastObject;
                NSString *tokensFound = [screenContent substringWithRange:[lastMatch rangeAtIndex:1]];
                text = [NSString stringWithFormat:@"%@ t", tokensFound];
            }
            
            // Check for explicit "X / Y" or "X of Y"
            NSRegularExpression *fractionRegex = [NSRegularExpression regularExpressionWithPattern:@"([\\d,]+(?:\\.\\d+)?[kM]?)\\s*(?:/|of)\\s*([\\d,]+(?:\\.\\d+)?[kM]?)" options:NSRegularExpressionCaseInsensitive error:&error];
            NSArray<NSTextCheckingResult *> *fractionMatches = [fractionRegex matchesInString:screenContent options:0 range:NSMakeRange(0, screenContent.length)];
            if (fractionMatches.count > 0) {
                NSTextCheckingResult *lastMatch = fractionMatches.lastObject;
                NSString *usedStr = [screenContent substringWithRange:[lastMatch rangeAtIndex:1]];
                NSString *limitStr = [screenContent substringWithRange:[lastMatch rangeAtIndex:2]];
                text = [NSString stringWithFormat:@"%@/%@ t", usedStr, limitStr];
                
                // Try to parse values to calculate percentage
                double used = 0;
                double limit = 0;
                // parse used
                NSString *usedLower = usedStr.lowercaseString;
                if ([usedLower hasSuffix:@"k"]) {
                    used = usedLower.doubleValue * 1000.0;
                } else if ([usedLower hasSuffix:@"m"]) {
                    used = usedLower.doubleValue * 1000000.0;
                } else {
                    used = [usedLower stringByReplacingOccurrencesOfString:@"," withString:@""].doubleValue;
                }
                // parse limit
                NSString *limitLower = limitStr.lowercaseString;
                if ([limitLower hasSuffix:@"k"]) {
                    limit = limitLower.doubleValue * 1000.0;
                } else if ([limitLower hasSuffix:@"m"]) {
                    limit = limitLower.doubleValue * 1000000.0;
                } else {
                    limit = [limitLower stringByReplacingOccurrencesOfString:@"," withString:@""].doubleValue;
                }
                
                if (limit > 0) {
                    pct = (NSInteger)((used * 100) / limit);
                    text = [NSString stringWithFormat:@"%ld%% (%@/%@)", (long)pct, usedStr, limitStr];
                }
            }
            
            // Fallback to screen percentage
            if (pct == -1) {
                NSRegularExpression *pctRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s*%" options:0 error:&error];
                NSArray<NSTextCheckingResult *> *pctMatches = [pctRegex matchesInString:screenContent options:0 range:NSMakeRange(0, screenContent.length)];
                if (pctMatches.count > 0) {
                    NSTextCheckingResult *lastMatch = pctMatches.lastObject;
                    NSString *pctFound = [screenContent substringWithRange:[lastMatch rangeAtIndex:1]];
                    pct = pctFound.integerValue;
                    text = [NSString stringWithFormat:@"%@%%", pctFound];
                }
            }
        }
    }
    
    info.contextPercentage = pct;
    info.contextText = text;
}

- (NSString *)runShell:(NSString *)command {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[@"-lc", [CmuxPathPrefix stringByAppendingString:command]];

    NSPipe *pipe = [NSPipe pipe];
    NSPipe *err = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = err;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return @"";
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (data.length == 0) {
        data = [[err fileHandleForReading] readDataToEndOfFile];
    }
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output ?: @"";
}

- (NSString *)providerFromName:(NSString *)name title:(NSString *)title {
    NSString *lowerName = name.lowercaseString ?: @"";
    NSString *lowerTitle = title.lowercaseString ?: @"";
    if ([lowerName containsString:@"codex"] || [lowerTitle containsString:@"codex"]) {
        return @"codex";
    }
    if ([lowerName containsString:@"claude"] ||
        [lowerTitle containsString:@"claude"] ||
        [lowerTitle containsString:@"클로드"] ||
        [lowerName hasPrefix:@"2."]) {
        return @"claude";
    }
    if ([lowerName containsString:@"agy"] ||
        [lowerName containsString:@"gemini"] ||
        [lowerTitle containsString:@"agy"] ||
        [lowerTitle containsString:@"gemini"]) {
        return @"agy";
    }
    return @"shell";
}

- (NSString *)tabNameFromSurfaceTitle:(NSString *)title fallback:(NSString *)fallback {
    NSString *name = title.length > 0 ? title : fallback;
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSCharacterSet *prefixSet = [NSCharacterSet characterSetWithCharactersInString:@"⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏✳✱*·• "];
    while (name.length > 0) {
        unichar first = [name characterAtIndex:0];
        BOOL isBrailleSpinner = first >= 0x2800 && first <= 0x28FF;
        if (![prefixSet characterIsMember:first] && !isBrailleSpinner) {
            break;
        }
        name = [[name substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    if ([name containsString:@"/"]) {
        NSString *trimmed = [name stringByReplacingOccurrencesOfString:@"…" withString:@""];
        NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"/"];
        NSString *last = parts.lastObject;
        if (last.length > 0) {
            name = last;
        }
    }

    if (name.length == 0) {
        return fallback.length > 0 ? fallback : @"cmux";
    }
    return name;
}

- (NSDictionary<NSString *, NSString *> *)readFocusedRefs {
    NSString *output = [self runShell:@"CMUX_QUIET=1 cmux identify --no-caller 2>/dev/null"];
    NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @{};
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return @{};
    }

    id focused = ((NSDictionary *)json)[@"focused"];
    if (![focused isKindOfClass:NSDictionary.class]) {
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *refs = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"surface_ref", @"pane_ref", @"workspace_ref", @"window_ref"]) {
        id value = ((NSDictionary *)focused)[key];
        if ([value isKindOfClass:NSString.class] && [value length] > 0) {
            refs[key] = value;
        }
    }
    return refs;
}

- (void)collectDescendantsOfPid:(NSInteger)parentPid fromMap:(NSDictionary<NSNumber *, PSProcess *> *)processes intoArray:(NSMutableArray<PSProcess *> *)array {
    for (PSProcess *p in processes.allValues) {
        if (p.ppid == parentPid) {
            [array addObject:p];
            [self collectDescendantsOfPid:p.pid fromMap:processes intoArray:array];
        }
    }
}

- (NSArray<SessionInfo *> *)readLocalSystemSessions {
    NSString *output = [self runShell:@"ps -cx -u $(id -u) -o pid,ppid,%cpu,rss,comm 2>/dev/null"];
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    
    NSMutableDictionary<NSNumber *, PSProcess *> *processes = [NSMutableDictionary dictionary];
    NSMutableArray<PSProcess *> *shells = [NSMutableArray array];
    
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"PID"]) {
            continue;
        }
        
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger pid = 0;
        NSInteger ppid = 0;
        double cpu = 0.0;
        double rss = 0.0;
        
        if ([scanner scanInteger:&pid] &&
            [scanner scanInteger:&ppid] &&
            [scanner scanDouble:&cpu] &&
            [scanner scanDouble:&rss]) {
            NSString *comm = [trimmed substringFromIndex:scanner.scanLocation];
            comm = [comm stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            
            if (comm.length > 0) {
                PSProcess *proc = [[PSProcess alloc] init];
                proc.pid = pid;
                proc.ppid = ppid;
                proc.cpu = cpu;
                proc.rss = rss * 1024.0; // RSS in ps is in KB, convert to bytes
                proc.comm = comm;
                processes[@(pid)] = proc;
                
                if ([comm isEqualToString:@"zsh"] ||
                    [comm isEqualToString:@"bash"] ||
                    [comm isEqualToString:@"sh"] ||
                    [comm isEqualToString:@"fish"] ||
                    [comm isEqualToString:@"cmd.exe"] ||
                    [comm isEqualToString:@"powershell.exe"]) {
                    [shells addObject:proc];
                }
            }
        }
    }
    
    NSMutableArray<SessionInfo *> *sessions = [NSMutableArray array];
    for (PSProcess *shell in shells) {
        NSMutableArray<PSProcess *> *descendants = [NSMutableArray array];
        [self collectDescendantsOfPid:shell.pid fromMap:processes intoArray:descendants];
        
        double totalCpu = shell.cpu;
        double totalRss = shell.rss;
        NSString *activeComm = shell.comm;
        double maxChildCpu = -1.0;
        
        for (PSProcess *child in descendants) {
            totalCpu += child.cpu;
            totalRss += child.rss;
            if (child.cpu > maxChildCpu) {
                maxChildCpu = child.cpu;
                activeComm = child.comm;
            } else if (maxChildCpu <= 0.0 && [activeComm isEqualToString:shell.comm]) {
                activeComm = child.comm;
            }
        }
        
        SessionInfo *info = [[SessionInfo alloc] init];
        info.key = [NSString stringWithFormat:@"shell:%ld", (long)shell.pid];
        info.surfaceRef = info.key;
        info.paneRef = info.key;
        info.workspaceRef = info.key;
        info.windowRef = info.key;
        info.title = activeComm;
        info.provider = @"shell";
        info.status = @"active";
        info.cpu = totalCpu;
        info.memoryBytes = totalRss;
        info.processCount = descendants.count;
        info.seenAt = NSDate.date.timeIntervalSince1970;
        info.focused = NO;
        
        [sessions addObject:info];
    }
    
    return sessions;
}

- (NSArray<SessionInfo *> *)readSessions {
    NSString *mode = SharedConfig().monitorMode;
    BOOL useCmux = [mode isEqualToString:@"cmux"];
    if ([mode isEqualToString:@"auto"] || !mode) {
        NSString *test = [self runShell:@"which cmux 2>/dev/null"];
        useCmux = (test.length > 0);
    }
    
    if (!useCmux) {
        return [self readLocalSystemSessions];
    }

    NSString *output = [self runShell:@"cmux top --all --processes --format tsv 2>/dev/null"];
    NSDictionary<NSString *, NSString *> *focusedRefs = [self readFocusedRefs];
    NSString *focusedSurfaceRef = focusedRefs[@"surface_ref"];
    NSString *focusedPaneRef = focusedRefs[@"pane_ref"];
    NSMutableDictionary<NSString *, SessionInfo *> *surfaces = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *processes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *paneToWorkspace = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *workspaceToWindow = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *workspaceNames = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *workspaceContexts = [NSMutableDictionary dictionary];

    // Parse latest notifications by workspace
    NSString *notifOutput = [self runShell:@"cmux list-notifications 2>/dev/null"];
    NSMutableDictionary<NSString *, NSString *> *latestNotifByWorkspace = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *latestNotifIsUnreadByWorkspace = [NSMutableDictionary dictionary];
    for (NSString *line in [notifOutput componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length == 0 || [line hasPrefix:@"Error:"]) {
            continue;
        }
        NSArray<NSString *> *firstSplit = [line componentsSeparatedByString:@"|"];
        if (firstSplit.count < 7) {
            continue;
        }
        NSString *workspaceName = nil;
        for (NSString *col in firstSplit) {
            if ([col hasPrefix:@"pct:"]) {
                workspaceName = [col substringFromIndex:4];
                break;
            }
        }
        if (!workspaceName || workspaceName.length == 0) {
            workspaceName = firstSplit[4];
        }
        NSString *status = firstSplit[3];
        BOOL isUnread = ![status isEqualToString:@"read"];
        NSString *body = firstSplit[6];
        if (workspaceName.length > 0 && body.length > 0) {
            if (!latestNotifByWorkspace[workspaceName]) {
                latestNotifByWorkspace[workspaceName] = body;
                latestNotifIsUnreadByWorkspace[workspaceName] = @(isUnread);
            }
        }
    }

    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length == 0) {
            continue;
        }
        NSArray<NSString *> *cols = [line componentsSeparatedByString:@"\t"];
        if (cols.count < 7) {
            continue;
        }
        NSString *type = cols[3];
        NSString *identifier = cols[4];
        NSString *parent = cols[5];
        NSString *title = cols[6];
        if ([type isEqualToString:@"workspace"] && [identifier hasPrefix:@"workspace:"]) {
            workspaceToWindow[identifier] = parent ?: @"";
            workspaceNames[identifier] = title ?: @"";
        } else if ([type isEqualToString:@"pane"] && [identifier hasPrefix:@"pane:"]) {
            paneToWorkspace[identifier] = parent ?: @"";
        } else if ([type isEqualToString:@"tag"]) {
            if ([identifier containsString:@":tag:context"] || 
                [identifier containsString:@":tag:progress"] || 
                [identifier containsString:@":tag:token"]) {
                if (parent.length > 0 && title.length > 0) {
                    workspaceContexts[parent] = title;
                }
            }
        } else if ([type isEqualToString:@"surface"] && [identifier hasPrefix:@"surface:"]) {
            SessionInfo *info = [[SessionInfo alloc] init];
            info.key = identifier;
            info.surfaceRef = identifier;
            info.paneRef = parent ?: @"";
            info.workspaceRef = paneToWorkspace[info.paneRef] ?: @"";
            info.windowRef = workspaceToWindow[info.workspaceRef] ?: @"";
            info.title = [self tabNameFromSurfaceTitle:title fallback:identifier];
            info.provider = [self providerFromName:@"" title:info.title];
            info.status = @"active";
            info.cpu = cols[0].doubleValue;
            info.memoryBytes = cols[1].doubleValue;
            info.processCount = 0;
            info.seenAt = NSDate.date.timeIntervalSince1970;
            info.focused = (focusedSurfaceRef.length > 0 && [info.surfaceRef isEqualToString:focusedSurfaceRef]) ||
                           (focusedPaneRef.length > 0 && [info.paneRef isEqualToString:focusedPaneRef]);
            surfaces[identifier] = info;
        } else if ([type isEqualToString:@"process"] && [parent hasPrefix:@"surface:"]) {
            NSMutableArray<NSString *> *items = processes[parent];
            if (!items) {
                items = [NSMutableArray array];
                processes[parent] = items;
            }
            [items addObject:title ?: @""];
        }
    }

    NSMutableArray<SessionInfo *> *sessions = [NSMutableArray array];
    for (NSString *key in surfaces) {
        SessionInfo *info = surfaces[key];
        NSArray<NSString *> *names = processes[key] ?: @[];
        info.processCount = names.count;
        info.processNames = names;

        NSString *wsName = workspaceNames[info.workspaceRef] ?: @"";
        info.lastNotification = latestNotifByWorkspace[wsName] ?: @"";
        info.lastNotificationIsUnread = [latestNotifIsUnreadByWorkspace[wsName] boolValue];
        
        [self extractContextInfoForSession:info workspaceContexts:workspaceContexts workspaceNames:workspaceNames];
        
        BOOL expired = NO;
        if (info.lastNotification.length > 0 && info.lastNotificationIsUnread) {
            NSString *lower = info.lastNotification.lowercaseString;
            if ([lower containsString:@"token"] || 
                [lower containsString:@"limit"] || 
                [lower containsString:@"exceeded"] ||
                [lower containsString:@"만료"] ||
                [lower containsString:@"제한"] ||
                [lower containsString:@"초과"]) {
                expired = YES;
            }
        }
        info.tokenExpired = expired;

        for (NSString *name in names) {
            NSString *provider = [self providerFromName:name title:info.title];
            if (![provider isEqualToString:@"shell"]) {
                info.provider = provider;
                break;
            }
        }
        BOOL shouldShow = SharedConfig().showShellTabs || ![info.provider isEqualToString:@"shell"];
        if (shouldShow && !TextContainsConfiguredExclusion(info.title)) {
            [sessions addObject:info];
        }
    }

    [sessions sortUsingComparator:^NSComparisonResult(SessionInfo *a, SessionInfo *b) {
        if (a.cpu > b.cpu) return NSOrderedAscending;
        if (a.cpu < b.cpu) return NSOrderedDescending;
        return [a.title compare:b.title];
    }];

    return sessions;
}

- (NSArray<AlertInfo *> *)readNewAlerts {
    NSString *output = [self runShell:@"cmux list-notifications 2>/dev/null"];
    NSMutableArray<AlertInfo *> *alerts = [NSMutableArray array];
    NSMutableSet<NSString *> *seenThisPoll = [NSMutableSet set];

    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length == 0 || [line hasPrefix:@"Error:"]) {
            continue;
        }
        NSArray<NSString *> *firstSplit = [line componentsSeparatedByString:@"|"];
        if (firstSplit.count < 8) {
            continue;
        }
        NSString *indexAndId = firstSplit[0];
        NSRange colon = [indexAndId rangeOfString:@":"];
        NSString *key = colon.location == NSNotFound ? indexAndId : [indexAndId substringFromIndex:colon.location + 1];
        if (key.length == 0) {
            continue;
        }
        [seenThisPoll addObject:key];
        if (!self.notificationBaselineReady) {
            [self.knownNotifications addObject:key];
            continue;
        }
        if ([self.knownNotifications containsObject:key]) {
            continue;
        }

        AlertInfo *alert = [[AlertInfo alloc] init];
        alert.key = key;
        alert.title = firstSplit.count > 4 && [firstSplit[4] length] > 0 ? firstSplit[4] : @"cmux";
        alert.body = firstSplit.count > 6 ? firstSplit[6] : @"작업 알림이 도착했습니다.";
        alert.provider = [self providerFromName:@"" title:[NSString stringWithFormat:@"%@ %@", alert.title, alert.body]];
        
        // Classify the kind of notification to distinguish completion from wait/input states
        NSString *lowerBody = alert.body.lowercaseString;
        if ([lowerBody containsString:@"permission"] || 
            [lowerBody containsString:@"waiting"] || 
            [lowerBody containsString:@"input"] ||
            [lowerBody containsString:@"허가"] ||
            [lowerBody containsString:@"입력"] ||
            [lowerBody containsString:@"대기"]) {
            alert.kind = @"action_required";
        } else {
            alert.kind = @"notification";
        }
        
        alert.createdAt = NSDate.date.timeIntervalSince1970;
        
        // Match surfaceKey using the raw surface UUID at index 2
        NSString *rawSurface = firstSplit.count > 2 ? firstSplit[2] : @"";
        if (rawSurface.length > 0) {
            alert.surfaceKey = [rawSurface hasPrefix:@"surface:"] ? rawSurface : [NSString stringWithFormat:@"surface:%@", rawSurface];
        }
        
        [alerts addObject:alert];
        [self.knownNotifications addObject:key];
    }

    if (!self.notificationBaselineReady) {
        self.notificationBaselineReady = YES;
    }
    [self.knownNotifications unionSet:seenThisPoll];
    return alerts;
}

- (NSArray<AlertInfo *> *)trackEndedSessionsFromActiveSessions:(NSArray<SessionInfo *> *)sessions {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableDictionary<NSString *, SessionInfo *> *nextSessionsByKey = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *activeKeys = [NSMutableSet set];

    for (SessionInfo *session in sessions) {
        if (session.key.length == 0) {
            continue;
        }
        session.status = @"active";
        session.seenAt = now;
        nextSessionsByKey[session.key] = session;
        [activeKeys addObject:session.key];
    }

    if (!self.sessionBaselineReady) {
        self.lastSessionsByKey = nextSessionsByKey;
        self.sessionBaselineReady = YES;
        return @[];
    }

    NSMutableArray<AlertInfo *> *endedAlerts = [NSMutableArray array];
    for (NSString *key in self.lastSessionsByKey) {
        if ([activeKeys containsObject:key]) {
            continue;
        }
        SessionInfo *ended = self.lastSessionsByKey[key];
        AlertInfo *alert = [[AlertInfo alloc] init];
        alert.key = [NSString stringWithFormat:@"ended:%@:%lld", key, (long long)now];
        alert.title = ended.title.length > 0 ? ended.title : key;
        alert.body = @"탭 작업이 종료됐습니다.";
        alert.provider = ended.provider.length > 0 ? ended.provider : @"shell";
        alert.kind = @"ended";
        alert.surfaceKey = key;
        alert.paneRef = ended.paneRef;
        alert.workspaceRef = ended.workspaceRef;
        alert.windowRef = ended.windowRef;
        alert.createdAt = now;
        [endedAlerts addObject:alert];
    }

    self.lastSessionsByKey = nextSessionsByKey;
    return endedAlerts;
}

@end

typedef struct {
    CGFloat leftStart, leftWidth;
    CGFloat middleStart, middleWidth;
    CGFloat rightStart, rightWidth;
} LaneLayout;

@interface OverlayView : NSView
- (LaneLayout)laneLayoutForBoundsWidth:(CGFloat)boundsWidth;
@property(nonatomic, strong) NSMutableDictionary<NSString *, PetInfo *> *petsByKey;
@property(nonatomic, strong) NSMutableArray<AlertInfo *> *alerts;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSImage *> *statusBadgeImages;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *manualPositionsByKey;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSSound *> *soundEffectsByName;
@property(nonatomic, strong) NSTimer *animationTimer;
@property(nonatomic, strong) NSImage *frontSprite;
@property(nonatomic, strong) NSMutableArray<NSImage *> *frontSpriteFrames;
@property(nonatomic) NSInteger frontSpriteFrameCount;
@property(nonatomic, strong) NSSound *completionVoice;
@property(nonatomic, strong) NSImage *stateRailImage;
@property(nonatomic, copy) NSString *stateRailSignature;
@property(nonatomic) NSTimeInterval lastUpdateAt;
@property(nonatomic) NSTimeInterval lastMouseSyncAt;
@property(nonatomic) NSTimeInterval lastSoundEffectAt;
@property(nonatomic) NSTimeInterval lastCompletionVoiceAt;
@property(nonatomic, weak) PetInfo *pressedPet;
@property(nonatomic) NSPoint pressPoint;
@property(nonatomic) NSPoint pressPetPosition;
@property(nonatomic) BOOL pressStartedOnNameplate;
@property(nonatomic) BOOL draggingPet;
@property(nonatomic) NSRect previousFrameDirtyRect;
@property(nonatomic) BOOL hasPreviousFrameDirtyRect;
@property(nonatomic) CGFloat currentFPS;
@property(nonatomic, weak) PetInfo *hoveredPet;
- (void)updateSessions:(NSArray<SessionInfo *> *)sessions;
- (void)addAlerts:(NSArray<AlertInfo *> *)alerts;
- (void)addDemoEndedPet;
- (BOOL)playCompletionVoiceIfNeededAtTime:(NSTimeInterval)now;
- (BOOL)playSoundEffectNamed:(NSString *)name atTime:(NSTimeInterval)now force:(BOOL)force;
- (void)loadManualPetPositions;
- (void)saveManualPetPositions;
@end

@implementation OverlayView

- (LaneLayout)laneLayoutForBoundsWidth:(CGFloat)boundsWidth {
    CGFloat usableWidth = MAX(1.0, boundsWidth - 36.0);
    LaneLayout layout;
    layout.leftWidth = usableWidth * 0.30;
    layout.middleWidth = usableWidth * 0.38;
    layout.rightWidth = usableWidth * 0.26;
    
    layout.leftStart = 18.0;
    layout.middleStart = 18.0 + layout.leftWidth + usableWidth * 0.03;
    layout.rightStart = 18.0 + usableWidth - layout.rightWidth;
    return layout;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _petsByKey = [NSMutableDictionary dictionary];
        _alerts = [NSMutableArray array];
        _statusBadgeImages = [NSMutableDictionary dictionary];
        _manualPositionsByKey = [NSMutableDictionary dictionary];
        _soundEffectsByName = [NSMutableDictionary dictionary];
        [self loadManualPetPositions];
        NSString *assetRoot = [ProjectRootPath() stringByAppendingPathComponent:@"assets/mochi"];
        _frontSprite = [[NSImage alloc] initWithContentsOfFile:[assetRoot stringByAppendingPathComponent:@"mochi-front.png"]];
        _frontSpriteFrames = [NSMutableArray array];
        NSString *gifPath = [assetRoot stringByAppendingPathComponent:@"mochi-front-animated.gif"];
        NSImage *gifImage = [[NSImage alloc] initWithContentsOfFile:gifPath];
        if (gifImage) {
            NSBitmapImageRep *gifRep = nil;
            for (NSImageRep *rep in gifImage.representations) {
                if ([rep isKindOfClass:NSBitmapImageRep.class]) {
                    gifRep = (NSBitmapImageRep *)rep;
                    break;
                }
            }
            if (gifRep) {
                NSInteger count = [[gifRep valueForProperty:NSImageFrameCount] integerValue];
                for (NSInteger i = 0; i < count; i++) {
                    [gifRep setProperty:NSImageCurrentFrame withValue:@(i)];
                    CGImageRef cgImage = [gifRep CGImage];
                    if (cgImage) {
                        NSImage *frameImage = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(gifRep.pixelsWide, gifRep.pixelsHigh)];
                        [_frontSpriteFrames addObject:frameImage];
                    }
                }
            }
        }
        if (_frontSpriteFrames.count == 0 && _frontSprite) {
            [_frontSpriteFrames addObject:_frontSprite];
        }
        _frontSpriteFrameCount = _frontSpriteFrames.count;
        _lastUpdateAt = NSDate.date.timeIntervalSince1970;
        [self resetAnimationTimerWithFPS:SharedConfig().fpsActive];
    }
    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)loadManualPetPositions {
    NSData *data = [NSData dataWithContentsOfFile:ManualPetPositionsPath()];
    if (!data) {
        return;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
        return;
    }

    [self.manualPositionsByKey removeAllObjects];
    NSDictionary *dictionary = (NSDictionary *)json;
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSDictionary.class]) {
            continue;
        }
        id xValue = ((NSDictionary *)value)[@"x"];
        id yValue = ((NSDictionary *)value)[@"y"];
        if (![xValue respondsToSelector:@selector(doubleValue)] || ![yValue respondsToSelector:@selector(doubleValue)]) {
            continue;
        }
        CGFloat x = [self clampValue:[xValue doubleValue] min:0.0 max:1.0];
        CGFloat y = [self clampValue:[yValue doubleValue] min:0.0 max:1.0];
        self.manualPositionsByKey[key] = [NSValue valueWithPoint:NSMakePoint(x, y)];
    }
}

- (void)saveManualPetPositions {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    for (NSString *key in self.manualPositionsByKey) {
        NSPoint ratio = [self.manualPositionsByKey[key] pointValue];
        payload[key] = @{
            @"x": @([self clampValue:ratio.x min:0.0 max:1.0]),
            @"y": @([self clampValue:ratio.y min:0.0 max:1.0])
        };
    }

    NSString *path = ManualPetPositionsPath();
    NSString *directory = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

- (BOOL)playSoundEffectNamed:(NSString *)name atTime:(NSTimeInterval)now force:(BOOL)force {
    if (!SharedConfig().soundEffectsEnabled) {
        return NO;
    }
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return NO;
    }
    if (!force && now - self.lastSoundEffectAt < SharedConfig().soundEffectsCooldownSeconds) {
        return NO;
    }

    NSSound *sound = self.soundEffectsByName[trimmed];
    if (!sound) {
        sound = SoundFromNameOrPath(trimmed);
        if (!sound) {
            return NO;
        }
        self.soundEffectsByName[trimmed] = sound;
    }

    sound.volume = SharedConfig().soundEffectsVolume;
    if (sound.isPlaying) {
        [sound stop];
    }
    if ([sound play]) {
        self.lastSoundEffectAt = now;
        return YES;
    }
    return NO;
}

- (NSPoint)positionFromStoredRatio:(NSPoint)ratio size:(CGFloat)size {
    NSRect area = [self walkAreaForPetSize:size];
    return NSMakePoint(NSMinX(area) + NSWidth(area) * [self clampValue:ratio.x min:0.0 max:1.0],
                       NSMinY(area) + NSHeight(area) * [self clampValue:ratio.y min:0.0 max:1.0]);
}

- (NSPoint)storedRatioForPosition:(NSPoint)position size:(CGFloat)size {
    NSRect area = [self walkAreaForPetSize:size];
    CGFloat x = NSWidth(area) > 0 ? (position.x - NSMinX(area)) / NSWidth(area) : 0.5;
    CGFloat y = NSHeight(area) > 0 ? (position.y - NSMinY(area)) / NSHeight(area) : 0.5;
    return NSMakePoint([self clampValue:x min:0.0 max:1.0],
                       [self clampValue:y min:0.0 max:1.0]);
}

- (CGFloat)randBetween:(CGFloat)min max:(CGFloat)max {
    return min + ((CGFloat)arc4random_uniform(10000) / 10000.0) * (max - min);
}

- (CGFloat)clampValue:(CGFloat)value min:(CGFloat)min max:(CGFloat)max {
    return MIN(MAX(value, min), max);
}

- (void)resetAnimationTimerWithFPS:(CGFloat)fps {
    CGFloat safeFPS = [self clampValue:fps min:4.0 max:90.0];
    if (self.animationTimer && fabs(self.currentFPS - safeFPS) < 0.5) {
        return;
    }

    [self.animationTimer invalidate];
    self.currentFPS = safeFPS;
    self.animationTimer = [NSTimer timerWithTimeInterval:(1.0 / safeFPS)
                                                  target:self
                                                selector:@selector(step:)
                                                userInfo:nil
                                                 repeats:YES];
    self.animationTimer.tolerance = 0.001;
    [[NSRunLoop mainRunLoop] addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
}

- (void)pauseAnimation {
    [self.animationTimer invalidate];
    self.animationTimer = nil;
    self.currentFPS = 0.0;
}

- (void)resumeAnimation {
    [self resetAnimationTimerWithFPS:[self desiredAnimationFPS]];
}

- (CGFloat)desiredAnimationFPS {
    if (self.petsByKey.count == 0 && self.alerts.count == 0) {
        return SharedConfig().fpsQuiet;
    }

    if (self.alerts.count > 0) {
        return SharedConfig().fpsActive;
    }

    for (PetInfo *pet in self.petsByKey.allValues) {
        if (pet.alerting) {
            return SharedConfig().fpsActive;
        }
    }
    return SharedConfig().fpsIdle;
}

- (NSRect)walkAreaForPetSize:(CGFloat)size {
    CGFloat bandHeight = MIN(MAX(164.0, self.bounds.size.height * 0.55), 264.0);
    CGFloat left = 18.0 + size / 2.0;
    CGFloat right = self.bounds.size.width - 18.0 - size / 2.0;
    CGFloat bottom = 18.0 + size / 2.0;
    CGFloat top = MAX(bottom + 1.0, bandHeight - size / 2.0);
    
    // Apply 1/2 of the vertical wandering range (가동범위 수직 2분의1 적용)
    top = bottom + (top - bottom) * 0.5;
    
    return NSMakeRect(left, bottom, MAX(1.0, right - left), MAX(1.0, top - bottom));
}

- (NSRect)stateRailDirtyRect {
    return NSMakeRect(0, 0, self.bounds.size.width, 26.0);
}

- (NSRect)alertDirtyRect {
    NSRect walkArea = [self walkAreaForPetSize:SharedConfig().petMaxSize];
    CGFloat y = MAX(0, NSMaxY(walkArea) - 10.0);
    return NSMakeRect(0, y, self.bounds.size.width, self.bounds.size.height - y);
}

- (NSPoint)randomPositionForPetSize:(CGFloat)size {
    NSRect area = [self walkAreaForPetSize:size];
    return NSMakePoint([self randBetween:NSMinX(area) max:NSMaxX(area)],
                       [self randBetween:NSMinY(area) max:NSMaxY(area)]);
}

- (CGFloat)homeYForSlotIndex:(NSUInteger)slotIndex size:(CGFloat)size {
    NSRect area = [self walkAreaForPetSize:size];
    CGFloat ratios[] = {0.28, 0.62, 0.45};
    CGFloat ratio = ratios[slotIndex % 3];
    return [self clampValue:NSMinY(area) + NSHeight(area) * ratio
                        min:NSMinY(area)
                        max:NSMaxY(area)];
}

- (NSPoint)clampPoint:(NSPoint)point toArea:(NSRect)area {
    return NSMakePoint(MIN(MAX(point.x, NSMinX(area)), NSMaxX(area)),
                       MIN(MAX(point.y, NSMinY(area)), NSMaxY(area)));
}

- (void)includeDirtyRect:(NSRect)rect dirty:(NSRect *)dirty hasDirty:(BOOL *)hasDirty {
    rect = NSIntersectionRect(NSInsetRect(rect, -18.0, -18.0), self.bounds);
    if (NSIsEmptyRect(rect)) {
        return;
    }
    if (!*hasDirty) {
        *dirty = rect;
        *hasDirty = YES;
    } else {
        *dirty = NSUnionRect(*dirty, rect);
    }
}

- (void)addDirtyRect:(NSRect)rect toArray:(NSMutableArray<NSValue *> *)dirtyRects {
    rect = NSIntersectionRect(NSInsetRect(rect, -18.0, -18.0), self.bounds);
    if (!NSIsEmptyRect(rect)) {
        [dirtyRects addObject:[NSValue valueWithRect:rect]];
    }
}

- (NSRect)dirtyRectForAllPets {
    NSRect result = NSZeroRect;
    BOOL hasRect = NO;
    for (PetInfo *pet in self.petsByKey.allValues) {
        NSRect rect = NSIntersectionRect(NSInsetRect([self dirtyRectForPet:pet], -18.0, -18.0), self.bounds);
        if (NSIsEmptyRect(rect)) {
            continue;
        }
        if (!hasRect) {
            result = rect;
            hasRect = YES;
        } else {
            result = NSUnionRect(result, rect);
        }
    }
    return hasRect ? result : NSZeroRect;
}

- (PetInfo *)petForKey:(NSString *)key create:(BOOL)create {
    PetInfo *pet = self.petsByKey[key];
    if (!pet && create) {
        pet = [[PetInfo alloc] init];
        pet.key = key;
        pet.size = [self randBetween:SharedConfig().petMinSize max:SharedConfig().petMaxSize];
        pet.position = [self randomPositionForPetSize:pet.size];
        pet.velocity = NSMakePoint([self randBetween:-0.35 max:0.35], [self randBetween:-0.16 max:0.16]);
        pet.facing = pet.velocity.x >= 0 ? 1.0 : -1.0;
        pet.bobPhase = [self randBetween:0 max:6.28];
        pet.homeX = pet.position.x;
        pet.homeY = pet.position.y;
        pet.laneWidth = 140.0;
        pet.slotIndex = 0;
        pet.nextTurnAt = NSDate.date.timeIntervalSince1970 + [self randBetween:1 max:4];
        pet.status = @"active";
        pet.state = @"prework";
        pet.lastActiveAt = NSDate.date.timeIntervalSince1970;
        NSValue *manualRatio = self.manualPositionsByKey[key];
        if (manualRatio) {
            pet.position = [self positionFromStoredRatio:manualRatio.pointValue size:pet.size];
            pet.homeX = pet.position.x;
            pet.homeY = pet.position.y;
            pet.velocity = NSZeroPoint;
            pet.manuallyPlaced = YES;
        }
        self.petsByKey[key] = pet;
    }
    return pet;
}

- (NSRect)walkAreaForPet:(PetInfo *)pet {
    return [self walkAreaForPetSize:pet.size];
}

- (NSUInteger)stableHashForText:(NSString *)text {
    NSString *value = text.length > 0 ? text : @"cmux";
    const char *bytes = value.UTF8String;
    unsigned long long hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; bytes[i] != '\0'; i++) {
        hash ^= (unsigned char)bytes[i];
        hash *= 1099511628211ULL;
    }
    return (NSUInteger)hash;
}

- (NSColor *)accentColorForPet:(PetInfo *)pet alpha:(CGFloat)alpha {
    NSString *key = pet.title.length > 0 ? pet.title : pet.key;
    switch ([self stableHashForText:key] % 10) {
        case 0: return [NSColor colorWithCalibratedRed:0.00 green:0.58 blue:0.80 alpha:alpha];
        case 1: return [NSColor colorWithCalibratedRed:0.95 green:0.43 blue:0.08 alpha:alpha];
        case 2: return [NSColor colorWithCalibratedRed:0.16 green:0.66 blue:0.38 alpha:alpha];
        case 3: return [NSColor colorWithCalibratedRed:0.86 green:0.22 blue:0.50 alpha:alpha];
        case 4: return [NSColor colorWithCalibratedRed:0.55 green:0.39 blue:0.95 alpha:alpha];
        case 5: return [NSColor colorWithCalibratedRed:0.88 green:0.60 blue:0.03 alpha:alpha];
        case 6: return [NSColor colorWithCalibratedRed:0.12 green:0.47 blue:0.90 alpha:alpha];
        case 7: return [NSColor colorWithCalibratedRed:0.86 green:0.28 blue:0.18 alpha:alpha];
        case 8: return [NSColor colorWithCalibratedRed:0.04 green:0.63 blue:0.56 alpha:alpha];
        default: return [NSColor colorWithCalibratedRed:0.45 green:0.48 blue:0.56 alpha:alpha];
    }
}

- (NSColor *)colorForProvider:(NSString *)provider alpha:(CGFloat)alpha {
    if ([provider isEqualToString:@"codex"]) {
        return [NSColor colorWithCalibratedRed:0.13 green:0.65 blue:0.95 alpha:alpha];
    }
    if ([provider isEqualToString:@"claude"]) {
        return [NSColor colorWithCalibratedRed:0.96 green:0.45 blue:0.11 alpha:alpha];
    }
    if ([provider isEqualToString:@"agy"]) {
        return [NSColor colorWithCalibratedRed:0.66 green:0.33 blue:0.97 alpha:alpha];
    }
    return [NSColor colorWithCalibratedWhite:0.45 alpha:alpha];
}

- (void)updateSessions:(NSArray<SessionInfo *> *)sessions {
    NSMutableSet<NSString *> *activeKeys = [NSMutableSet set];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    
    // 1. Identify which active sessions are working
    NSMutableDictionary<NSString *, NSNumber *> *workingByKey = [NSMutableDictionary dictionary];
    for (SessionInfo *session in sessions) {
        PetInfo *existingPet = self.petsByKey[session.key];
        BOOL wasWorking = [existingPet.state isEqualToString:@"working"];
        
        BOOL isAgy = [session.provider isEqualToString:@"agy"] || [session.title containsString:@"agy"];
        CGFloat threshold = isAgy ? 55.0 : SharedConfig().workingCpuThreshold;
        CGFloat exitThreshold = isAgy ? 50.0 : SharedConfig().workingCpuExitThreshold;
        
        BOOL working = wasWorking ? (session.cpu >= exitThreshold) : (session.cpu >= threshold);
        workingByKey[session.key] = @(working);
    }

    // 2. Update/create active pets
    for (SessionInfo *session in sessions) {
        [activeKeys addObject:session.key];
        PetInfo *pet = [self petForKey:session.key create:YES];
        pet.title = session.title;
        pet.provider = session.provider;
        pet.paneRef = session.paneRef;
        pet.workspaceRef = session.workspaceRef;
        pet.windowRef = session.windowRef;
        pet.cpu = session.cpu;
        pet.focused = session.focused;
        pet.processNames = session.processNames;
        if (session.lastNotification.length > 0) {
            pet.lastNotification = session.lastNotification;
        }
        pet.lastNotificationIsUnread = session.lastNotificationIsUnread;
        pet.memoryBytes = session.memoryBytes;
        pet.tokenExpired = session.tokenExpired;
        pet.contextPercentage = session.contextPercentage;
        pet.contextText = session.contextText;
        pet.status = @"active";
        pet.endedAt = 0;
        
        // Update state
        BOOL working = [workingByKey[session.key] boolValue];
        BOOL isDone = pet.alerting || pet.tokenExpired;
        if (isDone) {
            pet.state = @"alerting";
        } else if (working) {
            pet.state = @"working";
        } else {
            pet.state = @"prework";
        }

        // Smoothly interpolate size
        double memMB = pet.memoryBytes / (1024.0 * 1024.0);
        CGFloat minSize = SharedConfig().petMinSize;
        CGFloat maxSize = SharedConfig().petMaxSize;
        double scaleInput = MAX(16.0, memMB);
        double logVal = log2(scaleInput) - 4.0; 
        double fraction = MIN(1.0, MAX(0.0, logVal / 6.0));
        CGFloat targetSize = minSize + (maxSize - minSize) * fraction;
        if (pet.size < 1.0) {
            pet.size = targetSize;
        } else {
            pet.size = pet.size * 0.94 + targetSize * 0.06;
        }
    }

    // 3. Remove inactive pets that are not "ended"
    for (NSString *key in self.petsByKey.allKeys) {
        if (![activeKeys containsObject:key]) {
            PetInfo *pet = self.petsByKey[key];
            if ([pet.status isEqualToString:@"ended"] && now - pet.endedAt <= EndedPetVisibleSeconds) {
                continue;
            }
            [self.petsByKey removeObjectForKey:key];
        }
    }

    // 4. Gather all layoutable pets (active + ended)
    NSMutableArray<PetInfo *> *layoutPets = [NSMutableArray array];
    for (PetInfo *pet in self.petsByKey.allValues) {
        if ([pet.status isEqualToString:@"ended"]) {
            pet.state = @"alerting"; // Ended pets are always alerting/done
        }
        [layoutPets addObject:pet];
    }

    // 5. Sort layoutable pets: Prework -> Working -> Done, and by name
    [layoutPets sortUsingComparator:^NSComparisonResult(PetInfo *a, PetInfo *b) {
        NSInteger aPriority = [a.state isEqualToString:@"alerting"] ? 2 : ([a.state isEqualToString:@"working"] ? 1 : 0);
        NSInteger bPriority = [b.state isEqualToString:@"alerting"] ? 2 : ([b.state isEqualToString:@"working"] ? 1 : 0);
        if (aPriority != bPriority) {
            return aPriority < bPriority ? NSOrderedAscending : NSOrderedDescending;
        }
        NSString *left = a.title.length > 0 ? a.title : a.key;
        NSString *right = b.title.length > 0 ? b.title : b.key;
        return [left localizedStandardCompare:right];
    }];

    // 6. Partition counts & slot assignments evenly across the entire width of the screen
    NSUInteger count = layoutPets.count;
    CGFloat usableWidth = self.bounds.size.width - 36.0;
    CGFloat slotWidth = usableWidth / MAX((NSUInteger)1, count);
    
    for (NSUInteger i = 0; i < count; i++) {
        PetInfo *pet = layoutPets[i];
        if (pet.manuallyPlaced) {
            pet.homeX = pet.position.x;
            pet.homeY = pet.position.y;
            pet.velocity = NSMakePoint(pet.velocity.x * 0.35, pet.velocity.y * 0.35);
        } else {
            pet.laneWidth = slotWidth;
            pet.slotIndex = i;
            pet.homeX = 18.0 + slotWidth * ((CGFloat)i + 0.5);
            pet.homeY = [self homeYForSlotIndex:i size:pet.size];
        }

        // Apply gentle pull velocity adjustments
        CGFloat pullX = [self clampValue:(pet.homeX - pet.position.x) * 0.012 min:-0.65 max:0.65];
        CGFloat pullY = [self clampValue:(pet.homeY - pet.position.y) * 0.018 min:-0.22 max:0.22];
        pet.velocity = NSMakePoint([self clampValue:pet.velocity.x + pullX min:-0.90 max:0.90],
                                   [self clampValue:pet.velocity.y + pullY min:-0.36 max:0.36]);
        pet.position = [self clampPoint:pet.position toArea:[self walkAreaForPetSize:pet.size]];
    }
}

- (void)addAlerts:(NSArray<AlertInfo *> *)alerts {
    if (alerts.count == 0) {
        return;
    }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (AlertInfo *alert in alerts) {
        if ([alert.kind isEqualToString:@"ended"] && alert.surfaceKey.length > 0) {
            PetInfo *pet = [self petForKey:alert.surfaceKey create:YES];
            pet.title = alert.title;
            pet.provider = alert.provider;
            pet.paneRef = alert.paneRef;
            pet.workspaceRef = alert.workspaceRef;
            pet.windowRef = alert.windowRef;
            pet.cpu = 0;
            pet.focused = NO;
            pet.status = @"ended";
            pet.endedAt = alert.createdAt;
            pet.alerting = YES;
            pet.alertUntil = now + 86400.0;
        }
    }

    [self.alerts addObjectsFromArray:alerts];
    while (self.alerts.count > 3) {
        [self.alerts removeObjectAtIndex:0];
    }

    for (AlertInfo *alert in alerts) {
        // Skip persistent jumping/celebration for action-required wait states
        if ([alert.kind isEqualToString:@"action_required"]) {
            continue;
        }
        
        PetInfo *targetPet = nil;
        if (alert.title.length > 0) {
            for (PetInfo *p in self.petsByKey.allValues) {
                if ([p.title isEqualToString:alert.title]) {
                    targetPet = p;
                    break;
                }
            }
        }
        if (!targetPet && alert.surfaceKey.length > 0) {
            targetPet = self.petsByKey[alert.surfaceKey];
        }
        if (!targetPet) {
            targetPet = self.petsByKey.allValues.firstObject;
        }
        if (targetPet) {
            targetPet.alerting = YES;
            targetPet.alertUntil = now + 86400.0;
        }
    }
    BOOL voicePlayed = [self playCompletionVoiceIfNeededAtTime:now];
    if (!voicePlayed) {
        [self playSoundEffectNamed:SharedConfig().completionSoundName atTime:now force:NO];
    }
    [self resetAnimationTimerWithFPS:SharedConfig().fpsActive];
}

- (BOOL)playCompletionVoiceIfNeededAtTime:(NSTimeInterval)now {
    if (!SharedConfig().completionVoiceEnabled) {
        return NO;
    }
    if (now - self.lastCompletionVoiceAt < SharedConfig().completionVoiceCooldownSeconds) {
        return NO;
    }

    if (!self.completionVoice) {
        NSString *path = ProjectResolvedPath(SharedConfig().completionVoicePath);
        self.completionVoice = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
    }
    if (!self.completionVoice) {
        return NO;
    }

    self.completionVoice.volume = SharedConfig().completionVoiceVolume;
    if (self.completionVoice.isPlaying) {
        [self.completionVoice stop];
    }
    if ([self.completionVoice play]) {
        self.lastCompletionVoiceAt = now;
        return YES;
    }
    return NO;
}

- (void)addDemoEndedPet {
    AlertInfo *alert = [[AlertInfo alloc] init];
    alert.key = @"demo-ended";
    alert.title = @"예시 세션";
    alert.body = @"탭 작업이 종료됐습니다.";
    alert.provider = @"claude";
    alert.kind = @"ended";
    alert.surfaceKey = @"surface:demo-ended";
    alert.createdAt = NSDate.date.timeIntervalSince1970;
    [self addAlerts:@[alert]];
}

- (void)step:(NSTimer *)timer {
    if (self.petsByKey.count == 0 && self.alerts.count == 0) {
        [self resetAnimationTimerWithFPS:SharedConfig().fpsQuiet];
        [self syncMousePassthroughIfNeededAtTime:NSDate.date.timeIntervalSince1970];
        return;
    }

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    CGFloat dt = MAX(0.001, MIN(0.1, now - self.lastUpdateAt));
    self.lastUpdateAt = now;
    NSMutableArray<NSValue *> *dirtyRects = [NSMutableArray arrayWithCapacity:self.petsByKey.count * 3 + 2];

    BOOL shouldRedrawAlertArea = self.alerts.count > 0;
    for (AlertInfo *alert in self.alerts.copy) {
        if (now - alert.createdAt > 9.0) {
            [self.alerts removeObject:alert];
            shouldRedrawAlertArea = YES;
        }
    }

    for (NSString *key in self.petsByKey.allKeys) {
        PetInfo *pet = self.petsByKey[key];
        if ([pet.status isEqualToString:@"ended"] && now - pet.endedAt > EndedPetVisibleSeconds) {
            [self addDirtyRect:[self dirtyRectForPet:pet] toArray:dirtyRects];
            [self.petsByKey removeObjectForKey:key];
        }
    }

    for (PetInfo *pet in self.petsByKey.allValues) {
        [self addDirtyRect:[self dirtyRectForPet:pet] toArray:dirtyRects];

        if (pet.focused) {
            pet.alertUntil = 0;
        }
        pet.alerting = pet.alertUntil > now;
        BOOL isActive = (pet.cpu > 0.08) || [pet.state isEqualToString:@"working"] || pet.alerting || pet.focused;
        if (isActive) {
            pet.lastActiveAt = now;
        } else if (pet.lastActiveAt == 0) {
            pet.lastActiveAt = now;
        }
        if (pet.tokenExpired) {
            pet.velocity = NSZeroPoint;
            pet.nextTurnAt = now + 9999.0;
            CGFloat rx = pet.homeX - pet.position.x;
            CGFloat ry = pet.homeY - pet.position.y;
            if (fabs(rx) > 2.0 || fabs(ry) > 2.0) {
                pet.position = NSMakePoint(pet.position.x + rx * 0.10, pet.position.y + ry * 0.10);
            }
        } else if (now >= pet.nextTurnAt) {
            CGFloat pullHomeX = [self clampValue:(pet.homeX - pet.position.x) * 0.0015 min:-0.15 max:0.15];
            CGFloat pullHomeY = [self clampValue:(pet.homeY - pet.position.y) * 0.0020 min:-0.10 max:0.10];
            pet.velocity = NSMakePoint([self randBetween:-0.58 max:0.58] + pullHomeX,
                                       [self randBetween:-0.42 max:0.42] + pullHomeY);
            pet.nextTurnAt = now + [self randBetween:1.5 max:4.0];
        }

        if (!pet.tokenExpired) {
            CGFloat distToHomeX = pet.homeX - pet.position.x;
            CGFloat distToHomeY = pet.homeY - pet.position.y;
            CGFloat framePullX = 0.0;
            CGFloat framePullY = 0.0;
            
            if (fabs(distToHomeX) > 120.0) {
                framePullX = [self clampValue:distToHomeX * 0.0015 min:-0.15 max:0.15];
            }
            if (fabs(distToHomeY) > 60.0) {
                framePullY = [self clampValue:distToHomeY * 0.0025 min:-0.12 max:0.12];
            }

            // Steering avoidance: naturally steer away from nearby pets
            CGFloat avoidX = 0.0;
            CGFloat avoidY = 0.0;
            for (PetInfo *other in self.petsByKey.allValues) {
                if (other == pet || [other.status isEqualToString:@"ended"]) {
                    continue;
                }
                CGFloat dx = pet.position.x - other.position.x;
                CGFloat dy = pet.position.y - other.position.y;
                
                // Steering proximity bounds (84px horizontally, 40px vertically)
                CGFloat limitX = 84.0;
                CGFloat limitY = 40.0;
                if (fabs(dx) < limitX && fabs(dy) < limitY) {
                    CGFloat forceX = (limitX - fabs(dx)) / limitX; // 1.0 (touching) to 0.0 (far)
                    CGFloat forceY = (limitY - fabs(dy)) / limitY;
                    
                    CGFloat dirX = dx >= 0 ? 1.0 : -1.0;
                    CGFloat dirY = dy >= 0 ? 1.0 : -1.0;
                    if (fabs(dy) < 0.01) {
                        dirY = (pet.slotIndex % 2 == 0) ? 1.0 : -1.0;
                    }
                    
                    // Steer velocity away gently
                    avoidX += dirX * forceX * 0.16;
                    avoidY += dirY * forceY * 0.10;
                }
            }

            pet.velocity = NSMakePoint([self clampValue:pet.velocity.x * 0.992 + framePullX + avoidX min:-1.5 max:1.5],
                                       [self clampValue:pet.velocity.y * 0.988 + framePullY + avoidY min:-1.1 max:1.1]);

            // Speed factor scales inversely with pet size (larger pets are slower/heavier, smaller are faster/zippier)
            CGFloat speedScale = 16.0 / MAX(1.0, pet.size);
            speedScale = MIN(2.2, MAX(0.5, speedScale));

            pet.position = NSMakePoint(pet.position.x + pet.velocity.x * dt * 90 * speedScale,
                                       pet.position.y + pet.velocity.y * dt * 90 * speedScale);
            if (fabs(pet.velocity.x) > 0.01) {
                pet.facing = pet.velocity.x >= 0 ? 1.0 : -1.0;
            }
            pet.bobPhase += dt * (5.5 + hypot(pet.velocity.x, pet.velocity.y) * 5.0) * speedScale;
        }

        NSRect area = [self walkAreaForPet:pet];
        NSRect baseArea = [self walkAreaForPetSize:pet.size];
        if (pet.position.x < NSMinX(area) || pet.position.x > NSMaxX(area)) {
            CGFloat direction = pet.homeX >= pet.position.x ? 1.0 : -1.0;
            pet.velocity = NSMakePoint([self clampValue:pet.velocity.x * 0.70 + direction * 0.34 min:-0.85 max:0.85],
                                       pet.velocity.y);
            pet.position = [self clampPoint:pet.position toArea:baseArea];
        }
        if (pet.position.y < NSMinY(area) || pet.position.y > NSMaxY(area)) {
            pet.velocity = NSMakePoint(pet.velocity.x, -pet.velocity.y);
            pet.position = [self clampPoint:pet.position toArea:area];
        }

        [self addDirtyRect:[self dirtyRectForPet:pet] toArray:dirtyRects];
    }

    [self separateOverlappingPets];
    for (PetInfo *pet in self.petsByKey.allValues) {
        [self addDirtyRect:[self dirtyRectForPet:pet] toArray:dirtyRects];
    }
    self.previousFrameDirtyRect = NSZeroRect;
    self.hasPreviousFrameDirtyRect = NO;

    if (shouldRedrawAlertArea) {
        [self addDirtyRect:[self alertDirtyRect] toArray:dirtyRects];
    }

    for (NSValue *value in dirtyRects) {
        [self setNeedsDisplayInRect:value.rectValue];
    }
    [self syncMousePassthroughIfNeededAtTime:now];
    [self resetAnimationTimerWithFPS:[self desiredAnimationFPS]];
}

- (NSString *)shortTitle:(NSString *)title {
    if (title.length <= 18) {
        return title;
    }
    return [[title substringToIndex:17] stringByAppendingString:@"…"];
}

- (NSRect)dirtyRectForPet:(PetInfo *)pet {
    CGFloat s = pet.size;
    CGFloat spriteW = s * 1.9;
    CGFloat labelW = MIN(MAX(58.0, pet.laneWidth - 20.0), 178.0) + 18.0;
    CGFloat width = MAX(spriteW + 24.0, labelW);
    CGFloat top = pet.position.y + spriteW * 0.62;
    CGFloat bottom = pet.position.y - spriteW * 0.72 - 28.0;

    if (self.hoveredPet == pet) {
        width = MAX(width, 300.0);
        top += 160.0;
    }

    return NSMakeRect(pet.position.x - width / 2.0,
                      bottom,
                      width,
                      MAX(1.0, top - bottom));
}

- (NSRect)spriteRectForPet:(PetInfo *)pet {
    CGFloat s = pet.size;
    CGFloat bob = sin(pet.bobPhase) * (pet.alerting ? 2.8 : 1.4);
    NSRect body = NSMakeRect(pet.position.x - s / 2.0, pet.position.y - s / 2.0 + bob, s, s);
    CGFloat spriteScale = 1.9;
    return NSMakeRect(NSMidX(body) - s * spriteScale / 2.0,
                      NSMinY(body) - s * 0.28,
                      s * spriteScale,
                      s * spriteScale);
}

- (void)updateNameplateCacheForPet:(PetInfo *)pet {
    CGFloat labelSize = 10.8;
    CGFloat maxTextWidth = MIN(MAX(58.0, pet.laneWidth - 20.0), 178.0);
    NSString *base = pet.title ?: pet.provider ?: @"cmux";
    
    // Calculate short status summary
    NSString *statusText = nil;
    BOOL ended = [pet.status isEqualToString:@"ended"];
    if (ended) {
        statusText = [NSString stringWithFormat:@"⏹️ %@", LocalizedStr(@"ended")];
    } else if (pet.tokenExpired) {
        statusText = [NSString stringWithFormat:@"❌ %@", LocalizedStr(@"expired")];
    } else if (pet.lastNotification.length > 0 && pet.lastNotificationIsUnread) {
        NSString *notif = pet.lastNotification;
        if ([notif containsString:@"permission"]) {
            statusText = [NSString stringWithFormat:@"⚠️ %@", LocalizedStr(@"approval")];
        } else if ([notif containsString:@"waiting"]) {
            statusText = [NSString stringWithFormat:@"💬 %@", LocalizedStr(@"input")];
        } else if ([notif containsString:@"종료"] || [notif.lowercaseString containsString:@"ended"] || [notif.lowercaseString containsString:@"exit"]) {
            statusText = [NSString stringWithFormat:@"⏹️ %@", LocalizedStr(@"ended")];
        } else if ([notif containsString:@"완료"] || [notif.lowercaseString containsString:@"done"] || [notif.lowercaseString containsString:@"complete"]) {
            statusText = [NSString stringWithFormat:@"✅ %@", LocalizedStr(@"completed")];
        } else {
            statusText = notif.length > 14 ? [[notif substringToIndex:12] stringByAppendingString:@"…"] : notif;
        }
    } else if ([pet.state isEqualToString:@"working"]) {
        NSMutableArray<NSString *> *procList = [NSMutableArray array];
        for (NSString *p in pet.processNames) {
            if (![procList containsObject:p] && ![p isEqualToString:@"zsh"] && ![p isEqualToString:@"sleep"] && ![p isEqualToString:@"caffeinate"] && ![p isEqualToString:@"cmux"]) {
                [procList addObject:p];
            }
        }
        if (procList.count > 0) {
            statusText = [NSString stringWithFormat:@"⚙️ %@", [procList componentsJoinedByString:@", "]];
        } else {
            statusText = [NSString stringWithFormat:@"⚡ %@", LocalizedStr(@"working")];
        }
    } else {
        statusText = [NSString stringWithFormat:@"💤 %@", LocalizedStr(@"prework")];
    }

    if (pet.contextText.length > 0 && statusText != nil) {
        statusText = [NSString stringWithFormat:@"%@ (%@)", statusText, pet.contextText];
    } else if (pet.contextPercentage >= 0 && statusText != nil) {
        statusText = [NSString stringWithFormat:@"%@ (%ld%%)", statusText, (long)pet.contextPercentage];
    }

    NSString *signature = [NSString stringWithFormat:@"%@|%@|%.1f|%.1f|%@", base, statusText ?: @"", maxTextWidth, labelSize, pet.key ?: @""];
    if (pet.nameplateImage && [pet.nameplateSignature isEqualToString:signature]) {
        return;
    }

    NSString *label = [self shortTitle:base maxWidth:maxTextWidth size:labelSize];
    NSDictionary *attrs = [self outlinedLabelAttributesWithSize:labelSize];
    NSSize textSize = [label sizeWithAttributes:attrs];
    
    NSString *subLabel = statusText;
    NSDictionary *subAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.2 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.85 alpha:0.90]
    };
    NSSize subSize = subLabel ? [subLabel sizeWithAttributes:subAttrs] : NSZeroSize;
    
    CGFloat maxTextW = MAX(textSize.width, subSize.width);
    CGFloat plateW = MIN(maxTextWidth + 16.0, MAX(54.0, maxTextW + 14.0));
    CGFloat plateH = textSize.height + (subLabel ? subSize.height + 4.0 : 0) + 7.0;
    
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(plateW, plateH)];
    [image lockFocus];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, plateW, plateH));

    NSRect plate = NSMakeRect(0, 0, plateW, plateH);
    [[NSColor colorWithCalibratedWhite:0 alpha:0.65] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:plate xRadius:5.0 yRadius:5.0] fill];
    
    [[self accentColorForPet:pet alpha:0.88] setFill];
    NSRect strip = NSMakeRect(0, 0, plateW, 3.0);
    [[NSBezierPath bezierPathWithRoundedRect:strip xRadius:2.5 yRadius:2.5] fill];

    if (subLabel) {
        NSRect titleRect = NSMakeRect((plateW - textSize.width) / 2.0,
                                      plateH - textSize.height - 4.0,
                                      textSize.width,
                                      textSize.height);
        [label drawInRect:titleRect withAttributes:attrs];
        
        NSRect subRect = NSMakeRect((plateW - subSize.width) / 2.0,
                                    4.0,
                                    subSize.width,
                                    subSize.height);
        [subLabel drawInRect:subRect withAttributes:subAttrs];
    } else {
        NSRect textRect = NSMakeRect((plateW - textSize.width) / 2.0,
                                     (plateH - textSize.height) / 2.0 + 0.5,
                                     textSize.width,
                                     textSize.height);
        [label drawInRect:textRect withAttributes:attrs];
    }
    
    [image unlockFocus];

    pet.nameplateImage = image;
    pet.nameplateSignature = signature;
    pet.nameplateSize = image.size;
}

- (NSRect)nameplateRectForPet:(PetInfo *)pet {
    [self updateNameplateCacheForPet:pet];
    CGFloat plateW = pet.nameplateSize.width > 1.0 ? pet.nameplateSize.width : 64.0;
    CGFloat plateH = pet.nameplateSize.height > 1.0 ? pet.nameplateSize.height : 18.0;
    NSRect spriteRect = [self spriteRectForPet:pet];
    CGFloat labelY = NSMinY(spriteRect) - plateH - 4.0;
    if (pet.tokenExpired) {
        labelY -= pet.size * 0.16;
    }
    return NSMakeRect(pet.position.x - plateW / 2.0, labelY, plateW, plateH);
}

- (NSRect)clickRectForPet:(PetInfo *)pet {
    NSRect nameplate = NSInsetRect([self nameplateRectForPet:pet], -8.0, -6.0);
    if (SharedConfig().clickNameplateOnly) {
        return nameplate;
    }
    return NSUnionRect(nameplate, [self spriteRectForPet:pet]);
}

- (NSRect)dragRectForPet:(PetInfo *)pet {
    NSRect nameplate = NSInsetRect([self nameplateRectForPet:pet], -8.0, -6.0);
    if (!SharedConfig().petDraggingEnabled || !SharedConfig().dragPetBodyEnabled) {
        return nameplate;
    }
    NSRect sprite = NSInsetRect([self spriteRectForPet:pet], -4.0, -4.0);
    return NSUnionRect(nameplate, sprite);
}

- (PetInfo *)petAtPoint:(NSPoint)point {
    PetInfo *nearest = nil;
    CGFloat nearestDistance = CGFLOAT_MAX;
    for (PetInfo *pet in self.petsByKey.allValues) {
        if (!NSPointInRect(point, [self dragRectForPet:pet])) {
            continue;
        }
        CGFloat dx = point.x - pet.position.x;
        CGFloat dy = point.y - pet.position.y;
        CGFloat distance = dx * dx + dy * dy;
        if (distance < nearestDistance) {
            nearest = pet;
            nearestDistance = distance;
        }
    }
    return nearest;
}

- (void)separateOverlappingPets {
    NSArray<PetInfo *> *pets = self.petsByKey.allValues;
    if (pets.count < 2) {
        return;
    }

    // Run 4 passes to fully resolve cascading overlaps for up to 6-8 pets
    for (NSUInteger pass = 0; pass < 4; pass++) {
        for (NSUInteger i = 0; i < pets.count; i++) {
            PetInfo *a = pets[i];
            if ([a.status isEqualToString:@"ended"]) {
                continue;
            }
            for (NSUInteger j = i + 1; j < pets.count; j++) {
                PetInfo *b = pets[j];
                if ([b.status isEqualToString:@"ended"]) {
                    continue;
                }

                CGFloat dx = b.position.x - a.position.x;
                CGFloat dy = b.position.y - a.position.y;
                
                // Increase minimum distances to prevent sprite and nameplate overlapping
                CGFloat minX = MAX(64.0, (a.size + b.size) * 1.55);
                CGFloat minY = MAX(36.0, (a.size + b.size) * 0.78);
                if (fabs(dx) >= minX || fabs(dy) >= minY) {
                    continue;
                }

                // Push horizontally (gentler push coefficient 0.18 instead of 0.52 to prevent violent rebound jitters)
                CGFloat directionX = dx >= 0 ? 1.0 : -1.0;
                CGFloat pushX = (minX - fabs(dx)) * 0.18 + 0.2;
                a.position = NSMakePoint(a.position.x - directionX * pushX, a.position.y);
                b.position = NSMakePoint(b.position.x + directionX * pushX, b.position.y);

                // Push slightly vertically as well to slide past each other smoothly
                if (fabs(dy) < minY) {
                    CGFloat directionY = dy >= 0 ? 1.0 : -1.0;
                    if (fabs(dy) < 0.01) {
                        directionY = [self randBetween:-1.0 max:1.0] >= 0 ? 1.0 : -1.0;
                    }
                    CGFloat pushY = (minY - fabs(dy)) * 0.10 + 0.1;
                    a.position = NSMakePoint(a.position.x, a.position.y - directionY * pushY);
                    b.position = NSMakePoint(b.position.x, b.position.y + directionY * pushY);
                }

                // Damp velocities on collision to prevent jitter/vibration
                a.velocity = NSMakePoint(a.velocity.x * 0.40, a.velocity.y * 0.40);
                b.velocity = NSMakePoint(b.velocity.x * 0.40, b.velocity.y * 0.40);
            }
        }
    }
    
    // Clamp to boundaries ONCE after all passes are resolved to prevent high-frequency vibration loops against boundary walls
    for (PetInfo *pet in pets) {
        if (![pet.status isEqualToString:@"ended"]) {
            pet.position = [self clampPoint:pet.position toArea:[self walkAreaForPet:pet]];
        }
    }
}

- (NSArray<PetInfo *> *)petsInDrawOrder {
    return [self.petsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(PetInfo *a, PetInfo *b) {
        if (a.position.y > b.position.y) {
            return NSOrderedAscending;
        }
        if (a.position.y < b.position.y) {
            return NSOrderedDescending;
        }
        NSString *left = a.title.length > 0 ? a.title : a.key;
        NSString *right = b.title.length > 0 ? b.title : b.key;
        return [left localizedStandardCompare:right];
    }];
}

- (void)syncMousePassthrough {
    if (!self.window) {
        return;
    }
    if (self.pressedPet) {
        self.window.ignoresMouseEvents = NO;
        return;
    }
    NSPoint cursor = [self.window convertPointFromScreen:NSEvent.mouseLocation];
    PetInfo *overPet = [self petAtPoint:cursor];

    if (self.hoveredPet != overPet) {
        if (self.hoveredPet) {
            [self setNeedsDisplayInRect:[self dirtyRectForPet:self.hoveredPet]];
        }
        self.hoveredPet = overPet;
        if (overPet) {
            [self setNeedsDisplayInRect:[self dirtyRectForPet:overPet]];
        }
    }

    BOOL shouldIgnore = !overPet;
    if (self.window.ignoresMouseEvents != shouldIgnore) {
        self.window.ignoresMouseEvents = shouldIgnore;
    }
}

- (void)syncMousePassthroughIfNeededAtTime:(NSTimeInterval)now {
    if (now - self.lastMouseSyncAt < 0.05) {
        return;
    }
    self.lastMouseSyncAt = now;
    [self syncMousePassthrough];
}

- (NSString *)shellQuoted:(NSString *)value {
    NSString *safe = value ?: @"";
    safe = [safe stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", safe];
}

- (void)focusPet:(PetInfo *)pet {
    if (pet.paneRef.length == 0) {
        return;
    }

    NSMutableArray<NSString *> *commands = [NSMutableArray array];
    if (pet.workspaceRef.length > 0) {
        NSMutableString *selectWorkspace = [NSMutableString stringWithFormat:@"CMUX_QUIET=1 cmux select-workspace --workspace %@",
                                            [self shellQuoted:pet.workspaceRef]];
        if (pet.windowRef.length > 0) {
            [selectWorkspace appendFormat:@" --window %@", [self shellQuoted:pet.windowRef]];
        }
        [selectWorkspace appendString:@" >/dev/null 2>&1"];
        [commands addObject:selectWorkspace];
    }

    NSMutableString *focus = [NSMutableString stringWithFormat:@"CMUX_QUIET=1 cmux focus-pane --pane %@",
                              [self shellQuoted:pet.paneRef]];
    if (pet.workspaceRef.length > 0) {
        [focus appendFormat:@" --workspace %@", [self shellQuoted:pet.workspaceRef]];
    }
    if (pet.windowRef.length > 0) {
        [focus appendFormat:@" --window %@", [self shellQuoted:pet.windowRef]];
    }
    [focus appendString:@" >/dev/null 2>&1"];
    [commands addObject:focus];

    NSString *command = [NSString stringWithFormat:@"%@%@; /usr/bin/open -b com.cmuxterm.app >/dev/null 2>&1",
                         CmuxPathPrefix,
                         [commands componentsJoinedByString:@"; "]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
        task.arguments = @[@"-lc", command];
        task.standardOutput = [NSPipe pipe];
        task.standardError = [NSPipe pipe];
        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
        }
    });
}

- (NSView *)hitTest:(NSPoint)point {
    if (self.hidden || self.alphaValue <= 0.01) {
        return nil;
    }
    return [self petAtPoint:point] ? self : nil;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    PetInfo *pet = [self petAtPoint:point];
    if (!pet) {
        return;
    }
    self.pressedPet = pet;
    self.pressPoint = point;
    self.pressPetPosition = pet.position;
    self.pressStartedOnNameplate = YES;
    self.draggingPet = NO;
    self.window.ignoresMouseEvents = NO;
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    PetInfo *pet = [self petAtPoint:point];
    if (pet) {
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"com.neogenesis.cmux-pet-overlay.toggle"
                                                                     object:nil
                                                                   userInfo:@{@"action": @"off"}
                                                         deliverImmediately:YES];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!SharedConfig().petDraggingEnabled || !self.pressedPet) {
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = point.x - self.pressPoint.x;
    CGFloat dy = point.y - self.pressPoint.y;
    if (!self.draggingPet && dx * dx + dy * dy < 16.0) {
        return;
    }

    BOOL startedDrag = !self.draggingPet;
    self.draggingPet = YES;
    PetInfo *pet = self.pressedPet;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSRect oldRect = [self dirtyRectForPet:pet];
    NSPoint proposed = NSMakePoint(self.pressPetPosition.x + dx, self.pressPetPosition.y + dy);
    pet.position = [self clampPoint:proposed toArea:[self walkAreaForPetSize:pet.size]];
    pet.homeX = pet.position.x;
    pet.homeY = pet.position.y;
    pet.velocity = NSZeroPoint;
    pet.manuallyPlaced = YES;
    pet.nextTurnAt = now + 3.0;
    if (startedDrag) {
        [self playSoundEffectNamed:SharedConfig().dragStartSoundName atTime:now force:NO];
    }
    [self setNeedsDisplayInRect:NSUnionRect(NSInsetRect(oldRect, -18.0, -18.0),
                                            NSInsetRect([self dirtyRectForPet:pet], -18.0, -18.0))];
    [self resetAnimationTimerWithFPS:SharedConfig().fpsActive];
}

- (void)mouseUp:(NSEvent *)event {
    PetInfo *pet = self.pressedPet;
    if (!pet) {
        return;
    }

    BOOL didDrag = self.draggingPet;
    BOOL shouldFocus = self.pressStartedOnNameplate && !didDrag;
    if (didDrag) {
        pet.homeX = pet.position.x;
        pet.homeY = pet.position.y;
        pet.velocity = NSZeroPoint;
        pet.manuallyPlaced = YES;
        self.manualPositionsByKey[pet.key] = [NSValue valueWithPoint:[self storedRatioForPosition:pet.position size:pet.size]];
        [self saveManualPetPositions];
        [self playSoundEffectNamed:SharedConfig().dragDropSoundName atTime:NSDate.date.timeIntervalSince1970 force:YES];
    }

    self.pressedPet = nil;
    self.draggingPet = NO;
    self.pressStartedOnNameplate = NO;
    [self syncMousePassthrough];

    if (shouldFocus) {
        [self playSoundEffectNamed:SharedConfig().focusSoundName atTime:NSDate.date.timeIntervalSince1970 force:NO];
        [self focusPet:pet];
    }
}

- (NSString *)shortTitle:(NSString *)title maxWidth:(CGFloat)maxWidth size:(CGFloat)size {
    NSString *value = title.length > 0 ? title : @"cmux";
    NSDictionary *attrs = [self outlinedLabelAttributesWithSize:size];
    if ([value sizeWithAttributes:attrs].width <= maxWidth) {
        return value;
    }
    NSString *suffix = @"…";
    for (NSInteger length = (NSInteger)value.length - 1; length > 1; length--) {
        NSString *candidate = [[value substringToIndex:(NSUInteger)length] stringByAppendingString:suffix];
        if ([candidate sizeWithAttributes:attrs].width <= maxWidth) {
            return candidate;
        }
    }
    return suffix;
}

- (NSFont *)labelFontOfSize:(CGFloat)size {
    NSFont *font = [NSFont fontWithName:@"Pretendard-ExtraBold" size:size];
    if (!font) {
        font = [NSFont fontWithName:@"PretendardStd-ExtraBold" size:size];
    }
    if (!font) {
        font = [NSFont boldSystemFontOfSize:size];
    }
    return font;
}

- (NSDictionary *)outlinedLabelAttributesWithSize:(CGFloat)size {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    return @{
        NSFontAttributeName: [self labelFontOfSize:size],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSStrokeColorAttributeName: [NSColor colorWithCalibratedWhite:0 alpha:0.92],
        NSStrokeWidthAttributeName: @(-5.0),
        NSParagraphStyleAttributeName: style
    };
}

- (void)drawOutlinedText:(NSString *)text centeredAtX:(CGFloat)x y:(CGFloat)y size:(CGFloat)size {
    NSDictionary *attrs = [self outlinedLabelAttributesWithSize:size];
    NSSize textSize = [text sizeWithAttributes:attrs];
    NSRect rect = NSMakeRect(x - textSize.width / 2.0, y, textSize.width + 2.0, textSize.height + 2.0);
    [text drawInRect:rect withAttributes:attrs];
}

- (void)drawStatusBadgeForPet:(PetInfo *)pet inRect:(NSRect)spriteRect {
    BOOL ended = [pet.status isEqualToString:@"ended"];
    BOOL alerting = pet.alerting;
    BOOL working = [pet.state isEqualToString:@"working"];
    
    // Dynamic size scaling: clamp badge size between 14x11 and 21x17 based on pet.size (8 to 28)
    CGFloat badgeW = MAX(14.0, pet.size * 0.58);
    CGFloat badgeH = MAX(11.0, pet.size * 0.46);
    
    CGFloat badgeX = 0.0;
    CGFloat badgeY = 0.0;
    
    if (pet.tokenExpired) {
        // Collapsed/rotated pet: put badge near the back/feet (opposite of face direction)
        // Shift it outside the body boundary to completely avoid covering the face/body
        if (pet.facing >= 0) {
            badgeX = NSMinX(spriteRect) - badgeW + 2.0;
            badgeY = NSMaxY(spriteRect) - badgeH - 2.0;
        } else {
            badgeX = NSMaxX(spriteRect) - 2.0;
            badgeY = NSMaxY(spriteRect) - badgeH - 2.0;
        }
    } else {
        // Standing pet: put badge on the opposite side of the facing direction (the back of the head)
        // Offset it outside the body boundary so it floats adjacent to the pet
        if (pet.facing >= 0) {
            // Facing right (face is on the right): draw badge pushed out to the left (back)
            badgeX = NSMinX(spriteRect) - badgeW + 3.0;
        } else {
            // Facing left (face is on the left): draw badge pushed out to the right (back)
            badgeX = NSMaxX(spriteRect) - 3.0;
        }
        badgeY = NSMaxY(spriteRect) - badgeH + 4.0; // Float slightly higher to look like a small balloon/badge
    }
    
    NSRect badge = NSMakeRect(badgeX, badgeY, badgeW, badgeH);

    NSString *key = ended ? @"ended" : (pet.tokenExpired ? @"expired" : (alerting ? @"alerting" : (working ? @"working" : @"prework")));
    NSImage *image = [self statusBadgeImageForKey:key size:NSMakeSize(badgeW, badgeH)];
    [image drawInRect:badge
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:NO
                hints:nil];
}

- (NSImage *)statusBadgeImageForKey:(NSString *)key size:(NSSize)size {
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.0fx%.0f", key, size.width, size.height];
    NSImage *cached = self.statusBadgeImages[cacheKey];
    if (cached) {
        return cached;
    }

    NSColor *fill = nil;
    NSString *icon = nil;
    if ([key isEqualToString:@"ended"]) {
        fill = [NSColor colorWithCalibratedWhite:0.18 alpha:0.86];
        icon = @"×";
    } else if ([key isEqualToString:@"expired"]) {
        fill = [NSColor colorWithCalibratedRed:0.80 green:0.12 blue:0.12 alpha:0.92];
        icon = @"😵";
    } else if ([key isEqualToString:@"alerting"]) {
        fill = [NSColor colorWithCalibratedRed:0.12 green:0.66 blue:0.36 alpha:0.92];
        icon = @"✓";
    } else if ([key isEqualToString:@"working"]) {
        fill = [NSColor colorWithCalibratedRed:0.95 green:0.43 blue:0.08 alpha:0.92];
        icon = @"⚡";
    } else {
        fill = [NSColor colorWithCalibratedRed:0.38 green:0.42 blue:0.48 alpha:0.84];
        icon = @"Ⅱ";
    }

    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    NSRect badge = NSMakeRect(0, 0, size.width, size.height);
    CGFloat cornerRad = size.height * 0.30;
    
    [[NSColor colorWithCalibratedWhite:0 alpha:0.48] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(badge, 0.6, -0.6) xRadius:cornerRad yRadius:cornerRad] fill];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:cornerRad yRadius:cornerRad] fill];
    [[NSColor whiteColor] setStroke];
    NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(badge, 0.4, 0.4) xRadius:cornerRad - 0.4 yRadius:cornerRad - 0.4];
    ring.lineWidth = 0.8;
    [ring stroke];

    // Scale font dynamically based on badge height
    CGFloat fontSize = MAX(6.5, size.height * 0.58);
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize iconSize = [icon sizeWithAttributes:attrs];
    NSRect iconRect = NSMakeRect(NSMidX(badge) - iconSize.width / 2.0,
                                 NSMidY(badge) - iconSize.height / 2.0 - 0.2,
                                 iconSize.width,
                                 iconSize.height);
    [icon drawInRect:iconRect withAttributes:attrs];
    [image unlockFocus];

    self.statusBadgeImages[cacheKey] = image;
    return image;
}

- (void)drawNameplateForPet:(PetInfo *)pet belowSpriteRect:(NSRect)spriteRect {
    [self updateNameplateCacheForPet:pet];
    NSRect plate = [self nameplateRectForPet:pet];
    [pet.nameplateImage drawInRect:plate
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0
                     respectFlipped:NO
                              hints:nil];
}

- (void)drawSprite:(NSImage *)image inRect:(NSRect)rect facing:(CGFloat)facing rotation:(CGFloat)rotation alpha:(CGFloat)alpha {
    if (!image) {
        return;
    }

    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    NSImageInterpolation oldInterpolation = context.imageInterpolation;
    context.imageInterpolation = NSImageInterpolationNone;
    [NSGraphicsContext saveGraphicsState];
    
    if (rotation != 0.0) {
        NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
        NSAffineTransform *rotTransform = [NSAffineTransform transform];
        [rotTransform translateXBy:center.x yBy:center.y];
        [rotTransform rotateByRadians:rotation];
        [rotTransform translateXBy:-center.x yBy:-center.y];
        [rotTransform concat];
    }

    if (facing < 0) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:NSMaxX(rect) yBy:0];
        [transform scaleXBy:-1.0 yBy:1.0];
        [transform concat];
        rect = NSMakeRect(0, rect.origin.y, rect.size.width, rect.size.height);
    }
    
    [image drawInRect:rect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:alpha
       respectFlipped:NO
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationNone)}];
    [NSGraphicsContext restoreGraphicsState];
    context.imageInterpolation = oldInterpolation;
}

- (void)drawFocusHaloInSpriteRect:(NSRect)spriteRect {
    NSRect halo = NSInsetRect(spriteRect, -5.0, -4.0);
    [[NSColor colorWithCalibratedRed:1.00 green:0.78 blue:0.18 alpha:0.22] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:halo] fill];

    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(halo, 2.0, 2.0)];
    ring.lineWidth = 2.0;
    [[NSColor colorWithCalibratedRed:1.00 green:0.86 blue:0.22 alpha:0.88] setStroke];
    [ring stroke];

    NSRect dot = NSMakeRect(NSMidX(spriteRect) - 3.2, NSMaxY(spriteRect) + 1.0, 6.4, 6.4);
    [[NSColor colorWithCalibratedRed:1.00 green:0.86 blue:0.22 alpha:0.96] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
}

- (void)drawHoverDetailsForPet:(PetInfo *)pet inRect:(NSRect)spriteRect {
    NSString *cpuText = [NSString stringWithFormat:@"CPU: %.1f%%", pet.cpu];
    
    NSMutableArray<NSString *> *procList = [NSMutableArray array];
    for (NSString *p in pet.processNames) {
        if (![procList containsObject:p]) {
            [procList addObject:p];
        }
    }
    NSString *procText = procList.count > 0 ? [procList componentsJoinedByString:@", "] : @"none";
    
    NSMutableString *details = [NSMutableString string];
    [details appendFormat:@"%@\n", pet.title];
    [details appendFormat:@"%@  ·  Processes: %@\n", cpuText, procText];
    if (pet.contextText.length > 0) {
        [details appendFormat:@"Context: %@\n", pet.contextText];
    } else if (pet.contextPercentage >= 0) {
        [details appendFormat:@"Context: %ld%%\n", (long)pet.contextPercentage];
    }
    if (pet.lastNotification.length > 0) {
        [details appendFormat:@"Status: %@", pet.lastNotification];
    }
    
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.95 alpha:1.0],
        NSParagraphStyleAttributeName: style
    };
    
    CGFloat panelW = 270.0;
    NSRect textRect = NSMakeRect(0, 0, panelW - 22.0, 160.0);
    NSSize measured = [details boundingRectWithSize:textRect.size
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:attrs].size;
    CGFloat panelH = measured.height + 18.0;
    
    CGFloat x = pet.position.x - panelW / 2.0;
    x = MIN(MAX(x, 10.0), self.bounds.size.width - panelW - 10.0);
    CGFloat y = NSMaxY(spriteRect) + 12.0;
    
    NSRect panelRect = NSMakeRect(x, y, panelW, panelH);
    
    [NSGraphicsContext saveGraphicsState];
    // Sleek dark panel with a soft white glow border
    [[NSColor colorWithCalibratedWhite:0.04 alpha:0.90] setFill];
    [[NSColor colorWithCalibratedWhite:0.25 alpha:0.80] setStroke];
    NSBezierPath *borderPath = [NSBezierPath bezierPathWithRoundedRect:panelRect xRadius:8.0 yRadius:8.0];
    [borderPath fill];
    borderPath.lineWidth = 1.0;
    [borderPath stroke];
    
    // Top accent indicator line matching pet provider
    NSRect accentStrip = NSMakeRect(x + 8.0, y + panelH - 3.0, panelW - 16.0, 3.0);
    [[self accentColorForPet:pet alpha:0.92] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:accentStrip xRadius:1.5 yRadius:1.5] fill];
    
    [NSGraphicsContext restoreGraphicsState];
    
    [details drawInRect:NSInsetRect(panelRect, 11.0, 9.0) withAttributes:attrs];
}

- (void)drawPet:(PetInfo *)pet {
    CGFloat s = pet.size;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    BOOL ended = [pet.status isEqualToString:@"ended"];
    BOOL isSleeping = (now - pet.lastActiveAt > 20.0);
    
    // Calculate bobbing, squash/stretch and celebration bounce
    CGFloat bob = sin(pet.bobPhase) * 1.4;
    CGFloat squashX = 1.0;
    CGFloat squashY = 1.0;
    
    if (pet.alerting) {
        // Celebratory platformer-style bounce
        CGFloat bounceVal = sin(pet.bobPhase * 1.8);
        bob = -fabs(bounceVal) * 18.0;
        
        if (bounceVal < -0.1) {
            // Stretching up in the air
            squashX = 0.88;
            squashY = 1.12;
        } else {
            // Squashing flat on landing
            squashX = 1.16;
            squashY = 0.84;
        }
    } else if (isSleeping) {
        // Sleep breathing (very slow bobbing and subtle scaling)
        bob = sin(pet.bobPhase) * 0.6;
        squashX = 1.0 + sin(pet.bobPhase) * 0.03;
        squashY = 1.0 - sin(pet.bobPhase) * 0.03;
    }
    
    NSRect body = NSMakeRect(pet.position.x - (s * squashX) / 2.0, pet.position.y - (s * squashY) / 2.0 + bob, s * squashX, s * squashY);
    
    // Choose sprite frame based on state and animation speed
    NSImage *sprite = nil;
    if (self.frontSpriteFrames.count > 0) {
        double stagger = (double)(pet.slotIndex * 0.17);
        double animSpeed = 8.0;
        if (ended || pet.tokenExpired) {
            animSpeed = 0.0;
        } else if (isSleeping) {
            animSpeed = 2.0; // Slow breathing rate
        } else {
            if ([pet.state isEqualToString:@"working"]) {
                animSpeed = 15.0; // Fast walking/running animation
            } else {
                animSpeed = 7.0;  // Normal wandering animation
            }
            // Adjust foot-stepping speed to match actual Ground Speed (speedScale)
            CGFloat speedScale = 16.0 / MAX(1.0, pet.size);
            speedScale = MIN(2.2, MAX(0.5, speedScale));
            animSpeed *= speedScale;
        }
        
        NSInteger frameIndex = 0;
        if (animSpeed > 0.0) {
            frameIndex = (NSInteger)((now + stagger) * animSpeed) % self.frontSpriteFrames.count;
        }
        sprite = self.frontSpriteFrames[frameIndex];
    } else {
        sprite = self.frontSprite;
    }
    
    if (sprite) {
        CGFloat spriteScale = 1.9;
        NSRect shadow = NSMakeRect(NSMidX(body) - s * 0.44,
                                   NSMinY(body) - s * 0.12,
                                   s * 0.88,
                                   s * 0.18);
        [[NSColor colorWithCalibratedWhite:0 alpha:ended ? 0.10 : 0.18] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:shadow] fill];

        NSRect spriteRect = NSMakeRect(NSMidX(body) - (s * squashX * spriteScale) / 2.0,
                                       NSMinY(body) - s * squashY * 0.28,
                                       s * squashX * spriteScale,
                                       s * squashY * spriteScale);
        if (pet.alerting) {
            [[self accentColorForPet:pet alpha:0.20] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(spriteRect, -4.0, -3.0)] fill];
        }
        if (pet.focused && !ended) {
            [self drawFocusHaloInSpriteRect:spriteRect];
        }
        CGFloat rotation = pet.tokenExpired ? (pet.facing >= 0 ? -M_PI_2 : M_PI_2) : 0.0;
        if (pet.tokenExpired) {
            spriteRect.origin.y -= s * 0.15;
        }
        [self drawSprite:sprite inRect:spriteRect facing:pet.facing rotation:rotation alpha:ended ? 0.38 : 0.92];
        [self drawStatusBadgeForPet:pet inRect:spriteRect];
        [self drawNameplateForPet:pet belowSpriteRect:spriteRect];
        
        // Zzz floating bubbles if sleeping
        if (isSleeping && !ended) {
            double stagger = (double)(pet.slotIndex * 0.17);
            double zOffset = fmod((now + stagger) * 1.5, 1.0);
            CGFloat zX = pet.position.x + s * 0.34 + zOffset * 8.0;
            CGFloat zY = pet.position.y + s * 0.45 + bob + zOffset * 22.0;
            CGFloat zAlpha = (zOffset < 0.2) ? (zOffset / 0.2) : (1.0 - zOffset);
            
            NSString *zText = (zOffset < 0.33) ? @"z" : ((zOffset < 0.66) ? @"zz" : @"zZz");
            NSDictionary *zAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:7.5 + zOffset * 4.5 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.75 green:0.88 blue:1.0 alpha:zAlpha * 0.88]
            };
            [zText drawAtPoint:NSMakePoint(zX, zY) withAttributes:zAttrs];
        }

        if (self.hoveredPet == pet) {
            [self drawHoverDetailsForPet:pet inRect:spriteRect];
        }
        
        return;
    }

    NSColor *base = ended
        ? [NSColor colorWithCalibratedRed:0.50 green:0.45 blue:0.50 alpha:0.42]
        : [NSColor colorWithCalibratedRed:1.00 green:0.56 blue:0.76 alpha:0.86];
    NSColor *edge = ended
        ? [NSColor colorWithCalibratedWhite:0.22 alpha:0.40]
        : [NSColor colorWithCalibratedRed:0.80 green:0.25 blue:0.48 alpha:0.72];
    NSColor *innerEar = ended
        ? [NSColor colorWithCalibratedWhite:0.10 alpha:0.38]
        : [NSColor colorWithCalibratedRed:0.18 green:0.16 blue:0.25 alpha:0.74];

    [[NSColor colorWithCalibratedWhite:0 alpha:0.18] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(body) - s * 0.42,
                                                       NSMinY(body) - s * 0.14,
                                                       s * 0.84,
                                                       s * 0.18)] fill];

    NSBezierPath *leftEar = [NSBezierPath bezierPath];
    [leftEar moveToPoint:NSMakePoint(NSMinX(body) + s * 0.17, NSMaxY(body) - s * 0.14)];
    [leftEar lineToPoint:NSMakePoint(NSMinX(body) + s * 0.30, NSMaxY(body) + s * 0.23)];
    [leftEar lineToPoint:NSMakePoint(NSMinX(body) + s * 0.49, NSMaxY(body) - s * 0.04)];
    [leftEar closePath];
    [base setFill];
    [leftEar fill];
    [edge setStroke];
    leftEar.lineWidth = 1.0;
    [leftEar stroke];

    NSBezierPath *rightEar = [NSBezierPath bezierPath];
    [rightEar moveToPoint:NSMakePoint(NSMaxX(body) - s * 0.17, NSMaxY(body) - s * 0.14)];
    [rightEar lineToPoint:NSMakePoint(NSMaxX(body) - s * 0.30, NSMaxY(body) + s * 0.23)];
    [rightEar lineToPoint:NSMakePoint(NSMaxX(body) - s * 0.49, NSMaxY(body) - s * 0.04)];
    [rightEar closePath];
    [base setFill];
    [rightEar fill];
    [edge setStroke];
    rightEar.lineWidth = 1.0;
    [rightEar stroke];

    [innerEar setFill];
    NSRect innerA = NSMakeRect(NSMinX(body) + s * 0.28, NSMaxY(body) - s * 0.03, s * 0.12, s * 0.14);
    NSRect innerB = NSMakeRect(NSMaxX(body) - s * 0.40, NSMaxY(body) - s * 0.03, s * 0.12, s * 0.14);
    [[NSBezierPath bezierPathWithOvalInRect:innerA] fill];
    [[NSBezierPath bezierPathWithOvalInRect:innerB] fill];

    [base setFill];
    [[NSBezierPath bezierPathWithOvalInRect:body] fill];
    [edge setStroke];
    NSBezierPath *bodyPath = [NSBezierPath bezierPathWithOvalInRect:body];
    bodyPath.lineWidth = 1.0;
    [bodyPath stroke];

    [[self colorForProvider:pet.provider alpha:ended ? 0.30 : 0.62] setFill];
    CGFloat dotX = pet.facing >= 0 ? NSMaxX(body) - s * 0.18 : NSMinX(body) + s * 0.08;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, NSMinY(body) + s * 0.16, s * 0.10, s * 0.10)] fill];

    [[NSColor colorWithCalibratedRed:0.92 green:0.42 blue:0.62 alpha:ended ? 0.22 : 0.56] setFill];
    NSRect armA = NSMakeRect(NSMinX(body) - s * 0.05, NSMidY(body) - s * 0.02, s * 0.18, s * 0.11);
    NSRect armB = NSMakeRect(NSMaxX(body) - s * 0.13, NSMidY(body) - s * 0.02, s * 0.18, s * 0.11);
    [[NSBezierPath bezierPathWithOvalInRect:armA] fill];
    [[NSBezierPath bezierPathWithOvalInRect:armB] fill];

    [[NSColor colorWithCalibratedRed:0.38 green:0.76 blue:0.90 alpha:ended ? 0.28 : 0.90] setFill];
    NSRect eyeA = NSMakeRect(NSMidX(body) - s * 0.27, NSMidY(body) + s * 0.02, s * 0.17, s * 0.23);
    NSRect eyeB = NSMakeRect(NSMidX(body) + s * 0.10, NSMidY(body) + s * 0.02, s * 0.17, s * 0.23);
    [[NSBezierPath bezierPathWithOvalInRect:eyeA] fill];
    [[NSBezierPath bezierPathWithOvalInRect:eyeB] fill];

    [[NSColor colorWithCalibratedWhite:1 alpha:ended ? 0.30 : 0.92] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(eyeA) + s * 0.04, NSMaxY(eyeA) - s * 0.08, s * 0.05, s * 0.05)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(eyeB) + s * 0.04, NSMaxY(eyeB) - s * 0.08, s * 0.05, s * 0.05)] fill];

    [[NSColor colorWithCalibratedRed:0.74 green:0.18 blue:0.37 alpha:ended ? 0.24 : 0.56] setStroke];
    NSBezierPath *curl = [NSBezierPath bezierPath];
    [curl moveToPoint:NSMakePoint(NSMidX(body) - s * 0.01, NSMaxY(body) - s * 0.03)];
    [curl curveToPoint:NSMakePoint(NSMidX(body) - s * 0.16, NSMaxY(body) - s * 0.10)
         controlPoint1:NSMakePoint(NSMidX(body) - s * 0.16, NSMaxY(body) + s * 0.11)
         controlPoint2:NSMakePoint(NSMidX(body) - s * 0.25, NSMaxY(body) - s * 0.02)];
    [curl curveToPoint:NSMakePoint(NSMidX(body) + s * 0.05, NSMaxY(body) - s * 0.17)
         controlPoint1:NSMakePoint(NSMidX(body) - s * 0.02, NSMaxY(body) - s * 0.20)
         controlPoint2:NSMakePoint(NSMidX(body) + s * 0.15, NSMaxY(body) - s * 0.18)];
    curl.lineWidth = MAX(1.3, s * 0.07);
    [curl stroke];

    [[NSColor colorWithCalibratedRed:0.54 green:0.14 blue:0.25 alpha:ended ? 0.22 : 0.48] setStroke];
    NSBezierPath *mouth = [NSBezierPath bezierPath];
    [mouth moveToPoint:NSMakePoint(NSMidX(body) - s * 0.05, NSMidY(body) - s * 0.14)];
    [mouth curveToPoint:NSMakePoint(NSMidX(body) + s * 0.05, NSMidY(body) - s * 0.14)
          controlPoint1:NSMakePoint(NSMidX(body) - s * 0.02, NSMidY(body) - s * 0.19)
          controlPoint2:NSMakePoint(NSMidX(body) + s * 0.02, NSMidY(body) - s * 0.19)];
    mouth.lineWidth = 1.0;
    [mouth stroke];

    [[NSColor colorWithCalibratedWhite:0 alpha:ended ? 0.16 : 0.26] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(body) + s * 0.17, NSMinY(body) - s * 0.04, s * 0.22, s * 0.08)
                                     xRadius:s * 0.04
                                     yRadius:s * 0.04] fill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMaxX(body) - s * 0.39, NSMinY(body) - s * 0.04, s * 0.22, s * 0.08)
                                     xRadius:s * 0.04
                                     yRadius:s * 0.04] fill];

    NSString *labelBase = [self shortTitle:pet.title ?: pet.provider ?: @"cmux"];
    NSString *label = labelBase;
    [self drawOutlinedText:label centeredAtX:pet.position.x y:pet.position.y - s / 2.0 - 17 size:10.0];
}

- (void)drawAlertBubble {
    AlertInfo *alert = self.alerts.lastObject;
    if (!alert) {
        return;
    }
    NSPoint cursor = [self.window convertPointFromScreen:NSEvent.mouseLocation];
    if (cursor.x < -10 || cursor.x > self.bounds.size.width + 10) {
        return;
    }
    NSString *body = alert.body.length > 0 ? alert.body : @"작업 알림이 도착했습니다.";
    if (body.length > 80) {
        body = [[body substringToIndex:79] stringByAppendingString:@"…"];
    }
    NSString *title = alert.title.length > 0 ? alert.title : @"cmux";
    NSString *prefix = [alert.kind isEqualToString:@"ended"] ? @"종료" : @"완료";
    NSString *text = [NSString stringWithFormat:@"%@: %@\n%@", prefix, title, body];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSParagraphStyleAttributeName: style
    };

    CGFloat width = 280;
    NSRect textRect = NSMakeRect(0, 0, width - 24, 68);
    NSSize measured = [text boundingRectWithSize:textRect.size
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:attrs].size;
    CGFloat bubbleW = MIN(width, measured.width + 28);
    CGFloat bubbleH = measured.height + 24;
    NSRect walkArea = [self walkAreaForPetSize:SharedConfig().petMaxSize];
    CGFloat x = MIN(MAX(cursor.x - bubbleW / 2.0, 14), self.bounds.size.width - bubbleW - 14);
    CGFloat y = MIN(MAX(NSMaxY(walkArea) + 8, 14), self.bounds.size.height - bubbleH - 14);
    NSRect bubble = NSMakeRect(x, y, bubbleW, bubbleH);

    [[NSColor colorWithCalibratedWhite:0.06 alpha:0.62] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bubble xRadius:10 yRadius:10] fill];

    [[self colorForProvider:alert.provider alpha:0.90] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(bubble) + 10, NSMaxY(bubble) - 22, 10, 10)] fill];

    [text drawInRect:NSInsetRect(bubble, 14, 10) withAttributes:attrs];
}

- (void)drawStateRail {
    if (!SharedConfig().showStateRail || self.bounds.size.width < 280.0) {
        return;
    }

    NSString *signature = [NSString stringWithFormat:@"%.0f|%.3f|%.3f",
                           self.bounds.size.width,
                           SharedConfig().preworkAreaRatio,
                           SharedConfig().workingAreaRatio];
    if (!self.stateRailImage || ![self.stateRailSignature isEqualToString:signature]) {
        [self rebuildStateRailImageWithSignature:signature];
    }

    [self.stateRailImage drawInRect:[self stateRailDirtyRect]
                            fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver
                            fraction:1.0
                      respectFlipped:NO
                               hints:nil];
}

- (void)rebuildStateRailImageWithSignature:(NSString *)signature {
    CGFloat width = self.bounds.size.width;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, 26.0)];
    [image lockFocus];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, width, 26.0));

    CGFloat usableWidth = MAX(1.0, self.bounds.size.width - 36.0);
    
    // Partition usableWidth into 3 lanes: 시작전 (30%), 작업중 (38%), 완료/실패 (26%)
    // with two 3% gaps between them.
    CGFloat leftWidth = usableWidth * 0.30;
    CGFloat middleWidth = usableWidth * 0.38;
    CGFloat rightWidth = usableWidth * 0.26;
    
    CGFloat leftStart = 18.0;
    CGFloat middleStart = 18.0 + leftWidth + usableWidth * 0.03;
    CGFloat rightStart = 18.0 + usableWidth - rightWidth;
    
    CGFloat y = 6.0;
    CGFloat h = 14.0;
    NSRect leftRail = NSMakeRect(leftStart, y, leftWidth, h);
    NSRect middleRail = NSMakeRect(middleStart, y, middleWidth, h);
    NSRect rightRail = NSMakeRect(rightStart, y, rightWidth, h);

    // Draw background pills
    [[NSColor colorWithCalibratedWhite:0 alpha:0.20] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:leftRail xRadius:5.0 yRadius:5.0] fill];
    [[NSBezierPath bezierPathWithRoundedRect:middleRail xRadius:5.0 yRadius:5.0] fill];
    [[NSBezierPath bezierPathWithRoundedRect:rightRail xRadius:5.0 yRadius:5.0] fill];

    // Left Rail top line (시작전 - Gray/Blue)
    [[NSColor colorWithCalibratedRed:0.38 green:0.42 blue:0.48 alpha:0.82] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(leftRail), NSMinY(leftRail), NSWidth(leftRail), 3.0)
                                     xRadius:2.0
                                     yRadius:2.0] fill];
                                     
    // Middle Rail top line (작업중 - Orange/Lightning)
    [[NSColor colorWithCalibratedRed:0.95 green:0.43 blue:0.08 alpha:0.90] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(middleRail), NSMinY(middleRail), NSWidth(middleRail), 3.0)
                                     xRadius:2.0
                                     yRadius:2.0] fill];

    // Right Rail top line (완료/실패 - Green)
    [[NSColor colorWithCalibratedRed:0.12 green:0.66 blue:0.36 alpha:0.90] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(rightRail), NSMinY(rightRail), NSWidth(rightRail), 3.0)
                                     xRadius:2.0
                                     yRadius:2.0] fill];

    [self drawOutlinedText:[NSString stringWithFormat:@"Ⅱ %@", LocalizedStr(@"prework")] centeredAtX:NSMidX(leftRail) y:NSMinY(leftRail) + 1.0 size:9.0];
    [self drawOutlinedText:[NSString stringWithFormat:@"⚡ %@", LocalizedStr(@"working")] centeredAtX:NSMidX(middleRail) y:NSMinY(middleRail) + 1.0 size:9.0];
    [self drawOutlinedText:[NSString stringWithFormat:@"✓ %@", LocalizedStr(@"done")] centeredAtX:NSMidX(rightRail) y:NSMinY(rightRail) + 1.0 size:9.0];
    [image unlockFocus];

    self.stateRailImage = image;
    self.stateRailSignature = signature;
}

- (BOOL)rect:(NSRect)rect intersectsDirtyRects:(const NSRect *)rects count:(NSInteger)count fallback:(NSRect)fallback {
    if (count <= 0 || !rects) {
        return NSIntersectsRect(rect, fallback);
    }
    for (NSInteger i = 0; i < count; i++) {
        if (NSIntersectsRect(rect, rects[i])) {
            return YES;
        }
    }
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    const NSRect *dirtyRects = NULL;
    NSInteger dirtyCount = 0;
    [self getRectsBeingDrawn:&dirtyRects count:&dirtyCount];
    // Bottom state rail disabled per user request
    if (NO && [self rect:[self stateRailDirtyRect] intersectsDirtyRects:dirtyRects count:dirtyCount fallback:dirtyRect]) {
        [self drawStateRail];
    }
    for (PetInfo *pet in [self petsInDrawOrder]) {
        if (![self rect:[self dirtyRectForPet:pet] intersectsDirtyRects:dirtyRects count:dirtyCount fallback:dirtyRect]) {
            continue;
        }
        [self drawPet:pet];
    }
    if (self.alerts.count > 0 &&
        [self rect:[self alertDirtyRect] intersectsDirtyRects:dirtyRects count:dirtyCount fallback:dirtyRect]) {
        [self drawAlertBubble];
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    CGFloat _lastPollInterval;
    BOOL _paused;
}
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) OverlayView *overlayView;
@property(nonatomic, strong) NSMutableArray<NSWindow *> *windows;
@property(nonatomic, strong) NSMutableArray<OverlayView *> *overlayViews;
@property(nonatomic, strong) CmuxStateReader *reader;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) dispatch_queue_t pollQueue;
@property(nonatomic) BOOL pollInFlight;
@property(nonatomic) BOOL demoAlert;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic) BOOL overlayEnabled;
@property(nonatomic) NSInteger screenMode; // 0: Main Screen, 1: Leftmost Screen, 2: All Screens, 3: Center Screen
- (void)rebuildOverlays;
- (void)rebuildMenu;
- (NSScreen *)centerScreen;
@end

@implementation AppDelegate

- (instancetype)initWithDemoAlert:(BOOL)demoAlert {
    self = [super init];
    if (self) {
        _demoAlert = demoAlert;
    }
    return self;
}

- (NSRect)desktopFrame {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) {
        return NSScreen.mainScreen.frame;
    }

    NSRect frame = screens.firstObject.frame;
    for (NSScreen *screen in screens) {
        frame = NSUnionRect(frame, screen.frame);
    }
    return frame;
}

- (NSScreen *)leftmostScreen {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) {
        return NSScreen.mainScreen;
    }

    NSScreen *leftmost = screens.firstObject;
    for (NSScreen *screen in screens) {
        CGFloat screenX = NSMinX(screen.frame);
        CGFloat leftmostX = NSMinX(leftmost.frame);
        if (screenX < leftmostX ||
            (screenX == leftmostX && NSMinY(screen.frame) < NSMinY(leftmost.frame))) {
            leftmost = screen;
        }
    }
    return leftmost;
}

- (void)addOverlayForFrame:(NSRect)frame {
    CGFloat height = MIN(SharedConfig().overlayBandHeight, frame.size.height);
    NSRect overlayFrame = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:overlayFrame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.ignoresMouseEvents = YES;
    window.level = NSScreenSaverWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorStationary |
                                NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorIgnoresCycle;
    [window setReleasedWhenClosed:NO];

    OverlayView *overlayView = [[OverlayView alloc] initWithFrame:NSMakeRect(0, 0, overlayFrame.size.width, overlayFrame.size.height)];
    overlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = overlayView;
    [window orderFrontRegardless];

    [self.windows addObject:window];
    [self.overlayViews addObject:overlayView];

    if (!self.window) {
        self.window = window;
        self.overlayView = overlayView;
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    
    _overlayEnabled = YES;
    _screenMode = 1; // Default to 1: Leftmost Screen
    
    self.reader = [[CmuxStateReader alloc] init];
    self.pollQueue = dispatch_queue_create("com.neogenesis.cmux-pet-overlay.poll", DISPATCH_QUEUE_SERIAL);
    self.windows = [NSMutableArray array];
    self.overlayViews = [NSMutableArray array];

    // Setup Status Item Menu Bar Icon
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🍮"; // Mochi emoji icon
    [self rebuildMenu];

    // Register Distributed Notification Observer for CLI toggling
    _lastPollInterval = SharedConfig().pollIntervalSeconds;
    _paused = NO;

    // Register Distributed Notification Observer for CLI toggling
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                     selector:@selector(handleToggleNotification:)
                                                         name:@"com.neogenesis.cmux-pet-overlay.toggle"
                                                       object:nil];
    
    // Register Distributed Notification Observer for CLI screen switching
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                     selector:@selector(handleScreenModeNotification:)
                                                         name:@"com.neogenesis.cmux-pet-overlay.screenMode"
                                                       object:nil];

    // Enterprise Feature: Register system sleep/wake and screen lock/unlock observers for extreme battery saving
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(handleSystemSleep:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(handleSystemWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(handleScreenLock:)
                                                            name:@"com.apple.screenIsLocked"
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(handleScreenUnlock:)
                                                            name:@"com.apple.screenIsUnlocked"
                                                          object:nil];

    [self rebuildOverlays];

    [self poll:nil];
    self.pollTimer = [NSTimer timerWithTimeInterval:SharedConfig().pollIntervalSeconds
                                             target:self
                                           selector:@selector(poll:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];

    if (self.demoAlert) {
        AlertInfo *alert = [[AlertInfo alloc] init];
        alert.key = @"demo";
        alert.title = @"cmux pet overlay";
        alert.body = @"데모 알림입니다. 커서 근처에 표시됩니다.";
        alert.provider = @"codex";
        alert.kind = @"notification";
        alert.createdAt = NSDate.date.timeIntervalSince1970;
        for (OverlayView *overlayView in self.overlayViews) {
            [overlayView addAlerts:@[alert]];
            [overlayView addDemoEndedPet];
        }
    }
}

- (void)handleSystemSleep:(NSNotification *)note {
    [self pauseWork];
}

- (void)handleSystemWake:(NSNotification *)note {
    [self resumeWork];
}

- (void)handleScreenLock:(NSNotification *)note {
    [self pauseWork];
}

- (void)handleScreenUnlock:(NSNotification *)note {
    [self resumeWork];
}

- (void)pauseWork {
    if (_paused) return;
    _paused = YES;
    
    // Invalidate main polling timer
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    
    // Freeze all overlays animations to save CPU/GPU cycles
    for (OverlayView *overlayView in self.overlayViews) {
        [overlayView pauseAnimation];
    }
}

- (void)resumeWork {
    if (!_paused) return;
    _paused = NO;
    
    // Reload configurations fresh
    [SharedConfig() loadFromDisk];
    _lastPollInterval = SharedConfig().pollIntervalSeconds;
    
    // Restart poll timer
    self.pollTimer = [NSTimer timerWithTimeInterval:SharedConfig().pollIntervalSeconds
                                             target:self
                                           selector:@selector(poll:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    
    // Unfreeze all animations
    for (OverlayView *overlayView in self.overlayViews) {
        [overlayView resumeAnimation];
    }
    
    [self poll:nil];
}

- (void)poll:(NSTimer *)timer {
    if (_paused) {
        return;
    }
    
    // Enterprise Feature: Auto-reload config file in real-time
    [SharedConfig() loadFromDisk];
    
    // Dynamically hot-swap poll timer interval if config changes
    if (fabs(_lastPollInterval - SharedConfig().pollIntervalSeconds) > 0.05) {
        _lastPollInterval = SharedConfig().pollIntervalSeconds;
        [self.pollTimer invalidate];
        self.pollTimer = [NSTimer timerWithTimeInterval:_lastPollInterval
                                                 target:self
                                               selector:@selector(poll:)
                                               userInfo:nil
                                                repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    }

    if (self.pollInFlight) {
        return;
    }
    self.pollInFlight = YES;

    __weak AppDelegate *weakSelf = self;
    dispatch_async(self.pollQueue, ^{
        AppDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSArray<SessionInfo *> *sessions = [strongSelf.reader readSessions];
        NSArray<AlertInfo *> *endedAlerts = [strongSelf.reader trackEndedSessionsFromActiveSessions:sessions];
        NSArray<AlertInfo *> *alerts = [strongSelf.reader readNewAlerts];

        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainSelf = weakSelf;
            if (!mainSelf) {
                return;
            }
            NSUInteger viewCount = MAX((NSUInteger)1, mainSelf.overlayViews.count);
            for (NSUInteger i = 0; i < mainSelf.overlayViews.count; i++) {
                OverlayView *overlayView = mainSelf.overlayViews[i];
                NSArray<SessionInfo *> *assignedSessions = [mainSelf sessions:sessions forBucket:i bucketCount:viewCount];
                NSArray<AlertInfo *> *assignedEndedAlerts = [mainSelf alerts:endedAlerts forBucket:i bucketCount:viewCount];
                [overlayView addAlerts:assignedEndedAlerts];
                [overlayView updateSessions:assignedSessions];
                [overlayView addAlerts:alerts];
            }
            mainSelf.pollInFlight = NO;
        });
    });
}

- (NSUInteger)bucketForSurfaceKey:(NSString *)surfaceKey bucketCount:(NSUInteger)bucketCount {
    if (bucketCount <= 1 || surfaceKey.length == 0) {
        return 0;
    }

    NSScanner *scanner = [NSScanner scannerWithString:surfaceKey];
    [scanner scanUpToString:@":" intoString:nil];
    if (!scanner.isAtEnd) {
        [scanner scanString:@":" intoString:nil];
    }

    NSInteger value = 0;
    if ([scanner scanInteger:&value]) {
        return (NSUInteger)llabs((long long)value) % bucketCount;
    }
    return surfaceKey.hash % bucketCount;
}

- (NSArray<SessionInfo *> *)sessions:(NSArray<SessionInfo *> *)sessions
                            forBucket:(NSUInteger)bucket
                          bucketCount:(NSUInteger)bucketCount {
    if (bucketCount <= 1) {
        return sessions;
    }

    NSMutableArray<SessionInfo *> *result = [NSMutableArray array];
    for (SessionInfo *session in sessions) {
        if ([self bucketForSurfaceKey:session.key bucketCount:bucketCount] == bucket) {
            [result addObject:session];
        }
    }
    return result;
}

- (NSArray<AlertInfo *> *)alerts:(NSArray<AlertInfo *> *)alerts
                       forBucket:(NSUInteger)bucket
                     bucketCount:(NSUInteger)bucketCount {
    if (bucketCount <= 1) {
        return alerts;
    }

    NSMutableArray<AlertInfo *> *result = [NSMutableArray array];
    for (AlertInfo *alert in alerts) {
        if (alert.surfaceKey.length == 0 || [self bucketForSurfaceKey:alert.surfaceKey bucketCount:bucketCount] == bucket) {
            [result addObject:alert];
        }
    }
    return result;
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"🍮 cmux 펫 오버레이" action:nil keyEquivalent:@""];
    titleItem.enabled = NO;
    [menu addItem:titleItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:@"오버레이 활성화" action:@selector(toggleOverlay:) keyEquivalent:@""];
    toggleItem.state = self.overlayEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:toggleItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *screenMenu = [[NSMenuItem alloc] initWithTitle:@"표시 화면 설정" action:nil keyEquivalent:@""];
    NSMenu *subMenu = [[NSMenu alloc] init];
    
    NSMenuItem *centerScreenItem = [[NSMenuItem alloc] initWithTitle:@"중앙 모니터 (Center)" action:@selector(setScreenModeCenter:) keyEquivalent:@""];
    centerScreenItem.state = (self.screenMode == 3) ? NSControlStateValueOn : NSControlStateValueOff;
    [subMenu addItem:centerScreenItem];

    NSMenuItem *mainScreenItem = [[NSMenuItem alloc] initWithTitle:@"메인 모니터 (현재 작업 화면)" action:@selector(setScreenModeMain:) keyEquivalent:@""];
    mainScreenItem.state = (self.screenMode == 0) ? NSControlStateValueOn : NSControlStateValueOff;
    [subMenu addItem:mainScreenItem];
    
    NSMenuItem *leftScreenItem = [[NSMenuItem alloc] initWithTitle:@"가장 왼쪽 모니터" action:@selector(setScreenModeLeftmost:) keyEquivalent:@""];
    leftScreenItem.state = (self.screenMode == 1) ? NSControlStateValueOn : NSControlStateValueOff;
    [subMenu addItem:leftScreenItem];
    
    NSMenuItem *allScreenItem = [[NSMenuItem alloc] initWithTitle:@"모든 모니터" action:@selector(setScreenModeAll:) keyEquivalent:@""];
    allScreenItem.state = (self.screenMode == 2) ? NSControlStateValueOn : NSControlStateValueOff;
    [subMenu addItem:allScreenItem];
    
    screenMenu.submenu = subMenu;
    [menu addItem:screenMenu];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"종료" action:@selector(terminate:) keyEquivalent:@"q"];
    [menu addItem:quitItem];
    
    self.statusItem.menu = menu;
}

- (void)toggleOverlay:(id)sender {
    self.overlayEnabled = !self.overlayEnabled;
    for (NSWindow *window in self.windows) {
        if (self.overlayEnabled) {
            [window orderFrontRegardless];
        } else {
            [window orderOut:nil];
        }
    }
    [self rebuildMenu];
}

- (void)setScreenModeMain:(id)sender {
    self.screenMode = 0;
    [self rebuildOverlays];
    [self rebuildMenu];
}

- (void)setScreenModeLeftmost:(id)sender {
    self.screenMode = 1;
    [self rebuildOverlays];
    [self rebuildMenu];
}

- (void)setScreenModeAll:(id)sender {
    self.screenMode = 2;
    [self rebuildOverlays];
    [self rebuildMenu];
}

- (void)setScreenModeCenter:(id)sender {
    self.screenMode = 3;
    [self rebuildOverlays];
    [self rebuildMenu];
}

- (void)terminate:(id)sender {
    [NSApp terminate:nil];
}

- (NSScreen *)centerScreen {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) {
        return nil;
    }
    if (screens.count < 3) {
        return NSScreen.mainScreen;
    }
    
    // Sort screens by their horizontal midpoint (NSMidX)
    NSArray<NSScreen *> *sorted = [screens sortedArrayUsingComparator:^NSComparisonResult(NSScreen *a, NSScreen *b) {
        CGFloat midA = NSMidX(a.frame);
        CGFloat midB = NSMidX(b.frame);
        if (midA < midB) return NSOrderedAscending;
        if (midA > midB) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // Return the middle screen (index 1 for 3 screens)
    return sorted[sorted.count / 2];
}

- (void)rebuildOverlays {
    // Close old windows
    for (NSWindow *window in self.windows) {
        [window close];
    }
    [self.windows removeAllObjects];
    [self.overlayViews removeAllObjects];
    self.window = nil;
    self.overlayView = nil;
    
    // Setup screens based on screenMode
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (self.screenMode == 0) {
        // Main Screen
        NSScreen *screen = NSScreen.mainScreen;
        if (screen) {
            [self addOverlayForFrame:screen.visibleFrame];
        } else {
            [self addOverlayForFrame:[self desktopFrame]];
        }
    } else if (self.screenMode == 1) {
        // Leftmost Screen
        NSScreen *screen = [self leftmostScreen];
        if (screen) {
            [self addOverlayForFrame:screen.visibleFrame];
        } else {
            [self addOverlayForFrame:[self desktopFrame]];
        }
    } else if (self.screenMode == 3) {
        // Center Screen
        NSScreen *screen = [self centerScreen];
        if (screen) {
            [self addOverlayForFrame:screen.visibleFrame];
        } else {
            [self addOverlayForFrame:[self desktopFrame]];
        }
    } else {
        // All Screens
        for (NSScreen *screen in screens) {
            [self addOverlayForFrame:screen.visibleFrame];
        }
    }
    
    // Make sure they respect the visibility setting
    for (NSWindow *window in self.windows) {
        if (self.overlayEnabled) {
            [window orderFrontRegardless];
        } else {
            [window orderOut:nil];
        }
    }
}

- (void)handleToggleNotification:(NSNotification *)note {
    NSString *action = note.userInfo[@"action"];
    if ([action isEqualToString:@"on"]) {
        self.overlayEnabled = YES;
    } else if ([action isEqualToString:@"off"]) {
        self.overlayEnabled = NO;
    } else {
        self.overlayEnabled = !self.overlayEnabled;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *window in self.windows) {
            if (self.overlayEnabled) {
                [window orderFrontRegardless];
            } else {
                [window orderOut:nil];
            }
        }
        [self rebuildMenu];
    });
}

- (void)handleScreenModeNotification:(NSNotification *)note {
    NSString *mode = note.userInfo[@"mode"];
    if ([mode isEqualToString:@"main"]) {
        self.screenMode = 0;
    } else if ([mode isEqualToString:@"leftmost"]) {
        self.screenMode = 1;
    } else if ([mode isEqualToString:@"center"]) {
        self.screenMode = 3;
    } else if ([mode isEqualToString:@"all"]) {
        self.screenMode = 2;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rebuildOverlays];
        [self rebuildMenu];
    });
}

@end

static int TestCompletionVoice(void) {
    NSString *path = ProjectResolvedPath(SharedConfig().completionVoicePath);
    NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
    BOOL enabled = SharedConfig().completionVoiceEnabled;
    BOOL played = NO;
    if (enabled && sound) {
        sound.volume = SharedConfig().completionVoiceVolume;
        played = [sound play];
        if (played) {
            NSTimeInterval wait = sound.duration > 0 ? MIN(sound.duration + 0.15, 1.2) : 0.55;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:wait]];
        }
    }

    NSDictionary *payload = @{
        @"enabled": @(enabled),
        @"played": @(played),
        @"path": path ?: @"",
        @"volume": @(SharedConfig().completionVoiceVolume)
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    printf("%s\n", text.UTF8String);
    return played ? 0 : 2;
}

static int TestSoundEffects(void) {
    NSArray<NSDictionary *> *items = @[
        @{@"event": @"drag-start", @"name": SharedConfig().dragStartSoundName ?: @""},
        @{@"event": @"drag-drop", @"name": SharedConfig().dragDropSoundName ?: @""},
        @{@"event": @"focus", @"name": SharedConfig().focusSoundName ?: @""},
        @{@"event": @"completion-fallback", @"name": SharedConfig().completionSoundName ?: @""}
    ];
    BOOL enabled = SharedConfig().soundEffectsEnabled;
    NSUInteger playedCount = 0;
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:items.count];

    for (NSDictionary *item in items) {
        NSString *name = item[@"name"] ?: @"";
        BOOL played = enabled && PlayNamedSystemSound(name, SharedConfig().soundEffectsVolume, 0.18);
        if (played) {
            playedCount++;
        }
        [results addObject:@{
            @"event": item[@"event"] ?: @"",
            @"name": name,
            @"played": @(played)
        }];
    }

    NSDictionary *payload = @{
        @"enabled": @(enabled),
        @"playedCount": @(playedCount),
        @"volume": @(SharedConfig().soundEffectsVolume),
        @"cooldownSeconds": @(SharedConfig().soundEffectsCooldownSeconds),
        @"results": results
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    printf("%s\n", text.UTF8String);
    return playedCount > 0 ? 0 : 2;
}

static int ResetPetPositions(void) {
    NSString *path = ManualPetPositionsPath();
    BOOL existed = [NSFileManager.defaultManager fileExistsAtPath:path];
    NSError *error = nil;
    BOOL removed = !existed || [NSFileManager.defaultManager removeItemAtPath:path error:&error];
    NSDictionary *payload = @{
        @"path": path ?: @"",
        @"existed": @(existed),
        @"removed": @(removed),
        @"error": error.localizedDescription ?: @""
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    printf("%s\n", text.UTF8String);
    return removed ? 0 : 2;
}

static void PrintStatusJSON(void) {
    CmuxStateReader *reader = [[CmuxStateReader alloc] init];
    NSArray<SessionInfo *> *sessions = [reader readSessions];
    NSMutableArray *rows = [NSMutableArray array];
    NSString *focusedName = @"";
    for (SessionInfo *session in sessions) {
        BOOL isAgy = [session.provider isEqualToString:@"agy"] || [session.title containsString:@"agy"];
        CGFloat threshold = isAgy ? 55.0 : SharedConfig().workingCpuThreshold;
        BOOL working = session.cpu >= threshold;
        if (session.focused && focusedName.length == 0) {
            focusedName = session.title ?: @"";
        }
        [rows addObject:@{
            @"name": session.title ?: @"",
            @"agent": session.provider ?: @"",
            @"state": working ? @"working" : @"prework",
            @"stateLabel": working ? @"작업중" : @"작업시작전",
            @"focused": @(session.focused),
            @"cpu": @(session.cpu),
            @"processCount": @(session.processCount)
        }];
    }
    NSMutableDictionary *payload = [@{
        @"sessions": rows,
        @"count": @(rows.count),
        @"checkedAt": @((NSInteger)NSDate.date.timeIntervalSince1970)
    } mutableCopy];
    if (focusedName.length > 0) {
        payload[@"focusedName"] = focusedName;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    printf("%s\n", text.UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL statusOnly = NO;
        BOOL demoAlert = NO;
        BOOL testVoice = NO;
        BOOL testSoundEffects = NO;
        BOOL resetPetPositions = NO;
        BOOL turnOn = NO;
        BOOL turnOff = NO;
        BOOL toggle = NO;
        BOOL screenMain = NO;
        BOOL screenLeft = NO;
        BOOL screenCenter = NO;
        BOOL screenAll = NO;
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--status-json"]) {
                statusOnly = YES;
            } else if ([arg isEqualToString:@"--demo-alert"]) {
                demoAlert = YES;
            } else if ([arg isEqualToString:@"--test-voice"]) {
                testVoice = YES;
            } else if ([arg isEqualToString:@"--test-sfx"]) {
                testSoundEffects = YES;
            } else if ([arg isEqualToString:@"--reset-pet-positions"]) {
                resetPetPositions = YES;
            } else if ([arg isEqualToString:@"--on"]) {
                turnOn = YES;
            } else if ([arg isEqualToString:@"--off"]) {
                turnOff = YES;
            } else if ([arg isEqualToString:@"--toggle"]) {
                toggle = YES;
            } else if ([arg isEqualToString:@"--screen-main"]) {
                screenMain = YES;
            } else if ([arg isEqualToString:@"--screen-left"]) {
                screenLeft = YES;
            } else if ([arg isEqualToString:@"--screen-center"]) {
                screenCenter = YES;
            } else if ([arg isEqualToString:@"--screen-all"]) {
                screenAll = YES;
            }
        }

        if (turnOn || turnOff || toggle) {
            NSString *action = @"toggle";
            if (turnOn) action = @"on";
            if (turnOff) action = @"off";
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"com.neogenesis.cmux-pet-overlay.toggle"
                                                                         object:nil
                                                                       userInfo:@{@"action": action}
                                                             deliverImmediately:YES];
            printf("Sent overlay visibility command: %s\n", action.UTF8String);
            return 0;
        }

        if (screenMain || screenLeft || screenCenter || screenAll) {
            NSString *mode = @"main";
            if (screenLeft) mode = @"leftmost";
            if (screenCenter) mode = @"center";
            if (screenAll) mode = @"all";
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"com.neogenesis.cmux-pet-overlay.screenMode"
                                                                         object:nil
                                                                       userInfo:@{@"mode": mode}
                                                             deliverImmediately:YES];
            printf("Sent screen mode command: %s\n", mode.UTF8String);
            return 0;
        }

        if (resetPetPositions) {
            return ResetPetPositions();
        }

        if (testVoice) {
            return TestCompletionVoice();
        }

        if (testSoundEffects) {
            return TestSoundEffects();
        }

        if (statusOnly) {
            PrintStatusJSON();
            return 0;
        }

        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] initWithDemoAlert:demoAlert];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
