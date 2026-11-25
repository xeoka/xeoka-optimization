using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace XeokaPack.Core;

public sealed record SpecCard(string I, string T, string P, int M, string Ml);

/// <summary>Характеристики ПК для центрального экрана: процессор, видеокарта, память, диск, сеть.</summary>
public static class Specs
{
    [StructLayout(LayoutKind.Sequential)]
    struct FT { public uint Lo, Hi; public ulong V => ((ulong)Hi << 32) | Lo; }
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out FT idle, out FT kernel, out FT user);

    [StructLayout(LayoutKind.Sequential)]
    struct MEM
    {
        public uint Len, Load;
        public ulong Total, Avail, TotalPage, AvailPage, TotalVirt, AvailVirt, AvailExt;
    }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEM m);

    static string Reg(string sub, string name)
    {
        try
        {
            using var b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var k = b.OpenSubKey(sub);
            return k?.GetValue(name)?.ToString() ?? "";
        }
        catch { return ""; }
    }

    internal static int CpuLoad(int ms = 250)
    {
        try
        {
            GetSystemTimes(out var i1, out var k1, out var u1);
            Thread.Sleep(ms);
            GetSystemTimes(out var i2, out var k2, out var u2);
            double idle = i2.V - i1.V, total = (k2.V - k1.V) + (u2.V - u1.V);
            return total <= 0 ? 0 : (int)Math.Round(Math.Clamp(100 - idle * 100 / total, 0, 100));
        }
        catch { return 0; }
    }

    internal static (ulong Total, ulong Avail) Mem()
    {
        var ms = new MEM { Len = (uint)Marshal.SizeOf<MEM>() };
        return GlobalMemoryStatusEx(ref ms) ? (ms.Total, ms.Avail) : (0, 0);
    }

    internal static string PlanName()
    {
        try
        {
            var o = Sys.Powercfg("/getactivescheme").Output;
            int a = o.IndexOf('('), z = o.LastIndexOf(')');
            return a >= 0 && z > a ? o.Substring(a + 1, z - a - 1) : "";
        }
        catch { return ""; }
    }

    static string Gb(double bytes)
    {
        var g = bytes / 1e9;
        return g >= 950 ? $"{g / 1000:0.#} TB" : $"{Math.Round(g)} GB";
    }

    static (string Name, string Sub) Gpu()
    {
        try
        {
            using var b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var cls = b.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}");
            if (cls == null) return ("?", "");
            var best = ("", "", 0L, -1);
            foreach (var n in cls.GetSubKeyNames().Where(n => n.Length == 4 && char.IsDigit(n[0])))
            {
                using var k = cls.OpenSubKey(n);
                var d = k?.GetValue("DriverDesc")?.ToString();
                if (string.IsNullOrWhiteSpace(d) || d.Contains("Basic", StringComparison.OrdinalIgnoreCase) || d.Contains("Microsoft", StringComparison.OrdinalIgnoreCase)) continue;
                var ver = k!.GetValue("DriverVersion")?.ToString() ?? "";
                long vram = 0;
                var raw = k.GetValue("HardwareInformation.qwMemorySize");
                if (raw is long l) vram = l;
                else if (raw is byte[] bb && bb.Length >= 8) vram = BitConverter.ToInt64(bb, 0);
                int score = Regex.IsMatch(d, "NVIDIA|GeForce|RTX|GTX|Radeon RX|Arc", RegexOptions.IgnoreCase) ? 2 : 1;
                if (score > best.Item4) best = (d, ver, vram, score);
            }
            if (best.Item4 < 0) return ("?", "");
            var name = Regex.Replace(best.Item1, @"^NVIDIA\s+", "", RegexOptions.IgnoreCase).Trim();
            var parts = new List<string>();
            if (best.Item3 > 0) parts.Add(Math.Round(best.Item3 / 1073741824.0) + " GB");
            var v = best.Item2.Split('.');
            if (Regex.IsMatch(best.Item1, "NVIDIA|GeForce", RegexOptions.IgnoreCase) && v.Length == 4 && v[2].Length >= 1 && v[3].Length >= 4)
                parts.Add(Loc.L("драйвер ", "driver ") + v[2][^1] + v[3][..^2] + "." + v[3][^2..]);
            else if (best.Item2 != "") parts.Add(Loc.L("драйвер ", "driver ") + best.Item2);
            return (name, string.Join(" · ", parts));
        }
        catch { return ("?", ""); }
    }

    public static (List<SpecCard> Cards, string Line) Collect(PackLocator pack)
    {
        var cards = new List<SpecCard>();

        var cpu = Reg(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "ProcessorNameString").Trim();
        cpu = Regex.Replace(cpu, @"\((R|TM)\)|\s+\d+-Core Processor|\s+CPU\b|\s+Processor\b", "", RegexOptions.IgnoreCase);
        cpu = Regex.Replace(cpu, @"\s+", " ").Trim();
        int load = CpuLoad();
        cards.Add(new("cpu", cpu == "" ? Loc.L("Процессор", "Processor") : cpu, Loc.L($"{Environment.ProcessorCount} потоков", $"{Environment.ProcessorCount} threads"), load, Loc.L($"загрузка {load}%", $"load {load}%")));

        var (gn, gs) = Gpu();
        cards.Add(new("gpu", gn, gs == "" ? Loc.L("видеокарта", "graphics card") : gs, 0, Loc.L("готова", "ready")));

        try
        {
            var ms = new MEM { Len = (uint)Marshal.SizeOf<MEM>() };
            if (GlobalMemoryStatusEx(ref ms))
                cards.Add(new("ram", Math.Round(ms.Total / 1073741824.0) + " GB", Loc.L("оперативная память", "system memory"), (int)ms.Load, Loc.L($"занято {ms.Load}%", $"used {ms.Load}%")));
        }
        catch { }

        try
        {
            var root = Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
            var di = new DriveInfo(root);
            var used = di.TotalSize - di.AvailableFreeSpace;
            cards.Add(new("disk", Gb(di.TotalSize), Loc.L($"системный диск {root.TrimEnd('\\')}", $"system drive {root.TrimEnd('\\')}"), (int)Math.Round(used * 100.0 / di.TotalSize), Loc.L($"свободно {Gb(di.AvailableFreeSpace)}", $"{Gb(di.AvailableFreeSpace)} free")));
        }
        catch { }

        try
        {
            var ad = NetInfo.Primary();
            if (ad == null) cards.Add(new("net", Loc.L("Нет сети", "No network"), Loc.L("нет активного подключения", "no active connection"), 0, "offline"));
            else cards.Add(new("net", ad.Description, $"{(ad.Ethernet ? "Ethernet" : "Wi-Fi")} · {Loc.L("драйвер", "driver")} {NetInfo.DriverType(ad.SubKey)}", 0, "online"));
        }
        catch { }

        // строка снизу: ОС, аптайм, план питания
        var line = new List<string>();
        try
        {
            var prod = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductName");
            var disp = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "DisplayVersion");
            var build = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuild");
            var ubr = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "UBR");
            if (int.TryParse(build, out var bn) && bn >= 22000) prod = prod.Replace("Windows 10", "Windows 11");
            line.Add($"{prod} {disp}".Trim());
            line.Add(Loc.L("сборка ", "build ") + $"{build}{(ubr != "" ? "." + ubr : "")}");
            var up = TimeSpan.FromMilliseconds(Environment.TickCount64);
            line.Add(Loc.L("без перезагрузки ", "uptime ") + (up.Days > 0 ? Loc.L($"{up.Days} д {up.Hours} ч", $"{up.Days} d {up.Hours} h") : Loc.L($"{up.Hours} ч {up.Minutes} мин", $"{up.Hours} h {up.Minutes} min")));
            var o = Sys.Powercfg("/getactivescheme").Output;
            int a = o.IndexOf('('), z = o.LastIndexOf(')');
            if (a >= 0 && z > a) line.Add(Loc.L("план питания: ", "power plan: ") + o.Substring(a + 1, z - a - 1));
        }
        catch { }
        return (cards, string.Join(" · ", line));
    }
}
