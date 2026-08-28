#ifndef MOOST_STATUS_NOTIFIER_ITEM_H_
#define MOOST_STATUS_NOTIFIER_ITEM_H_

#include <gio/gio.h>
#include <glib.h>

#include <flutter_linux/flutter_linux.h>

// Linux トレイ（自前 StatusNotifierItem）を初期化する。
// connection: session bus。成功時 TRUE。
gboolean stc_init(GDBusConnection* connection);

// Dart 側から呼ばれる MethodChannel を設定する。
void stc_set_channel(FlMethodChannel* channel);

// メニュー文言を設定する（Dart の l10n から受け取る）。
void stc_set_labels(const char* open_label, const char* quit_label);

// 稼働中か。
gboolean stc_is_available();

#endif  // MOOST_STATUS_NOTIFIER_ITEM_H_
