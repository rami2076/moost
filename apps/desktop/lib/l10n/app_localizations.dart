import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Moost'**
  String get appTitle;

  /// No description provided for @tabRecentSessions.
  ///
  /// In en, this message translates to:
  /// **'Recent Sessions'**
  String get tabRecentSessions;

  /// No description provided for @tabMemos.
  ///
  /// In en, this message translates to:
  /// **'Memos'**
  String get tabMemos;

  /// No description provided for @noSessionsFound.
  ///
  /// In en, this message translates to:
  /// **'No sessions found'**
  String get noSessionsFound;

  /// No description provided for @noMemosFound.
  ///
  /// In en, this message translates to:
  /// **'No memos found'**
  String get noMemosFound;

  /// No description provided for @copyResumeCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy resume command'**
  String get copyResumeCommand;

  /// No description provided for @resumeCommandCopied.
  ///
  /// In en, this message translates to:
  /// **'Resume command copied'**
  String get resumeCommandCopied;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String loadFailed(String error);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @memoFormNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Register Memo'**
  String get memoFormNewTitle;

  /// No description provided for @memoFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Memo'**
  String get memoFormEditTitle;

  /// No description provided for @fieldTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitleLabel;

  /// No description provided for @fieldTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get fieldTagsLabel;

  /// No description provided for @fieldBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get fieldBodyLabel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete this memo?'**
  String get deleteConfirmMessage;

  /// No description provided for @sessionIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Session ID: {id}'**
  String sessionIdLabel(String id);

  /// No description provided for @sessionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Session Detail'**
  String get sessionDetailTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @summaryScopeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get summaryScopeRecent;

  /// No description provided for @summaryScopeFull.
  ///
  /// In en, this message translates to:
  /// **'Whole session'**
  String get summaryScopeFull;

  /// No description provided for @summaryRalliesLabel.
  ///
  /// In en, this message translates to:
  /// **'Rallies'**
  String get summaryRalliesLabel;

  /// No description provided for @runSummary.
  ///
  /// In en, this message translates to:
  /// **'Summarize with {agent}'**
  String runSummary(String agent);

  /// No description provided for @summaryNotice.
  ///
  /// In en, this message translates to:
  /// **'Runs the agent CLI headless and consumes your usage quota.'**
  String get summaryNotice;

  /// No description provided for @summaryRunning.
  ///
  /// In en, this message translates to:
  /// **'Summarizing…'**
  String get summaryRunning;

  /// No description provided for @summaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Summarize failed: {error}'**
  String summaryFailed(String error);

  /// No description provided for @registerMemo.
  ///
  /// In en, this message translates to:
  /// **'Register memo'**
  String get registerMemo;

  /// No description provided for @lastPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Last prompt'**
  String get lastPromptLabel;

  /// No description provided for @metaAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get metaAgent;

  /// No description provided for @metaTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get metaTitle;

  /// No description provided for @metaProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get metaProject;

  /// No description provided for @metaSessionId.
  ///
  /// In en, this message translates to:
  /// **'Session ID'**
  String get metaSessionId;

  /// No description provided for @metaLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get metaLastUsed;

  /// No description provided for @ralliesTarget.
  ///
  /// In en, this message translates to:
  /// **'Last {count} rallies'**
  String ralliesTarget(int count);

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedToClipboard;

  /// No description provided for @footerSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get footerSettings;

  /// No description provided for @footerNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get footerNotes;

  /// No description provided for @footerQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get footerQuit;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingTerminal.
  ///
  /// In en, this message translates to:
  /// **'Resume terminal'**
  String get settingTerminal;

  /// No description provided for @settingRecentLimit.
  ///
  /// In en, this message translates to:
  /// **'Recent sessions shown'**
  String get settingRecentLimit;

  /// No description provided for @settingClaudePath.
  ///
  /// In en, this message translates to:
  /// **'claude command path (for summaries)'**
  String get settingClaudePath;

  /// No description provided for @settingClaudePathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to auto-detect'**
  String get settingClaudePathHint;

  /// No description provided for @settingClaudePathDetected.
  ///
  /// In en, this message translates to:
  /// **'Auto-detected: {path}'**
  String settingClaudePathDetected(String path);

  /// No description provided for @settingClaudePathNotFound.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect: not found'**
  String get settingClaudePathNotFound;

  /// No description provided for @notesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesTitle;

  /// No description provided for @noteAutomationTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal automation permission'**
  String get noteAutomationTitle;

  /// No description provided for @noteAutomationBody.
  ///
  /// In en, this message translates to:
  /// **'The first time you resume a session, macOS asks for automation permission. Allow it once and it won\'t ask again.'**
  String get noteAutomationBody;

  /// No description provided for @noteRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session retention'**
  String get noteRetentionTitle;

  /// No description provided for @noteRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Sessions are kept by Claude Code based on cleanupPeriodDays (default 30 days). Even with a memo, an expired session may no longer be resumable.'**
  String get noteRetentionBody;

  /// No description provided for @noteSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'About summaries'**
  String get noteSummaryTitle;

  /// No description provided for @noteSummaryBody.
  ///
  /// In en, this message translates to:
  /// **'Summaries run claude -p (model: Haiku) and consume your usage quota each time. \'Recent\' extracts locally and is fast/cheap; \'Whole session\' reads everything and costs more.'**
  String get noteSummaryBody;

  /// No description provided for @noteRefreshTitle.
  ///
  /// In en, this message translates to:
  /// **'List refresh timing'**
  String get noteRefreshTitle;

  /// No description provided for @noteRefreshBody.
  ///
  /// In en, this message translates to:
  /// **'The recent-sessions list refreshes when you open the app, switch tabs, or return from a form. There is no manual reload; it does not update while left open.'**
  String get noteRefreshBody;

  /// No description provided for @trayOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Moost'**
  String get trayOpen;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Moost'**
  String get trayQuit;

  /// No description provided for @openInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in terminal'**
  String get openInTerminal;

  /// No description provided for @resumeInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Resume in terminal'**
  String get resumeInTerminal;

  /// No description provided for @terminalLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open terminal: {error}'**
  String terminalLaunchFailed(String error);

  /// No description provided for @unknownAgent.
  ///
  /// In en, this message translates to:
  /// **'Unknown agent: {agent}'**
  String unknownAgent(String agent);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
