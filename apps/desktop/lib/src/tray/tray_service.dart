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

  /// トレイアイコンが実際に動作しているか。false のときは通常ウィンドウ
  /// として振る舞う（GNOME 等の Linux フォールバック、Q4）。
  bool _available = false;
  bool get available => _available;

  TrayService({required this.openLabel, required this.quitLabel});

  /// トレイを初期化する。成功したら true。
  ///
  /// Linux（GNOME）は AppIndicator 拡張がないとトレイへの登録に失敗する
  /// ため、ここで失敗を検出してフォールバック（通常ウィンドウ）に回す。
  Future<bool> init() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    // 閉じる操作で終了させず onWindowClose に回す
    await windowManager.setPreventClose(true);
    try {
      // macOS は isTemplate で自動配色（黒テンプレートで良い）。Linux の
      // AppIndicator は isTemplate を無視して画像をそのまま表示するため、
      // 黒いテンプレートを出すとダークパネルで見えにくい。白版を出す
      // （asset: tray_icon_white.png。白 + 透明度のみ）
      if (Platform.isLinux) {
        await trayManager.setIcon('assets/tray_icon_white.png');
      } else {
        await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
      }
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: _keyOpen, label: openLabel),
        MenuItem.separator(),
        MenuItem(key: _keyQuit, label: quitLabel),
      ]));
      _available = true;
    } on Object {
      _available = false;
    }
    return _available;
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
    // トレイなし（Linux フォールバック）では閉じる = 終了。
    // 常駐アプリの場合は閉じる = 隠す
    if (!_available) {
      exit(0);
    }
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
    // Linux は blur での自動非表示をしない。macOS の NSPopover 風挙動
    // （外側クリックで閉じる）は単左クリックトグルが効く前提だが、Linux の
    // AppIndicator はクリックイベントを渡さず「開く」は常にメニュー経由に
    // なるため、自動非表示は開いた瞬間に隠れる事故のもとになる（目撃例）。
    // 閉じる操作（タイトルバー X 等）でトレイへ戻る形に統一する
    if (Platform.isLinux) {
      return;
    }
    // トレイなしフォールバックでは通常ウィンドウなので blur で隠さない
    if (!_available) {
      return;
    }
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
    if (Platform.isMacOS) {
      await _positionUnderTrayIcon();
    }
    // Linux では setPosition/setAlignment が window_manager に実装されて
    // いないため、トレイ直下への配置は行わず OS 既定の位置で表示する
    await windowManager.show();
    await windowManager.focus();
    shownCount.value++;
  }

  /// トレイアイコンの直下・中央揃えに配置する（NSPopover の見た目に寄せる）。
  ///
  /// マルチディスプレイではクリック位置（カーソル）のあるディスプレイを
  /// 基準にする（Issue #16。計算本体は popover_position.dart）。
  /// macOS 専用: 呼び出し側（showWindow）で Platform.isMacOS を確認済み。
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
