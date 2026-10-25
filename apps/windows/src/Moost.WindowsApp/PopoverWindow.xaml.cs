using System.Windows;

namespace Moost.WindowsApp;

/// <summary>
/// ポップオーバー相当のウィンドウ（#102）。macOS の NSPopover の写像。
///
/// 表示/非表示・位置決め・フォーカス喪失での非表示は <see cref="TrayService"/> が担う。
/// 画面の中身は #103 で実装する。
/// </summary>
public partial class PopoverWindow : Window
{
    public PopoverWindow()
    {
        InitializeComponent();
    }
}
