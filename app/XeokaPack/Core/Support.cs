using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

namespace XeokaPack.Core;

/// <summary>Архив для поддержки: сводка о системе, состояние твиков, журналы и файлы отката. Личных данных не собирает.</summary>
public static class Support
{
    public static string Build(PackLocator pack, IEnumerable<SumItem> summary, IEnumerable<(string Title, string State)> tweaks, Settings st)
    {
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        if (string.IsNullOrEmpty(desktop) || !Directory.Exists(desktop)) desktop = Paths.DataDir;
        var zipPath = Path.Combine(desktop, "XEOKA-support-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".zip");

        var sb = new StringBuilder();
        var ver = Assembly.GetExecutingAssembly().GetName().Version;
        sb.AppendLine("xeoka optimization support report");
        sb.AppendLine("App version : " + ver);
        sb.AppendLine("Created     : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        sb.AppendLine("Language    : " + (Loc.En ? "en" : "ru") + "  (setting: " + st.Lang + ")");
        sb.AppendLine("Theme       : " + st.Theme);
        sb.AppendLine("Pack found  : " + pack.IsPack + "  (" + pack.Root + ")");
        sb.AppendLine("OS 64-bit   : " + Environment.Is64BitOperatingSystem + ", .NET " + Environment.Version);
        sb.AppendLine();
        sb.AppendLine("== System ==");
        foreach (var s in summary) sb.AppendLine($"{s.Label}: {s.Value}");
        sb.AppendLine();
        sb.AppendLine("== Tweaks state ==");
        foreach (var t in tweaks) sb.AppendLine($"{t.Title}: {t.State}");

        try
        {
            using var fs = new FileStream(zipPath, FileMode.Create);
            using var zip = new ZipArchive(fs, ZipArchiveMode.Create);
            AddText(zip, "info.txt", sb.ToString());
            try { AddText(zip, "powercfg.txt", Sys.Powercfg("/getactivescheme").Output + Environment.NewLine + Sys.Powercfg("/list").Output); } catch { }
            try
            {
                if (pack.IsPack)
                    AddText(zip, "pack-folders.txt", string.Join(Environment.NewLine, Directory.GetDirectories(pack.Root).Select(Path.GetFileName)));
            }
            catch { }
            foreach (var f in Directory.GetFiles(Paths.DataDir, "log-*.txt").OrderByDescending(x => x).Take(4)) AddFile(zip, f);
            foreach (var f in Directory.GetFiles(Paths.DataDir, "run-*.json").OrderByDescending(x => x).Take(5)) AddFile(zip, f);
            foreach (var n in new[] { "settings.json", "error.txt" })
            {
                var p = Path.Combine(Paths.DataDir, n);
                if (File.Exists(p)) AddFile(zip, p);
            }
        }
        catch { throw; }
        return zipPath;
    }

    static void AddText(ZipArchive z, string name, string text)
    {
        var e = z.CreateEntry(name);
        using var w = new StreamWriter(e.Open(), new UTF8Encoding(false));
        w.Write(text);
    }

    static void AddFile(ZipArchive z, string path)
    {
        try
        {
            var e = z.CreateEntry(Path.GetFileName(path));
            using var src = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var dst = e.Open();
            src.CopyTo(dst);
        }
        catch { }
    }
}
