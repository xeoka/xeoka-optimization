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
    double _sum = 230;
    public double SumWidth { get => _sum; set => Set(ref _sum, value); }
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
    TweakState _state;
    public TweakState State { get => _state; set { if (Set(ref _state, value)) RefreshState(); } }
    void RefreshState() { Raise(nameof(StateText)); Raise(nameof(StateBrush)); Raise(nameof(StateVis)); }
    public string StateText => _state switch
    {
        TweakState.Applied => "●  " + Loc.L("Применено", "Applied"),
        TweakState.Partial => "◐  " + Loc.L("Частично", "Partially applied"),
        TweakState.NotApplied => "○  " + Loc.L("Не применено", "Not applied"),
        _ => ""
    };
    public Brush StateBrush => (Brush)Application.Current.FindResource(_state switch
    {
        TweakState.Applied => "OkBrush", TweakState.Partial => "WarnBrush", _ => "DimBrush"
    });
    public Visibility StateVis => _state == TweakState.Unknown ? Visibility.Collapsed : Visibility.Visible;
    public bool IsOn { get => _on; set { if (Set(ref _on, value)) Changed?.Invoke(this); } }
    public void Refresh() { Raise(nameof(Title)); Raise(nameof(Desc)); RefreshState(); }
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
    public string Info => Found ? Def.Desc : Loc.L("файл не найден: укажите папку пака", "file not found: pick the pack folder");
    public Brush InfoBrush => (Brush)Application.Current.FindResource(Found ? "DimBrush" : "WarnBrush");
    public Brush Badge => (Brush)Application.Current.FindResource(!Found ? "MutedGradient" : Def.Risk ? "AmberGradient" : "AccentGradient");
    public double Opacity => Found ? 1.0 : 0.75;
    public void Refresh() { Raise(nameof(Title)); Raise(nameof(Info)); Raise(nameof(Badge)); Raise(nameof(InfoBrush)); }
}

public sealed class ThemeVM : Notify
{
    readonly ThemeDef _d; readonly Func<string> _cur;
    public ThemeVM(ThemeDef d, Func<string> cur) { _d = d; _cur = cur; }
    public string Id => _d.Id;
    public string Name => Loc.L(_d.NameRu, _d.NameEn);
    public Brush SwatchBrush => Freeze(new SolidColorBrush((Color)ColorConverter.ConvertFromString(_d.Swatch)));
    static Brush Freeze(SolidColorBrush b) { b.Freeze(); return b; }
    public Brush Border => (Brush)Application.Current.FindResource(_cur() == _d.Id || (_cur() is not ("violet" or "cyan" or "emerald" or "rose" or "crimson" or "mono") && _d.Id == "violet") ? "Accent2Brush" : "LineBrush");
    public void Refresh() { Raise(nameof(Name)); Raise(nameof(Border)); }
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
