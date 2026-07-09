import 'dart:io';

import 'package:moost_core/moost_core.dart';

const _help = '''
moost — セッションメモ & 復帰コマンド（フェーズ 1 CLI サンプル）

使用法:
  moost sessions [--limit N]        直近セッション一覧を表示する
  moost memos                       メモ一覧を表示する
  moost add <sessionId> [options]   セッションにメモを登録する
    --title <title>                 メモタイトル（省略時はセッションタイトル）
    --tags <a,b,c>                  カンマ区切りのタグ
    --body <text>                   メモ本文
  moost resume <id>                 復帰コマンドを出力する（メモ ID または セッション ID）
  moost -h | --help                 このヘルプを表示する

セッション ID は先頭の数文字だけでも指定できる。
''';

Future<int> run(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.write(_help);
    return args.isEmpty ? 1 : 0;
  }

  final adapter = ClaudeCodeAdapter();
  final memoStore = MemoStore.defaultLocation();

  switch (args.first) {
    case 'sessions':
      return _sessions(adapter, args.skip(1).toList());
    case 'memos':
      return _memos(memoStore);
    case 'add':
      return _add(adapter, memoStore, args.skip(1).toList());
    case 'resume':
      return _resume(adapter, memoStore, args.skip(1).toList());
    default:
      stderr.writeln('unknown command: ${args.first}');
      stdout.write(_help);
      return 1;
  }
}

Future<int> _sessions(AgentAdapter adapter, List<String> args) async {
  final limit = _intOption(args, '--limit') ?? 20;
  final sessions = await adapter.recentSessions(limit: limit);
  if (sessions.isEmpty) {
    stdout.writeln('no sessions found');
    return 0;
  }
  for (final session in sessions) {
    final id = session.sessionId.substring(0, 8);
    final date = _formatDate(session.updatedAt.toLocal());
    stdout.writeln('$id  $date  ${session.displayTitle}');
    stdout.writeln('          ${session.projectPath}');
  }
  return 0;
}

Future<int> _memos(MemoStore store) async {
  final memos = await store.load();
  if (memos.isEmpty) {
    stdout.writeln('no memos found');
    return 0;
  }
  for (final memo in memos) {
    final id = memo.id.substring(0, 8);
    final date = _formatDate(memo.updatedAt.toLocal());
    final tags = memo.tags.isEmpty ? '' : '  [${memo.tags.join(', ')}]';
    stdout.writeln('$id  $date  ${memo.title}$tags');
    if (memo.body.isNotEmpty) {
      stdout.writeln('          ${memo.body.split('\n').first}');
    }
  }
  return 0;
}

Future<int> _add(
  AgentAdapter adapter,
  MemoStore store,
  List<String> args,
) async {
  final idPrefix = args.where((a) => !a.startsWith('--')).firstOrNull;
  if (idPrefix == null) {
    stderr.writeln('usage: moost add <sessionId> [--title ...] '
        '[--tags a,b] [--body ...]');
    return 1;
  }
  final sessions = await adapter.recentSessions(limit: 100);
  final session = sessions
      .where((s) => s.sessionId.startsWith(idPrefix))
      .firstOrNull;
  if (session == null) {
    stderr.writeln('session not found: $idPrefix');
    return 1;
  }

  final now = DateTime.now().toUtc();
  final memo = Memo(
    id: generateUuidV4(),
    agent: adapter.agentId,
    sessionId: session.sessionId,
    // メモタイトルの初期値はセッションタイトル（requirements.md 3.3）
    title: _stringOption(args, '--title') ?? session.displayTitle,
    tags: parseTags(_stringOption(args, '--tags') ?? ''),
    body: _stringOption(args, '--body') ?? '',
    projectPath: session.projectPath,
    createdAt: now,
    updatedAt: now,
  );
  await store.add(memo);
  stdout.writeln('memo added: ${memo.id}');
  stdout.writeln('  title: ${memo.title}');
  return 0;
}

Future<int> _resume(
  AgentAdapter adapter,
  MemoStore store,
  List<String> args,
) async {
  final idPrefix = args.firstOrNull;
  if (idPrefix == null) {
    stderr.writeln('usage: moost resume <memoId | sessionId>');
    return 1;
  }

  // メモ ID を優先して探す（メモは復帰情報を自己完結で持つ）
  final memos = await store.load();
  final memo = memos.where((m) => m.id.startsWith(idPrefix)).firstOrNull;
  if (memo != null) {
    stdout.writeln(adapter.buildResumeCommand(
      projectPath: memo.projectPath,
      sessionId: memo.sessionId,
    ));
    return 0;
  }

  final sessions = await adapter.recentSessions(limit: 100);
  final session = sessions
      .where((s) => s.sessionId.startsWith(idPrefix))
      .firstOrNull;
  if (session == null) {
    stderr.writeln('not found: $idPrefix');
    return 1;
  }
  stdout.writeln(adapter.buildResumeCommand(
    projectPath: session.projectPath,
    sessionId: session.sessionId,
  ));
  return 0;
}

String? _stringOption(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}

int? _intOption(List<String> args, String name) {
  final value = _stringOption(args, name);
  return value == null ? null : int.tryParse(value);
}

String _formatDate(DateTime dt) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
      '${pad(dt.hour)}:${pad(dt.minute)}';
}

Future<void> main(List<String> args) async {
  final code = await run(args);
  // exit() はバッファされた出力を捨てることがあるため先に flush する
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
