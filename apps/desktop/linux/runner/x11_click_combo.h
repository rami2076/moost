#ifndef MOOST_X11_CLICK_COMBO_H_
#define MOOST_X11_CLICK_COMBO_H_

#include <glib.h>

// X11 トレイクリック補正。
//
// GNOME(ubuntu-appindicators) はシングルクリックでは必ずメニューを開き、
// Activate（アプリへの直接通知・メニューなし）はダブルクリックでのみ送る。
// そこで下の「補正」を提供する（X11 のみ。Wayland/非 X11 では no-op で
// 呼び出し元は通常動作にフォールバックする）。
//
//   none       : 補正なし（シングル = メニュー、ダブル = Activate）
//   fakeDouble : 監視(XRecord)でトレイの 1 クリックを検知し、直ちに
//                2 発目のクリックを合成(XTest)して「ダブル扱い」にする。
//                → メニューを出さずに開く（ユーザー要望 A）
//   closeMenu  : シングルクリックでウィンドウを開き、続いて開いたメニューに
//                ESC(XTest)を送って自動で閉じる（ユーザー要望 B）
gboolean x11_click_combo_available(void);
void x11_click_combo_set_mode(const char* mode);
// 現在のモード（0: none / 1: fakeDouble / 2: closeMenu）。
// X11 でなければ常に 0。AboutToShow などの分岐判定に使う
int x11_click_combo_current_mode(void);
// AboutToShow（メニュー表示直前）で呼ばれる。closeMenu のとき ESC を送る
void x11_click_combo_on_menu_open(void);
void x11_click_combo_shutdown(void);

#endif  // MOOST_X11_CLICK_COMBO_H_
