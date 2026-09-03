#include "my_application.h"

#include <cstdlib>

int main(int argc, char** argv) {
  // 一部の NVIDIA EGL/GLX 環境では Flutter の描画（Impeller/OpenGLES・
  // ウィンドウ表示時の GTK との GL ブリット）が libnvidia-*core.so 内で
  // SIGSEGV する。engine をソフトウェアレンダリングにして GL 経路を
  // 回避し、確実に動かす（トレイアプリの描画は軽量なので性能は問題ない）。
  // 環境変数で既に渡されていれば尊重する（ユーザーが上書き可能）。
  setenv("FLUTTER_ENGINE_SWITCHES", "--enable-software-rendering", 0);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
