#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <sys/utsname.h>
#import <unistd.h>

static NSString * const HSONReportFilename = @"HSONScanReport.json";

static NSString *HSONArchitecture(void) {
#if defined(__arm64e__)
    return @"arm64e";
#elif defined(__aarch64__) || defined(__arm64__)
    return @"arm64";
#elif defined(__arm__)
    return @"arm";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}

static BOOL HSONPathIsInsideBundle(NSString *path, NSString *bundlePath) {
    if (path.length == 0 || bundlePath.length == 0) return NO;
    NSString *prefix = [bundlePath stringByAppendingString:@"/"];
    return [path isEqualToString:bundlePath] || [path hasPrefix:prefix];
}

static NSString *HSONRelativeImagePath(const char *rawPath, NSString *bundlePath) {
    if (rawPath == NULL) return @"";
    NSString *path = [NSString stringWithUTF8String:rawPath];
    if (path.length == 0) return @"";
    if (HSONPathIsInsideBundle(path, bundlePath)) {
        if ([path isEqualToString:bundlePath]) return @".";
        return [path substringFromIndex:bundlePath.length + 1];
    }
    return path.lastPathComponent ?: @"";
}

static BOOL HSONIsSubclassOfClass(Class candidate, Class parent) {
    if (candidate == Nil || parent == Nil) return NO;
    for (Class current = candidate; current != Nil; current = class_getSuperclass(current)) {
        if (current == parent) return YES;
    }
    return NO;
}

static NSArray<NSDictionary *> *HSONCollectBundleImages(NSString *bundlePath) {
    NSMutableArray<NSDictionary *> *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *rawPath = _dyld_get_image_name(i);
        if (rawPath == NULL) continue;
        NSString *path = [NSString stringWithUTF8String:rawPath];
        if (!HSONPathIsInsideBundle(path, bundlePath)) continue;
        [images addObject:@{
            @"name": path.lastPathComponent ?: @"",
            @"bundleRelativePath": HSONRelativeImagePath(rawPath, bundlePath)
        }];
    }
    return images;
}

// Deliberately limited to app-bundled UI class metadata. No selectors, method
// implementations, arguments, credentials, purchase state, or network data
// are read or invoked.
static NSArray<NSDictionary *> *HSONCollectBundleUIClasses(NSString *bundlePath) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return @[];

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (classes == NULL) return @[];

    int actualCount = objc_getClassList(classes, classCount);
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    Class viewClass = NSClassFromString(@"UIView");
    Class viewControllerClass = NSClassFromString(@"UIViewController");

    for (int i = 0; i < actualCount; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *rawImage = class_getImageName(cls);
        if (rawImage == NULL) continue;
        NSString *imagePath = [NSString stringWithUTF8String:rawImage];
        if (!HSONPathIsInsideBundle(imagePath, bundlePath)) continue;

        BOOL isView = HSONIsSubclassOfClass(cls, viewClass);
        BOOL isViewController = HSONIsSubclassOfClass(cls, viewControllerClass);
        // UIApplicationDelegate/UISceneDelegate are protocols, not classes.
        Protocol *appDelegateProtocol = @protocol(UIApplicationDelegate);
        Protocol *sceneDelegateProtocol = @protocol(UISceneDelegate);
        BOOL isAppDelegate = appDelegateProtocol != nil && class_conformsToProtocol(cls, appDelegateProtocol);
        BOOL isSceneDelegate = sceneDelegateProtocol != nil && class_conformsToProtocol(cls, sceneDelegateProtocol);

        if (!(isView || isViewController || isAppDelegate || isSceneDelegate)) continue;

        Class superClass = class_getSuperclass(cls);
        NSString *className = NSStringFromClass(cls) ?: @"";
        NSString *superName = superClass ? (NSStringFromClass(superClass) ?: @"") : @"";
        NSString *kind = isViewController ? @"UIViewController" :
                         (isView ? @"UIView" :
                         (isAppDelegate ? @"UIApplicationDelegate" : @"UISceneDelegate"));

        [results addObject:@{
            @"class": className,
            @"superclass": superName,
            @"category": kind,
            @"image": imagePath.lastPathComponent ?: @""
        }];
    }

    free(classes);
    [results sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"class"] compare:b[@"class"] options:NSLiteralSearch];
    }];
    return results;
}

static NSDictionary *HSONCollectVisibleUI(void) {
    NSMutableArray<NSString *> *visibleControllers = [NSMutableArray array];
    NSMutableArray<NSString *> *visibleViews = [NSMutableArray array];

    UIApplication *application = UIApplication.sharedApplication;
    if (application == nil) {
        return @{@"available": @NO, @"viewControllers": visibleControllers, @"viewClasses": visibleViews};
    }

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.hidden || window.alpha <= 0.01) continue;
            UIViewController *controller = window.rootViewController;
            if (controller != nil) {
                [visibleControllers addObject:NSStringFromClass(controller.class) ?: @"unknown"];
                UIViewController *top = controller;
                while (top.presentedViewController != nil) top = top.presentedViewController;
                if (top != controller) {
                    [visibleControllers addObject:NSStringFromClass(top.class) ?: @"unknown"];
                }
            }
            for (UIView *view in window.subviews) {
                [visibleViews addObject:NSStringFromClass(view.class) ?: @"unknown"];
            }
        }
    }

    return @{
        @"available": @YES,
        @"viewControllers": visibleControllers,
        @"topLevelViewClasses": visibleViews
    };
}

static NSString *HSONISO8601Now(void) {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:[NSDate date]] ?: @"";
}

static void HSONWriteReport(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSString *bundlePath = bundle.bundlePath ?: @"";
        NSDictionary *info = bundle.infoDictionary ?: @{};
        struct utsname systemInfo;
        uname(&systemInfo);

        NSDictionary *appInfo = @{
            @"bundleIdentifier": info[@"CFBundleIdentifier"] ?: @"",
            @"name": info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"",
            @"shortVersion": info[@"CFBundleShortVersionString"] ?: @"",
            @"build": info[@"CFBundleVersion"] ?: @"",
            @"executable": info[@"CFBundleExecutable"] ?: @""
        };

        NSDictionary *deviceInfo = @{
            @"architecture": HSONArchitecture(),
            @"machine": [NSString stringWithUTF8String:systemInfo.machine] ?: @"",
            @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"",
            @"deviceModel": UIDevice.currentDevice.model ?: @"",
            @"processID": @(getpid()),
            @"processName": NSProcessInfo.processInfo.processName ?: @""
        };

        NSDictionary *report = @{
            @"tool": @{
                @"name": @"HSONScanner",
                @"version": @"1.0.0",
                @"scope": @"read-only-ui-runtime-metadata",
                @"generatedAt": HSONISO8601Now()
            },
            @"app": appInfo,
            @"device": deviceInfo,
            @"loadedAppImages": HSONCollectBundleImages(bundlePath),
            @"appUIClasses": HSONCollectBundleUIClasses(bundlePath),
            @"visibleUI": HSONCollectVisibleUI(),
            @"privacy": @{
                @"networkRequests": @NO,
                @"methodImplementationsRead": @NO,
                @"methodsInvoked": @NO,
                @"authenticationOrPaymentDataCollected": @NO
            }
        };

        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:report
                                                            options:NSJSONWritingPrettyPrinted
                                                              error:&jsonError];
        if (jsonData == nil) {
            NSLog(@"[HSONScanner] JSON serialization failed: %@", jsonError.localizedDescription ?: @"unknown error");
            return;
        }

        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (documents.length == 0) documents = NSTemporaryDirectory();
        NSString *outputPath = [documents stringByAppendingPathComponent:HSONReportFilename];
        NSError *writeError = nil;
        BOOL ok = [jsonData writeToFile:outputPath options:NSDataWritingAtomic error:&writeError];
        if (ok) {
            NSLog(@"[HSONScanner] Report written: %@ (%lu bytes)", outputPath, (unsigned long)jsonData.length);
        } else {
            NSLog(@"[HSONScanner] Report write failed: %@", writeError.localizedDescription ?: @"unknown error");
        }
    }
}

__attribute__((constructor)) static void HSONScannerEntry(void) {
    @autoreleasepool {
        // Wait for app startup so UIKit's scene/window metadata is available.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{ HSONWriteReport(); });
        });
    }
}
