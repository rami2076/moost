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
    if (_suppressHideCount > 0) {
      return;
    }
    // 常駐アプリなので閉じる = 隠す
    await windowManager.hide();
  }

  /// blur で隠した直後のトレイクリックを「隠す」として扱うためのガード。
  /// （トレイクリック時、先に blur → hide が走ると isVisible が false になり
  /// トグルが再表示してしまうため）
  DateTime? _hiddenByBlurAt;

  /// blur による自動非表示を一時的に止める段数。フォルダ選択ダイアログ
  /// （NSOpenPanel のシート）を開いている間に呼び出し元をアクティブにされ
  /// blur → hide が走ると、シートが開いたまま親ウィンドウが隠れてしまい、
  /// ネイティブ側のパネルの状態が壊れて次回以降ダイアログが開かなくなる
  /// 事故があったため。ネストする可能性を考えカウンタにする。
  int _suppressHideCount = 0;

  /// [action] の実行中は blur による自動非表示を止め、実行後に元に戻す。
  Future<T> withoutBlurHide<T>(Future<T> Function() action) async {
    _suppressHideCount++;
    try {
      return await action();
    } finally {
      _suppressHideCount--;
    }
  }

  @override
  void onWindowBlur() async {
    // アプリ外を触ったら隠れる（ポップオーバー挙動。design.md 6 章）。
    // ただし withoutBlurHide 実行中（フォルダ選択ダイアログ表示中等）は
    // 隠さない
    if (_suppressHideCount > 0) {
      return;
    }
    if (await windowManager.isVisible()) {
      _hiddenByBlurAt = DateTime.now();
      await windowManager.hide();
    }
  }

  Future<void> _toggleWindow() async {
    // ダイアログ（NSOpenPanel のシート等）を表示中は、トレイクリックでも
    // 隠さない。シートが開いたまま親ウィンドウを hide（= orderOut）すると
    // シートの正規の終了手続き（endSheet）を経由しないため、ネイティブ側に
    // 「まだシートがアタッチされている」状態が残り、次回以降ダイアログが
    // 開かなくなる（ビープ音のみでエラーも出ない）事故があった
    if (_suppressHideCount > 0) {
      await showWindow();
      return;
    }
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
