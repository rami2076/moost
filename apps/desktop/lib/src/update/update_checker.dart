import 'dart:io';

import 'package:flutter/foundation.dart';

/// 新しいバージョンの情報。
@immutable
class UpdateInfo {
  /// 例: "1.4.0"（先頭の v は含まない）。
  final String version;

  final Uri releaseUrl;

  const UpdateInfo({required this.version, required this.releaseUrl});
}

/// `releases/latest` へのリクエストに対するリダイレクト先を返す。
/// リダイレクトでなかった・失敗したときは null。
typedef LatestReleaseFetcher = Future<Uri?> Function(Uri endpoint);

/// GitHub の最新リリースを「リダイレクト方式」でチェックする（Issue #12）。
///
/// Web の `releases/latest` は最新安定版のタグページへ 302 を返し、
/// `Location` ヘッダにタグが含まれる。API ではないのでレート制限がなく、
/// JSON / XML のパースも不要（方式の比較は docs の app-update-check-methods.md）。
///
/// 失敗（オフライン・想定外のレスポンス）は null 扱いで沈黙する。
/// 通知機能の不具合でアプリ本体を壊さない。
class UpdateChecker {
  final String currentVersion;
  final Uri endpoint;
  final LatestReleaseFetcher _fetchRedirect;

  UpdateChecker({
    required this.currentVersion,
    Uri? endpoint,
    LatestReleaseFetcher? fetchRedirect,
  })  : endpoint = endpoint ??
            Uri.parse('https://github.com/rami2076/moost/releases/latest'),
        _fetchRedirect = fetchRedirect ?? _headRedirect;

  /// 新しいバージョンがあれば [UpdateInfo]、なければ null。
  Future<UpdateInfo?> check() async {
    try {
      final location = await _fetchRedirect(endpoint);
      if (location == null) {
        return null;
      }
      // .../releases/tag/v1.4.0 の末尾からタグを取り出す
      final segments = location.pathSegments;
      final tagIndex = segments.lastIndexOf('tag');
      if (tagIndex < 0 || tagIndex + 1 >= segments.length) {
        return null;
      }
      final tag = segments[tagIndex + 1];
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      // テストタグ等（`-` 入り）は通知しない
      if (latest.contains('-')) {
        return null;
      }
      if (!isNewerVersion(latest, currentVersion)) {
        return null;
      }
      return UpdateInfo(version: latest, releaseUrl: location);
    } on Object {
      return null;
    }
  }

  static Future<Uri?> _headRedirect(Uri endpoint) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.headUrl(endpoint);
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return null;
      }
      final location =
          response.headers.value(HttpHeaders.locationHeader);
      if (location == null) {
        return null;
      }
      return endpoint.resolve(location);
    } finally {
      client.close();
    }
  }
}

/// `latest` が `current` より新しいか（"x.y.z" の数値比較。
/// ビルド番号 `+n` は無視する）。
bool isNewerVersion(String latest, String current) {
  List<int> parse(String version) {
    final core = version.split('+').first.split('-').first;
    return [
      for (final part in core.split('.')) int.tryParse(part) ?? 0,
    ];
  }

  final a = parse(latest);
  final b = parse(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) {
      return x > y;
    }
  }
  return false;
}
