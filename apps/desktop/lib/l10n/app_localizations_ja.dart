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
}
