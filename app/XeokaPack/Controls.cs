using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using XeokaPack.Core;

namespace XeokaPack;

public abstract class Notify : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name)); return true;
    }
    protected void Raise([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>Ширины карточек, зависящие от размера окна.</summary>
public sealed class LayoutState : Notify
{
    double _card = 440, _tool = 300, _about = 300;
    public double CardWidth { get => _card; set => Set(ref _card, value); }
    public double ToolWidth { get => _tool; set => Set(ref _tool, value); }
    public double AboutCardWidth { get => _about; set => Set(ref _about, value); }
}

public sealed class TweakVM : Notify
{
    public Tweak T { get; }
    bool _on;
    public Action<TweakVM>? Changed;
    public TweakVM(Tweak t) { T = t; _on = t.Default; }
    public string Id => T.Id;
    public string Title => T.Title;
    public string Desc => T.Desc;
    public bool IsOn { get => _on; set { if (Set(ref _on, value)) Changed?.Invoke(this); } }
    public void SetSilently(bool v) { if (Set(ref _on, v, nameof(IsOn))) { } }
}

public sealed class ToolVM : Notify
{
    public ToolDef Def { get; }
    public ToolVM(ToolDef d) { Def = d; }
    string? _path;
    public string? Path { get => _path; set { if (Set(ref _path, value)) { Raise(nameof(Found)); Raise(nameof(Badge)); Raise(nameof(Info)); Raise(nameof(InfoBrush)); Raise(nameof(Opacity)); } } }
    public bool Found => _path != null;
    public string Title => Def.Title;
    public string Glyph => Def.Glyph;
    public string Info => Found ? Def.Desc : "файл не найден: укажите папку пака";
    public Brush InfoBrush => (Brush)Application.Current.FindResource(Found ? "DimBrush" : "WarnBrush");
    public Brush Badge => (Brush)Application.Current.FindResource(!Found ? "MutedGradient" : Def.Risk ? "AmberGradient" : "AccentGradient");
    public double Opacity => Found ? 1.0 : 0.75;
}

public sealed class LogItem
{
    public string Text { get; init; } = "";
    public LogLevel Level { get; init; }
}

/// <summary>ScrollViewer с плавной (инерционной) прокруткой колесом мыши.</summary>
public class SmoothScrollViewer : ScrollViewer
{
    double _target;
    bool _running;
    DateTime _last;

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        if (ScrollableHeight <= 0.5) { base.OnMouseWheel(e); return; }
        if (!_running) _target = VerticalOffset;
        _target = Math.Clamp(_target - e.Delta * 0.9, 0, ScrollableHeight);
        if (!_running) { _running = true; _last = DateTime.UtcNow; CompositionTarget.Rendering += Tick; }
        e.Handled = true;
    }

    void Tick(object? s, EventArgs e)
    {
        var now = DateTime.UtcNow;
        double dt = Math.Min(0.05, (now - _last).TotalSeconds); _last = now;
        double cur = VerticalOffset, d = _target - cur;
        if (Math.Abs(d) < 0.4) { ScrollToVerticalOffset(_target); Stop(); return; }
        ScrollToVerticalOffset(cur + d * (1 - Math.Exp(-dt * 13)));
    }

    void Stop() { _running = false; CompositionTarget.Rendering -= Tick; }
}
