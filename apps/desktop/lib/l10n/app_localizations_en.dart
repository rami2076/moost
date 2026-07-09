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
}
