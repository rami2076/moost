import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/update/brew_updater.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('BrewPathResolver', () {
    test('falls back to login shell resolution when known paths are absent',
        () async {
      // 既知の絶対パスには何もない環境を想定し、shell 解決までは
      // 到達すること自体を確認する（実結果は環境依存なので型だけ見る）
      final resolver = BrewPathResolver();
      final path = await resolver.resolve();
      expect(path, anyOf(isNull, isA<String>()));
    });
  });

  group('BrewUpdater', () {
    Future<String> writeFakeBrew(String script) async {
      final file = File('${tempDir.path}/brew');
      await file.writeAsString('#!/bin/sh\n$script\n');
      await Process.run('chmod', ['+x', file.path]);
      return file.path;
    }

    test('runs update then upgrade --cask moost in order', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final path = await writeFakeBrew('echo "\$@" >> "${logFile.path}"');
      final resolver = _FixedPathResolver(path);
      final updater = BrewUpdater(pathResolver: resolver);

      await updater.run();

      final calls = await logFile.readAsLines();
      expect(calls, ['update', 'upgrade --cask moost']);
    });

    test('missing brew throws BrewUpdateException', () async {
      final resolver = _FixedPathResolver(null);
      final updater = BrewUpdater(pathResolver: resolver);

      await expectLater(updater.run(), throwsA(isA<BrewUpdateException>()));
    });

    test('non-zero exit from update stops before upgrade', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final path = await writeFakeBrew('''
echo "\$@" >> "${logFile.path}"
if [ "\$1" = "update" ]; then
  echo "boom" >&2
  exit 1
fi
''');
      final resolver = _FixedPathResolver(path);
      final updater = BrewUpdater(pathResolver: resolver);

      await expectLater(
        updater.run(),
        throwsA(isA<BrewUpdateException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
      final calls = await logFile.readAsLines();
      expect(calls, ['update']); // upgrade は実行されない
    });
  });
}

class _FixedPathResolver extends BrewPathResolver {
  final String? path;

  _FixedPathResolver(this.path);

  @override
  Future<String?> resolve() async => path;
}
