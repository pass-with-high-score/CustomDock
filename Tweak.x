#import <UIKit/UIKit.h>

#define PLIST_PATH @"/var/jb/var/mobile/Library/Preferences/com.minh.customdock.plist"

static BOOL isTransparentDockEnabled() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    if (!prefs) return NO;
    NSNumber *value = prefs[@"isTransparentDockEnabled"];
    return value ? [value boolValue] : NO;
}

%hook SBDockView

- (void)setBackgroundAlpha:(double)arg1 {
    if (isTransparentDockEnabled()) {
        %orig(0.0);
    } else {
        %orig(arg1);
    }
}

%end
