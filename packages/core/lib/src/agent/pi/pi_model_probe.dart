import 'dart:convert';
import 'dart:io';

/// pi の設定（`~/.pi/agent/models.json`）に載っている provider/model のうち、
/// 実際にサーバーが配信している 1 組を返す。
///
/// pi は起動時に既定 provider/model を使うため、複数のローカル LLM を
/// 切り替える環境では既定モデルが配信されておらず 404 になる（Issue #68）。
/// moost から復帰・新規作成するコマンドに配信中のモデルを渡せば、
/// 設定なしでも動くようになる。検出できない場合は null（pi 既定に従う）。
class PiModelProbe {
  /// pi の models.json。テストで差し替えられるようにする。
  final File modelsFile;

  /// HTTP クライアント生成（テストで置き換え可能）。
  final HttpClient Function() httpClientFactory;

  PiModelProbe({
    File? modelsFile,
    HttpClient Function()? httpClientFactory,
  })  : modelsFile =
            modelsFile ??
                File('${Platform.environment['HOME'] ?? ''}/.pi/agent/models.json'),
        httpClientFactory =
            httpClientFactory ?? (() => HttpClient());

  /// 配信中の (provider, model) を 1 組返す。無ければ null。
  Future<(String, String)?> detectServedModel() async {
    final Map<String, Object?>? providers;
    try {
      providers = _readProviders(modelsFile);
    } on Object {
      return null;
    }
    if (providers == null || providers.isEmpty) {
      return null;
    }

    final client = httpClientFactory();
    try {
      for (final entry in providers.entries) {
        final providerName = entry.key;
        final provider = entry.value;
        if (provider is! Map<String, Object?>) {
          continue;
        }
        final baseUrl = provider['baseUrl'];
        final configured = provider['models'];
        if (baseUrl is! String ||
            baseUrl.isEmpty ||
            configured is! List<Object?>) {
          continue;
        }
        final ids = configured
            .whereType<Map<String, Object?>>()
            .map((m) => m['id'])
            .whereType<String>()
            .toSet();
        if (ids.isEmpty) {
          continue;
        }
        final served = await _fetchServedModelIds(client, baseUrl);
        if (served == null) {
          continue; // 接続できない provider は飛ばす
        }
        // 設定に載っている ID の中で「サーバーが実際に配信している」ものを優先
        final matched = served
            .where(ids.contains)
            .toList()
          ..sort();
        if (matched.isNotEmpty) {
          return (providerName, matched.first);
        }
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?>? _readProviders(File file) {
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?> || decoded['providers'] is! Map) {
      return null;
    }
    final providers = decoded['providers'] as Map;
    return providers.cast<String, Object?>();
  }

  Future<Set<String>?> _fetchServedModelIds(
      HttpClient client, String baseUrl) async {
    final uri = Uri.parse(baseUrl.endsWith('/')
        ? '${baseUrl}models'
        : '$baseUrl/models');
    try {
      final request = await client.getUrl(uri);
      final response = await request
          .close()
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final data = decoded['data'];
      if (data is! List<Object?>) {
        return null;
      }
      return data
          .whereType<Map<String, Object?>>()
          .map((m) => m['id'])
          .whereType<String>()
          .toSet();
    } on Object {
      return null;
    }
  }
}
