#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>

#define PREFS_DOMAIN CFSTR("com.minh.customdock")

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

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

// Read preference using CFPreferences (always up to date, no file path issues)
static id pref(NSString *key, id fallback) {
    CFPreferencesAppSynchronize(PREFS_DOMAIN);
    CFPropertyListRef val = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PREFS_DOMAIN);
    if (val) return (__bridge_transfer id)val;
    return fallback;
}

static UIImage *iconForBundleID(NSString *bundleID) {
    if (!bundleID) return nil;

    static NSData *(*SBSCopyIcon)(NSString *) = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
        if (handle)
            SBSCopyIcon = (NSData *(*)(NSString *))dlsym(handle, "SBSCopyIconImagePNGDataForDisplayIdentifier");
    });
    if (SBSCopyIcon) {
        NSData *data = SBSCopyIcon(bundleID);
        if (data.length > 0) return [UIImage imageWithData:data];
    }

    for (int fmt = 2; fmt >= 0; fmt--) {
        UIImage *img = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:fmt scale:[UIScreen mainScreen].scale];
        if (img) return img;
    }
    return nil;
}

static NSArray<NSString *> *getDockBundleIDs(void) {
    NSArray *paths = @[
        @"/var/mobile/Library/SpringBoard/IconState.plist",
        @"/var/jb/var/mobile/Library/SpringBoard/IconState.plist"
    ];

    NSDictionary *iconState = nil;
    for (NSString *path in paths) {
        iconState = [NSDictionary dictionaryWithContentsOfFile:path];
        if (iconState) break;
    }

    NSMutableArray *bundleIDs = [NSMutableArray array];
    if (iconState) {
        NSArray *dock = iconState[@"buttonBar"] ?: iconState[@"dock"];
        if ([dock.firstObject isKindOfClass:[NSArray class]])
            dock = dock.firstObject;
        for (id item in dock) {
            NSString *bid = nil;
            if ([item isKindOfClass:[NSDictionary class]])
                bid = item[@"bundleIdentifier"] ?: item[@"displayIdentifier"];
            else if ([item isKindOfClass:[NSString class]])
                bid = item;
            if (bid) [bundleIDs addObject:bid];
        }
    }

    if (bundleIDs.count == 0)
        [bundleIDs addObjectsFromArray:@[
            @"com.apple.mobilephone", @"com.apple.MobileSMS",
            @"com.apple.mobilesafari", @"com.apple.Music"
        ]];

    return bundleIDs;
}

@interface CustomDockPreferencesListController : PSListController {
    UIView *_previewContainer;
    UIView *_dockBgView;
    UIVisualEffectView *_blurView;
    UIView *_dockColorOverlay;
    NSMutableArray<UIImageView *> *_iconViews;
}
@end

@implementation CustomDockPreferencesListController

- (NSArray *)specifiers {
    if (!_specifiers)
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

// Catches switches, text fields, and some slider changes
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    [self updatePreview];
}

#pragma mark - Preview

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildPreviewHeader];

    // Listen for Darwin notifications (catches slider PostNotification)
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        (CFNotificationCallback)onPrefsChanged,
        CFSTR("com.minh.customdock.prefschanged"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

static void onPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef info) {
    CustomDockPreferencesListController *vc = (__bridge CustomDockPreferencesListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc updatePreview];
    });
}

- (void)buildPreviewHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 210)];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"PREVIEW";
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    label.textColor = [UIColor secondaryLabelColor];
    label.tag = 999;
    [header addSubview:label];

    _previewContainer = [[UIView alloc] init];
    _previewContainer.clipsToBounds = YES;
    _previewContainer.layer.cornerRadius = 20;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.08 green:0.08 blue:0.25 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.18 green:0.08 blue:0.22 alpha:1.0].CGColor
    ];
    gradient.name = @"wallpaper";
    [_previewContainer.layer insertSublayer:gradient atIndex:0];

    _dockBgView = [[UIView alloc] init];
    _dockBgView.clipsToBounds = YES;

    _blurView = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    [_dockBgView addSubview:_blurView];

    _dockColorOverlay = [[UIView alloc] init];
    _dockColorOverlay.hidden = YES;
    [_dockBgView addSubview:_dockColorOverlay];

    [_previewContainer addSubview:_dockBgView];
    [header addSubview:_previewContainer];

    self.table.tableHeaderView = header;

    [self layoutPreview];
    [self loadDockIcons];
    [self updatePreview];
}

- (void)layoutPreview {
    UIView *header = self.table.tableHeaderView;
    if (!header) return;

    CGFloat w = self.table.bounds.size.width;
    if (w < 1) w = self.view.bounds.size.width;
    if (w < 1) w = [UIScreen mainScreen].bounds.size.width;

    header.frame = CGRectMake(0, 0, w, 210);

    UILabel *label = [header viewWithTag:999];
    label.frame = CGRectMake(0, 4, w, 16);

    CGFloat pad = 16;
    _previewContainer.frame = CGRectMake(pad, 24, w - pad * 2, 178);

    for (CALayer *layer in _previewContainer.layer.sublayers) {
        if ([layer.name isEqualToString:@"wallpaper"]) {
            layer.frame = _previewContainer.bounds;
            break;
        }
    }

    CGFloat dockH = 90;
    CGFloat cw = _previewContainer.bounds.size.width;
    CGFloat ch = _previewContainer.bounds.size.height;
    _dockBgView.frame = CGRectMake(0, ch - dockH, cw, dockH);
    _blurView.frame = _dockBgView.bounds;
    _dockColorOverlay.frame = _dockBgView.bounds;

    CGFloat iconSize = 48;
    NSUInteger count = _iconViews.count;
    if (count == 0) return;
    CGFloat spacing = (cw - count * iconSize) / (count + 1);
    for (NSUInteger i = 0; i < count; i++) {
        _iconViews[i].frame = CGRectMake(
            spacing + i * (iconSize + spacing),
            (dockH - iconSize) / 2,
            iconSize, iconSize);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutPreview];
    self.table.tableHeaderView = self.table.tableHeaderView;
}

- (void)loadDockIcons {
    _iconViews = [NSMutableArray array];

    NSArray<NSString *> *bundleIDs = getDockBundleIDs();
    NSUInteger count = MIN(bundleIDs.count, (NSUInteger)6);

    NSArray *colors = @[
        [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0],
        [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.6 blue:0.2 alpha:1.0],
        [UIColor colorWithRed:0.6 green:0.3 blue:0.9 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.4 blue:0.6 alpha:1.0],
    ];

    CGFloat iconSize = 48;
    CGFloat dockW = _dockBgView.bounds.size.width;
    CGFloat spacing = (dockW - count * iconSize) / (count + 1);

    for (NSUInteger i = 0; i < count; i++) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(
            spacing + i * (iconSize + spacing),
            (_dockBgView.bounds.size.height - iconSize) / 2,
            iconSize, iconSize)];
        iv.layer.cornerRadius = iconSize * 0.225;
        iv.clipsToBounds = YES;
        iv.contentMode = UIViewContentModeScaleAspectFill;

        UIImage *img = iconForBundleID(bundleIDs[i]);
        if (img) {
            iv.image = img;
        } else {
            iv.backgroundColor = colors[i % colors.count];
            UILabel *lbl = [[UILabel alloc] initWithFrame:iv.bounds];
            NSString *ext = [bundleIDs[i] pathExtension] ?: @"?";
            lbl.text = [[ext substringToIndex:MIN((NSUInteger)1, ext.length)] uppercaseString];
            lbl.textAlignment = NSTextAlignmentCenter;
            lbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
            lbl.textColor = [UIColor whiteColor];
            lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [iv addSubview:lbl];
        }

        [_dockBgView addSubview:iv];
        [_iconViews addObject:iv];
    }
}

- (void)updatePreview {
    BOOL on          = [pref(@"enabled", @NO) boolValue];
    BOOL transparent = [pref(@"transparentDock", @NO) boolValue];
    BOOL hidden      = [pref(@"hideDock", @NO) boolValue];
    BOOL colorOn     = [pref(@"customColorEnabled", @NO) boolValue];
    NSString *hex    = pref(@"dockColorHex", @"000000");
    CGFloat cAlpha   = [pref(@"dockColorAlpha", @(0.5)) doubleValue];
    CGFloat blur     = [pref(@"blurIntensity", @(1.0)) doubleValue];
    BOOL radiusOn    = [pref(@"customCornerRadiusEnabled", @NO) boolValue];
    CGFloat radius   = [pref(@"cornerRadius", @(20.0)) doubleValue];
    CGFloat scale    = [pref(@"iconScale", @(1.0)) doubleValue];

    if (!on) {
        _dockBgView.hidden = NO;
        _dockBgView.alpha = 1.0;
        _blurView.alpha = 1.0;
        _dockColorOverlay.hidden = YES;
        _dockBgView.layer.cornerRadius = 0;
        for (UIImageView *iv in _iconViews)
            iv.transform = CGAffineTransformIdentity;
        return;
    }

    _dockBgView.hidden = hidden;
    if (hidden) return;
    _dockBgView.alpha = 1.0;

    _blurView.alpha = transparent ? 0.0 : blur;

    if (colorOn && !transparent) {
        _dockColorOverlay.backgroundColor = [colorFromHex(hex) colorWithAlphaComponent:cAlpha];
        _dockColorOverlay.hidden = NO;
    } else {
        _dockColorOverlay.hidden = YES;
    }

    CGFloat r = radiusOn ? radius : 0;
    _dockBgView.layer.cornerRadius = r;
    _dockColorOverlay.layer.cornerRadius = r;
    _dockColorOverlay.clipsToBounds = YES;

    for (UIImageView *iv in _iconViews) {
        iv.transform = (scale != 1.0)
            ? CGAffineTransformMakeScale(scale, scale)
            : CGAffineTransformIdentity;
    }
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CFSTR("com.minh.customdock.prefschanged"), NULL);
}

#pragma mark - Actions

- (void)resetDefaults {
    NSArray *keys = @[
        @"enabled", @"transparentDock", @"hideDock",
        @"customColorEnabled", @"dockColorHex", @"dockColorAlpha",
        @"blurIntensity", @"customCornerRadiusEnabled", @"cornerRadius",
        @"iconScale", @"hideLabels", @"disableBounce", @"hideOnLandscape"
    ];
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, PREFS_DOMAIN);
    }
    CFPreferencesAppSynchronize(PREFS_DOMAIN);

    // Reload UI
    [self reloadSpecifiers];
    [self updatePreview];

    // Notify tweak
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.minh.customdock.prefschanged"),
        NULL, NULL, true);
}

- (void)respring {
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char **)args, NULL);
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/pass-with-high-score/CustomDock"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
