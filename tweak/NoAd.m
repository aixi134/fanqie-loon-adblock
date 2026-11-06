// NoAd.m —— 番茄小说 7.4.1 iOS 去广告 tweak（保守版）
//
// 设计原则（v2）：
//   不再 hook SSReadingAdManager 的整个方法族，那会连带打断阅读流的分页/内容管线。
//   只关掉「广告请求的开关」和「广告数据源的返回」，让阅读器正常排版，只是拿不到广告。
//
// 分层开关（从外到内）：
//   1. SSAdCommonSwitchHelper   —— 全局广告闸门（VIP / 地区 / 实验 / 免费权益）
//   2. SSAdSwitchManager        —— 各业务场景的 feed 开关
//   3. SSReaderAttachmentAdSwitchComponent —— 段中内嵌广告
//   4. BDADReaderBottomBannerManager.requestBannerWithType: —— 底部 banner 请求
//   5. SSReaderGenreContentManager 的 noAdFor* —— 阅读流推荐内容（含广告插页）
//
// 每一步都可以用环境变量单独关掉以便二分定位：
//   NOAD_DISABLE=1 全部关闭；NOAD_SKIP=1,2,3 跳过指定层。

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#define LOG(fmt, ...) NSLog(@"[NoAd] " fmt, ##__VA_ARGS__)
#define TAG(level) LOG(@"L%d %s", level, __func__)

static bool env_skip(int level) {
    static NSMutableSet<NSNumber *> *skip = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        skip = [NSMutableSet set];
        NSDictionary *env = [[NSProcessInfo processInfo] environment];
        if (env[@"NOAD_DISABLE"]) { for (int i = 1; i <= 9; i++) [skip addObject:@(i)]; }
        NSString *s = env[@"NOAD_SKIP"];
        if (s.length) {
            for (NSString *p in [s componentsSeparatedByString:@","]) {
                [skip addObject:@([p integerValue])];
            }
        }
    });
    return [skip containsObject:@(level)];
}

static void swizzleClass(Class cls, NSString *selName, IMP imp) {
    if (!cls) { LOG(@"skip (no class) %@", selName); return; }
    SEL sel = NSSelectorFromString(selName);
    Method m = class_getClassMethod(cls, sel);
    if (!m) { LOG(@"miss +[%@ %@]", NSStringFromClass(cls), selName); return; }
    method_setImplementation(m, imp);
    LOG(@"+[%@ %@]", NSStringFromClass(cls), selName);
}

static void swizzleInst(Class cls, NSString *selName, IMP imp) {
    if (!cls) { LOG(@"skip (no class) %@", selName); return; }
    SEL sel = NSSelectorFromString(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { LOG(@"miss -[%@ %@]", NSStringFromClass(cls), selName); return; }
    method_setImplementation(m, imp);
    LOG(@"-[%@ %@]", NSStringFromClass(cls), selName);
}

static void swizzleAll(Class cls, NSString *prefix, IMP imp) {
    if (!cls) return;
    unsigned int n = 0;
    Method *ms = class_copyMethodList(cls, &n);
    const char *pfx = prefix.UTF8String;
    size_t plen = strlen(pfx);
    for (unsigned int i = 0; i < n; i++) {
        const char *name = sel_getName(method_getName(ms[i]));
        if (strncmp(name, pfx, plen) == 0) {
            method_setImplementation(ms[i], imp);
            LOG(@"  -[%@ %s]", NSStringFromClass(cls), name);
        }
    }
    free(ms);
}

#pragma mark - 各层替代实现

// L1 全局闸
static BOOL noad_canShowAdInReader(Class c, SEL s, id bookId, BOOL local, BOOL autoRead, BOOL syncRead, id *reason) {
    return NO;
}
static BOOL noad_baseCommonAdSwitch(Class c, SEL s, BOOL networkCheck) { return NO; }
static BOOL noad_isCommonShouldRequestAd(Class c, SEL s) { return NO; }

// L2 业务场景开关
static BOOL noad_feedOpen(Class c, SEL s, NSInteger type, id data) { return NO; }
static BOOL noad_inspireOpen(Class c, SEL s, NSInteger type, id data) { return NO; }

// L3 段中内嵌广告
static BOOL noad_isAvailable(Class c, SEL s, id *reason) { return NO; }

// L4 底部 banner 请求
static void noad_requestBanner(id self, SEL s, id type) { LOG(@"L4 banner request blocked"); }
static void noad_tryRefreshBanner(id self, SEL s) {}

// L5 阅读流推荐（广告插页的来源）
static BOOL noad_readerNoAd(id self, SEL s) { return YES; }

#pragma mark - 入口

__attribute__((constructor))
static void noad_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        LOG(@"=== NoAd v2 loaded ===");

        if (!env_skip(1)) {
            Class h = NSClassFromString(@"SSAdCommonSwitchHelper");
            swizzleClass(h, @"canShowAdInReaderWithBookId:isLocalBook:autoReading:syncReading:outReason:", (IMP)noad_canShowAdInReader);
            swizzleClass(h, @"baseCommonAdSwitchWithNetworkCheck:", (IMP)noad_baseCommonAdSwitch);
            swizzleClass(h, @"isCommonShouldRequestAd", (IMP)noad_isCommonShouldRequestAd);
        }

        if (!env_skip(2)) {
            Class s = NSClassFromString(@"SSAdSwitchManager");
            swizzleClass(s, @"feedOpenWithType:data:", (IMP)noad_feedOpen);
            swizzleClass(s, @"inspireOpenWithType:data:", (IMP)noad_inspireOpen);
        }

        if (!env_skip(3)) {
            Class a = NSClassFromString(@"SSReaderAttachmentAdSwitchComponent");
            swizzleClass(a, @"isAvailableWithReason:", (IMP)noad_isAvailable);
        }

        if (!env_skip(4)) {
            Class b = NSClassFromString(@"BDADReaderBottomBannerManager");
            swizzleInst(b, @"requestBannerWithType:", (IMP)noad_requestBanner);
            swizzleInst(b, @"tryRefreshBannerView", (IMP)noad_tryRefreshBanner);
        }

        if (!env_skip(5)) {
            Class g = NSClassFromString(@"SSReaderGenreContentManager");
            if (g) {
                const char *names[] = {"noAdForAllScene", "noAdForBook", "noAdForReaderVideo", "noAdForNewUser", "noAdForVip"};
                for (int i = 0; i < 5; i++) {
                    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:names[i]]);
                    Method m = class_getInstanceMethod(g, sel);
                    if (m) { method_setImplementation(m, (IMP)noad_readerNoAd); LOG(@"  -[SSReaderGenreContentManager %s]", names[i]); }
                }
            }
        }

        LOG(@"=== NoAd v2 done ===");
    });
}
