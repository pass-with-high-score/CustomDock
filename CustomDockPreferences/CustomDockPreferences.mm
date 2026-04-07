#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>

@interface CustomDockPreferencesListController : PSListController
@end

@implementation CustomDockPreferencesListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring:(PSSpecifier *)specifier {
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char **)args, NULL);
}

- (void)openGitHub:(PSSpecifier *)specifier {
    NSURL *url = [NSURL URLWithString:@"https://github.com/yourusername/CustomDock"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
