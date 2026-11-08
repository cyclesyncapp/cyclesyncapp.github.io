import 'platform_actions_io.dart'
    if (dart.library.js_interop) 'platform_actions_web.dart' as impl;
import 'push_types.dart';

export 'push_types.dart';

/// True when the web app is running from the home screen (installed PWA).
bool isInstalledWebApp() => impl.isInstalledWebApp();

/// True on iPhone / iPad browsers (for install instructions).
bool isAppleMobileBrowser() => impl.isAppleMobileBrowser();

/// Saves a text file: browser download on web, share sheet on Android.
Future<void> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) =>
    impl.saveTextFile(fileName: fileName, content: content, mimeType: mimeType);

/// Saves a binary file (e.g. PDF): download on web, share sheet on Android.
Future<void> saveBytesFile({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) =>
    impl.saveBytesFile(fileName: fileName, bytes: bytes, mimeType: mimeType);

/// True inside an app's built-in browser (WhatsApp, Facebook, Instagram).
bool isInAppBrowser() => impl.isInAppBrowser();

/// Remembers, for this browser tab session only, that the user is signed in.
/// Used for "sign me out when I close the app".
void markTabSession() => impl.markTabSession();
bool hasTabSession() => impl.hasTabSession();

/// Current web-push status for this browser.
Future<WebPushState> webPushState() => impl.webPushState();

/// Asks permission and subscribes this browser. Null if refused/unsupported.
Future<WebPushSubscriptionData?> subscribeWebPush(String vapidPublicKey) =>
    impl.subscribeWebPush(vapidPublicKey);

/// The push endpoint of this browser, if subscribed.
Future<String?> currentWebPushEndpoint() => impl.currentWebPushEndpoint();

/// Stops notifications in this browser.
Future<void> unsubscribeWebPush() => impl.unsubscribeWebPush();
