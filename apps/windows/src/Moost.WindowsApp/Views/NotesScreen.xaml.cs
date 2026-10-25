using System.Windows.Controls;

namespace Moost.WindowsApp.Views;

/// <summary>注意画面（design.md 6.1 の notes）。</summary>
public partial class NotesScreen : UserControl
{
    private readonly IAppNavigator _navigator;

    public NotesScreen(IAppNavigator navigator)
    {
        _navigator = navigator;
        InitializeComponent();
    }

    private void OnBack(object sender, System.Windows.RoutedEventArgs e) => _navigator.ShowList();
}
