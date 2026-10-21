#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const FSPLogPrefix = @"[FullScreenContentPop]";
static IMP FSPOriginalViewDidAppearIMP = NULL;
static IMP FSPOriginalPushViewControllerIMP = NULL;

static void FSPLog(NSString *message) {
    // Keep diagnostics enabled in release builds: NSLog is visible in device console.
    NSLog(@"%@ %@", FSPLogPrefix, message);
}

static void FSPConfigureNavigationController(UINavigationController *navigationController) {
    if (!navigationController || ![navigationController isKindOfClass:UINavigationController.class]) return;

    // Loading the view makes UIKit install its navigation gesture recognizers when appropriate.
    (void)navigationController.view;

    SEL contentPopSelector = NSSelectorFromString(@"interactiveContentPopGestureRecognizer");
    if ([navigationController respondsToSelector:contentPopSelector]) {
        UIGestureRecognizer *gesture =
            ((id (*)(id, SEL))objc_msgSend)(navigationController, contentPopSelector);
        if (gesture) {
            BOOL wasEnabled = gesture.enabled;
            gesture.enabled = YES;
            FSPLog([NSString stringWithFormat:
                @"iOS=%@ nav=%@ stack=%lu contentPop=%@ enabled:%@->%@ delegate=%@",
                UIDevice.currentDevice.systemVersion,
                NSStringFromClass(navigationController.class),
                (unsigned long)navigationController.viewControllers.count,
                NSStringFromClass(gesture.class),
                wasEnabled ? @"YES" : @"NO",
                gesture.enabled ? @"YES" : @"NO",
                gesture.delegate ? NSStringFromClass(gesture.delegate.class) : @"nil"]);
        } else {
            FSPLog([NSString stringWithFormat:@"contentPop selector exists but returned nil; nav=%@ stack=%lu",
                NSStringFromClass(navigationController.class),
                (unsigned long)navigationController.viewControllers.count]);
        }
    } else {
        FSPLog([NSString stringWithFormat:@"contentPop API unavailable; iOS=%@ nav=%@",
            UIDevice.currentDevice.systemVersion, NSStringFromClass(navigationController.class)]);
    }

    UIGestureRecognizer *edgeGesture = navigationController.interactivePopGestureRecognizer;
    FSPLog([NSString stringWithFormat:@"edgePop=%@ enabled=%@ stack=%lu",
        edgeGesture ? NSStringFromClass(edgeGesture.class) : @"nil",
        edgeGesture.enabled ? @"YES" : @"NO",
        (unsigned long)navigationController.viewControllers.count]);
}

static void FSPWalkViewController(UIViewController *viewController) {
    if (!viewController) return;

    if ([viewController isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)viewController;
        FSPConfigureNavigationController(nav);
        for (UIViewController *child in nav.viewControllers) FSPWalkViewController(child);
    }
    if ([viewController isKindOfClass:UITabBarController.class]) {
        for (UIViewController *child in ((UITabBarController *)viewController).viewControllers)
            FSPWalkViewController(child);
    }
    if ([viewController isKindOfClass:UISplitViewController.class]) {
        for (UIViewController *child in ((UISplitViewController *)viewController).viewControllers)
            FSPWalkViewController(child);
    }
    if (viewController.presentedViewController)
        FSPWalkViewController(viewController.presentedViewController);
}

static void FSPConfigureVisibleApplications(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ FSPConfigureVisibleApplications(); });
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    NSUInteger sceneCount = 0, windowCount = 0;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached) continue;
        sceneCount++;
        for (UIWindow *window in windowScene.windows) {
            windowCount++;
            if (window.rootViewController) FSPWalkViewController(window.rootViewController);
        }
    }
    FSPLog([NSString stringWithFormat:@"scan complete scenes=%lu windows=%lu bundle=%@",
        (unsigned long)sceneCount, (unsigned long)windowCount,
        NSBundle.mainBundle.bundleIdentifier ?: @"(unknown)"]);
}

static void FSPNavigationControllerViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (FSPOriginalViewDidAppearIMP)
        ((void (*)(id, SEL, BOOL))FSPOriginalViewDidAppearIMP)(self, _cmd, animated);
    if ([self isKindOfClass:UINavigationController.class]) {
        FSPConfigureNavigationController((UINavigationController *)self);
        dispatch_async(dispatch_get_main_queue(), ^{ FSPConfigureVisibleApplications(); });
    }
}

static void FSPNavigationControllerPushViewController(id self, SEL _cmd,
                                                       UIViewController *viewController,
                                                       BOOL animated) {
    if (FSPOriginalPushViewControllerIMP)
        ((void (*)(id, SEL, UIViewController *, BOOL))FSPOriginalPushViewControllerIMP)
            (self, _cmd, viewController, animated);
    if ([self isKindOfClass:UINavigationController.class]) {
        // UIKit may adjust recognizer state while pushing; re-apply after the transition starts.
        dispatch_async(dispatch_get_main_queue(), ^{
            FSPConfigureNavigationController((UINavigationController *)self);
        });
    }
}

static void FSPInstallHook(Class cls, SEL selector, IMP replacement, IMP *originalIMP) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        FSPLog([NSString stringWithFormat:@"hook failed: %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector)]);
        return;
    }
    *originalIMP = method_getImplementation(method);
    BOOL added = class_addMethod(cls, selector, replacement, method_getTypeEncoding(method));
    if (!added) method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    FSPLog([NSString stringWithFormat:@"hook installed: %@ %@", NSStringFromClass(cls), NSStringFromSelector(selector)]);
}

static void FSPApplicationDidBecomeActive(NSNotification *notification) {
    (void)notification;
    FSPConfigureVisibleApplications();
}

__attribute__((constructor))
static void FullScreenContentPopInitialize(void) {
    @autoreleasepool {
        FSPLog([NSString stringWithFormat:@"LOADED version=2 iOS=%@ bundle=%@",
            UIDevice.currentDevice.systemVersion, NSBundle.mainBundle.bundleIdentifier ?: @"(unknown)"]);
        FSPInstallHook(UINavigationController.class, @selector(viewDidAppear:),
                       (IMP)FSPNavigationControllerViewDidAppear, &FSPOriginalViewDidAppearIMP);
        FSPInstallHook(UINavigationController.class, @selector(pushViewController:animated:),
                       (IMP)FSPNavigationControllerPushViewController, &FSPOriginalPushViewControllerIMP);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                FSPApplicationDidBecomeActive(note);
            }];
        dispatch_async(dispatch_get_main_queue(), ^{ FSPConfigureVisibleApplications(); });
    }
}
