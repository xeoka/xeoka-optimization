using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace XeokaPack;

public partial class TgBadge : UserControl
{
    public static readonly DependencyProperty RingBrushProperty =
        DependencyProperty.Register(nameof(RingBrush), typeof(Brush), typeof(TgBadge), new PropertyMetadata(new SolidColorBrush(Color.FromRgb(0xA7, 0x8B, 0xFA))));
    public Brush RingBrush { get => (Brush)GetValue(RingBrushProperty); set => SetValue(RingBrushProperty, value); }
    public TgBadge() { InitializeComponent(); }
}
