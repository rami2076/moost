import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:moost_core/moost_core.dart';

/// MCP 設定の登録・自己診断に失敗したときに投げる（Issue #45）。
class McpSetupException implements Exception {
  final String message;

  const McpSetupException(this.message);

  @override
  String toString() => 'McpSetupException: $message';
}

/// Moost の MCP サーバー（`moost-mcp`）を Claude Code / Codex CLI /
/// Claude Desktop へワンクリックで連携登録する（Issue #45）。
///
/// CLI 経由の登録（Claude Code / Codex）は `<cli> mcp add` を内部的に実行
/// するだけ。Claude Desktop だけは CLI サブコマンドがなく、設定 JSON を
/// 直接編集する必要があるため、既存の `mcpServers` を壊さないよう
/// `moost` キーだけをマージする。
class McpSetupService {
  final ClaudePathResolver _claudeResolver;
  final CodexPathResolver _codexResolver;
  final String _home;

  McpSetupService({
    ClaudePathResolver? claudeResolver,
    CodexPathResolver? codexResolver,
    String? home,
  })  : _claudeResolver = claudeResolver ?? ClaudePathResolver(),
        _codexResolver = codexResolver ?? CodexPathResolver(),
        _home = home ?? Platform.environment['HOME'] ?? '';

  Future<void> registerClaudeCode(String binaryPath) async {
    final claudePath = await _claudeResolver.resolve();
    if (claudePath == null) {
      throw const McpSetupException('claude command not found');
    }
    await _run(claudePath, ['mcp', 'add', '-s', 'user', 'moost', '--', binaryPath]);
  }

  Future<void> registerCodex(String binaryPath) async {
    final codexPath = await _codexResolver.resolve();
    if (codexPath == null) {
      throw const McpSetupException('codex command not found');
    }
    await _run(codexPath, ['mcp', 'add', 'moost', '--', binaryPath]);
  }

  Future<void> unregisterClaudeCode() async {
    final claudePath = await _claudeResolver.resolve();
    if (claudePath == null) {
      throw const McpSetupException('claude command not found');
    }
    await _run(claudePath, ['mcp', 'remove', 'moost', '-s', 'user']);
  }

  Future<void> unregisterCodex() async {
    final codexPath = await _codexResolver.resolve();
    if (codexPath == null) {
      throw const McpSetupException('codex command not found');
    }
    await _run(codexPath, ['mcp', 'remove', 'moost']);
  }

  /// `claude mcp get moost` の終了コードで登録済みかを判定する。
  Future<bool> isClaudeCodeConnected() async {
    final claudePath = await _claudeResolver.resolve();
    if (claudePath == null) {
      return false;
    }
    return _exitsZero(claudePath, ['mcp', 'get', 'moost']);
  }

  /// `codex mcp get moost` の終了コードで登録済みかを判定する。
  Future<bool> isCodexConnected() async {
    final codexPath = await _codexResolver.resolve();
    if (codexPath == null) {
      return false;
    }
    return _exitsZero(codexPath, ['mcp', 'get', 'moost']);
  }

  Future<bool> _exitsZero(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// `claude_desktop_config.json` の `mcpServers` に `moost` キーが
  /// 既にあるかを見るだけ（実際に接続できるかまでは検証しない）。
  Future<bool> isClaudeDesktopConnected() async {
    final file = File(
        '$_home/Library/Application Support/Claude/claude_desktop_config.json');
    if (!await file.exists()) {
      return false;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return false;
      }
      final servers = decoded['mcpServers'];
      return servers is Map && servers.containsKey('moost');
    } on FormatException {
      return false;
    }
  }

  Future<void> _run(String executable, List<String> arguments) async {
    final ProcessResult result;
    try {
      result = await Process.run(executable, arguments);
    } on ProcessException catch (e) {
      throw McpSetupException('failed to start $executable: ${e.message}');
    }
    if (result.exitCode != 0) {
      final stderrText = (result.stderr as String).trim();
      final stdoutText = (result.stdout as String).trim();
      final detail = stderrText.isEmpty ? stdoutText : stderrText;
      throw McpSetupException(
          detail.isEmpty ? 'exit code ${result.exitCode}' : detail);
    }
  }

  /// `~/Library/Application Support/Claude/claude_desktop_config.json` の
  /// `mcpServers.moost` だけを追記/更新する。他社製 MCP サーバーを含む
  /// 既存設定は壊さない（ファイル全体の上書きはしない）。
  Future<void> registerClaudeDesktop(String binaryPath) async {
    final file = File(
        '$_home/Library/Application Support/Claude/claude_desktop_config.json');

    Map<String, Object?> config = {};
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final Object? decoded;
        try {
          decoded = jsonDecode(content);
        } on FormatException {
          throw McpSetupException(
              '${file.path} is not valid JSON. Fix or remove it manually before retrying.');
        }
        if (decoded is! Map<String, Object?>) {
          throw McpSetupException('${file.path} does not contain a JSON object');
        }
        config = decoded;
      }
    }

    final rawServers = config['mcpServers'];
    final servers = rawServers is Map
        ? Map<String, Object?>.from(rawServers)
        : <String, Object?>{};
    servers['moost'] = {'command': binaryPath};
    config['mcpServers'] = servers;

    await file.parent.create(recursive: true);
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config));
  }

  /// `claude_desktop_config.json` の `mcpServers.moost` キーだけを取り除く。
  /// 他社製 MCP サーバーを含む既存設定は壊さない。
  Future<void> unregisterClaudeDesktop() async {
    final file = File(
        '$_home/Library/Application Support/Claude/claude_desktop_config.json');
    if (!await file.exists()) {
      return;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw McpSetupException(
          '${file.path} is not valid JSON. Fix or remove it manually before retrying.');
    }
    if (decoded is! Map<String, Object?>) {
      throw McpSetupException('${file.path} does not contain a JSON object');
    }
    final rawServers = decoded['mcpServers'];
    if (rawServers is! Map) {
      return;
    }
    final servers = Map<String, Object?>.from(rawServers)..remove('moost');
    decoded['mcpServers'] = servers;
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(decoded));
  }

  /// バイナリを実際に一度起動し、`initialize` ハンドシェイクが通るかを
  /// 自己診断する。成功したら true、タイムアウトしたら false を返す。
  Future<bool> testConnection(
    String binaryPath, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!await File(binaryPath).exists()) {
      throw const McpSetupException('binary not found');
    }

    final Process process;
    try {
      process = await Process.start(binaryPath, []);
    } on ProcessException catch (e) {
      throw McpSetupException('failed to start: ${e.message}');
    }

    final requestId = DateTime.now().millisecondsSinceEpoch;
    final request = jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-11-25',
        'capabilities': <String, Object?>{},
        'clientInfo': {
          'name': 'moost-desktop-selftest',
          'version': '1.0.0',
        },
      },
    });
    process.stdin.writeln(request);

    final completer = Completer<bool>();
    final subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        return; // ハンドシェイク以外の出力行は無視する
      }
      if (decoded is Map &&
          decoded['id'] == requestId &&
          decoded.containsKey('result') &&
          !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    final success = await completer.future;
    timeoutTimer.cancel();
    await subscription.cancel();
    process.kill();
    return success;
  }
}
