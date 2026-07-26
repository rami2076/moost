import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_mcp_server/moost_mcp_server.dart';

/// エントリポイント。stdio 経由で MCP ホスト（Claude Desktop / Claude Code
/// 等）から subprocess として起動される想定（Issue #43）。
void main() {
  MoostMcpServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    registry: AdapterRegistry([
      ClaudeCodeAdapter(),
      CodexAdapter(),
    ]),
    memoStore: MemoStore.defaultLocation(),
    projectStore: ProjectStore.defaultLocation(),
  );
}
