import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/update/update_checker.dart';

void main() {
  UpdateChecker checker(String current, Uri? Function() redirect) {
    return UpdateChecker(
      currentVersion: current,
      fetchRedirect: (_) async => redirect(),
    );
  }

  Uri tag(String tag) =>
      Uri.parse('https://github.com/rami2076/moost/releases/tag/$tag');

  group('UpdateChecker.check', () {
    test('newer release: returns version and release url', () async {
      final update = await checker('1.3.0', () => tag('v1.4.0')).check();
      expect(update!.version, '1.4.0');
      expect(update.releaseUrl, tag('v1.4.0'));
    });

    test('same version: returns null', () async {
      expect(await checker('1.4.0', () => tag('v1.4.0')).check(), isNull);
    });

    test('older release than current: returns null', () async {
      expect(await checker('2.0.0', () => tag('v1.4.0')).check(), isNull);
    });

    test('test tags with a hyphen are ignored', () async {
      expect(
        await checker('1.3.0', () => tag('v9.9.9-citest')).check(),
        isNull,
      );
    });

    test('no redirect: returns null silently', () async {
      expect(await checker('1.3.0', () => null).check(), isNull);
    });

    test('fetcher failure: returns null silently', () async {
      final failing = UpdateChecker(
        currentVersion: '1.3.0',
        fetchRedirect: (_) async => throw Exception('offline'),
      );
      expect(await failing.check(), isNull);
    });

    test('unexpected redirect target: returns null', () async {
      expect(
        await checker('1.3.0', () => Uri.parse('https://github.com/'))
            .check(),
        isNull,
      );
    });
  });

  group('isNewerVersion', () {
    test('compares numerically per segment', () {
      expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('1.3.0', '1.3.0'), isFalse);
      expect(isNewerVersion('1.2.9', '1.3.0'), isFalse);
    });

    test('ignores build metadata', () {
      expect(isNewerVersion('1.4.0', '1.3.0+4'), isTrue);
      expect(isNewerVersion('1.3.0', '1.3.0+4'), isFalse);
    });
  });
}
