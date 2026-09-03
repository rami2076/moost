// X11 トレイクリック補正の実装（詳細は x11_click_combo.h）。
//
// 方針（ユーザー要望に応えて 2 方式を実装）:
//  A. fakeDouble … XRecord でサーバー全体の左ボタン押下を監視し、
//     トレイ領域（最上部バー右側）への 1 クリックを検知したら、XTest で
//     直ちに 2 発目のクリックを合成する。GNOME は「ダブルクリック」として
//     Activate を送る（＝メニューなしでアプリが開く）。
//  B. closeMenu … メニュー表示直前（AboutToShow）に XTest で ESC を送り、
//     開いたメニューを自動で閉じる（メニューは一瞬見えるだけ）。
//
// 制約: X11 専用。Wayland・非 X11 では no-op（呼び出し元は通常動作に戻る）。
#include "x11_click_combo.h"

#include <cstdio>
#include <glib.h>
#include <gdk/gdk.h>

// GDK_WINDOWING_X11 は gdk.h を include して初めて定義される。判定より先に
// 読んでおくこと（X11 ビルドでこれが定義されないと X 補正が丸ごと無効になる）

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xproto.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/record.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <thread>
#endif

namespace {
#ifdef GDK_WINDOWING_X11

// トレイ領域の判定: 最上部バー（先頭 48px）の右側 340px。
// GNOME のアプリインジケーターは右上に並ぶ。時計等が重なる可能性はあるが
// 補正対象を狭めるためこの粗い範囲で見る。
constexpr int kPanelMaxY = 48;
constexpr int kRightBand = 340;

// ダブルクリック判定窓（Clutter の既定 ~400ms）より手前で 2 発目を送る。
// 実クリックから遅すぎず・ユーザー本人の 2 発目を邪魔しない 180ms。
constexpr gint64 kInjectDelayMs = 180;
constexpr gint64 kDoubleWindowMs = 380;

std::atomic<int> s_mode{0};  // 0 none / 1 fakeDouble / 2 closeMenu

// --- fakeDouble 用 ---
std::atomic<bool> g_fake_run{false};
std::thread g_record_thread;
std::thread g_inject_thread;
std::atomic<gint64> g_press_ms{0};     // 最後に見つけた実クリック時刻
std::atomic<gint64> g_prev_press_ms{0}; // そのひとつ前の実クリック時刻
std::atomic<gint64> g_consumed_ms{0};  // 処理済み（合成済み/破棄済み）時刻
std::atomic<gint64> g_injected_ms{0};  // 直近に合成した時刻（自己検知ガード用）
std::atomic<int> g_screen_w{100000};

// closeMenu 用（ESC を送る）の Display（メインスレッド専用）
Display* g_escape_display = nullptr;

gint64 now_ms() { return g_get_monotonic_time() / 1000; }

extern "C" void record_intercept_cb(XPointer closure,
                                    XRecordInterceptData* data) {
  (void)closure;
  if (data->category != XRecordFromServer || data->data == nullptr) {
    if (data->data != nullptr) XRecordFreeData(data);
    return;
  }
  // この環境（X サーバー）では ButtonPress は 8 バイトのレコード
  // （type=0x04, detail=button、あとは time）で届く。32 バイトの xEvent 想定の
  // デコードは位置も含め合わないため、先頭 2 バイトだけで判定する。
  // 座標はここでは取れないので、合成時の XQueryPointer でトレイ領域を判定する
  const unsigned char* b = reinterpret_cast<const unsigned char*>(data->data);
  const int n = static_cast<int>(data->data_len);
  int step = (n % 8 == 0 && n >= 8) ? 8 : 4;
  for (int i = 0; i + 4 <= n; i += step) {
    if (b[i] != ButtonPress) continue;      // 0x04
    if (b[i + 1] != Button1) continue;      // 左ボタン
    const gint64 now = now_ms();
    // 自分が合成したクリックは無視する（自己増幅防止: 合成後 400ms は無視）
    if (now - g_injected_ms.load() < 400) {
      break;
    }
    g_prev_press_ms.store(g_press_ms.exchange(now));
    break;
  }
  XRecordFreeData(data);
}

void inject_double_click() {
  Display* disp = XOpenDisplay(nullptr);
  if (disp == nullptr) {
    // 開けなければ（X が無い等）フェイクダブルは諦める
    g_consumed_ms.store(now_ms());
    return;
  }
  // 合成する前に、現在のポインタ位置がトレイ領域（最上部バー右側）か確認する。
  // XRecord は 8 バイトレコードのため座標が取れず、ポインタ位置で置き換える
  Window root, child;
  int rx = 0, ry = 0;
  unsigned int mask;
  if (XQueryPointer(disp, DefaultRootWindow(disp), &root, &child, &rx, &ry,
                    &rx, &ry, &mask) == True) {
    // トレイ以外でのクリックには合成しない（余計なダブルクリック防止）
    if (ry > kPanelMaxY || g_screen_w.load() - rx > kRightBand) {
      g_consumed_ms.store(now_ms());
      XCloseDisplay(disp);
      return;
    }
  }
  // 2 回目の押下+解放を 1 回だけ送る。拡張は「実クリック(1回目) + この合成(2回目)
  // → ダブルクリック」と見なして Activate を送る。ここで 2 回送ると 3 回目が
  // また単クリック扱いになりメニューが開いてしまうため、必ず 1 回だけ
  XTestFakeButtonEvent(disp, Button1, True, CurrentTime);
  std::this_thread::sleep_for(std::chrono::milliseconds(40));
  XTestFakeButtonEvent(disp, Button1, False, CurrentTime);
  XFlush(disp);
  XCloseDisplay(disp);
}

void record_loop() {
  Display* rec_display = XOpenDisplay(nullptr);
  if (rec_display == nullptr) {
    g_fake_run.store(false);
    return;
  }
  const int screen_num = DefaultScreen(rec_display);
  g_screen_w.store(XDisplayWidth(rec_display, screen_num));

  XRecordRange range;
  std::memset(&range, 0, sizeof(range));
  range.device_events.first = ButtonPress;
  range.device_events.last = ButtonPress;  // 押下のみ監視

  XRecordClientSpec clients[1] = {XRecordAllClients};
  XRecordRange* ranges[1] = {&range};
  XRecordContext ctx = XRecordCreateContext(rec_display, 0, clients, 1,
                                            ranges, 1);
  if (ctx == 0) {
    XCloseDisplay(rec_display);
    g_fake_run.store(false);
    return;
  }
  // EnableContext はデータを処理しながらブロックし続ける。
  // シャットダウン時は g_fake_run を false にして
  // XRecordDisableContext → EnableContext から復帰させる
  g_fake_run.store(true);
  XRecordEnableContext(rec_display, ctx, record_intercept_cb, nullptr);
  XRecordFreeContext(rec_display, ctx);
  XCloseDisplay(rec_display);
}

void inject_loop() {
  while (g_fake_run.load()) {
    const gint64 press = g_press_ms.load();
    const gint64 consumed = g_consumed_ms.load();
    if (press != 0 && press != consumed) {
      const gint64 now = now_ms();
      if (now < press + kInjectDelayMs) {
        // タイミング来るまで少し待つ
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        continue;
      }
      // 判定: 実クリックの後に別の実クリックが来ていたら（ユーザー本人の
      // ダブルクリック）合成は不要。shell の本来のダブル検知に任せる
      if (g_press_ms.load() != press) {
        g_consumed_ms.store(press);
        continue;
      }
      const gint64 elapsed = now_ms() - press;
      if (elapsed > kDoubleWindowMs) {
        // 既に窓が過ぎた（メニューは出る）。合成しても意味なし
        g_consumed_ms.store(press);
        continue;
      }
      // ユーザー本人のダブルクリック（前回の実クリックと 250ms 以内に連続）
      // の場合は合成せず、shell の本来のダブル検知に任せる（Activate が来る）。
      // ここで合成すると 3 発目になりメニューが開いてしまう
      if (press - g_prev_press_ms.load() < 250) {
        g_consumed_ms.store(press);
        continue;
      }
      // 1 クリックをダブル扱いに: 2 発目を合成
      g_injected_ms.store(now_ms());
      inject_double_click();
      g_consumed_ms.store(press);
      continue;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
}

void start_fake_double() {
  if (!g_fake_run.load()) {
    g_fake_run.store(true);
    g_record_thread = std::thread(record_loop);
    g_inject_thread = std::thread(inject_loop);
  }
}

// --- closeMenu: AboutToShow の直後に ESC を送ってメニューを閉じる ---
gboolean send_escape(gpointer user_data) {
  (void)user_data;
  if (g_escape_display == nullptr) {
    g_escape_display = XOpenDisplay(nullptr);
  }
  if (g_escape_display != nullptr) {
    const KeyCode kc = XKeysymToKeycode(g_escape_display, XK_Escape);
    if (kc != 0) {
      XTestFakeKeyEvent(g_escape_display, kc, True, CurrentTime);
      XTestFakeKeyEvent(g_escape_display, kc, False, CurrentTime);
      XFlush(g_escape_display);
    }
  }
  return G_SOURCE_REMOVE;
}

#endif  // GDK_WINDOWING_X11
}  // namespace

// ---------------------------------------------------------------------------
// 公開 API
// ---------------------------------------------------------------------------
gboolean x11_click_combo_available() {
#ifdef GDK_WINDOWING_X11
  // GdkDisplay が X11 で、なおかつデフォルトディスプレイが開けるか
  return GDK_IS_X11_DISPLAY(gdk_display_get_default());
#else
  return FALSE;
#endif
}

void x11_click_combo_set_mode(const char* mode) {
#ifdef GDK_WINDOWING_X11
  int next = 0;
  if (g_strcmp0(mode, "fakeDouble") == 0) {
    next = 1;
  } else if (g_strcmp0(mode, "closeMenu") == 0) {
    next = 2;
  }
  const int prev = s_mode.exchange(next);
  if (next == 1 && prev != 1) {
    start_fake_double();  // 一度だけ開始（X11 でないと no-op 経由で開始しない）
  }
#else
  (void)mode;
#endif
}

int x11_click_combo_current_mode() {
#ifdef GDK_WINDOWING_X11
  return s_mode.load();
#else
  return 0;
#endif
}

void x11_click_combo_on_menu_open() {
#ifdef GDK_WINDOWING_X11
  if (s_mode.load() == 2) {
    // メニューが開こうとしている。描画が走ってから閉じる
    if (g_escape_display == nullptr) {
      g_escape_display = XOpenDisplay(nullptr);
    }
    if (g_escape_display != nullptr) {
      g_timeout_add(120, send_escape, nullptr);
    }
  }
#else
  // 何もしない
#endif
}

void x11_click_combo_shutdown() {
#ifdef GDK_WINDOWING_X11
  if (g_fake_run.exchange(false)) {
    if (g_record_thread.joinable()) g_record_thread.join();
    if (g_inject_thread.joinable()) g_inject_thread.join();
  }
  if (g_escape_display != nullptr) {
    XCloseDisplay(g_escape_display);
    g_escape_display = nullptr;
  }
#endif
}
