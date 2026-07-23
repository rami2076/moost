import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/project/folder_picker.dart';

void main() {
  group('FolderPicker', () {
    test('returns the path chosen by the injected dialog function',
        () async {
      final picker =
          FolderPicker(getDirectoryPathFn: () async => '/Users/foo/project');
      expect(await picker.pick(), '/Users/foo/project');
    });

    test('returns null when the user cancels', () async {
      final picker = FolderPicker(getDirectoryPathFn: () async => null);
      expect(await picker.pick(), isNull);
    });
  });
}
