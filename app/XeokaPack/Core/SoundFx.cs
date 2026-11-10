using System.IO;
using System.Windows.Media;
using System.Reflection;
using System.Text.Json;

namespace XeokaPack.Core;

public sealed class Settings
{
    public bool Sound { get; set; } = true;
    public string Lang { get; set; } = "auto";
    public string Theme { get; set; } = "crimson";
    /// <summary>true, если тему когда-либо выбирали вручную в Настройках — иначе значение могло
    /// остаться от старого дефолта ("violet") и его можно безопасно мигрировать на новый.</summary>
    public bool ThemeChosen { get; set; } = false;
    static string FilePath => Path.Combine(Paths.DataDir, "settings.json");
    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var s = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
                if (!s.ThemeChosen && s.Theme == "violet") { s.Theme = "crimson"; s.Save(); }
                return s;
            }
        }
        catch { }
        return new Settings();
    }
    public void Save() { try { File.WriteAllText(FilePath, JsonSerializer.Serialize(this)); } catch { } }
}

/// <summary>Звуки интерфейса (встроены в exe). Каждый запуск идёт в свободном плеере, поэтому звуки накладываются друг на друга.</summary>
public static class SoundFx
{
    public static bool Enabled { get; set; } = true;

    sealed class Slot { public MediaPlayer P = new(); public bool Busy; }
    static readonly Dictionary<string, List<Slot>> Pools = new();
    static readonly Dictionary<string, Uri> Files = new();
    const int MaxVoices = 12;

    static Uri? FileFor(string name)
    {
        if (Files.TryGetValue(name, out var u)) return u;
        try
        {
            var dir = Path.Combine(Path.GetTempPath(), "XEOKA-PACK-sounds");
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, name + ".wav");
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("XeokaPack.Assets.Sounds." + name + ".wav");
            if (s == null) return null;
            using (var f = File.Create(path)) s.CopyTo(f);
            u = new Uri(path);
            Files[name] = u;
            return u;
        }
        catch { return null; }
    }

    static Slot? Acquire(string name)
    {
        var uri = FileFor(name);
        if (uri == null) return null;
        if (!Pools.TryGetValue(name, out var list)) Pools[name] = list = new List<Slot>();
        foreach (var s in list) if (!s.Busy) return s;
        if (list.Count >= MaxVoices) return list[0];
        var slot = new Slot();
        slot.P.Open(uri);
        slot.P.MediaEnded += (_, _) => slot.Busy = false;
        slot.P.MediaFailed += (_, _) => slot.Busy = false;
        list.Add(slot);
        return slot;
    }

    public static void Play(string name)
    {
        if (!Enabled) return;
        try
        {
            var slot = Acquire(name);
            if (slot == null) return;
            slot.Busy = true;
            slot.P.Position = TimeSpan.Zero;
            slot.P.Volume = 1.0;
            slot.P.Play();
        }
        catch { }
    }
    public static void Tap() => Play("tap");
    public static void Tick() => Play("tick");
    public static void Deep() => Play("deep");
    public static void Chime() => Play("chime");
}
