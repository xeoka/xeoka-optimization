using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace XeokaPack.Core;

public sealed class RegRecord
{
    public string Hive { get; set; } = "";
    public string Sub { get; set; } = "";
    public string Name { get; set; } = "";
    public bool Existed { get; set; }
    public string? Kind { get; set; }
    public string? Value { get; set; }
}

public sealed class OffloadState { public string Rsc { get; set; } = ""; public string Pcf { get; set; } = ""; }

/// <summary>Журнал изменений одного запуска: из него делается откат.</summary>
public sealed class RunState
{
    public string Time { get; set; } = DateTime.Now.ToString("s");
    public List<RegRecord> Ops { get; set; } = new();
    public string? PowerPrev { get; set; }
    public string? PowerNew { get; set; }
    public OffloadState? Offload { get; set; }

    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static RegistryKey? Root(string hive) => hive switch
    {
        "HKEY_LOCAL_MACHINE" => Registry.LocalMachine,
        "HKEY_CURRENT_USER" => Registry.CurrentUser,
        "HKEY_CLASSES_ROOT" => Registry.ClassesRoot,
        "HKEY_USERS" => Registry.Users,
        _ => null
    };

    /// <summary>Записывает значение, предварительно сохранив прежнее в журнал.</summary>
    public void Apply(RegOp op)
    {
        var root = Root(op.Hive) ?? throw new InvalidOperationException("Неизвестный раздел реестра: " + op.Hive);
        using var key = root.OpenSubKey(op.Sub, true) ?? root.CreateSubKey(op.Sub);
        var rec = new RegRecord { Hive = op.Hive, Sub = op.Sub, Name = op.Name };
        if (key.GetValueNames().Contains(op.Name, StringComparer.OrdinalIgnoreCase))
        {
            rec.Existed = true;
            var kind = key.GetValueKind(op.Name);
            rec.Kind = kind.ToString();
            var old = key.GetValue(op.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            rec.Value = old switch
            {
                byte[] b => Convert.ToBase64String(b),
                string[] sa => string.Join("\n", sa),
                null => null,
                _ => Convert.ToString(old, System.Globalization.CultureInfo.InvariantCulture)
            };
        }
        switch (op.Kind)
        {
            case RegKind.DWord: key.SetValue(op.Name, (int)op.Value!, RegistryValueKind.DWord); break;
            case RegKind.String: key.SetValue(op.Name, (string)op.Value!, RegistryValueKind.String); break;
            case RegKind.Delete: if (rec.Existed) key.DeleteValue(op.Name, false); break;
        }
        Ops.Add(rec);
    }

    public static void Restore(RegRecord r)
    {
        var root = Root(r.Hive);
        if (root == null) return;
        using var key = root.OpenSubKey(r.Sub, true);
        if (key == null) return;
        if (!r.Existed) { key.DeleteValue(r.Name, false); return; }
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        switch (r.Kind)
        {
            case "DWord": key.SetValue(r.Name, int.Parse(r.Value ?? "0", inv), RegistryValueKind.DWord); break;
            case "QWord": key.SetValue(r.Name, long.Parse(r.Value ?? "0", inv), RegistryValueKind.QWord); break;
            case "String": key.SetValue(r.Name, r.Value ?? "", RegistryValueKind.String); break;
            case "ExpandString": key.SetValue(r.Name, r.Value ?? "", RegistryValueKind.ExpandString); break;
            case "MultiString": key.SetValue(r.Name, (r.Value ?? "").Split('\n'), RegistryValueKind.MultiString); break;
            case "Binary": key.SetValue(r.Name, Convert.FromBase64String(r.Value ?? ""), RegistryValueKind.Binary); break;
        }
    }

    public void Save()
    {
        var f = Path.Combine(Paths.DataDir, "run-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".json");
        File.WriteAllText(f, JsonSerializer.Serialize(this, Json));
    }

    public static (FileInfo File, RunState State)? LoadLatest()
    {
        try
        {
            var f = new DirectoryInfo(Paths.DataDir).GetFiles("run-*.json").OrderByDescending(x => x.Name).FirstOrDefault();
            if (f == null) return null;
            var st = JsonSerializer.Deserialize<RunState>(File.ReadAllText(f.FullName));
            return st == null ? null : (f, st);
        }
        catch { return null; }
    }
}
