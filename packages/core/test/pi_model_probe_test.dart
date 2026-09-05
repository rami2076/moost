import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

/// 配信モデル一覧を返すダミー OpenAI 互換サーバー。
Future<HttpServer> startServing(List<String> modelIds) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/v1/models' || request.uri.path == '/models') {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': [for (final id in modelIds) {'id': id}],
        }));
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pimodelprobe_');
  });
  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File writeModels(Map<String, Object?> providers) {
    final file = File('${tempDir.path}/models.json');
    file.writeAsStringSync(jsonEncode({'providers': providers}));
    return file;
  }

  /// 既定 provider/model を持つ settings.json を書く（無ければ ''.''）
  File writeSettings({String provider = '', String model = ''}) {
    final file = File('${tempDir.path}/settings.json');
    file.writeAsStringSync(jsonEncode({
      if (provider.isNotEmpty) 'defaultProvider': provider,
      if (model.isNotEmpty) 'defaultModel': model,
    }));
    return file;
  }

  test('detects the first provider/model that the server serves', () async {
    final server = await startServing(['deepseek-v4-flash-0731']);
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}/v1';
    final file = writeModels({
      'gemma4': {
        'baseUrl': 'http://127.0.0.1:1/v1', // 接続不可 → スキップ
        'models': [
          {'id': 'gemma-4-26B-A4B'},
        ],
      },
      'dspark': {
        'baseUrl': base,
        'models': [
          {'id': 'deepseek-v4-flash-0731'},
          {'id': 'other-model'},
        ],
      },
    });

    final probe = PiModelProbe(
      modelsFile: file,
      settingsFile: writeSettings(),
    );
    final result = await probe.detectServedModel();
    expect(result, isNotNull);
    expect(result!.$1, 'dspark');
    expect(result.$2, 'deepseek-v4-flash-0731');
  });

  test('served default model is preferred even when later providers match',
      () async {
    final server = await startServing(
        ['deepseek-v4-flash-0731', 'gemma-4-26B-A4B']);
    addTearDown(() => server.close(force: true));
    final file = writeModels({
      'gemma4': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'gemma-4-26B-A4B'},
        ],
      },
      'dspark': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'deepseek-v4-flash-0731'},
        ],
      },
    });
    final probe = PiModelProbe(
      modelsFile: file,
      settingsFile: writeSettings(provider: 'gemma4', model: 'gemma-4-26B-A4B'),
    );
    final result = await probe.detectServedModel();
    expect(result, isNotNull);
    expect(result!.$1, 'gemma4');
    expect(result.$2, 'gemma-4-26B-A4B');
  });

  test('returns null when no configured model is served', () async {
    final server = await startServing(['Qwen3-8B-AWQ']);
    addTearDown(() => server.close(force: true));
    final file = writeModels({
      'gemma4': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'gemma-4-26B-A4B'},
        ],
      },
    });
    final probe = PiModelProbe(
      modelsFile: file,
      settingsFile: writeSettings(),
    );
    expect(await probe.detectServedModel(), isNull);
  });

  test('non-served default falls back to scanning other providers', () async {
    // settings.json で既定は gemma4 だが配信は dspark のみ → 走査で dspark を選ぶ
    final server = await startServing(['deepseek-v4-flash-0731']);
    addTearDown(() => server.close(force: true));
    final file = writeModels({
      'gemma4': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'gemma-4-26B-A4B'},
        ],
      },
      'dspark': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'deepseek-v4-flash-0731'},
        ],
      },
    });
    final probe = PiModelProbe(
      modelsFile: file,
      settingsFile: writeSettings(provider: 'gemma4', model: 'gemma-4-26B-A4B'),
    );
    final result = await probe.detectServedModel();
    expect(result, isNotNull);
    expect(result!.$1, 'dspark');
    expect(result.$2, 'deepseek-v4-flash-0731');
  });

  test('returns null when models.json is missing or malformed', () async {
    final missing = PiModelProbe(
      modelsFile: File('${tempDir.path}/nope.json'),
      settingsFile: writeSettings(),
    );
    expect(await missing.detectServedModel(), isNull);

    final malformed = PiModelProbe(
      modelsFile: (() {
        final f = File('${tempDir.path}/bad.json');
        f.writeAsStringSync('not json');
        return f;
      })(),
      settingsFile: writeSettings(),
    );
    expect(await malformed.detectServedModel(), isNull);
  });

  test('returns null when the server errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 500;
      await request.response.close();
    });
    final file = writeModels({
      'dspark': {
        'baseUrl': 'http://127.0.0.1:${server.port}/v1',
        'models': [
          {'id': 'deepseek-v4-flash-0731'},
        ],
      },
    });
    final probe = PiModelProbe(
      modelsFile: file,
      settingsFile: writeSettings(),
    );
    expect(await probe.detectServedModel(), isNull);
  });
}
