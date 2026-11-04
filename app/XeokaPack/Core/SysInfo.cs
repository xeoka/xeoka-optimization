using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace XeokaPack.Core;

public sealed record SumItem(string Label, string Value);

public static class SysInfo
{
    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX s);

    static string Reg(string sub, string name, RegistryHive hive = RegistryHive.LocalMachine)
    {
        try
        {
            using var b = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64);
            using var k = b.OpenSubKey(sub);
            return k?.GetValue(name)?.ToString() ?? "";
        }
        catch { return ""; }
    }

    public static List<SumItem> Collect(PackLocator pack)
    {
        var list = new List<SumItem>();

        // Windows
        var prod = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "ProductName");
        var disp = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "DisplayVersion");
        var build = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuild");
        var ubr = Reg(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion", "UBR");
        if (int.TryParse(build, out var bn) && bn >= 22000) prod = prod.Replace("Windows 10", "Windows 11");
        list.Add(new("Windows", $"{prod} {disp}  (build {build}{(ubr != "" ? "." + ubr : "")})".Trim()));

        // CPU
        var cpu = Reg(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "ProcessorNameString").Trim();
        list.Add(new(Loc.L("Процессор", "Processor"), (cpu == "" ? "?" : System.Text.RegularExpressions.Regex.Replace(cpu, @"\s+", " ")) + $"  ({Environment.ProcessorCount} " + Loc.L("потоков", "threads") + ")"));

        // RAM
        try
        {
            var ms = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
            if (GlobalMemoryStatusEx(ref ms))
                list.Add(new(Loc.L("Память", "Memory"), $"{ms.ullTotalPhys / 1073741824.0:0.#} GB  ({Loc.L("занято", "used")} {ms.dwMemoryLoad}%)"));
        }
        catch { }

        // GPU
        try
        {
            using var b = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var cls = b.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}");
            var gpus = new List<string>();
            if (cls != null)
                foreach (var n in cls.GetSubKeyNames().Where(n => n.Length == 4 && char.IsDigit(n[0])))
                {
                    using var k = cls.OpenSubKey(n);
                    var d = k?.GetValue("DriverDesc")?.ToString();
                    if (!string.IsNullOrWhiteSpace(d) && !gpus.Contains(d) && !d.Contains("Basic", StringComparison.OrdinalIgnoreCase)) gpus.Add(d);
                }
            list.Add(new(Loc.L("Видеокарта", "Graphics"), gpus.Count == 0 ? "?" : string.Join(", ", gpus)));
        }
        catch { }

        // Сеть
        try
        {
            var ad = NetInfo.Primary();
            if (ad == null) list.Add(new(Loc.L("Сеть", "Network"), Loc.L("нет активного подключения", "no active connection")));
            else list.Add(new(Loc.L("Сеть", "Network"), $"{ad.Description}  ({(ad.Ethernet ? "Ethernet" : "Wi-Fi")}, {NetInfo.DriverType(ad.SubKey)})"));
        }
        catch { }

        // План питания
        try
        {
            var r = Sys.Powercfg("/getactivescheme");
            var o = r.Output;
            int a = o.IndexOf('('), z = o.LastIndexOf(')');
            list.Add(new(Loc.L("План питания", "Power plan"), a >= 0 && z > a ? o.Substring(a + 1, z - a - 1) : o.Trim()));
        }
        catch { }

        // Аптайм
        var up = TimeSpan.FromMilliseconds(Environment.TickCount64);
        list.Add(new(Loc.L("Работает без перезагрузки", "Uptime"), up.Days > 0 ? $"{up.Days} " + Loc.L("д", "d") + $" {up.Hours} " + Loc.L("ч", "h") : $"{up.Hours} " + Loc.L("ч", "h") + $" {up.Minutes} " + Loc.L("мин", "min")));

        // Пак
        list.Add(new(Loc.L("Пак XEOKA", "XEOKA pack"), pack.IsPack ? Loc.L("найден", "found") : Loc.L("не найден", "not found")));
        return list;
    }
}
