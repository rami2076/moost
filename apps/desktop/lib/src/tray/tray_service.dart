import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// システムトレイ常駐の面倒を見る（design.md 6 章）。
///
/// - トレイアイコン左クリック: ウィンドウの表示/非表示をトグル
/// - 右クリック: コンテキストメニュー（開く / 終了）
/// - ウィンドウを閉じる操作: 終了せずトレイへ隠れる
class TrayService with TrayListener, WindowListener {
  /// ウィンドウが表示されるたびにインクリメントされる。
  /// UI 側はこれを監視して一覧を再読込する（design.md 6.1 の更新タイミング）。
  final ValueNotifier<int> shownCount = ValueNotifier(0);

  final String openLabel;
  final String quitLabel;

  TrayService({required this.openLabel, required this.quitLabel});

  Future<void> init() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    // 閉じる操作で終了させず onWindowClose に回す
    await windowManager.setPreventClose(true);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: _keyOpen, label: openLabel),
      MenuItem.separator(),
      MenuItem(key: _keyQuit, label: quitLabel),
    ]));
  }

  static const _keyOpen = 'open';
  static const _keyQuit = 'quit';

  @override
  void onTrayIconMouseDown() => _toggleWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _keyOpen:
        showWindow();
      case _keyQuit:
        exit(0);
    }
  }

  @override
  void onWindowClose() async {
    // 常駐アプリなので閉じる = 隠す
    await windowManager.hide();
  }

  Future<void> _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await showWindow();
    }
  }

  Future<void> showWindow() async {
    await windowManager.setAlignment(Alignment.topRight);
    await windowManager.show();
    await windowManager.focus();
    shownCount.value++;
  }
}
