#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define PLIST_PATH @"/var/jb/var/mobile/Library/Preferences/com.minh.customdock.plist"
#define PREFS_NOTIFICATION CFSTR("com.minh.customdock.prefschanged")

// --- Forward declarations ---
@interface SBDockView : UIView
- (void)setBackgroundAlpha:(double)arg1;
@end

@interface SBIconView : UIView
- (void)setIconContentScale:(double)scale;
- (BOOL)_cd_isInDock;
- (void)_cd_setLabelsHidden:(BOOL)hidden inView:(UIView *)view depth:(int)depth;
@end

@interface SpringBoard : UIApplication
- (UIView *)_cd_findDockView:(UIView *)root;
@end

// --- Preferences ---
static BOOL enabled = NO;
static BOOL transparentDock = NO;
static BOOL hideDock = NO;
static BOOL customColorEnabled = NO;
static NSString *dockColorHex = nil;
static CGFloat dockColorAlpha = 0.5;
static CGFloat blurIntensity = 1.0;
static BOOL customCornerRadiusEnabled = NO;
static CGFloat cornerRadius = 20.0;
static CGFloat iconScale = 1.0;
static BOOL hideLabels = NO;
static BOOL disableBounce = NO;
static BOOL hideOnLandscape = NO;

static UIColor *parsedDockColor = nil;

static UIColor *colorFromHex(NSString *hex) {
    if (!hex || hex.length == 0) return [UIColor blackColor];
    hex = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
    if (hex.length != 6) return [UIColor blackColor];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static void loadPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];

    enabled             = [prefs[@"enabled"] ?: @NO boolValue];
    transparentDock     = [prefs[@"transparentDock"] ?: @NO boolValue];
    hideDock            = [prefs[@"hideDock"] ?: @NO boolValue];
    customColorEnabled  = [prefs[@"customColorEnabled"] ?: @NO boolValue];
    dockColorHex        = prefs[@"dockColorHex"] ?: @"000000";
    dockColorAlpha      = [prefs[@"dockColorAlpha"] ?: @(0.5) doubleValue];
    blurIntensity       = [prefs[@"blurIntensity"] ?: @(1.0) doubleValue];
    customCornerRadiusEnabled = [prefs[@"customCornerRadiusEnabled"] ?: @NO boolValue];
    cornerRadius        = [prefs[@"cornerRadius"] ?: @(20.0) doubleValue];
    iconScale           = [prefs[@"iconScale"] ?: @(1.0) doubleValue];
    hideLabels          = [prefs[@"hideLabels"] ?: @NO boolValue];
    disableBounce       = [prefs[@"disableBounce"] ?: @NO boolValue];
    hideOnLandscape     = [prefs[@"hideOnLandscape"] ?: @NO boolValue];

    parsedDockColor = colorFromHex(dockColorHex);
}

static void prefsChanged(CFNotificationCenterRef center, void *observer,
                          CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPrefs();
}

static char kColorOverlayKey;

// ============================================================
#pragma mark - SBDockView
// ============================================================

%hook SBDockView

- (void)setBackgroundAlpha:(double)arg1 {
    if (!enabled) { %orig; return; }

    if (hideDock || transparentDock) {
        %orig(0.0);
        return;
    }

    %orig(arg1 * blurIntensity);
}

- (void)layoutSubviews {
    %orig;
    if (!enabled) {
        self.hidden = NO;
        self.alpha = 1.0;
        self.layer.cornerRadius = 0;
        UIView *overlay = objc_getAssociatedObject(self, &kColorOverlayKey);
        if (overlay) overlay.hidden = YES;
        return;
    }

    // Hide dock completely
    if (hideDock) {
        self.hidden = YES;
        return;
    }
    self.hidden = NO;

    // Hide on landscape
    if (hideOnLandscape) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIInterfaceOrientation ori = [[UIApplication sharedApplication] statusBarOrientation];
#pragma clang diagnostic pop
        if (UIInterfaceOrientationIsLandscape(ori)) {
            self.alpha = 0.0;
            return;
        } else {
            self.alpha = 1.0;
        }
    } else {
        self.alpha = 1.0;
    }

    // Corner radius
    if (customCornerRadiusEnabled) {
        self.layer.cornerRadius = cornerRadius;
        self.clipsToBounds = YES;
    } else {
        self.layer.cornerRadius = 0;
        self.clipsToBounds = NO;
    }

    // Custom color overlay
    UIView *overlay = objc_getAssociatedObject(self, &kColorOverlayKey);
    if (customColorEnabled && !transparentDock && !hideDock) {
        if (!overlay) {
            overlay = [[UIView alloc] init];
            overlay.userInteractionEnabled = NO;
            [self insertSubview:overlay atIndex:0];
            objc_setAssociatedObject(self, &kColorOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        overlay.frame = self.bounds;
        overlay.backgroundColor = [parsedDockColor colorWithAlphaComponent:dockColorAlpha];
        overlay.layer.cornerRadius = customCornerRadiusEnabled ? cornerRadius : 0;
        overlay.clipsToBounds = YES;
        overlay.hidden = NO;
    } else if (overlay) {
        overlay.hidden = YES;
    }
}

%end

// ============================================================
#pragma mark - SBIconView (scale, labels, bounce)
// ============================================================

%hook SBIconView

- (void)layoutSubviews {
    %orig;
    if (!enabled) return;

    BOOL isInDock = [self _cd_isInDock];
    if (!isInDock) return;

    // Icon scale
    if (iconScale != 1.0) {
        self.transform = CGAffineTransformMakeScale(iconScale, iconScale);
    } else {
        self.transform = CGAffineTransformIdentity;
    }

    // Hide labels
    if (hideLabels) {
        [self _cd_setLabelsHidden:YES inView:self depth:0];
    }
}

- (void)setIconContentScale:(double)scale {
    if (enabled && disableBounce && [self _cd_isInDock]) {
        %orig(1.0);
        return;
    }
    %orig;
}

%new
- (BOOL)_cd_isInDock {
    UIView *v = self.superview;
    while (v) {
        if ([v isKindOfClass:%c(SBDockView)]) return YES;
        v = v.superview;
    }
    return NO;
}

%new
- (void)_cd_setLabelsHidden:(BOOL)hidden inView:(UIView *)view depth:(int)depth {
    if (depth > 5) return;
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Label"] || [cls containsString:@"label"]) {
            sub.hidden = hidden;
        }
        if ([sub isKindOfClass:[UILabel class]]) {
            sub.hidden = hidden;
        }
        [self _cd_setLabelsHidden:hidden inView:sub depth:depth + 1];
    }
}

%end

// ============================================================
#pragma mark - Orientation change (for hideOnLandscape)
// ============================================================

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note) {
        UIView *dockView = [self _cd_findDockView:[[UIApplication sharedApplication] keyWindow]];
        if (dockView) [dockView setNeedsLayout];
    }];
}

%new
- (UIView *)_cd_findDockView:(UIView *)root {
    if (!root) return nil;
    if ([root isKindOfClass:%c(SBDockView)]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = [self _cd_findDockView:sub];
        if (found) return found;
    }
    return nil;
}

%end

#pragma clang diagnostic pop

// ============================================================
#pragma mark - Constructor
// ============================================================

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        prefsChanged, PREFS_NOTIFICATION, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
