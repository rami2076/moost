import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:moost_core/moost_core.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'src/screens/root_screen.dart';
import 'src/tray/tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // トレイメニューはウィジェットツリー外なので、OS ロケールから文言を引く
  final l10n = lookupAppLocalizations(PlatformDispatcher.instance.locale);
  final tray = TrayService(
    openLabel: l10n.trayOpen,
    quitLabel: l10n.trayQuit,
  );

  const windowOptions = WindowOptions(
    size: Size(570, 660),
    skipTaskbar: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 初回起動はウィンドウを見せる。以後、閉じるとトレイに隠れる
    await windowManager.show();
    await windowManager.focus();
  });
  await tray.init();

  runApp(MoostApp(
    adapter: ClaudeCodeAdapter(),
    memoStore: MemoStore.defaultLocation(),
    settingsStore: SettingsStore.defaultLocation(),
    windowShown: tray.shownCount,
  ));
}

class MoostApp extends StatelessWidget {
  final AgentAdapter adapter;
  final MemoStore memoStore;
  final SettingsStore settingsStore;

  /// トレイからウィンドウが表示されたことを知らせる通知（null なら常駐なし）。
  final ValueListenable<int>? windowShown;

  const MoostApp({
    super.key,
    required this.adapter,
    required this.memoStore,
    required this.settingsStore,
    this.windowShown,
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
        adapter: adapter,
        memoStore: memoStore,
        settingsStore: settingsStore,
        windowShown: windowShown,
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
