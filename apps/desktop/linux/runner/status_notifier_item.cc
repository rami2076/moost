// Linux 用の自前 StatusNotifierItem 実装。
//
// AppIndicator（freedesktop StatusNotifierItem）では左クリックが Activate に、
// 右クリックが SecondaryActivate / ContextMenu になります。既存プラグイン
// （tray_manager）は Linux でこの Activate を Dart 側へ届けられないため、
// runner で GDBus サーバーを立ててアイコン自体を提供し、
// 「左クリック → MethodChannel で Dart に通知」を実現する。
//
// 対応:
//  - org.kde.StatusNotifierItem (Activate / SecondaryActivate / ContextMenu)
//  - com.canonical.dbusmenu（「Open Moost」「Quit Moost」のメニュー）
//  - アイコン画像は実行ファイル直下の data/flutter_assets/assets/ から解決
#include "status_notifier_item.h"

#include <glib.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <flutter_linux/flutter_linux.h>

namespace {

constexpr int kMenuOpen = 1;
constexpr int kMenuQuit = 3;

GDBusConnection* g_connection = nullptr;
FlMethodChannel* g_channel = nullptr;
GtkMenu* g_menu = nullptr;
char* g_open_label = nullptr;
char* g_quit_label = nullptr;
gboolean g_available = false;
guint g_item_registration_id = 0;
guint g_menu_registration_id = 0;
// 登録直後にホストが AboutToShow を一度呼ぶことがある（初期化）。その間は
// クリックとみなさない（起動時にウィンドウを出さないため）
constexpr gint64 kIgnoreAboutToShowMs = 3000;
gint64 g_registered_at_ms = 0;

const char* g_item_path = "/org/ayatana/NotificationItem/moost";
const char* g_menu_path = "/org/ayatana/NotificationItem/moost/Menu";

void SendMenuClick(const char* key) {
  if (g_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(key));
  fl_method_channel_invoke_method(g_channel, "onTrayMenuItemClick", args,
                                  nullptr, nullptr, nullptr);
}

gboolean OpenMenuItemActivate(GtkWidget* widget, gpointer user_data) {
  SendMenuClick("open");
  return FALSE;
}

gboolean QuitMenuItemActivate(GtkWidget* widget, gpointer user_data) {
  SendMenuClick("quit");
  return FALSE;
}

void BuildMenu() {
  if (g_menu != nullptr) return;
  g_menu = GTK_MENU(gtk_menu_new());

  GtkWidget* open_item = gtk_menu_item_new_with_label(
      g_open_label != nullptr ? g_open_label : "Open Moost");
  g_signal_connect(open_item, "activate",
                   G_CALLBACK(OpenMenuItemActivate), nullptr);
  gtk_menu_shell_append(GTK_MENU_SHELL(g_menu), open_item);

  GtkWidget* sep = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(g_menu), sep);

  GtkWidget* quit_item = gtk_menu_item_new_with_label(
      g_quit_label != nullptr ? g_quit_label : "Quit Moost");
  g_signal_connect(quit_item, "activate",
                   G_CALLBACK(QuitMenuItemActivate), nullptr);
  gtk_menu_shell_append(GTK_MENU_SHELL(g_menu), quit_item);
  gtk_widget_show_all(GTK_WIDGET(g_menu));
}

void PopupMenu() {
  BuildMenu();
  gtk_menu_popup_at_pointer(g_menu, nullptr);
}

// ---------------------------------------------------------------------------
// org.kde.StatusNotifierItem メソッド
// ---------------------------------------------------------------------------
void HandleItemMethodCall(GDBusConnection* connection, const char* sender,
                          const char* object_path, const char* interface_name,
                          const char* method_name, GVariant* params,
                          GDBusMethodInvocation* invocation, gpointer data) {
  if (g_strcmp0(method_name, "Activate") == 0 ||
      g_strcmp0(method_name, "SecondaryActivate") == 0) {
    // 左クリック = Activate → Dart へ通知（ウィンドウ表示トグル）。
    // 右クリック（SecondaryActivate）は多くのホストで ContextMenu と
    // 同義に扱われるため、ここでもトグルではなくメニュー表示にすると
    // 分かりにくい。ここでは両方とも Activate として通知する。
    if (g_channel != nullptr) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "kind",
                               fl_value_new_string("activate"));
      fl_method_channel_invoke_method(g_channel, "onTrayIconClicked", args,
                                      nullptr, nullptr, nullptr);
    }
  } else if (g_strcmp0(method_name, "ContextMenu") == 0) {
    PopupMenu();
  } else if (g_strcmp0(method_name, "Refresh") == 0) {
    // ホストからのアイコン更新要求。何もしない
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

// ---------------------------------------------------------------------------
// GetProperty
// ---------------------------------------------------------------------------
const char* IconPath() {
  static char* icon_path = nullptr;
  if (icon_path == nullptr) {
    g_autofree char* exe = g_file_read_link("/proc/self/exe", nullptr);
    g_autofree char* dir = g_path_get_dirname(exe);
    icon_path = g_build_filename(dir, "data", "flutter_assets", "assets",
                                 "tray_icon_white.png", nullptr);
  }
  return icon_path;
}

GVariant* LoadItemProperty(GDBusConnection* connection, const char* sender,
                           const char* object_path,
                           const char* interface_name,
                           const char* property_name, GError** error,
                           gpointer data) {
  if (g_strcmp0(property_name, "Category") == 0) {
    return g_variant_new_string("ApplicationStatus");
  }
  if (g_strcmp0(property_name, "Id") == 0) {
    return g_variant_new_string("moost");
  }
  if (g_strcmp0(property_name, "Title") == 0) {
    return g_variant_new_string("Moost");
  }
  if (g_strcmp0(property_name, "Status") == 0) {
    return g_variant_new_string("Active");
  }
  if (g_strcmp0(property_name, "IconName") == 0) {
    return g_variant_new_string(IconPath());
  }
  if (g_strcmp0(property_name, "AttentionIconName") == 0) {
    return g_variant_new_string(IconPath());
  }
  if (g_strcmp0(property_name, "IconThemePath") == 0) {
    return g_variant_new_string("");
  }
  if (g_strcmp0(property_name, "AttentionMovieName") == 0) {
    return g_variant_new_string("");
  }
  if (g_strcmp0(property_name, "Menu") == 0) {
    // Menu を "/"（無し）にすると ubuntu-appindicators はアイコン自体を
    // レンダリングしなくなる（実測）。Menu は有効なパスを返し、メニュー
    // 本体（dbusmenu）を 0 項目にして実質「メニューなし」にする
    return g_variant_new_object_path(g_menu_path);
  }
  if (g_strcmp0(property_name, "ItemIsMenu") == 0) {
    return g_variant_new_boolean(false);
  }
  if (g_strcmp0(property_name, "IconPixmap") == 0) {
    return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), nullptr, 0);
  }
  return nullptr;
}

// ---------------------------------------------------------------------------
// com.canonical.dbusmenu
// ---------------------------------------------------------------------------
GVariant* MenuItemStruct(int id, const char* label, const char* type) {
  GVariantBuilder props;
  g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
  if (label != nullptr) {
    g_variant_builder_add(&props, "{sv}", "label",
                          g_variant_new_string(label));
  }
  if (type != nullptr) {
    g_variant_builder_add(&props, "{sv}", "type",
                          g_variant_new_string(type));
  }
  g_variant_builder_add(&props, "{sv}", "enabled",
                        g_variant_new_boolean(true));
  g_variant_builder_add(&props, "{sv}", "visible",
                        g_variant_new_boolean(true));
  // コンテナ位置には builder のポインタを渡す（GLib 2.80 以降の正書法）
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
  return g_variant_new("(ia{sv}av)", id, &props, &children);
}

// 子アイテムの variant（av の要素）を作る。g_variant_new_variant が
// 引数を消費するので、ここで戻した値は呼び出し側に所有権移転する。
static void AddMenuItem(GVariantBuilder* children, int id, const char* label,
                        const char* type) {
  g_variant_builder_add_value(
      children,
      g_variant_new_variant(MenuItemStruct(id, label, type)));
}

GVariant* RootItem() {
  GVariantBuilder children;
  g_variant_builder_init(&children, G_VARIANT_TYPE("av"));

  AddMenuItem(&children, kMenuOpen,
              g_open_label != nullptr ? g_open_label : "Open Moost",
              "normal");
  AddMenuItem(&children, 2, nullptr, "separator");
  AddMenuItem(&children, kMenuQuit,
              g_quit_label != nullptr ? g_quit_label : "Quit Moost",
              "normal");

  GVariantBuilder props;
  g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&props, "{sv}", "children-display",
                        g_variant_new_string("submenu"));

  return g_variant_new("(ia{sv}av)", (gint32)0, &props, &children);
}

void HandleMenuMethodCall(GDBusConnection* connection, const char* sender,
                          const char* object_path, const char* interface_name,
                          const char* method_name, GVariant* parameters,
                          GDBusMethodInvocation* invocation, gpointer data) {
  if (g_strcmp0(method_name, "AboutToShow") == 0) {
    // シングルクリックでホストがメニューを開く際に呼ばれる。メニュー自体は
    // GNOME の仕様上消せないが、シングルクリックを「開く」として同時に
    // ウィンドウも表示する（＝トレイクリックで開く、を成立させる）。
    // 登録直後に来る初期化呼び出しでは開かない（起動時はトレイのみ）。
    if (g_get_monotonic_time() / 1000 - g_registered_at_ms <
        kIgnoreAboutToShowMs) {
      g_dbus_method_invocation_return_value(invocation,
                                            g_variant_new("(b)", TRUE));
      return;
    }
    if (g_channel != nullptr) {
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "kind",
                               fl_value_new_string("activate"));
      fl_method_channel_invoke_method(g_channel, "onTrayIconClicked", args,
                                      nullptr, nullptr, nullptr);
    }
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(b)", TRUE));
  } else if (g_strcmp0(method_name, "Event") == 0) {
    gint32 id;
    const char* event_id;
    GVariant* event_data;
    guint32 timestamp;
    g_variant_get(parameters, "(isvu)", &id, &event_id, &event_data,
                  &timestamp);
    if (g_strcmp0(event_id, "clicked") == 0) {
      if (id == kMenuOpen) {
        SendMenuClick("open");
      } else if (id == kMenuQuit) {
        SendMenuClick("quit");
      }
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "GetLayout") == 0) {
    gint32 parent_id;
    gint32 recursion_depth;
    GVariant* expanded;
    g_variant_get(parameters, "(iias)", &parent_id, &recursion_depth,
                  &expanded);
    g_autoptr(GVariant) root = RootItem();
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(u@(ia{sv}av))", (guint32)1, root));
  } else if (g_strcmp0(method_name, "GetProperty") == 0) {
    gint32 id;
    const char* name;
    g_variant_get(parameters, "(is)", &id, &name);
    // 返り値は out 型 v ＝「variant で包んだ値」をタプルで返す
    GVariant* value;
    if (g_strcmp0(name, "label") == 0) {
      const char* label =
          id == kMenuOpen
              ? (g_open_label != nullptr ? g_open_label : "Open Moost")
              : (g_quit_label != nullptr ? g_quit_label : "Quit Moost");
      value = g_variant_new_variant(g_variant_new_string(label));
    } else if (g_strcmp0(name, "type") == 0) {
      value = g_variant_new_variant(
          g_variant_new_string(id == 2 ? "separator" : "normal"));
    } else if (g_strcmp0(name, "enabled") == 0 ||
               g_strcmp0(name, "visible") == 0) {
      value = g_variant_new_variant(g_variant_new_boolean(id != 2));
    } else {
      value = g_variant_new_variant(g_variant_new_string(""));
    }
    g_dbus_method_invocation_return_value(invocation,
                                          g_variant_new("(v)", value));
  } else if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
    // この GLib は配列型には値を渡せず builder を要求する。空配列なら
    // 空 builder を渡せば良い
    GVariantBuilder arr;
    g_variant_builder_init(&arr, G_VARIANT_TYPE("a(ia{sv})"));
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(a(ia{sv}))", &arr));
  } else {
    g_dbus_method_invocation_return_value(invocation, nullptr);
  }
}

const char* kItemXml = "<node>"
                       "<interface name='org.kde.StatusNotifierItem'>"
                       "<method name='Activate'><arg type='i' direction='in'/>"
                       "<arg type='i' direction='in'/></method>"
                       "<method name='SecondaryActivate'>"
                       "<arg type='i' direction='in'/>"
                       "<arg type='i' direction='in'/></method>"
                       "<method name='ContextMenu'><arg type='i' direction='in'/></method>"
                       "<method name='Refresh'><arg type='i' direction='in'/>"
                       "<arg type='i' direction='in'/></method>"
                       "<property name='Category' type='s' access='read'/>"
                       "<property name='Id' type='s' access='read'/>"
                       "<property name='Title' type='s' access='read'/>"
                       "<property name='Status' type='s' access='read'/>"
                       "<property name='IconName' type='s' access='read'/>"
                       "<property name='IconThemePath' type='s' access='read'/>"
                       "<property name='AttentionIconName' type='s' access='read'/>"
                       "<property name='AttentionMovieName' type='s' access='read'/>"
                       "<property name='Menu' type='o' access='read'/>"
                       "<property name='ItemIsMenu' type='b' access='read'/>"
                       "<property name='IconPixmap' type='a(iiay)' access='read'/>"
                       "</interface>"
                       "</node>";

const char* kMenuXml = "<node>"
                       "<interface name='com.canonical.dbusmenu'>"
                       "<method name='AboutToShow'><arg type='i' direction='in'/>"
                       "<arg type='b' direction='out'/></method>"
                       "<method name='Event'><arg type='i' direction='in'/>"
                       "<arg type='s' direction='in'/><arg type='v' direction='in'/>"
                       "<arg type='u' direction='in'/></method>"
                       "<method name='GetLayout'>"
                       "<arg type='i' direction='in'/><arg type='i' direction='in'/>"
                       "<arg type='as' direction='in'/><arg type='u' direction='out'/>"
                       "<arg type='(ia{sv}av)' direction='out'/></method>"
                       "<method name='GetProperty'><arg type='i' direction='in'/>"
                       "<arg type='s' direction='in'/><arg type='v' direction='out'/></method>"
                       "<method name='GetGroupProperties'>"
                       "<arg type='ai' direction='in'/><arg type='as' direction='in'/>"
                       "<arg type='a(ia{sv})' direction='out'/></method>"
                       "<property name='Version' type='u' access='read'/>"
                       "</interface>"
                       "</node>";

}  // namespace

// ---------------------------------------------------------------------------
// Dart 側の TrayService からの呼び出し（MethodChannel 'moost/linux_tray'）
// ---------------------------------------------------------------------------
static void HandleChannelCall(FlMethodChannel* channel, FlMethodCall* call,
                              gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "init") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    const char* open_label = nullptr;
    const char* quit_label = nullptr;
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* o = fl_value_lookup_string(args, "openLabel");
      FlValue* q = fl_value_lookup_string(args, "quitLabel");
      if (o != nullptr && fl_value_get_type(o) == FL_VALUE_TYPE_STRING) {
        open_label = fl_value_get_string(o);
      }
      if (q != nullptr && fl_value_get_type(q) == FL_VALUE_TYPE_STRING) {
        quit_label = fl_value_get_string(q);
      }
    }
    stc_set_labels(open_label, quit_label);
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_success(
        call, fl_value_new_bool(stc_is_available()), &error);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

// ---------------------------------------------------------------------------
// 公開 API
// ---------------------------------------------------------------------------
gboolean stc_is_available() { return g_available; }

void stc_set_labels(const char* open_label, const char* quit_label) {
  g_free(g_open_label);
  g_free(g_quit_label);
  g_open_label = g_strdup(open_label != nullptr ? open_label : "Open Moost");
  g_quit_label = g_strdup(quit_label != nullptr ? quit_label : "Quit Moost");
  if (g_menu != nullptr) gtk_widget_destroy(GTK_WIDGET(g_menu));
  g_menu = nullptr;
}

void stc_set_channel(FlMethodChannel* channel) {
  if (g_channel != nullptr) {
    g_clear_object(&g_channel);
  }
  g_channel = channel;
  if (g_channel != nullptr) {
    g_object_ref(g_channel);
    fl_method_channel_set_method_call_handler(g_channel, HandleChannelCall,
                                              nullptr, nullptr);
  }
}

gboolean stc_init(GDBusConnection* connection) {
  g_connection = connection;
  // ガード開始時刻は登録より先に設定する（登録処理中の AboutToShow を
  // クリックと誤認しないため）
  g_registered_at_ms = g_get_monotonic_time() / 1000;

  g_autoptr(GDBusNodeInfo) item_info = g_dbus_node_info_new_for_xml(
      kItemXml, nullptr);
  g_autoptr(GDBusNodeInfo) menu_info =
      g_dbus_node_info_new_for_xml(kMenuXml, nullptr);
  if (item_info == nullptr || menu_info == nullptr) {
    return FALSE;
  }

  GDBusInterfaceVTable item_vtable = {HandleItemMethodCall, LoadItemProperty,
                                     nullptr};
  GDBusInterfaceVTable menu_vtable = {HandleMenuMethodCall, nullptr, nullptr};

  g_item_registration_id = g_dbus_connection_register_object(
      g_connection, g_item_path, item_info->interfaces[0], &item_vtable,
      nullptr, nullptr, nullptr);
  g_menu_registration_id = g_dbus_connection_register_object(
      g_connection, g_menu_path, menu_info->interfaces[0], &menu_vtable,
      nullptr, nullptr, nullptr);
  if (g_item_registration_id == 0 || g_menu_registration_id == 0) {
    return FALSE;
  }

  GError* error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      g_connection, "org.kde.StatusNotifierWatcher",
      "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
      "RegisterStatusNotifierItem",
      g_variant_new("(s)", g_item_path), G_VARIANT_TYPE("()"),
      G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);
  if (result == nullptr) {
    // ホスト（GNOME の appindicator 拡張）がいない等
    g_warning("moost: failed to register status notifier item: %s",
              error != nullptr ? error->message : "unknown");
    g_clear_error(&error);
    g_available = FALSE;
    return FALSE;
  }
  g_available = TRUE;
  return TRUE;
}
