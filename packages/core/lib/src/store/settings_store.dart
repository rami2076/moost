import 'dart:io';

import 'json_file_store.dart';

/// アプリ設定。`~/.moost/v1/settings.json` に保存する（design.md 6.7）。
///
/// ログイン時自動起動はここに持たない（OS 側の実状態を正とするため）。
class Settings {
  final String terminalApp;
  final int recentSessionLimit;

  /// 要約機能（claude -p）で使うパスの上書き。空なら自動検出。
  final String claudePath;

  final int summaryRallyCount;

  /// コピー成功時のフィードバックアニメーション（円周スイープ）の有無。
  final bool copyAnimation;

  const Settings({
    this.terminalApp = 'Terminal.app',
    this.recentSessionLimit = 20,
    this.claudePath = '',
    this.summaryRallyCount = 1,
    this.copyAnimation = true,
  });

  Settings copyWith({
    String? terminalApp,
    int? recentSessionLimit,
    String? claudePath,
    int? summaryRallyCount,
    bool? copyAnimation,
  }) {
    return Settings(
      terminalApp: terminalApp ?? this.terminalApp,
      recentSessionLimit: recentSessionLimit ?? this.recentSessionLimit,
      claudePath: claudePath ?? this.claudePath,
      summaryRallyCount: summaryRallyCount ?? this.summaryRallyCount,
      copyAnimation: copyAnimation ?? this.copyAnimation,
    );
  }

  Map<String, Object?> toJson() => {
        'terminalApp': terminalApp,
        'recentSessionLimit': recentSessionLimit,
        'claudePath': claudePath,
        'summaryRallyCount': summaryRallyCount,
        'copyAnimation': copyAnimation,
      };

  factory Settings.fromJson(Map<String, Object?> json) {
    const defaults = Settings();
    // 型が想定と違っても落とさず、その項目だけデフォルトに戻す
    String str(String key, String fallback) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    int integer(String key, int fallback) {
      final value = json[key];
      return value is num ? value.toInt() : fallback;
    }

    bool boolean(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return Settings(
      terminalApp: str('terminalApp', defaults.terminalApp),
      recentSessionLimit:
          integer('recentSessionLimit', defaults.recentSessionLimit),
      claudePath: str('claudePath', defaults.claudePath),
      summaryRallyCount:
          integer('summaryRallyCount', defaults.summaryRallyCount),
      copyAnimation: boolean('copyAnimation', defaults.copyAnimation),
    );
  }
}

class SettingsStore {
  static const schemaVersion = 1;

  final JsonFileStore _store;

  SettingsStore(File file) : _store = JsonFileStore(file);

  factory SettingsStore.defaultLocation() {
    final home = Platform.environment['HOME'] ?? '';
    return SettingsStore(File('$home/.moost/v1/settings.json'));
  }

  Future<Settings> load() async {
    final json = await _store.read();
    if (json == null) {
      return const Settings();
    }
    return Settings.fromJson(json);
  }

  Future<void> save(Settings settings) => _store.write({
        'schemaVersion': schemaVersion,
        ...settings.toJson(),
      });
}
