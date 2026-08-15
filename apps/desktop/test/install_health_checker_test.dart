import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/update/install_health_checker.dart';

void main() {
  group('InstallHealthChecker (Issue #58)', () {
    test('reports healthy when the executable exists and Caskroom is clean',
        () async {
      final checker = InstallHealthChecker(
        fileExists: (_) async => true,
        listEntries: (_) async => const ['1.9.1'],
      );

      expect(await checker.isBroken(), isFalse);
    });

    test('reports broken when the executable is missing', () async {
      final checker = InstallHealthChecker(
        fileExists: (_) async => false,
        listEntries: (_) async => const ['1.9.1'],
      );

      expect(await checker.isBroken(), isTrue);
    });

    test('reports broken when a leftover .upgrading directory remains',
        () async {
      final checker = InstallHealthChecker(
        fileExists: (_) async => true,
        listEntries: (dirPath) async =>
            dirPath.endsWith('/Caskroom/moost') ? ['1.9.0.upgrading'] : [],
      );

      expect(await checker.isBroken(), isTrue);
    });

    test('reports healthy when Caskroom directories do not exist (non-brew '
        'install)', () async {
      final checker = InstallHealthChecker(
        fileExists: (_) async => true,
        listEntries: (_) async => const [],
      );

      expect(await checker.isBroken(), isFalse);
    });
  });
}
