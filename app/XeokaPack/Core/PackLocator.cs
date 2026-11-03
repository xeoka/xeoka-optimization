using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace XeokaPack.Core;

/// <summary>Поиск корня пака (папки 1. ... 17.) и файлов внутри него.</summary>
public sealed class PackLocator
{
    public string Root { get; private set; } = AppContext.BaseDirectory.TrimEnd('\\', '/');
    readonly Dictionary<string, string?> _cache = new();
    static readonly Regex NumDir = new(@"^\d+\.", RegexOptions.Compiled);
    static readonly Regex NameHint = new(@"xeoka|pack|llc|optimi", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    static readonly Regex Skip = new(@"^\$|^Windows$|^Program|^System Volume|^Recovery|^AppData$|^node_modules$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    static readonly EnumerationOptions Safe = new() { IgnoreInaccessible = true, RecurseSubdirectories = false, AttributesToSkip = FileAttributes.ReparsePoint };

    public bool IsPack => IsPackRoot(Root);

    public static bool IsPackRoot(string? path)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path)) return false;
            return Directory.EnumerateDirectories(path, "*", Safe).Count(d => NumDir.IsMatch(Path.GetFileName(d))) >= 5;
        }
        catch { return false; }
    }

    public void SetRoot(string path)
    {
        Root = path;
        lock (_cache) _cache.Clear();
        try { File.WriteAllText(Path.Combine(Paths.DataDir, "root.txt"), path); } catch { }
    }

    /// <summary>Автоопределение: рядом с exe, сохранённый путь, затем быстрый поиск по типичным местам.</summary>
    public void AutoDetect()
    {
        var start = AppContext.BaseDirectory.TrimEnd('\\', '/');
        var cands = new List<string> { start };
        try { var par = Path.GetDirectoryName(start); if (par != null) cands.Add(par); } catch { }
        foreach (var b in cands.ToList())
            try { foreach (var d in Directory.EnumerateDirectories(b, "*", Safe)) if (NameHint.IsMatch(Path.GetFileName(d))) cands.Add(d); } catch { }
        try
        {
            var saved = Path.Combine(Paths.DataDir, "root.txt");
            if (File.Exists(saved)) cands.Add(File.ReadAllText(saved).Trim());
        }
        catch { }
        foreach (var c in cands) if (IsPackRoot(c)) { SetRootQuiet(c); return; }

        var bases = new List<string>();
        void AddB(string? p) { if (!string.IsNullOrEmpty(p) && Directory.Exists(p)) bases.Add(p); }
        var up = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        AddB(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
        AddB(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
        AddB(Path.Combine(up, "Downloads"));
        AddB(Path.Combine(up, "OneDrive", "Desktop"));
        AddB(up);
        foreach (var dr in DriveInfo.GetDrives()) { try { if (dr.DriveType == DriveType.Fixed && dr.IsReady) AddB(dr.RootDirectory.FullName); } catch { } }
        var sw = Stopwatch.StartNew();
        var found = new List<string>();
        foreach (var b in bases) Walk(b, 3, found, sw);
        foreach (var c in found) if (IsPackRoot(c)) { SetRootQuiet(c); return; }
    }

    void SetRootQuiet(string p) { Root = p; lock (_cache) _cache.Clear(); }

    static void Walk(string baseDir, int depth, List<string> acc, Stopwatch sw)
    {
        if (depth <= 0 || sw.ElapsedMilliseconds > 6000) return;
        IEnumerable<string> dirs;
        try { dirs = Directory.EnumerateDirectories(baseDir, "*", Safe).ToList(); } catch { return; }
        foreach (var d in dirs)
        {
            if (sw.ElapsedMilliseconds > 6000) return;
            var n = Path.GetFileName(d);
            if (Skip.IsMatch(n)) continue;
            if (NameHint.IsMatch(n)) acc.Add(d);
            if (depth > 1) Walk(d, depth - 1, acc, sw);
        }
    }

    /// <summary>Ищет файл (маска допускается) сначала в папках пака с нужным префиксом, потом по всему паку.</summary>
    public string? Find(string folderPrefix, string fileName)
    {
        var key = Root + "|" + folderPrefix + "|" + fileName;
        lock (_cache) if (_cache.TryGetValue(key, out var c) && c != null && File.Exists(c)) return c;
        string? res = null;
        try
        {
            var all = new EnumerationOptions { IgnoreInaccessible = true, RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint };
            if (Directory.Exists(Root))
            {
                foreach (var d in Directory.EnumerateDirectories(Root, "*", Safe))
                {
                    if (!Path.GetFileName(d).StartsWith(folderPrefix, StringComparison.OrdinalIgnoreCase)) continue;
                    res = Directory.EnumerateFiles(d, fileName, all).FirstOrDefault();
                    if (res != null) break;
                }
                res ??= Directory.EnumerateFiles(Root, fileName, all).FirstOrDefault();
            }
        }
        catch { }
        lock (_cache) _cache[key] = res;
        return res;
    }
}
