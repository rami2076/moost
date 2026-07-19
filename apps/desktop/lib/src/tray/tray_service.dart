import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'popover_position.dart';

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

  /// blur で隠した直後のトレイクリックを「隠す」として扱うためのガード。
  /// （トレイクリック時、先に blur → hide が走ると isVisible が false になり
  /// トグルが再表示してしまうため）
  DateTime? _hiddenByBlurAt;

  @override
  void onWindowBlur() async {
    // アプリ外を触ったら隠れる（ポップオーバー挙動。design.md 6 章）
    if (await windowManager.isVisible()) {
      _hiddenByBlurAt = DateTime.now();
      await windowManager.hide();
    }
  }

  Future<void> _toggleWindow() async {
    final hiddenJustNow = _hiddenByBlurAt != null &&
        DateTime.now().difference(_hiddenByBlurAt!) <
            const Duration(milliseconds: 400);
    if (hiddenJustNow || await windowManager.isVisible()) {
      _hiddenByBlurAt = null;
      await windowManager.hide();
    } else {
      await showWindow();
    }
  }

  Future<void> showWindow() async {
    await _positionUnderTrayIcon();
    await windowManager.show();
    await windowManager.focus();
    shownCount.value++;
  }

  /// トレイアイコンの直下・中央揃えに配置する（NSPopover の見た目に寄せる）。
  ///
  /// マルチディスプレイではクリック位置（カーソル）のあるディスプレイを
  /// 基準にする（Issue #16。計算本体は popover_position.dart）。
  Future<void> _positionUnderTrayIcon() async {
    final size = await windowManager.getSize();

    Offset? cursor;
    var workAreas = const <Rect>[];
    try {
      cursor = await screenRetriever.getCursorScreenPoint();
      final displays = await screenRetriever.getAllDisplays();
      workAreas = [
        for (final display in displays)
          if (display.visiblePosition != null && display.visibleSize != null)
            display.visiblePosition! & display.visibleSize!,
      ];
    } on Object {
      // ディスプレイ情報が取れなくても表示は続行する（下のフォールバックへ）
    }

    final position = popoverPosition(
      windowSize: size,
      cursor: cursor,
      iconBounds: await trayManager.getBounds(),
      workAreas: workAreas,
    );
    if (position == null) {
      await windowManager.setAlignment(Alignment.topRight);
      return;
    }
    await windowManager.setPosition(position);
  }
}
