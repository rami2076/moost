import 'package:flutter/services.dart';

/// Linux トレイ（自前 StatusNotifierItem）とのブリッジ。
///
/// 既存プラグイン（tray_manager）は Linux でアイコンのクリック（Activate）を
/// Dart へ届けられないため、runner 側（C++ / GDBus）で StatusNotifierItem を
/// 提供し、ここへ MethodChannel 経由でイベントを運んでもらう:
/// - `onTrayIconClicked`: アイコン左クリック（Activate）→ ウィンドウ表示のトグル
/// - `onTrayMenuItemClick`: メニュー（Open Moost / Quit Moost）のアイテム選択
class LinuxTray {
  static const MethodChannel _channel = MethodChannel('moost/linux_tray');

  final void Function() onActivate;
  final void Function() onMenuOpen;
  final void Function() onMenuQuit;

  LinuxTray({
    required this.onActivate,
    required this.onMenuOpen,
    required this.onMenuQuit,
  });

  /// run アプリが起動しトレイアイコンを出せたかを返す（false なら
  /// 呼び出し側は通常ウィンドウへフォールバックする）。
  Future<bool> init({required String openLabel, required String quitLabel}) {
    _channel.setMethodCallHandler(_handle);
    return _channel
        .invokeMethod<bool>('init', {
          'openLabel': openLabel,
          'quitLabel': quitLabel,
        })
        .then((available) => available ?? false);
  }

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onTrayIconClicked':
        onActivate();
      case 'onTrayMenuItemClick':
        final id = (call.arguments as Map<Object?, Object?>?)?['id'];
        if (id == 'open') {
          onMenuOpen();
        } else if (id == 'quit') {
          onMenuQuit();
        }
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
