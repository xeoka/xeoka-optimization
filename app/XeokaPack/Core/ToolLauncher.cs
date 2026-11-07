using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace XeokaPack.Core;

public static class ToolLauncher
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool DeleteFileW(string path);

    /// <summary>Снимает пометку «файл из интернета» (Zone.Identifier), из-за неё Windows спрашивает «Вы хотите запустить этот файл?».</summary>
    public static void Unblock(string file)
    {
        try { DeleteFileW(file + ":Zone.Identifier"); } catch { }
    }

    public static void UnblockTree(string root)
    {
        try
        {
            if (!Directory.Exists(root)) return;
            foreach (var f in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)) Unblock(f);
        }
        catch { }
    }

    // Системные инструменты (ToolKind.System) встроены в Windows: файла пака не нужно, поэтому
    // "найдены" всегда — t.File тут держит не путь, а имя команды/программы (UserAccountControlSettings.exe, appwiz.cpl, ms-settings:...).
    // ToolKind.ActivateWindows — тоже без файла пака, запускает сторонний скрипт по ссылке.
    public static string? Resolve(PackLocator pack, ToolDef t) =>
        t.Kind == ToolKind.System ? t.File :
        t.Kind == ToolKind.ActivateWindows ? "get.activated.win" :
        pack.Find(t.Prefix, t.File);

    public static void Launch(PackLocator pack, ToolDef t)
    {
        if (t.Kind == ToolKind.System)
        {
            Process.Start(new ProcessStartInfo(t.File) { UseShellExecute = true });
            return;
        }
        if (t.Kind == ToolKind.ActivateWindows)
        {
            // То же самое, что делает "Активация-Windows.BAT" в паке: скачивает и запускает скрипт
            // активации с get.activated.win (Microsoft Activation Scripts) в скрытом окне PowerShell.
            var ps = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            Process.Start(new ProcessStartInfo(ps, "-WindowStyle Hidden -Command \"iex (irm https://get.activated.win)\"") { UseShellExecute = true });
            return;
        }
        var p = Resolve(pack, t) ?? throw new FileNotFoundException(Loc.L("Файл «" + t.File + "» не найден в паке.", "File \"" + t.File + "\" was not found in the pack."));
        var dir = Path.GetDirectoryName(p)!;
        UnblockTree(dir);
        switch (t.Kind)
        {
            case ToolKind.Nvidia:
            {
                var nip = pack.Find("", "XEOKA-OPTIMIZED-V2.nip") ?? pack.Find("", "LLC-OPTIMIZED-V2.nip")
                          ?? throw new FileNotFoundException(Loc.L("Файл XEOKA-OPTIMIZED-V2.nip не найден в паке.", "File XEOKA-OPTIMIZED-V2.nip was not found in the pack."));
                Process.Start(new ProcessStartInfo(p, "\"" + nip + "\"") { WorkingDirectory = dir, UseShellExecute = true });
                break;
            }
            case ToolKind.Ps1:
            {
                var ps = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
                Process.Start(new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -File \"" + p + "\"") { WorkingDirectory = dir, UseShellExecute = true });
                break;
            }
            case ToolKind.Services:
            {
                var pr = pack.Find("", "PowerRun_x64.exe") ?? throw new FileNotFoundException(Loc.L("PowerRun_x64.exe не найден.", "PowerRun_x64.exe was not found."));
                Process.Start(new ProcessStartInfo(pr, "regedit.exe /s \"" + p + "\"") { WorkingDirectory = Path.GetDirectoryName(pr)!, UseShellExecute = true });
                break;
            }
            default:
                Process.Start(new ProcessStartInfo(p) { WorkingDirectory = dir, UseShellExecute = true });
                break;
        }
    }
}
