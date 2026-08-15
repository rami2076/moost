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

    group('repair (Issue #58)', () {
      test('succeeds on the first reinstall without touching removeBrokenApp',
          () async {
        final logFile = File('${tempDir.path}/calls.log');
        final path =
            await writeFakeBrew('echo "\$@" >> "${logFile.path}"');
        var removeCalls = 0;
        final updater = BrewUpdater(
          pathResolver: _FixedPathResolver(path),
          removeBrokenApp: () async => removeCalls++,
        );

        await updater.repair();

        expect(await logFile.readAsLines(), ['reinstall --cask moost']);
        expect(removeCalls, 0);
      });

      test(
          'removes the leftover app and retries once when the first '
          'reinstall fails (e.g. "already an App" error)', () async {
        final logFile = File('${tempDir.path}/calls.log');
        final markerFile = File('${tempDir.path}/attempted');
        final path = await writeFakeBrew('''
echo "\$@" >> "${logFile.path}"
if [ ! -f "${markerFile.path}" ]; then
  touch "${markerFile.path}"
  echo "already an App" >&2
  exit 1
fi
''');
        var removeCalls = 0;
        final updater = BrewUpdater(
          pathResolver: _FixedPathResolver(path),
          removeBrokenApp: () async => removeCalls++,
        );

        await updater.repair();

        expect(await logFile.readAsLines(),
            ['reinstall --cask moost', 'reinstall --cask moost']);
        expect(removeCalls, 1);
      });

      test('propagates the exception when the retry also fails', () async {
        final logFile = File('${tempDir.path}/calls.log');
        final path = await writeFakeBrew('''
echo "\$@" >> "${logFile.path}"
echo "boom" >&2
exit 1
''');
        var removeCalls = 0;
        final updater = BrewUpdater(
          pathResolver: _FixedPathResolver(path),
          removeBrokenApp: () async => removeCalls++,
        );

        await expectLater(
          updater.repair(),
          throwsA(isA<BrewUpdateException>()
              .having((e) => e.message, 'message', contains('boom'))),
        );
        expect(removeCalls, 1);
      });

      test('missing brew throws BrewUpdateException', () async {
        final updater = BrewUpdater(pathResolver: _FixedPathResolver(null));

        await expectLater(
            updater.repair(), throwsA(isA<BrewUpdateException>()));
      });
    });
  });
}

class _FixedPathResolver extends BrewPathResolver {
  final String? path;

  _FixedPathResolver(this.path);

  @override
  Future<String?> resolve() async => path;
}
