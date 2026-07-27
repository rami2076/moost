import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:moost_core/moost_core.dart';
import 'package:moost_mcp_server/moost_mcp_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'test_utils.dart';

void main() {
  Future<TestEnvironment> setUpServer({
    List<Memo>? memos,
    List<Project>? projects,
    List<AgentAdapter>? adapters,
  }) async {
    final env = TestEnvironment(
      (channel) => MoostMcpServer(
        channel,
        registry: AdapterRegistry(
          adapters ?? [FakeAdapter('claude-code'), FakeAdapter('codex')],
        ),
        memoStore: FakeMemoStore(memos),
        projectStore: FakeProjectStore(projects),
      ),
    );
    await env.initialize();
    return env;
  }

  List<Object?> decodeList(CallToolResult result) =>
      jsonDecode((result.content.single as TextContent).text) as List<Object?>;

  test('exposes exactly the 4 read-only tools', () async {
    final env = await setUpServer();

    final tools = await env.connection.listTools();

    expect(
      tools.tools.map((t) => t.name),
      unorderedEquals([
        'list_recent_sessions',
        'list_memos',
        'list_registered_projects',
        'get_resume_command',
      ]),
    );
  });

  test('list_recent_sessions merges adapters newest-first and respects limit',
      () async {
    final env = await setUpServer(adapters: [
      FakeAdapter('claude-code', [
        RecentSession(
          agentId: 'claude-code',
          sessionId: 's1',
          projectPath: '/p1',
          lastPrompt: 'older',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]),
      FakeAdapter('codex', [
        RecentSession(
          agentId: 'codex',
          sessionId: 's2',
          projectPath: '/p2',
          lastPrompt: 'newer',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      ]),
    ]);

    final result = await env.connection.callTool(
      CallToolRequest(name: 'list_recent_sessions', arguments: {'limit': 1}),
    );

    expect(result.isError, isNot(true));
    final sessions = decodeList(result).cast<Map<String, Object?>>();
    expect(sessions, hasLength(1));
    expect(sessions.single['sessionId'], 's2');
    expect(sessions.single['agent'], 'codex');
  });

  test('list_memos returns stored memos', () async {
    final memo = Memo(
      id: 'm1',
      agent: 'claude-code',
      sessionId: 's1',
      title: 'タイトル',
      tags: const ['tag1'],
      body: '本文',
      projectPath: '/p',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final env = await setUpServer(memos: [memo]);

    final result = await env.connection.callTool(
      CallToolRequest(name: 'list_memos'),
    );

    expect(result.isError, isNot(true));
    final memos = decodeList(result).cast<Map<String, Object?>>();
    expect(memos, [memo.toJson()]);
  });

  test('list_registered_projects returns stored projects', () async {
    final project = Project(
      id: 'p1',
      projectPath: '/Users/me/work',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final env = await setUpServer(projects: [project]);

    final result = await env.connection.callTool(
      CallToolRequest(name: 'list_registered_projects'),
    );

    expect(result.isError, isNot(true));
    final projects = decodeList(result).cast<Map<String, Object?>>();
    expect(projects.single['id'], 'p1');
    expect(projects.single['projectPath'], '/Users/me/work');
    expect(projects.single['displayName'], 'work');
  });

  test('get_resume_command builds the command via the matching adapter',
      () async {
    final env = await setUpServer(
      adapters: [FakeAdapter('claude-code'), FakeAdapter('codex')],
    );

    final result = await env.connection.callTool(
      CallToolRequest(
        name: 'get_resume_command',
        arguments: {
          'agent': 'codex',
          'projectPath': '/p',
          'sessionId': 's1',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(
      (result.content.single as TextContent).text,
      'codex resume s1 in /p',
    );
  });

  test('get_resume_command returns an error for an unknown agent', () async {
    final env = await setUpServer();

    final result = await env.connection.callTool(
      CallToolRequest(
        name: 'get_resume_command',
        arguments: {
          'agent': 'unknown-agent',
          'projectPath': '/p',
          'sessionId': 's1',
        },
      ),
    );

    expect(result.isError, true);
    expect(
      (result.content.single as TextContent).text,
      contains('unknown-agent'),
    );
  });
}
