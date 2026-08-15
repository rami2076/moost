import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_desktop/src/mcp/mcp_setup_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('moost_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> writeFakeScript(String name, String script) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString('#!/bin/sh\n$script\n');
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  group('registerClaudeCode', () {
    test('runs claude mcp add with the binary path', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final claudePath = await writeFakeScript(
          'claude', 'echo "\$@" >> "${logFile.path}"');
      final service = McpSetupService(
        claudeResolver: _FixedClaudeResolver(claudePath),
      );

      await service.registerClaudeCode('/path/to/moost-mcp');

      final calls = await logFile.readAsLines();
      expect(calls, ['mcp add -s user moost -- /path/to/moost-mcp']);
    });

    test('throws when claude command is not found', () async {
      final service =
          McpSetupService(claudeResolver: _FixedClaudeResolver(null));

      await expectLater(
        service.registerClaudeCode('/path/to/moost-mcp'),
        throwsA(isA<McpSetupException>()),
      );
    });

    test('throws with stderr detail on non-zero exit', () async {
      final claudePath = await writeFakeScript(
          'claude', 'echo "boom" >&2\nexit 1');
      final service = McpSetupService(
        claudeResolver: _FixedClaudeResolver(claudePath),
      );

      await expectLater(
        service.registerClaudeCode('/path/to/moost-mcp'),
        throwsA(isA<McpSetupException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });

  group('registerCodex', () {
    test('runs codex mcp add with the binary path', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final codexPath = await writeFakeScript(
          'codex', 'echo "\$@" >> "${logFile.path}"');
      final service = McpSetupService(
        codexResolver: _FixedCodexResolver(codexPath),
      );

      await service.registerCodex('/path/to/moost-mcp');

      final calls = await logFile.readAsLines();
      expect(calls, ['mcp add moost -- /path/to/moost-mcp']);
    });

    test('throws when codex command is not found', () async {
      final service =
          McpSetupService(codexResolver: _FixedCodexResolver(null));

      await expectLater(
        service.registerCodex('/path/to/moost-mcp'),
        throwsA(isA<McpSetupException>()),
      );
    });
  });

  group('unregisterClaudeCode', () {
    test('runs claude mcp remove for user scope', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final claudePath = await writeFakeScript(
          'claude', 'echo "\$@" >> "${logFile.path}"');
      final service = McpSetupService(
        claudeResolver: _FixedClaudeResolver(claudePath),
      );

      await service.unregisterClaudeCode();

      final calls = await logFile.readAsLines();
      expect(calls, ['mcp remove moost -s user']);
    });

    test('throws when claude command is not found', () async {
      final service =
          McpSetupService(claudeResolver: _FixedClaudeResolver(null));

      await expectLater(
        service.unregisterClaudeCode(),
        throwsA(isA<McpSetupException>()),
      );
    });
  });

  group('unregisterCodex', () {
    test('runs codex mcp remove', () async {
      final logFile = File('${tempDir.path}/calls.log');
      final codexPath = await writeFakeScript(
          'codex', 'echo "\$@" >> "${logFile.path}"');
      final service = McpSetupService(
        codexResolver: _FixedCodexResolver(codexPath),
      );

      await service.unregisterCodex();

      final calls = await logFile.readAsLines();
      expect(calls, ['mcp remove moost']);
    });
  });

  group('isClaudeCodeConnected', () {
    test('true when claude mcp get exits successfully', () async {
      final claudePath = await writeFakeScript('claude', 'exit 0');
      final service = McpSetupService(
        claudeResolver: _FixedClaudeResolver(claudePath),
      );

      expect(await service.isClaudeCodeConnected(), isTrue);
    });

    test('false when claude mcp get exits with an error', () async {
      final claudePath = await writeFakeScript('claude', 'exit 1');
      final service = McpSetupService(
        claudeResolver: _FixedClaudeResolver(claudePath),
      );

      expect(await service.isClaudeCodeConnected(), isFalse);
    });

    test('false when claude command is not found', () async {
      final service =
          McpSetupService(claudeResolver: _FixedClaudeResolver(null));

      expect(await service.isClaudeCodeConnected(), isFalse);
    });
  });

  group('isCodexConnected', () {
    test('true when codex mcp get exits successfully', () async {
      final codexPath = await writeFakeScript('codex', 'exit 0');
      final service = McpSetupService(
        codexResolver: _FixedCodexResolver(codexPath),
      );

      expect(await service.isCodexConnected(), isTrue);
    });

    test('false when codex mcp get exits with an error', () async {
      final codexPath = await writeFakeScript('codex', 'exit 1');
      final service = McpSetupService(
        codexResolver: _FixedCodexResolver(codexPath),
      );

      expect(await service.isCodexConnected(), isFalse);
    });
  });

  group('isClaudeDesktopConnected', () {
    File configFile(String home) => File(
        '$home/Library/Application Support/Claude/claude_desktop_config.json');

    test('false when the config file does not exist', () async {
      final service = McpSetupService(home: tempDir.path);

      expect(await service.isClaudeDesktopConnected(), isFalse);
    });

    test('false when moost is not registered', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'mcpServers': {
          'other-tool': {'command': '/usr/bin/other-tool'},
        },
      }));
      final service = McpSetupService(home: tempDir.path);

      expect(await service.isClaudeDesktopConnected(), isFalse);
    });

    test('true when moost is already registered', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'mcpServers': {
          'moost': {'command': '/path/to/moost-mcp'},
        },
      }));
      final service = McpSetupService(home: tempDir.path);

      expect(await service.isClaudeDesktopConnected(), isTrue);
    });

    test('false on invalid JSON instead of throwing', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{not valid json');
      final service = McpSetupService(home: tempDir.path);

      expect(await service.isClaudeDesktopConnected(), isFalse);
    });
  });

  group('registerClaudeDesktop', () {
    File configFile(String home) =>
        File('$home/Library/Application Support/Claude/claude_desktop_config.json');

    test('creates a new config file when none exists', () async {
      final service = McpSetupService(home: tempDir.path);

      await service.registerClaudeDesktop('/path/to/moost-mcp');

      final content = jsonDecode(await configFile(tempDir.path).readAsString())
          as Map<String, Object?>;
      expect(content['mcpServers'], {
        'moost': {'command': '/path/to/moost-mcp'},
      });
    });

    test('preserves other mcpServers entries and only touches moost', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'mcpServers': {
          'other-tool': {'command': '/usr/bin/other-tool'},
        },
      }));
      final service = McpSetupService(home: tempDir.path);

      await service.registerClaudeDesktop('/path/to/moost-mcp');

      final content = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final servers = content['mcpServers'] as Map<String, Object?>;
      expect(servers['other-tool'], {'command': '/usr/bin/other-tool'});
      expect(servers['moost'], {'command': '/path/to/moost-mcp'});
    });

    test('throws instead of overwriting invalid JSON', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{not valid json');
      final service = McpSetupService(home: tempDir.path);

      await expectLater(
        service.registerClaudeDesktop('/path/to/moost-mcp'),
        throwsA(isA<McpSetupException>()),
      );
      // ファイルは書き換えられていないこと
      expect(await file.readAsString(), '{not valid json');
    });
  });

  group('unregisterClaudeDesktop', () {
    File configFile(String home) =>
        File('$home/Library/Application Support/Claude/claude_desktop_config.json');

    test('no-op when the config file does not exist', () async {
      final service = McpSetupService(home: tempDir.path);

      await service.unregisterClaudeDesktop();

      expect(await configFile(tempDir.path).exists(), isFalse);
    });

    test('removes only the moost key, preserving other servers', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'mcpServers': {
          'other-tool': {'command': '/usr/bin/other-tool'},
          'moost': {'command': '/path/to/moost-mcp'},
        },
      }));
      final service = McpSetupService(home: tempDir.path);

      await service.unregisterClaudeDesktop();

      final content = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final servers = content['mcpServers'] as Map<String, Object?>;
      expect(servers.containsKey('moost'), isFalse);
      expect(servers['other-tool'], {'command': '/usr/bin/other-tool'});
    });

    test('throws instead of overwriting invalid JSON', () async {
      final file = configFile(tempDir.path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{not valid json');
      final service = McpSetupService(home: tempDir.path);

      await expectLater(
        service.unregisterClaudeDesktop(),
        throwsA(isA<McpSetupException>()),
      );
    });
  });

  group('testConnection', () {
    test('throws when the binary does not exist', () async {
      final service = McpSetupService();

      await expectLater(
        service.testConnection('${tempDir.path}/does-not-exist'),
        throwsA(isA<McpSetupException>()),
      );
    });

    test('returns true when initialize gets a matching response', () async {
      final binary = await writeFakeScript('moost-mcp', r'''
read -r line
id=$(echo "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
''');
      final service = McpSetupService();

      final result = await service.testConnection(binary,
          timeout: const Duration(seconds: 2));

      expect(result, isTrue);
    });

    test('returns false when no response arrives before the timeout',
        () async {
      final binary = await writeFakeScript('moost-mcp', 'sleep 5');
      final service = McpSetupService();

      final result = await service.testConnection(binary,
          timeout: const Duration(milliseconds: 200));

      expect(result, isFalse);
    });
  });
}

class _FixedClaudeResolver extends ClaudePathResolver {
  final String? path;

  _FixedClaudeResolver(this.path);

  @override
  Future<String?> resolve({String override = ''}) async => path;
}

class _FixedCodexResolver extends CodexPathResolver {
  final String? path;

  _FixedCodexResolver(this.path);

  @override
  Future<String?> resolve({String override = ''}) async => path;
}
