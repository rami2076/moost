import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/mcp/mcp_binary_locator.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('macOS: binaryPath derives Contents/Resources/moost-mcp from the '
      'running executable', () {
    final exePath =
        '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
    final locator = McpBinaryLocator(
      resolvedExecutable: exePath,
      isLinux: false,
    );

    expect(
      locator.binaryPath,
      '${tempDir.path}/Moost.app/Contents/Resources/moost-mcp',
    );
  });

  test('Linux: binaryPath sits next to the executable (bundle layout)',
      () {
    final exePath =
        '${tempDir.path}/bundle/moost_desktop';
    final locator = McpBinaryLocator(
      resolvedExecutable: exePath,
      isLinux: true,
    );

    expect(locator.binaryPath, '${tempDir.path}/bundle/moost-mcp');
  });

  group('exists', () {
    test('false when the binary is not bundled (e.g. dev build)', () async {
      final exePath =
          '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
      final locator = McpBinaryLocator(
        resolvedExecutable: exePath,
        isLinux: false,
      );

      expect(await locator.exists(), isFalse);
    });

    test('true when the binary is present at the derived path (macOS)',
        () async {
      final resourcesDir =
          Directory('${tempDir.path}/Moost.app/Contents/Resources');
      await resourcesDir.create(recursive: true);
      await File('${resourcesDir.path}/moost-mcp').writeAsString('');

      final exePath =
          '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
      final locator = McpBinaryLocator(
        resolvedExecutable: exePath,
        isLinux: false,
      );

      expect(await locator.exists(), isTrue);
    });

    test('true when the binary is present at the derived path (Linux)',
        () async {
      final bundleDir = Directory('${tempDir.path}/bundle');
      await bundleDir.create(recursive: true);
      await File('${bundleDir.path}/moost-mcp').writeAsString('');

      final exePath = '${tempDir.path}/bundle/moost_desktop';
      final locator = McpBinaryLocator(
        resolvedExecutable: exePath,
        isLinux: true,
      );

      expect(await locator.exists(), isTrue);
    });
  });
}
