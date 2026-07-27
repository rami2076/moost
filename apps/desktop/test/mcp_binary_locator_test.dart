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

  test('binaryPath derives Contents/Resources/moost-mcp from the running executable', () {
    final exePath =
        '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
    final locator = McpBinaryLocator(resolvedExecutable: exePath);

    expect(
      locator.binaryPath,
      '${tempDir.path}/Moost.app/Contents/Resources/moost-mcp',
    );
  });

  group('exists', () {
    test('false when the binary is not bundled (e.g. dev build)', () async {
      final exePath =
          '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
      final locator = McpBinaryLocator(resolvedExecutable: exePath);

      expect(await locator.exists(), isFalse);
    });

    test('true when the binary is present at the derived path', () async {
      final resourcesDir =
          Directory('${tempDir.path}/Moost.app/Contents/Resources');
      await resourcesDir.create(recursive: true);
      await File('${resourcesDir.path}/moost-mcp').writeAsString('');

      final exePath =
          '${tempDir.path}/Moost.app/Contents/MacOS/moost_desktop';
      final locator = McpBinaryLocator(resolvedExecutable: exePath);

      expect(await locator.exists(), isTrue);
    });
  });
}
