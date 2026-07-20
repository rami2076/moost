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
  String deleteConfirmTitled(String title) {
    return 'Delete \"$title\"?';
  }

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
  String runSummary(String agent) {
    return 'Summarize with $agent';
  }

  @override
  String get summaryNotice =>
      'Runs the agent CLI headless and consumes your usage quota.';

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

  @override
  String get metaAgent => 'Agent';

  @override
  String get metaTitle => 'Title';

  @override
  String get metaProject => 'Project';

  @override
  String get metaSessionId => 'Session ID';

  @override
  String get metaLastUsed => 'Last used';

  @override
  String ralliesTarget(int count) {
    return 'Last $count rallies';
  }

  @override
  String get footerSettings => 'Settings';

  @override
  String get footerNotes => 'Notes';

  @override
  String get footerQuit => 'Quit';

  @override
  String get settingsTitle => 'Settings';

  @override
  String settingVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingTerminal => 'Resume terminal';

  @override
  String get settingRecentLimit => 'Recent sessions shown';

  @override
  String get settingClaudePath => 'claude command path (for summaries)';

  @override
  String get settingClaudePathHint => 'Leave empty to auto-detect';

  @override
  String settingClaudePathDetected(String path) {
    return 'Auto-detected: $path';
  }

  @override
  String get settingClaudePathNotFound => 'Auto-detect: not found';

  @override
  String get settingCopyAnimation => 'Copy success animation';

  @override
  String get notesTitle => 'Notes';

  @override
  String get noteAutomationTitle => 'Terminal automation permission';

  @override
  String get noteAutomationBody =>
      'The first time you resume a session, macOS asks for automation permission. Allow it once and it won\'t ask again.';

  @override
  String get noteRetentionTitle => 'Session retention';

  @override
  String get noteRetentionBody =>
      'Sessions are kept by Claude Code based on cleanupPeriodDays (default 30 days). Even with a memo, an expired session may no longer be resumable.';

  @override
  String get noteSummaryTitle => 'About summaries';

  @override
  String get noteSummaryBody =>
      'Summaries run claude -p (model: Haiku) and consume your usage quota each time. \'Recent\' extracts locally and is fast/cheap; \'Whole session\' reads everything and costs more.';

  @override
  String get noteRefreshTitle => 'List refresh timing';

  @override
  String get noteRefreshBody =>
      'The recent-sessions list refreshes when you open the app, switch tabs, or return from a form. There is no manual reload; it does not update while left open.';

  @override
  String get trayOpen => 'Open Moost';

  @override
  String get trayQuit => 'Quit Moost';

  @override
  String get openInTerminal => 'Open in terminal';

  @override
  String get resumeInTerminal => 'Resume in terminal';

  @override
  String terminalLaunchFailed(String error) {
    return 'Failed to open terminal: $error';
  }

  @override
  String unknownAgent(String agent) {
    return 'Unknown agent: $agent';
  }

  @override
  String get update => 'Update';

  @override
  String updateAvailable(String version) {
    return '$version available';
  }

  @override
  String get updateConfirmQuestion => 'Update now?';

  @override
  String get updateConfirmCopyQuestion => 'Copy the update command instead?';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get updateCommandCopied => 'Command copied';

  @override
  String get updateRunning => 'Updating…';

  @override
  String get updateRestart => 'Restart';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String listUpdatedAt(int month, int day, String time) {
    return '$month/$day $time';
  }
}
