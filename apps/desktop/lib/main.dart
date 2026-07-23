import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:moost_core/moost_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'src/screens/root_screen.dart';
import 'src/tray/tray_service.dart';
import 'src/update/brew_updater.dart';
import 'src/update/update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // トレイメニューはウィジェットツリー外なので、OS ロケールから文言を引く
  final l10n = lookupAppLocalizations(PlatformDispatcher.instance.locale);
  final tray = TrayService(
    openLabel: l10n.trayOpen,
    quitLabel: l10n.trayQuit,
  );

  // ポップオーバー風の固定ウィンドウ: タイトルバーなし・移動/リサイズ不可
  const windowOptions = WindowOptions(
    size: Size(570, 660),
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await tray.init();
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setMovable(false);
    await windowManager.setResizable(false);
    // 起動時はトレイアイコンだけ。ウィンドウはトレイクリックで初めて表示する
  });

  final packageInfo = await PackageInfo.fromPlatform();

  runApp(MoostApp(
    registry: AdapterRegistry([
      ClaudeCodeAdapter(),
      CodexAdapter(),
    ]),
    memoStore: MemoStore.defaultLocation(),
    projectStore: ProjectStore.defaultLocation(),
    settingsStore: SettingsStore.defaultLocation(),
    windowShown: tray.shownCount,
    updateChecker: UpdateChecker(currentVersion: packageInfo.version),
    appVersion: packageInfo.version,
    // tray.showWindow は使わない: トレイアイコン基準の再配置と shownCount
    // 経由の一覧再読込を伴い、フォルダ選択ダイアログを閉じた直後に呼ぶと
    // 「配置し直し」と「再読込」が二重に走ってちらつく。ここでは今の位置の
    // まま show/focus するだけでよい（RootScreen.defaultShowWindow）
  ));
}

class MoostApp extends StatelessWidget {
  final AdapterRegistry registry;
  final MemoRepository memoStore;
  final ProjectRepository projectStore;
  final SettingsRepository settingsStore;

  /// 更新チェック（null なら通知機能なし。widget テストでは省略する）。
  final UpdateChecker? updateChecker;

  /// テスト用の注入ポイント（null なら実環境の既定動作）。
  final bool Function()? isBrewManaged;
  final Future<void> Function(Uri url)? openUrl;
  final BrewUpdater? brewUpdater;
  final Future<void> Function()? onRestart;
  final Future<String?> Function()? pickFolder;
  final Future<void> Function()? showWindow;

  /// 設定画面に表示するアプリバージョン。
  final String? appVersion;

  /// トレイからウィンドウが表示されたことを知らせる通知（null なら常駐なし）。
  final ValueListenable<int>? windowShown;

  const MoostApp({
    super.key,
    required this.registry,
    required this.memoStore,
    required this.projectStore,
    required this.settingsStore,
    this.windowShown,
    this.updateChecker,
    this.isBrewManaged,
    this.openUrl,
    this.brewUpdater,
    this.onRestart,
    this.pickFolder,
    this.showWindow,
    this.appVersion,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _buildTheme(),
      home: RootScreen(
        registry: registry,
        memoStore: memoStore,
        projectStore: projectStore,
        settingsStore: settingsStore,
        windowShown: windowShown,
        updateChecker: updateChecker,
        isBrewManaged: isBrewManaged,
        openUrl: openUrl,
        brewUpdater: brewUpdater,
        onRestart: onRestart,
        pickFolder: pickFolder,
        showWindow: showWindow,
        appVersion: appVersion,
      ),
    );
  }

  /// フォントは 3 スタイルだけで全画面をまかなう（design.md 6.5）。
  /// この 3 つの数値だけ変えれば全画面に反映される。
  ThemeData _buildTheme() {
    const textTheme = TextTheme(
      // appHeadline: 画面タイトル
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      // appBody: 本文・リスト行・フォーム入力（全体のデフォルト）
      bodyMedium: TextStyle(fontSize: 14),
      // appCaption: 補足（Swift 版は 10pt。Flutter のレンダリング差を
      // 考慮して 11 にしている。design.md 6.5 の注意参照）
      bodySmall: TextStyle(fontSize: 11),
    );
    return ThemeData(
      colorSchemeSeed: Colors.teal,
      textTheme: textTheme,
      useMaterial3: true,
    );
  }
}
