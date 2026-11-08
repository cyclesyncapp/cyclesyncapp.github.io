import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'push_types.dart';

bool isInstalledWebApp() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}

bool isAppleMobileBrowser() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
}

Future<void> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) =>
    _download(fileName, web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    ));

Future<void> saveBytesFile({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) =>
    _download(fileName, web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    ));

Future<void> _download(String fileName, web.Blob blob) async {
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

bool _pushSupported() {
  try {
    return globalContext.has('PushManager') &&
        globalContext.has('Notification') &&
        web.window.navigator.has('serviceWorker');
  } catch (_) {
    return false;
  }
}

Future<web.ServiceWorkerRegistration> _ready() => web
    .window.navigator.serviceWorker.ready.toDart
    .timeout(const Duration(seconds: 10));

Future<web.PushSubscription?> _currentSub() async {
  final reg = await _ready();
  return reg.pushManager.getSubscription().toDart;
}

Future<WebPushState> webPushState() async {
  if (!_pushSupported()) {
    return (isAppleMobileBrowser() && !isInstalledWebApp())
        ? WebPushState.needsInstall
        : WebPushState.unsupported;
  }
  final permission = web.Notification.permission;
  if (permission == 'denied') return WebPushState.denied;
  try {
    final sub = await _currentSub();
    if (permission == 'granted' && sub != null) return WebPushState.enabled;
  } catch (_) {
    return WebPushState.unsupported;
  }
  return WebPushState.notAsked;
}

String _b64(web.PushSubscription sub, String name) {
  final buffer = sub.getKey(name);
  if (buffer == null) return '';
  return base64Url.encode(buffer.toDart.asUint8List()).replaceAll('=', '');
}

Future<WebPushSubscriptionData?> subscribeWebPush(String vapidPublicKey) async {
  if (!_pushSupported()) return null;
  final permission = (await web.Notification.requestPermission().toDart).toDart;
  if (permission != 'granted') return null;
  final reg = await _ready();
  var sub = await reg.pushManager.getSubscription().toDart;
  sub ??= await reg.pushManager
      .subscribe(web.PushSubscriptionOptionsInit(
        userVisibleOnly: true,
        applicationServerKey: vapidPublicKey.toJS,
      ))
      .toDart;
  return WebPushSubscriptionData(
    endpoint: sub.endpoint,
    p256dh: _b64(sub, 'p256dh'),
    auth: _b64(sub, 'auth'),
  );
}

Future<String?> currentWebPushEndpoint() async {
  if (!_pushSupported()) return null;
  try {
    return (await _currentSub())?.endpoint;
  } catch (_) {
    return null;
  }
}

Future<void> unsubscribeWebPush() async {
  if (!_pushSupported()) return;
  try {
    final sub = await _currentSub();
    if (sub != null) await sub.unsubscribe().toDart;
  } catch (_) {
    // Best effort: the browser may already have dropped it.
  }
}

bool isInAppBrowser() {
  final ua = web.window.navigator.userAgent;
  return RegExp(r'WhatsApp|FBAN|FBAV|Instagram|; wv\)').hasMatch(ua);
}

const _tabKey = 'cyclesync_tab_session';

void markTabSession() {
  try {
    web.window.sessionStorage.setItem(_tabKey, '1');
  } catch (_) {
    // Storage blocked; nothing to remember.
  }
}

bool hasTabSession() {
  try {
    return web.window.sessionStorage.getItem(_tabKey) == '1';
  } catch (_) {
    return true;
  }
}
