#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// FullScreenContentPop for app-side dylib injection.
// Uses UINavigationController's interactiveContentPopGestureRecognizer when available.

static NSString * const FSPLogPrefix = @"[FullScreenContentPop]";
static const void *FSPDidConfigureKey = &FSPDidConfigureKey;

static void FSPLog(NSString *message) {
#if DEBUG
    NSLog(@"%@ %@", FSPLogPrefix, message);
#endif
}

static void FSPConfigureNavigationController(UINavigationController *navigationController) {
    if (![navigationController isKindOfClass:UINavigationController.class]) return;

    NSNumber *configured = objc_getAssociatedObject(navigationController, FSPDidConfigureKey);
    if (configured.boolValue) return;

    SEL contentPopSelector = NSSelectorFromString(@"interactiveContentPopGestureRecognizer");
    if ([navigationController respondsToSelector:contentPopSelector]) {
        UIGestureRecognizer *contentGesture =
            ((id (*)(id, SEL))objc_msgSend)(navigationController, contentPopSelector);
        if (contentGesture) {
            contentGesture.enabled = YES;
            objc_setAssociatedObject(navigationController, FSPDidConfigureKey,
                                     @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            FSPLog(@"Enabled interactiveContentPopGestureRecognizer");
            return;
        }
    }

    // No private-API fallback: preserve the normal system edge-swipe behavior.
    FSPLog(@"Content-area pop gesture unavailable; leaving system behavior unchanged");
}

static void FSPWalkViewController(UIViewController *viewController) {
    if (!viewController) return;

    if ([viewController isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigationController = (UINavigationController *)viewController;
        FSPConfigureNavigationController(navigationController);
        for (UIViewController *child in navigationController.viewControllers) {
            FSPWalkViewController(child);
        }
    }

    if ([viewController isKindOfClass:UITabBarController.class]) {
        for (UIViewController *child in ((UITabBarController *)viewController).viewControllers) {
            FSPWalkViewController(child);
        }
    }

    if ([viewController isKindOfClass:UISplitViewController.class]) {
        for (UIViewController *child in ((UISplitViewController *)viewController).viewControllers) {
            FSPWalkViewController(child);
        }
    }

    if (viewController.presentedViewController) {
        FSPWalkViewController(viewController.presentedViewController);
    }
}

static void FSPConfigureVisibleApplications(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ FSPConfigureVisibleApplications(); });
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached) continue;

        for (UIWindow *window in windowScene.windows) {
            if (window.rootViewController) FSPWalkViewController(window.rootViewController);
        }
    }
}

static void FSPApplicationDidBecomeActive(NSNotification *notification) {
    (void)notification;
    FSPConfigureVisibleApplications();
}

static void FSPNavigationControllerViewDidAppear(id self, SEL _cmd, BOOL animated);
static IMP FSPOriginalViewDidAppearIMP = NULL;

static void FSPNavigationControllerViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (FSPOriginalViewDidAppearIMP) {
        ((void (*)(id, SEL, BOOL))FSPOriginalViewDidAppearIMP)(self, _cmd, animated);
    }
    if ([self isKindOfClass:UINavigationController.class]) {
        FSPConfigureNavigationController((UINavigationController *)self);
    }
}

static void FSPInstallViewDidAppearHook(void) {
    Class cls = UINavigationController.class;
    SEL selector = @selector(viewDidAppear:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        FSPLog(@"Could not find UINavigationController viewDidAppear:");
        return;
    }

    FSPOriginalViewDidAppearIMP = method_getImplementation(method);
    IMP replacement = (IMP)FSPNavigationControllerViewDidAppear;

    BOOL added = class_addMethod(cls, selector, replacement, method_getTypeEncoding(method));
    if (added) return;
    method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void FullScreenContentPopInitialize(void) {
    @autoreleasepool {
        FSPLog(@"Loaded");
        FSPInstallViewDidAppearHook();
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *note) {
            FSPApplicationDidBecomeActive(note);
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            FSPConfigureVisibleApplications();
        });
    }
}
