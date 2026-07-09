// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Moost';

  @override
  String get tabRecentSessions => 'Recent Sessions';

  @override
  String get tabMemos => 'Memos';

  @override
  String get noSessionsFound => 'No sessions found';

  @override
  String get noMemosFound => 'No memos found';

  @override
  String get copyResumeCommand => 'Copy resume command';

  @override
  String get resumeCommandCopied => 'Resume command copied';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get settings => 'Settings';

  @override
  String get notes => 'Notes';

  @override
  String get memoFormNewTitle => 'Register Memo';

  @override
  String get memoFormEditTitle => 'Edit Memo';

  @override
  String get fieldTitleLabel => 'Title';

  @override
  String get fieldTagsLabel => 'Tags (comma separated)';

  @override
  String get fieldBodyLabel => 'Body';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get deleteConfirmMessage => 'Delete this memo?';

  @override
  String sessionIdLabel(String id) {
    return 'Session ID: $id';
  }

  @override
  String get sessionDetailTitle => 'Session Detail';

  @override
  String get back => 'Back';

  @override
  String get summaryScopeRecent => 'Recent';

  @override
  String get summaryScopeFull => 'Whole session';

  @override
  String get summaryRalliesLabel => 'Rallies';

  @override
  String get runSummary => 'Summarize with Claude';

  @override
  String get summaryNotice =>
      'Runs claude -p (model: Haiku) and consumes your usage quota.';

  @override
  String get summaryRunning => 'Summarizing…';

  @override
  String summaryFailed(String error) {
    return 'Summarize failed: $error';
  }

  @override
  String get registerMemo => 'Register memo';

  @override
  String get lastPromptLabel => 'Last prompt';
}
