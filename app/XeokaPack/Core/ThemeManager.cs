using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace XeokaPack.Core;

public sealed record ThemeDef(string Id, string NameRu, string NameEn, double Hue, double Sat, string Swatch);

/// <summary>Темы: сдвиг оттенка фиолетовой палитры. Кисти меняются «на месте», поэтому всё окно перекрашивается сразу и плавно.</summary>
public static class ThemeManager
{
    public const double BaseHue = 262;
    public static readonly List<ThemeDef> All = new()
    {
        new("violet",  "Фиолетовая", "Violet",  262, 1.00, "#8B5CF6"),
        new("cyan",    "Океан",      "Ocean",   196, 1.00, "#22B8E8"),
        new("emerald", "Изумруд",    "Emerald", 152, 0.95, "#2FD08A"),
        new("rose",    "Роза",       "Rose",    334, 1.00, "#E8509A"),
        new("crimson", "Рубин",      "Ruby",    352, 1.00, "#E8465E"),
        new("mono",    "Графит",     "Graphite",262, 0.12, "#A8A8B8"),
    };

    public static ThemeDef Current { get; private set; } = All[0];

    static readonly ConditionalWeakTable<object, Color[]> Originals = new();
    static bool _hooked;
    static double _delta, _satMul;

    public static ThemeDef Find(string? id) => All.FirstOrDefault(t => t.Id == id) ?? All[0];

    public static void Apply(string id, Window? win)
    {
        Current = Find(id);
        _delta = Current.Hue - BaseHue;
        _satMul = Current.Sat;
        if (!_hooked)
        {
            _hooked = true;
            EventManager.RegisterClassHandler(typeof(FrameworkElement), FrameworkElement.LoadedEvent, new RoutedEventHandler((s, _) =>
            {
                if (s is DependencyObject d) ProcessElement(d);
            }));
        }
        ProcessDictionary(Application.Current.Resources);
        if (win != null) Walk(win);
    }

    static void ProcessDictionary(ResourceDictionary rd)
    {
        foreach (var key in rd.Keys.Cast<object>().ToList())
        {
            try
            {
                var v = rd[key];
                if (v is Brush b) ShiftBrush(b);
            }
            catch { }
        }
        foreach (var m in rd.MergedDictionaries) ProcessDictionary(m);
    }

    static void Walk(DependencyObject d)
    {
        ProcessElement(d);
        int n = VisualTreeHelper.GetChildrenCount(d);
        for (int i = 0; i < n; i++) Walk(VisualTreeHelper.GetChild(d, i));
        if (d is FrameworkElement fe && fe.Resources.Count > 0) ProcessDictionary(fe.Resources);
    }

    static void ProcessElement(DependencyObject d)
    {
        try
        {
            var en = d.GetLocalValueEnumerator();
            while (en.MoveNext())
            {
                var v = en.Current.Value;
                if (v is Brush b) ShiftBrush(b);
                else if (v is DropShadowEffect ef && !ef.IsFrozen) ShiftEffect(ef);
            }
        }
        catch { }
    }

    static void ShiftEffect(DropShadowEffect ef)
    {
        if (!Originals.TryGetValue(ef, out var orig)) { orig = new[] { ef.Color }; Originals.Add(ef, orig); }
        ef.Color = Shift(orig[0]);
    }

    static void ShiftBrush(Brush b)
    {
        if (b.IsFrozen) return;
        if (b is SolidColorBrush sb)
        {
            if (!Originals.TryGetValue(sb, out var orig)) { orig = new[] { sb.Color }; Originals.Add(sb, orig); }
            sb.Color = Shift(orig[0]);
        }
        else if (b is GradientBrush gb)
        {
            if (!Originals.TryGetValue(gb, out var orig)) { orig = gb.GradientStops.Select(s => s.Color).ToArray(); Originals.Add(gb, orig); }
            for (int i = 0; i < gb.GradientStops.Count && i < orig.Length; i++) gb.GradientStops[i].Color = Shift(orig[i]);
        }
    }

    // ---- цвет
    static Color Shift(Color c)
    {
        RgbToHsv(c, out var h, out var s, out var v);
        if (s < 0.12 || h < 228 || h > 312) return c;
        h = (h + _delta + 360) % 360;
        s = Math.Clamp(s * _satMul, 0, 1);
        return HsvToRgb(h, s, v, c.A);
    }

    static void RgbToHsv(Color c, out double h, out double s, out double v)
    {
        double r = c.R / 255.0, g = c.G / 255.0, b = c.B / 255.0;
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), d = max - min;
        v = max; s = max <= 0 ? 0 : d / max;
        if (d <= 0) h = 0;
        else if (max == r) h = 60 * (((g - b) / d) % 6);
        else if (max == g) h = 60 * ((b - r) / d + 2);
        else h = 60 * ((r - g) / d + 4);
        if (h < 0) h += 360;
    }

    static Color HsvToRgb(double h, double s, double v, byte a)
    {
        double c = v * s, x = c * (1 - Math.Abs(h / 60 % 2 - 1)), m = v - c, r, g, b;
        if (h < 60) (r, g, b) = (c, x, 0);
        else if (h < 120) (r, g, b) = (x, c, 0);
        else if (h < 180) (r, g, b) = (0, c, x);
        else if (h < 240) (r, g, b) = (0, x, c);
        else if (h < 300) (r, g, b) = (x, 0, c);
        else (r, g, b) = (c, 0, x);
        return Color.FromArgb(a, (byte)Math.Round((r + m) * 255), (byte)Math.Round((g + m) * 255), (byte)Math.Round((b + m) * 255));
    }
}
