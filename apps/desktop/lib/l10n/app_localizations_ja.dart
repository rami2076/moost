// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Moost';

  @override
  String get tabRecentSessions => '直近セッション';

  @override
  String get tabMemos => 'メモ一覧';

  @override
  String get noSessionsFound => 'セッションがありません';

  @override
  String get noMemosFound => 'メモがありません';

  @override
  String get copyResumeCommand => '復帰コマンドをコピー';

  @override
  String get resumeCommandCopied => '復帰コマンドをコピーしました';

  @override
  String loadFailed(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get settings => '設定';

  @override
  String get notes => '注意';

  @override
  String get memoFormNewTitle => 'メモを登録';

  @override
  String get memoFormEditTitle => 'メモを編集';

  @override
  String get fieldTitleLabel => 'タイトル';

  @override
  String get fieldTagsLabel => 'タグ（カンマ区切り）';

  @override
  String get fieldBodyLabel => 'メモ本文';

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String get delete => '削除';

  @override
  String get deleteConfirmMessage => 'このメモを削除しますか？';

  @override
  String sessionIdLabel(String id) {
    return 'セッションID: $id';
  }

  @override
  String get sessionDetailTitle => 'セッション詳細';

  @override
  String get back => '戻る';

  @override
  String get summaryScopeRecent => '直近';

  @override
  String get summaryScopeFull => '全体';

  @override
  String get summaryRalliesLabel => 'ラリー数';

  @override
  String get runSummary => 'Claude で要約する';

  @override
  String get summaryNotice => 'claude -p（モデル: Haiku）を実行します（利用枠を消費）。';

  @override
  String get summaryRunning => '要約中…';

  @override
  String summaryFailed(String error) {
    return '要約に失敗しました: $error';
  }

  @override
  String get registerMemo => 'メモを登録';

  @override
  String get lastPromptLabel => '最終プロンプト';
}
