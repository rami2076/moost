using System.Windows;

namespace Moost.WindowsApp;

/// <summary>
/// プレースホルダのウィンドウ。常駐 UI の本体は #102（トレイ）・#103（画面）で置き換える。
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }
}
