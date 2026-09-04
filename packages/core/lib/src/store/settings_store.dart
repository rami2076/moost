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

  /// Linux のトレイクリック補正モード（macOS では使われない）。
  /// 0: なし / 1: ダブルクリック扱い（1クリックで開く・メニューなし）/
  /// 2: メニュー自動クローズ。
  final int trayClickMode;

  /// pi 起動時に指定する provider 名（空なら付けない）。
  /// ローカル LLM を複数切り替える環境だと pi 側の既定モデルが
  /// 配信されず 404 になることがあるため、明示できるようにする（Issue #68）。
  final String piProvider;

  /// pi 起動時に指定する model 名（空なら付けない）。
  final String piModel;

  /// 既定値は「ダブルクリック扱い（A）」。macOS では使われないため
  /// この既定値が macOS に悪影響はない。
  static const int trayClickModeDefault = 1;

  /// Linux のトレイクリック補正モードの意味づけ。
  static const trayClickModeNone = 0; // 補正なし（シングル=メニュー）
  static const trayClickModeFakeDouble = 1; // 1 クリックをダブル扱い（メニューなし）
  static const trayClickModeCloseMenu = 2; // メニューを自動クローズ（B）

  const Settings({
    this.terminalApp = 'Terminal.app',
    this.recentSessionLimit = 20,
    this.claudePath = '',
    this.summaryRallyCount = 1,
    this.copyAnimation = true,
    this.trayClickMode = trayClickModeDefault,
    this.piProvider = '',
    this.piModel = '',
  });

  Settings copyWith({
    String? terminalApp,
    int? recentSessionLimit,
    String? claudePath,
    int? summaryRallyCount,
    bool? copyAnimation,
    int? trayClickMode,
    String? piProvider,
    String? piModel,
  }) {
    return Settings(
      terminalApp: terminalApp ?? this.terminalApp,
      recentSessionLimit: recentSessionLimit ?? this.recentSessionLimit,
      claudePath: claudePath ?? this.claudePath,
      summaryRallyCount: summaryRallyCount ?? this.summaryRallyCount,
      copyAnimation: copyAnimation ?? this.copyAnimation,
      trayClickMode: trayClickMode ?? this.trayClickMode,
      piProvider: piProvider ?? this.piProvider,
      piModel: piModel ?? this.piModel,
    );
  }

  Map<String, Object?> toJson() => {
        'terminalApp': terminalApp,
        'recentSessionLimit': recentSessionLimit,
        'claudePath': claudePath,
        'summaryRallyCount': summaryRallyCount,
        'copyAnimation': copyAnimation,
        'trayClickMode': trayClickMode,
        'piProvider': piProvider,
        'piModel': piModel,
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
      trayClickMode: integer('trayClickMode', defaults.trayClickMode),
      piProvider: str('piProvider', defaults.piProvider),
      piModel: str('piModel', defaults.piModel),
    );
  }
}

/// 設定の永続化インターフェース。
///
/// UI 層（widget テスト）が実ファイル I/O を伴わないフェイクを注入できる
/// ように、[SettingsStore] の実体から切り離してある（Issue #30）。
abstract interface class SettingsRepository {
  Future<Settings> load();
  Future<void> save(Settings settings);
}

class SettingsStore implements SettingsRepository {
  static const schemaVersion = 1;

  final JsonFileStore _store;

  SettingsStore(File file) : _store = JsonFileStore(file);

  factory SettingsStore.defaultLocation() {
    final home = Platform.environment['HOME'] ?? '';
    return SettingsStore(File('$home/.moost/v1/settings.json'));
  }

  @override
  Future<Settings> load() async {
    final json = await _store.read();
    if (json == null) {
      return const Settings();
    }
    return Settings.fromJson(json);
  }

  @override
  Future<void> save(Settings settings) => _store.write({
        'schemaVersion': schemaVersion,
        ...settings.toJson(),
      });
}
