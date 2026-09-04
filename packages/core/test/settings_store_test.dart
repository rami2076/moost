import 'dart:io';

import 'package:moost_core/moost_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SettingsStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
    store = SettingsStore(File('${tempDir.path}/v1/settings.json'));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('returns defaults when file does not exist', () async {
    final settings = await store.load();
    expect(settings.terminalApp, 'Terminal.app');
    expect(settings.recentSessionLimit, 20);
    expect(settings.claudePath, '');
    expect(settings.summaryRallyCount, 1);
    expect(settings.copyAnimation, isTrue);
    // Issue #68: pi の provider/model は既定では空（フラグを付けない）
    expect(settings.piProvider, '');
    expect(settings.piModel, '');
  });

  test('save and load roundtrip', () async {
    await store.save(const Settings(
      terminalApp: 'iTerm2',
      recentSessionLimit: 50,
      claudePath: '~/.local/bin/claude',
      summaryRallyCount: 5,
      copyAnimation: false,
      piProvider: 'dspark',
      piModel: 'deepseek-v4-flash-0731',
    ));

    final settings = await store.load();
    expect(settings.terminalApp, 'iTerm2');
    expect(settings.recentSessionLimit, 50);
    expect(settings.claudePath, '~/.local/bin/claude');
    expect(settings.summaryRallyCount, 5);
    expect(settings.copyAnimation, isFalse);
    expect(settings.piProvider, 'dspark');
    expect(settings.piModel, 'deepseek-v4-flash-0731');
  });

  test('unknown or missing keys fall back to defaults', () async {
    final file = File('${tempDir.path}/v1/settings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"schemaVersion":1,"terminalApp":"iTerm2"}');

    final settings = await store.load();
    expect(settings.terminalApp, 'iTerm2');
    expect(settings.recentSessionLimit, 20);
    // 旧バージョンの settings.json に copyAnimation はない → デフォルト true
    expect(settings.copyAnimation, isTrue);
  });

  test('piProvider only; missing piModel falls back to default', () async {
    final file = File('${tempDir.path}/v1/settings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"schemaVersion":1,"piProvider":"glm"}');

    final settings = await store.load();
    expect(settings.piProvider, 'glm');
    expect(settings.piModel, '');
  });

  test('wrong value types fall back to defaults without crashing', () async {
    final file = File('${tempDir.path}/v1/settings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
        '{"schemaVersion":1,"recentSessionLimit":50.0,"terminalApp":123}');

    final settings = await store.load();
    // double は int に変換され、型違いはデフォルトに戻る
    expect(settings.recentSessionLimit, 50);
    expect(settings.terminalApp, 'Terminal.app');
  });
}
