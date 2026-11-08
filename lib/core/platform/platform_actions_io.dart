import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'push_types.dart';

bool isInstalledWebApp() => false;

bool isAppleMobileBrowser() => false;

Future<void> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: fileName,
    ),
  );
}

Future<WebPushState> webPushState() async => WebPushState.unsupported;

Future<WebPushSubscriptionData?> subscribeWebPush(String vapidPublicKey) async =>
    null;

Future<String?> currentWebPushEndpoint() async => null;

Future<void> unsubscribeWebPush() async {}

Future<void> saveBytesFile({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: fileName,
    ),
  );
}

bool isInAppBrowser() => false;

void markTabSession() {}

bool hasTabSession() => true;
