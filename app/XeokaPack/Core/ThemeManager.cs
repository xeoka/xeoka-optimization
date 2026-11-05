using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace XeokaPack.Core;

public sealed record ThemeDef(string Id, string NameRu, string NameEn, double Hue, double Sat, string Swatch, double RiskHue, string RiskRu, string RiskEn);

/// <summary>Темы: сдвиг оттенка фиолетовой палитры. Кисти меняются «на месте», поэтому всё окно перекрашивается сразу и плавно.</summary>
public static class ThemeManager
{
    public const double BaseHue = 262;
    public static readonly List<ThemeDef> All = new()
    {
        new("violet",  "Фиолетовая", "Violet",  262, 1.00, "#8B5CF6", 300, "розовые", "pink"),
        new("cyan",    "Океан",      "Ocean",   196, 1.00, "#22B8E8", 22, "оранжевые", "orange"),
        new("emerald", "Изумруд",    "Emerald", 152, 0.95, "#2FD08A", 318, "розовые", "pink"),
        new("rose",    "Роза",       "Rose",    334, 1.00, "#E8509A", 24, "оранжевые", "orange"),
        new("crimson", "Рубин",      "Ruby",    352, 1.00, "#E8465E", 30, "оранжевые", "orange"),
        new("mono",    "Графит",     "Graphite",262, 0.12, "#A8A8B8", 320, "розовые", "pink"),
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

    static readonly Dictionary<(ResourceDictionary, object), Brush> ResOrig = new();

    /// <summary>Общие кисти WPF замораживает, поэтому меняем их целиком: берём оригинал, красим копию и кладём в словарь. Всё оформление на DynamicResource обновляется само.</summary>
    static void ProcessDictionary(ResourceDictionary rd)
    {
        foreach (var key in rd.Keys.Cast<object>().ToList())
        {
            try
            {
                if (rd[key] is not Brush cur) continue;
                if (!ResOrig.TryGetValue((rd, key), out var orig)) { orig = cur; ResOrig[(rd, key)] = orig; }
                rd[key] = key is "AmberGradient" ? RecolorRisk(orig) : Recolor(orig);
            }
            catch { }
        }
        foreach (var m in rd.MergedDictionaries) ProcessDictionary(m);
    }

    /// <summary>Значки «осторожно»: отдельный оттенок под тему, чтобы отличались от обычных, при той же яркости.</summary>
    static Brush RecolorRisk(Brush orig)
    {
        var c = orig.CloneCurrentValue();
        if (c is GradientBrush gb)
            foreach (var st in gb.GradientStops)
            {
                RgbToHsv(st.Color, out _, out var s, out var v);
                double target = Lum(st.Color), lo = 0, hi = 1;
                for (int i = 0; i < 14; i++) { double m = (lo + hi) / 2; if (Lum(HsvToRgb(Current.RiskHue, s, m, 255)) < target) lo = m; else hi = m; }
                st.Color = HsvToRgb(Current.RiskHue, s, Math.Min(1, (lo + hi) / 2), st.Color.A);
            }
        return c;
    }

    static Brush Recolor(Brush orig)
    {
        var c = orig.CloneCurrentValue();
        if (c is SolidColorBrush sb) sb.Color = Shift(sb.Color);
        else if (c is GradientBrush gb) foreach (var st in gb.GradientStops) st.Color = Shift(st.Color);
        return c;
    }

    static void Walk(DependencyObject root)
    {
        var seen = new HashSet<DependencyObject>();
        void Go(DependencyObject d)
        {
            if (!seen.Add(d)) return;
            ProcessElement(d);
            if (d is Visual or System.Windows.Media.Media3D.Visual3D)
            {
                int n = VisualTreeHelper.GetChildrenCount(d);
                for (int i = 0; i < n; i++) Go(VisualTreeHelper.GetChild(d, i));
            }
            // логическое дерево: содержимое страниц, которые ещё ни разу не показывались
            foreach (var ch in LogicalTreeHelper.GetChildren(d)) if (ch is DependencyObject dc) Go(dc);
            if (d is FrameworkElement fe && fe.Resources.Count > 0) ProcessDictionary(fe.Resources);
        }
        Go(root);
    }

    static void ProcessElement(DependencyObject d)
    {
        try
        {
            var list = new List<LocalValueEntry>();
            var en = d.GetLocalValueEnumerator();
            while (en.MoveNext()) list.Add(en.Current);
            foreach (var cur in list)
            {
                var v = cur.Value;
                if (v is Brush b)
                {
                    if (!b.IsFrozen) ShiftBrush(b);
                    else if (!cur.Property.ReadOnly && d is not Freezable)
                    {
                        var nb = Recolor(b);
                        if (nb is SolidColorBrush sc) { Originals.Add(sc, new[] { b is SolidColorBrush ob ? ob.Color : sc.Color }); }
                        else if (nb is GradientBrush ng && b is GradientBrush og) { Originals.Add(ng, og.GradientStops.Select(x => x.Color).ToArray()); }
                        d.SetValue(cur.Property, nb);
                    }
                }
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
        if (Current.Id == "violet") return c;
        h = (h + _delta + 360) % 360;
        s = Math.Clamp(s * _satMul, 0, 1);
        // сохраняем яркость исходного цвета, чтобы белый текст читался так же, как на фиолетовой теме
        double target = Lum(c), lo = 0, hi = 1;
        for (int i = 0; i < 14; i++)
        {
            double mid = (lo + hi) / 2;
            if (Lum(HsvToRgb(h, s, mid, 255)) < target) lo = mid; else hi = mid;
        }
        return HsvToRgb(h, s, Math.Min(1, (lo + hi) / 2), c.A);
    }

    static double Lum(Color c) => 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B;

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
