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
        t.Kind == ToolKind.RemoveEdge ? "remove-edge" :
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
        if (t.Kind == ToolKind.RemoveEdge)
        {
            // Использует собственный скрытый деинсталлятор Edge (тот же механизм, которым корпоративные
            // админы пакуют отсутствие Edge в образах) — находит версию через EdgeUpdate ClientState и
            // запускает её setup.exe --uninstall --force-uninstall. Плюс глушим задачи автообновления Edge,
            // чтобы он сам себя не вернул. EdgeWebView2 Runtime не трогаем — от него зависят другие программы.
            var ps = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            const string script = @"
$ErrorActionPreference = 'SilentlyContinue'

# 1) Официальный деинсталлятор Edge (ClientState -> его собственный setup.exe --uninstall)
$key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
$ver = (Get-ItemProperty -Path $key).pv
if ($ver) {
    $setup = Join-Path ${env:ProgramFiles(x86)} ""Microsoft\Edge\Application\$ver\Installer\setup.exe""
    if (Test-Path $setup) { Start-Process -FilePath $setup -ArgumentList '--uninstall --system-level --verbose-logging --force-uninstall' -Wait }
}

# Погасить процессы, которые могут держать файлы/реестр занятыми
Get-Process msedge, msedge_proxy, MicrosoftEdgeUpdate -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 2) Автообновление — чтобы Edge не вернул сам себя
Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdateTaskMachine*' | Disable-ScheduledTask | Out-Null
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'UpdateDefault' -Value 0 -Type DWord
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'InstallDefault' -Value 0 -Type DWord

# 3) Хвост папки Application, который setup.exe иногда не дочищает (бывает защищён TrustedInstaller)
function Remove-Locked($path) {
    if (-not (Test-Path $path)) { return }
    & takeown /F $path /R /D Y | Out-Null
    & icacls $path /grant *S-1-5-32-544:F /T /C | Out-Null
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Locked (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application')

# 4) Ярлыки (меню Пуск, общий и личные столы всех пользователей)
Remove-Item 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk' -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Users\*\Desktop\Microsoft Edge.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Users\Public\Desktop\Microsoft Edge.lnk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# 5) Реестр: записи об установке/приложении, которые остаются после деинсталлятора
Remove-Item 'HKLM:\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -Recurse -Force -ErrorAction SilentlyContinue

# 6) Профили Edge по всем пользователям (история/кэш/пароли/закладки) — именно это обычно и
# остаётся после setup.exe --uninstall и создаёт ощущение, что Edge ""не удалился до конца""
Get-ChildItem 'C:\Users\*\AppData\Local\Microsoft\Edge' -ErrorAction SilentlyContinue -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Обновить проводник, чтобы пропали битые иконки/значок в трее
Stop-Process -ProcessName explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
";
            var tmp = Path.Combine(Path.GetTempPath(), "xk-remove-edge.ps1");
            File.WriteAllText(tmp, script);
            Process.Start(new ProcessStartInfo(ps, "-WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + tmp + "\"") { UseShellExecute = true });
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
            case ToolKind.BiosConfig:
            {
                // Сам конфиг BIOS применяется только вручную внутри SCEWIN-GUI (см. инструкцию в паке) —
                // мы не пишем в BIOS автоматически. Показываем нужный .cfg в проводнике и открываем GUI рядом.
                try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + p + "\"")); } catch { }
                var gui = pack.Find("", "SCEWIN-GUI.exe") ?? throw new FileNotFoundException(Loc.L("SCEWIN-GUI.exe не найден.", "SCEWIN-GUI.exe was not found."));
                Process.Start(new ProcessStartInfo(gui) { WorkingDirectory = Path.GetDirectoryName(gui)!, UseShellExecute = true });
                break;
            }
            default:
                Process.Start(new ProcessStartInfo(p) { WorkingDirectory = dir, UseShellExecute = true });
                break;
        }
    }
}
