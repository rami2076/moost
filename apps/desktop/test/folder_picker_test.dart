import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_desktop/src/project/folder_picker.dart';

void main() {
  group('FolderPicker', () {
    test('returns the trimmed path without a trailing slash', () async {
      final picker = FolderPicker(runOsascript: (args) async {
        return ProcessResult(0, 0, '/Users/foo/project/\n', '');
      });
      expect(await picker.pick(), '/Users/foo/project');
    });

    test('passes the choose folder script to osascript', () async {
      List<String>? calledArgs;
      final picker = FolderPicker(runOsascript: (args) async {
        calledArgs = args;
        return ProcessResult(0, 0, '/tmp/\n', '');
      });
      await picker.pick();
      expect(calledArgs![1], contains('choose folder'));
    });

    test('returns null when the user cancels (non-zero exit)', () async {
      final picker = FolderPicker(runOsascript: (args) async {
        return ProcessResult(0, 1, '', 'User canceled.');
      });
      expect(await picker.pick(), isNull);
    });

    test('returns null for empty stdout', () async {
      final picker = FolderPicker(runOsascript: (args) async {
        return ProcessResult(0, 0, '', '');
      });
      expect(await picker.pick(), isNull);
    });
  });
}
