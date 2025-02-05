#import "Satella.h"

static void refreshPrefs() { // prefs by skittyblock
	CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	if (keyList) {
		settings = (NSMutableDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, (CFStringRef)bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
		CFRelease(keyList);
	} else settings = nil;
	if (!settings) settings = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", bundleIdentifier]];

	enabled     = [([settings objectForKey:@"enabled"] ?: @(true)) boolValue];
	fakeReceipt = [([settings objectForKey:@"fakeReceipt"] ?: @(false)) boolValue];
	enableAll   = [([settings objectForKey:@"enableAll"] ?: @(false)) boolValue];
}

static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  refreshPrefs();
}

static bool enabledInApp (NSString* appName) { // this uses altlist to see what apps the user wants to hack and doesn't inject in any other processes
	NSDictionary* altlistPrefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/ai.paisseon.satella.plist"]; // get all enabled apps
	return [altlistPrefs[@"apps"] containsObject:appName]; // returns true if app is whitelisted
}

%group Main
%hook SKPaymentTransaction
- (long long) transactionState {
	return 1; // this sets transactionState to SKPaymentTransactionStatePurchased
}

- (void) _setTransactionState: (long long) arg1 {
	%orig(1); // iOS 14 compatibility
}
%end

%hook SKPaymentQueue
+ (bool) canMakePayments {
	return true; // allow restricted users to fake purchase
}
%end
%end

%group Receipts
%hook SKPaymentTransaction
- (NSData*) transactionReceipt {
	return [[NSData alloc] initWithBase64EncodedString:satellaReceipt options:0]; // this creates a fake receipt data (iOS 13 only!)
}

- (void) _setTransactionReceipt: (id) arg1 {
	%orig([[NSData alloc] initWithBase64EncodedString:satellaReceipt options:0]);
}
%end

%hook SKReceiptRefreshRequest
- (bool) _wantsRevoked {
	return false; // make the receipt not revoked
}

- (bool) _wantsExpired {
	return false; // make the receipt not expired
}
%end
%end

%ctor {
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback) PreferencesChangedCallback, (CFStringRef)[NSString stringWithFormat:@"%@.prefschanged", bundleIdentifier], NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	refreshPrefs();
	NSString* appName = [[NSBundle mainBundle] bundleIdentifier];
	if ((enabled && enabledInApp(appName)) || (enableAll && ![appName containsString:@"com.apple."])) {
		%init(Main);
		if (fakeReceipt) %init(Receipts);
	}
}