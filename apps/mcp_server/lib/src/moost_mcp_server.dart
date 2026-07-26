import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:moost_core/moost_core.dart';

/// Moost の直近セッション・メモ・登録プロジェクトを読み取り専用の MCP
/// ツールとして公開するサーバー（Issue #43）。
///
/// v1 は読み取り専用ツールのみ（LLM がデータを誤って書き換えるリスクを
/// 避けるため。design 詳細は docs リポジトリ project/moost/moost-mcp-plan.html）。
base class MoostMcpServer extends MCPServer with ToolsSupport {
  final AdapterRegistry registry;
  final MemoRepository memoStore;
  final ProjectRepository projectStore;

  MoostMcpServer(
    super.channel, {
    required this.registry,
    required this.memoStore,
    required this.projectStore,
  }) : super.fromStreamChannel(
          implementation: Implementation(
            name: 'moost',
            version: '0.1.0',
          ),
          instructions:
              'Moost の直近セッション・メモ・登録プロジェクトを読み取る'
              'ツール群。書き込み系のツールはまだない。',
        ) {
    registerTool(listRecentSessionsTool, _listRecentSessions);
    registerTool(listMemosTool, _listMemos);
    registerTool(listRegisteredProjectsTool, _listRegisteredProjects);
    registerTool(getResumeCommandTool, _getResumeCommand);
  }

  static final listRecentSessionsTool = Tool(
    name: 'list_recent_sessions',
    description:
        'Claude Code / Codex の直近セッションを最新順に一覧する。',
    inputSchema: Schema.object(
      properties: {
        'limit': Schema.int(
          description: '取得件数の上限（デフォルト 20）',
        ),
      },
    ),
  );

  Future<CallToolResult> _listRecentSessions(CallToolRequest request) async {
    final limit = (request.arguments?['limit'] as int?) ?? 20;
    final sessions = await registry.recentSessions(limit: limit);
    return _jsonResult(sessions
        .map((s) => {
              'agent': s.agentId,
              'sessionId': s.sessionId,
              'projectPath': s.projectPath,
              'title': s.displayTitle,
              'updatedAt': s.updatedAt.toUtc().toIso8601String(),
            })
        .toList());
  }

  static final listMemosTool = Tool(
    name: 'list_memos',
    description: '登録済みのメモを一覧する。',
    inputSchema: Schema.object(properties: {}),
  );

  Future<CallToolResult> _listMemos(CallToolRequest request) async {
    final memos = await memoStore.load();
    return _jsonResult(memos
        .map((m) => {
              'id': m.id,
              'agent': m.agent,
              'sessionId': m.sessionId,
              'title': m.title,
              'tags': m.tags,
              'body': m.body,
              'projectPath': m.projectPath,
              'createdAt': m.createdAt.toUtc().toIso8601String(),
              'updatedAt': m.updatedAt.toUtc().toIso8601String(),
            })
        .toList());
  }

  static final listRegisteredProjectsTool = Tool(
    name: 'list_registered_projects',
    description:
        'セッション履歴がまだないディレクトリでも登録しておける'
        '「登録プロジェクト」を一覧する。',
    inputSchema: Schema.object(properties: {}),
  );

  Future<CallToolResult> _listRegisteredProjects(
      CallToolRequest request) async {
    final projects = await projectStore.load();
    return _jsonResult(projects
        .map((p) => {
              'id': p.id,
              'projectPath': p.projectPath,
              'displayName': p.displayName,
              'createdAt': p.createdAt.toUtc().toIso8601String(),
            })
        .toList());
  }

  static final getResumeCommandTool = Tool(
    name: 'get_resume_command',
    description:
        '指定したセッションへ復帰するためのシェルコマンドを組み立てる。',
    inputSchema: Schema.object(
      properties: {
        'agent': Schema.string(
          description: 'エージェント種別（例: "claude-code", "codex"）',
        ),
        'projectPath': Schema.string(
          description: '復帰先ディレクトリの絶対パス',
        ),
        'sessionId': Schema.string(
          description: '復帰するセッションの ID',
        ),
      },
      required: ['agent', 'projectPath', 'sessionId'],
    ),
  );

  Future<CallToolResult> _getResumeCommand(CallToolRequest request) async {
    final args = request.arguments!;
    final agent = args['agent'] as String;
    final adapter = registry.byId(agent);
    if (adapter == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'unknown agent: $agent')],
      );
    }
    final command = adapter.buildResumeCommand(
      projectPath: args['projectPath'] as String,
      sessionId: args['sessionId'] as String,
    );
    return CallToolResult(content: [TextContent(text: command)]);
  }

  CallToolResult _jsonResult(Object? data) => CallToolResult(
        content: [TextContent(text: jsonEncode(data))],
      );
}
