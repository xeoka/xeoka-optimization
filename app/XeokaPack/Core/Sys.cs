using System.IO;
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace XeokaPack.Core;

public static class Sys
{
    /// <summary>Запуск консольной команды без окна. Возвращает код выхода и объединённый вывод.</summary>
    public static (int Code, string Output) Run(string file, string args, int timeoutMs = 120000)
    {
        var psi = new ProcessStartInfo(file, args)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        using var p = Process.Start(psi)!;
        var sb = new StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
        p.BeginOutputReadLine(); p.BeginErrorReadLine();
        if (!p.WaitForExit(timeoutMs)) { try { p.Kill(true); } catch { } return (-1, sb.ToString() + Loc.L("\n[таймаут]", "\n[timeout]")); }
        p.WaitForExit();
        return (p.ExitCode, sb.ToString());
    }

    public static (int Code, string Output) Powercfg(params string[] args)
    {
        var line = string.Join(" ", args.Select(a => a.Contains(' ') ? "\"" + a + "\"" : a));
        return Run(Path.Combine(Environment.SystemDirectory, "powercfg.exe"), line);
    }

    /// <summary>Запуск PowerShell-команды (для штатных командлетов Windows).</summary>
    public static (int Code, string Output) PowerShell(string script, int timeoutMs = 120000)
    {
        var enc = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var exe = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        return Run(exe, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + enc, timeoutMs);
    }

    static readonly Regex GuidRx = new(@"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})", RegexOptions.Compiled);
    public static string? GuidFrom(string text) { var m = GuidRx.Match(text ?? ""); return m.Success ? m.Groups[1].Value : null; }

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }
    public static void OpenFolder(string path)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = true }); } catch { }
    }
}
