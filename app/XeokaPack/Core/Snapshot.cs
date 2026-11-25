using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace XeokaPack.Core;

/// <summary>Замер состояния системы до и после оптимизации.</summary>
public sealed record Snap(int Procs, int RamMb, int Cpu, double TimerMs, string Plan, int Applied, int Total, string At);

public sealed record Cmp(Snap Before, Snap? After);

public static class Snapshot
{
    [DllImport("ntdll.dll")] static extern int NtQueryTimerResolution(out uint min, out uint max, out uint cur);

    public static Snap Take(int applied, int total)
    {
        int procs = 0;
        try { var all = Process.GetProcesses(); procs = all.Length; foreach (var p in all) p.Dispose(); } catch { }
        var (tot, avail) = Specs.Mem();
        double timer = 0;
        try { if (NtQueryTimerResolution(out _, out _, out var cur) == 0) timer = cur / 10000.0; } catch { }
        int cpu = Specs.CpuLoad(1200);
        return new Snap(procs, (int)((tot - avail) / 1048576), cpu, Math.Round(timer, 3), Specs.PlanName(), applied, total, DateTime.Now.ToString("dd.MM HH:mm"));
    }

    static string FilePath
    {
        get
        {
            var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XEOKA-Pack");
            Directory.CreateDirectory(d);
            return Path.Combine(d, "compare.json");
        }
    }

    static readonly JsonSerializerOptions Opt = new() { PropertyNameCaseInsensitive = true };

    public static Cmp? Load()
    {
        try { return File.Exists(FilePath) ? JsonSerializer.Deserialize<Cmp>(File.ReadAllText(FilePath), Opt) : null; }
        catch { return null; }
    }

    public static void Save(Cmp c)
    {
        try { File.WriteAllText(FilePath, JsonSerializer.Serialize(c)); } catch { }
    }
}
