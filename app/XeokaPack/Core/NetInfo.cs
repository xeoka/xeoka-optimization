using System.IO;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace XeokaPack.Core;

public sealed record NicInfo(string Name, string Description, string Guid, bool Ethernet, string SubKey);

/// <summary>Определение основного сетевого адаптера и типа его драйвера.</summary>
public static class NetInfo
{
    public const string ClassPath = @"SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}";
    static readonly Regex FourDigits = new(@"^\d{4}$", RegexOptions.Compiled);

    static (string? Sub, bool Physical) FindClassKey(string id)
    {
        using var cls = Registry.LocalMachine.OpenSubKey(ClassPath);
        if (cls == null) return (null, false);
        foreach (var n in cls.GetSubKeyNames())
        {
            if (!FourDigits.IsMatch(n)) continue;
            try
            {
                using var k = cls.OpenSubKey(n);
                var inst = k?.GetValue("NetCfgInstanceId") as string;
                if (inst != null && string.Equals(inst, id, StringComparison.OrdinalIgnoreCase))
                {
                    var ch = k!.GetValue("Characteristics");
                    bool phys = ch is int i && (i & 0x4) != 0;
                    return (n, phys);
                }
            }
            catch { }
        }
        return (null, false);
    }

    public static NicInfo? Primary()
    {
        var list = new List<NicInfo>();
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            try
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel or NetworkInterfaceType.Ppp) continue;
                var (sub, phys) = FindClassKey(ni.Id);
                if (sub == null || !phys) continue;
                bool eth = ni.NetworkInterfaceType is NetworkInterfaceType.Ethernet or NetworkInterfaceType.Ethernet3Megabit
                    or NetworkInterfaceType.FastEthernetT or NetworkInterfaceType.FastEthernetFx or NetworkInterfaceType.GigabitEthernet;
                list.Add(new NicInfo(ni.Name, ni.Description, ni.Id, eth, sub));
            }
            catch { }
        }
        return list.FirstOrDefault(x => x.Ethernet) ?? list.FirstOrDefault();
    }

    /// <summary>NDIS или NetAdapterCx: ищем строку NetAdapter в драйвере.</summary>
    public static string DriverType(string subKey)
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(ClassPath + "\\" + subKey + "\\Ndi");
            var svc = (k?.GetValue("Service") as string)?.TrimEnd('.');
            if (string.IsNullOrEmpty(svc)) return "NDIS";
            using var s = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\" + svc);
            var img = (s?.GetValue("ImagePath", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string)?.Trim();
            if (string.IsNullOrEmpty(img)) return "NDIS";
            var win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            if (img.StartsWith(@"\SystemRoot", StringComparison.OrdinalIgnoreCase)) img = win + img.Substring(11);
            else if (img.StartsWith("System32", StringComparison.OrdinalIgnoreCase)) img = Path.Combine(win, img);
            else if (img.StartsWith(@"\??\")) img = img.Substring(4);
            img = Environment.ExpandEnvironmentVariables(img.Trim('"'));
            if (!File.Exists(img)) return "NDIS";
            var txt = Encoding.ASCII.GetString(File.ReadAllBytes(img));
            return txt.Contains("NetAdapter", StringComparison.Ordinal) ? "NetAdapterCx" : "NDIS";
        }
        catch { return "NDIS"; }
    }
}
