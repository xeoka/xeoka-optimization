using System.IO;
using System.Media;
using System.Reflection;
using System.Text.Json;

namespace XeokaPack.Core;

public sealed class Settings
{
    public bool Sound { get; set; } = true;
    static string FilePath => Path.Combine(Paths.DataDir, "settings.json");
    public static Settings Load()
    {
        try { if (File.Exists(FilePath)) return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings(); } catch { }
        return new Settings();
    }
    public void Save() { try { File.WriteAllText(FilePath, JsonSerializer.Serialize(this)); } catch { } }
}

/// <summary>Звуки интерфейса (встроены в exe).</summary>
public static class SoundFx
{
    public static bool Enabled { get; set; } = true;
    static readonly Dictionary<string, SoundPlayer> Players = new();

    static SoundPlayer? Get(string name)
    {
        if (Players.TryGetValue(name, out var p)) return p;
        try
        {
            var asm = Assembly.GetExecutingAssembly();
            using var s = asm.GetManifestResourceStream("XeokaPack.Assets.Sounds." + name + ".wav");
            if (s == null) return null;
            var ms = new MemoryStream();
            s.CopyTo(ms); ms.Position = 0;
            p = new SoundPlayer(ms);
            p.Load();
            Players[name] = p;
            return p;
        }
        catch { return null; }
    }

    public static void Play(string name)
    {
        if (!Enabled) return;
        try { Get(name)?.Play(); } catch { }
    }
    public static void Tap() => Play("tap");
    public static void Tick() => Play("tick");
    public static void Deep() => Play("deep");
    public static void Chime() => Play("chime");
}
