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
  String deleteConfirmTitled(String title) {
    return '「$title」を削除しますか？';
  }

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
  String runSummary(String agent) {
    return '$agent で要約する';
  }

  @override
  String get summaryNotice => 'エージェント CLI をヘッドレス実行します（利用枠を消費）。';

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

  @override
  String get metaAgent => 'エージェント';

  @override
  String get metaTitle => 'タイトル';

  @override
  String get metaProject => 'プロジェクト';

  @override
  String get metaSessionId => 'セッションID';

  @override
  String get metaLastUsed => '最終利用';

  @override
  String ralliesTarget(int count) {
    return '直近 $count ラリーを対象';
  }

  @override
  String get footerSettings => '設定';

  @override
  String get footerNotes => '注意';

  @override
  String get footerQuit => '終了';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingTerminal => '復帰先ターミナル';

  @override
  String get settingRecentLimit => '直近セッション表示件数';

  @override
  String get settingClaudePath => 'claude コマンドのパス（要約用）';

  @override
  String get settingClaudePathHint => '空欄で自動検出';

  @override
  String settingClaudePathDetected(String path) {
    return '自動検出: $path';
  }

  @override
  String get settingClaudePathNotFound => '自動検出: 見つかりません';

  @override
  String get settingCopyAnimation => 'コピー成功アニメーション';

  @override
  String get notesTitle => '注意';

  @override
  String get noteAutomationTitle => 'ターミナル操作の権限';

  @override
  String get noteAutomationBody =>
      'セッションへの初回復帰時に macOS のオートメーション権限ダイアログが出ます。一度「許可」を選べば以後は表示されません。';

  @override
  String get noteRetentionTitle => 'セッションの保持期間';

  @override
  String get noteRetentionBody =>
      'セッションは Claude Code が cleanupPeriodDays（デフォルト 30 日）に基づいて保持します。メモを登録していても、期限切れのセッションには復帰できない場合があります。';

  @override
  String get noteSummaryTitle => 'Claude 要約について';

  @override
  String get noteSummaryBody =>
      '要約は claude -p（モデル: Haiku）で実行され、実行のたびに利用枠を消費します。「直近」はローカルで抜粋するため高速・低コスト、「全体」はセッション全体を読むため時間と枠を多く消費します。';

  @override
  String get noteRefreshTitle => '一覧の更新タイミング';

  @override
  String get noteRefreshBody =>
      '直近セッション一覧は、アプリを開いたとき・タブを切り替えたとき・フォームから戻ったときに更新されます。手動リロードはなく、開きっぱなしの間は更新されません。';

  @override
  String get trayOpen => 'Moost を開く';

  @override
  String get trayQuit => 'Moost を終了';

  @override
  String get openInTerminal => 'ターミナルで開く';

  @override
  String get resumeInTerminal => 'ターミナルで再開';

  @override
  String terminalLaunchFailed(String error) {
    return 'ターミナルの起動に失敗しました: $error';
  }

  @override
  String unknownAgent(String agent) {
    return '不明なエージェント: $agent';
  }

  @override
  String updateAvailable(String version) {
    return '$version が利用可能';
  }

  @override
  String listUpdatedAt(int month, int day, String time) {
    return '$month月$day日 $time';
  }
}
