using System.Diagnostics;
using System.IO;

namespace XeokaPack.Core;

public static class ToolLauncher
{
    public static string? Resolve(PackLocator pack, ToolDef t) => pack.Find(t.Prefix, t.File);

    public static void Launch(PackLocator pack, ToolDef t)
    {
        var p = Resolve(pack, t) ?? throw new FileNotFoundException(Loc.L("Файл «" + t.File + "» не найден в паке.", "File \"" + t.File + "\" was not found in the pack."));
        var dir = Path.GetDirectoryName(p)!;
        switch (t.Kind)
        {
            case ToolKind.Nvidia:
            {
                var nip = pack.Find("2.", "XEOKA-OPTIMIZED-V2.nip") ?? pack.Find("2.", "LLC-OPTIMIZED-V2.nip")
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
                var pr = pack.Find("10.", "PowerRun_x64.exe") ?? throw new FileNotFoundException(Loc.L("PowerRun_x64.exe не найден.", "PowerRun_x64.exe was not found."));
                Process.Start(new ProcessStartInfo(pr, "regedit.exe /s \"" + p + "\"") { WorkingDirectory = Path.GetDirectoryName(pr)!, UseShellExecute = true });
                break;
            }
            default:
                Process.Start(new ProcessStartInfo(p) { WorkingDirectory = dir, UseShellExecute = true });
                break;
        }
    }
}
