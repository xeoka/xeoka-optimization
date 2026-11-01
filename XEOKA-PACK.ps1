# XEOKA PACK - оптимизация Windows одной кнопкой
# ТГ: https://t.me/CMEPT0HOCHbIU

param([switch]$NoElevate)

$ErrorActionPreference = 'Stop'

trap {
    $m = $_.Exception.Message + "`r`n`r`n" + $_.InvocationInfo.PositionMessage
    try {
        $d = Join-Path $env:ProgramData 'XEOKA-Pack'
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Set-Content -Path (Join-Path $d 'error.txt') -Value $m -Encoding UTF8
    } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($m, 'XEOKA PACK: ошибка') | Out-Null
    } catch { }
    exit 1
}
$script:Version  = '1.0'
$script:TgUrl    = 'https://t.me/CMEPT0HOCHbIU'
$script:TgLabel  = 't.me/CMEPT0HOCHbIU'
$script:Root     = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:DataDir  = Join-Path $env:ProgramData 'XEOKA-Pack'

# ---------------------------------------------------------------- admin
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
    if ($NoElevate) { Write-Host 'Нужны права администратора.'; exit 1 }
    try {
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args2 = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoElevate' -f $MyInvocation.MyCommand.Path
        Start-Process -FilePath $psExe -ArgumentList $args2 -Verb RunAs
    } catch { }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    try { [System.Windows.Forms.MessageBox]::Show($e.Exception.Message, 'XEOKA PACK: ошибка') | Out-Null } catch { }
})

if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

# ---------------------------------------------------------------- поиск файлов пака
function Find-PackFile {
    param([string]$FolderPrefix, [string]$FileName)
    $dirs = @(Get-ChildItem -Path $script:Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$FolderPrefix*" })
    foreach ($d in $dirs) {
        $hit = Get-ChildItem -Path $d.FullName -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ---------------------------------------------------------------- реестр: разбор .reg, запись, бэкап
function Read-RegFile {
    param([string]$Path)
    $sr = New-Object System.IO.StreamReader($Path, $true)
    try { $text = $sr.ReadToEnd() } finally { $sr.Close() }
    $ops = New-Object System.Collections.ArrayList
    $hive = $null; $sub = $null
    foreach ($raw in ($text -split "`r?`n")) {
        $l = $raw.Trim()
        if ($l -eq '' -or $l.StartsWith(';') -or $l.StartsWith('Windows Registry Editor')) { continue }
        if ($l -match '^\[(-?)(HKEY_[A-Z_]+)\\?(.*)\]$') {
            if ($Matches[1] -eq '-') { $hive = $null; continue }
            $hive = $Matches[2]; $sub = $Matches[3]
            continue
        }
        if (-not $hive) { continue }
        $name = $null; $rest = $null
        if ($l -match '^@\s*=\s*(.+)$') { $name = ''; $rest = $Matches[1] }
        elseif ($l -match '^"((?:[^"\\]|\\.)*)"\s*=\s*(.+)$') {
            $name = ($Matches[1] -replace '\\(.)', '$1')
            $name = $name -replace '[​-‍﻿]', ''
            $rest = $Matches[2]
        } else { continue }
        $rest = $rest.Trim()
        $op = [ordered]@{ Hive = $hive; Sub = $sub; Name = $name; Kind = $null; Value = $null }
        if ($rest -match '^dword:([0-9a-fA-F]{1,8})$') {
            $u = [Convert]::ToUInt32($Matches[1], 16)
            $op.Kind = 'DWord'
            $op.Value = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$u), 0)
        } elseif ($rest -match '^"((?:[^"\\]|\\.)*)"$') {
            $op.Kind = 'String'
            $op.Value = ($Matches[1] -replace '\\(.)', '$1')
        } elseif ($rest -eq '-') {
            $op.Kind = 'Delete'
        } else {
            $op.Kind = 'Unsupported'
        }
        [void]$ops.Add($op)
    }
    return ,$ops
}

function Get-RegRoot {
    param([string]$Hive)
    switch ($Hive) {
        'HKEY_LOCAL_MACHINE' { return [Microsoft.Win32.Registry]::LocalMachine }
        'HKEY_CURRENT_USER'  { return [Microsoft.Win32.Registry]::CurrentUser }
        'HKEY_CLASSES_ROOT'  { return [Microsoft.Win32.Registry]::ClassesRoot }
        'HKEY_USERS'         { return [Microsoft.Win32.Registry]::Users }
    }
    return $null
}

$script:RunState = $null
function New-RunState {
    $script:RunState = [ordered]@{
        Time = (Get-Date).ToString('s')
        Ops = New-Object System.Collections.ArrayList
        PowerPrev = $null
        PowerNew = $null
        Offload = $null
    }
}

function Write-RegOp {
    param($Op)
    $root = Get-RegRoot $Op.Hive
    if (-not $root) { throw "Неизвестный раздел реестра: $($Op.Hive)" }
    $key = $root.OpenSubKey($Op.Sub, $true)
    if (-not $key) { $key = $root.CreateSubKey($Op.Sub) }
    try {
        $rec = [ordered]@{ Hive = $Op.Hive; Sub = $Op.Sub; Name = $Op.Name; Existed = $false; Kind = $null; Value = $null }
        if (@($key.GetValueNames()) -contains $Op.Name) {
            $rec.Existed = $true
            $rec.Kind = $key.GetValueKind($Op.Name).ToString()
            $old = $key.GetValue($Op.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($old -is [byte[]]) { $rec.Value = [Convert]::ToBase64String($old) }
            elseif ($old -is [string[]]) { $rec.Value = ($old -join "`n") }
            else { $rec.Value = $old }
        }
        if ($Op.Kind -eq 'DWord') {
            $key.SetValue($Op.Name, [int]$Op.Value, [Microsoft.Win32.RegistryValueKind]::DWord)
        } elseif ($Op.Kind -eq 'String') {
            $key.SetValue($Op.Name, [string]$Op.Value, [Microsoft.Win32.RegistryValueKind]::String)
        } elseif ($Op.Kind -eq 'Delete') {
            if ($rec.Existed) { $key.DeleteValue($Op.Name, $false) }
        }
        [void]$script:RunState.Ops.Add($rec)
    } finally { $key.Close() }
}

function Restore-RegOp {
    param($Rec)
    $root = Get-RegRoot $Rec.Hive
    if (-not $root) { return }
    $key = $root.OpenSubKey($Rec.Sub, $true)
    if (-not $key) { return }
    try {
        if (-not $Rec.Existed) { $key.DeleteValue($Rec.Name, $false); return }
        switch ($Rec.Kind) {
            'DWord'        { $key.SetValue($Rec.Name, [int]$Rec.Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
            'QWord'        { $key.SetValue($Rec.Name, [long]$Rec.Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
            'String'       { $key.SetValue($Rec.Name, [string]$Rec.Value, [Microsoft.Win32.RegistryValueKind]::String) }
            'ExpandString' { $key.SetValue($Rec.Name, [string]$Rec.Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
            'MultiString'  { $key.SetValue($Rec.Name, [string[]](([string]$Rec.Value) -split "`n"), [Microsoft.Win32.RegistryValueKind]::MultiString) }
            'Binary'       { $key.SetValue($Rec.Name, [Convert]::FromBase64String([string]$Rec.Value), [Microsoft.Win32.RegistryValueKind]::Binary) }
        }
    } finally { $key.Close() }
}

function Invoke-RegFile {
    param([string]$Path, [string]$NetSubKey)
    if (-not $Path -or -not (Test-Path $Path)) { throw 'Файл .reg не найден в паке.' }
    $ops = Read-RegFile -Path $Path
    $done = 0
    foreach ($op in $ops) {
        if ($op.Kind -eq 'Unsupported') { Write-Log ("  пропущено (тип значения не поддерживается): " + $op.Name) 'warn'; continue }
        if ($NetSubKey) {
            $op.Sub = [regex]::Replace($op.Sub, '(?i)(Control\\Class\\\{4D36E972-E325-11CE-BFC1-08002BE10318\})\\\d{4}$', ('$1\' + $NetSubKey))
        }
        try { Write-RegOp -Op $op; $done++ }
        catch { Write-Log ("  ошибка записи " + $op.Name + ": " + $_.Exception.Message) 'warn' }
    }
    Write-Log ("  записано параметров: $done из $($ops.Count)") 'dim'
}

# ---------------------------------------------------------------- сеть
function Get-PrimaryAdapter {
    $ads = @()
    try { $ads = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) } catch { }
    if ($ads.Count -eq 0) { return $null }
    $eth = @($ads | Where-Object { $_.PhysicalMediaType -eq '802.3' })
    if ($eth.Count -gt 0) { return $eth[0] }
    return $ads[0]
}

function Get-NetClassSubKey {
    param($Adapter)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}'
    foreach ($k in (Get-ChildItem -Path $base -ErrorAction SilentlyContinue)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }
        $id = (Get-ItemProperty -Path $k.PSPath -Name 'NetCfgInstanceId' -ErrorAction SilentlyContinue).NetCfgInstanceId
        if ($id -and ($id -ieq $Adapter.InterfaceGuid)) { return $k.PSChildName }
    }
    return $null
}

function Get-NicDriverType {
    param([string]$SubKey)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\' + $SubKey
    try {
        $svc = (Get-ItemProperty -Path ($base + '\Ndi') -Name 'Service' -ErrorAction Stop).Service
        if (-not $svc) { return 'NDIS' }
        $svc = $svc.TrimEnd('.')
        $img = (Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $svc) -Name 'ImagePath' -ErrorAction Stop).ImagePath
        $p = $img.Trim()
        if ($p -like '\SystemRoot*') { $p = $p -replace '^\\SystemRoot', $env:SystemRoot }
        elseif ($p -like 'System32*') { $p = Join-Path $env:SystemRoot $p }
        elseif ($p -match '^\\\?\?\\') { $p = $p -replace '^\\\?\?\\', '' }
        $p = $p.Trim('"')
        if (-not (Test-Path $p)) { return 'NDIS' }
        $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($p))
        if ($txt -match 'NetAdapter') { return 'NetAdapterCx' }
        return 'NDIS'
    } catch { return 'NDIS' }
}

# ---------------------------------------------------------------- твики
function Invoke-Tweak-Power {
    $pow = Find-PackFile '4.' 'xeoka.pow'
    if (-not $pow) { throw 'xeoka.pow не найден.' }
    $cur = (& powercfg /getactivescheme 2>&1 | Out-String)
    if ($cur -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $script:RunState.PowerPrev = $Matches[1] }
    $out = (& powercfg /import $pow 2>&1 | Out-String)
    if ($out -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { throw ('powercfg /import: ' + $out.Trim()) }
    $guid = $Matches[1]
    & powercfg /setactive $guid | Out-Null
    $script:RunState.PowerNew = $guid
    Write-Log ("  схема питания $guid активирована") 'dim'
}

function Invoke-Tweak-Priority {
    Invoke-RegFile (Find-PackFile '17.' 'Win32PrioritySeparation-18.reg')
}

function Invoke-Tweak-Timer {
    Invoke-RegFile (Find-PackFile '14.' 'SerializeTimerExpiration-1.reg')
}

function Invoke-Tweak-Mmcss {
    $type = 'NDIS'
    $ad = Get-PrimaryAdapter
    if ($ad) {
        $sub = Get-NetClassSubKey $ad
        if ($sub) { $type = Get-NicDriverType $sub }
    }
    Write-Log ("  тип драйвера сетевой карты: $type") 'dim'
    if ($type -eq 'NetAdapterCx') {
        Invoke-RegFile (Find-PackFile '15.' 'DISABLE-MMCSS.reg')
    } else {
        Invoke-RegFile (Find-PackFile '15.' 'XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg')
    }
}

function Invoke-Tweak-Network {
    $ad = Get-PrimaryAdapter
    if (-not $ad) { throw 'Не найден активный сетевой адаптер.' }
    if ($ad.PhysicalMediaType -ne '802.3') { throw 'Активное подключение не Ethernet (Wi-Fi пропущен для безопасности).' }
    $sub = Get-NetClassSubKey $ad
    if (-not $sub) { throw 'Не удалось определить ключ реестра адаптера.' }
    Write-Log ("  адаптер: " + $ad.Name + " (" + $ad.InterfaceDescription + "), ключ $sub") 'dim'
    Invoke-RegFile (Find-PackFile '9.' 'OPTIMIZE-NETWORKING.reg') $sub
    Invoke-RegFile (Find-PackFile '9.' 'DISABLE-POWERSAVING.reg') $sub
    try {
        $g = Get-NetOffloadGlobalSetting
        $script:RunState.Offload = [ordered]@{ Rsc = [string]$g.ReceiveSegmentCoalescing; Pcf = [string]$g.PacketCoalescingFilter }
        Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -PacketCoalescingFilter Disabled
    } catch { Write-Log ('  Set-NetOffloadGlobalSetting: ' + $_.Exception.Message) 'warn' }
    Write-Log '  перезапуск адаптера не выполняется: изменения вступят в силу после перезагрузки' 'dim'
}

function Invoke-Tweak-GameBar {
    $ops = @(
        @{ H = 'HKEY_CURRENT_USER'; S = 'System\GameConfigStore'; N = 'GameDVR_Enabled'; V = 0 },
        @{ H = 'HKEY_CURRENT_USER'; S = 'Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled'; V = 0 },
        @{ H = 'HKEY_CURRENT_USER'; S = 'Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; V = 0 },
        @{ H = 'HKEY_CURRENT_USER'; S = 'Software\Microsoft\GameBar'; N = 'AllowAutoGameMode'; V = 0 },
        @{ H = 'HKEY_CURRENT_USER'; S = 'Software\Microsoft\GameBar'; N = 'UseNexusForGameBarEnabled'; V = 0 }
    )
    foreach ($o in $ops) {
        Write-RegOp ([ordered]@{ Hive = $o.H; Sub = $o.S; Name = $o.N; Kind = 'DWord'; Value = $o.V })
    }
}

function Invoke-Tweak-Fse {
    Invoke-RegFile (Find-PackFile '16.' 'FSE.reg')
}

function Invoke-Tweak-Fso {
    Invoke-RegFile (Find-PackFile '16.' 'FSO.reg')
}

function Invoke-Tweak-Nvidia {
    $npi = Find-PackFile '2.' 'nvidiaProfileInspector.exe'
    $nip = Find-PackFile '2.' 'XEOKA-OPTIMIZED-V2.nip'
    if (-not $npi -or -not $nip) { throw 'Nvidia Profile Inspector или .nip не найдены.' }
    $p = Start-Process -FilePath $npi -ArgumentList ('-silentImport "{0}"' -f $nip) -WorkingDirectory (Split-Path $npi) -PassThru -WindowStyle Hidden
    $t = 0
    while (-not $p.HasExited -and $t -lt 60) { Start-Sleep -Milliseconds 250; $t++; [System.Windows.Forms.Application]::DoEvents() }
    if (-not $p.HasExited) { Write-Log '  Profile Inspector всё ещё запущен, проверьте окно' 'warn' }
}

function Invoke-Tweak-DevicePower {
    $bat = Find-PackFile '11.' 'Disable-All-Device-PowerSaving.bat'
    if (-not $bat) { throw 'Disable-All-Device-PowerSaving.bat не найден.' }
    Write-Log '  откроется окно с отчётом: нажмите любую клавишу в нём, когда прочитаете результат' 'dim'
    $p = Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ""{0}""' -f $bat) -WorkingDirectory (Split-Path $bat) -PassThru
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents() }
}

function Test-HasNvidia {
    try { return [bool](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }) } catch { return $false }
}

$script:Tweaks = @(
    @{ Id = 'power';   Group = 'rec'; Default = $true;  Title = 'План питания XEOKA';
       Desc = 'Импортирует и включает схему xeoka.pow. Предыдущая схема запоминается для отката.';
       Run = { Invoke-Tweak-Power } },
    @{ Id = 'prio';    Group = 'rec'; Default = $true;  Title = 'Приоритет процессов (Win32PrioritySeparation = 0x18)';
       Desc = 'Больше процессорного времени активному окну (игре).';
       Run = { Invoke-Tweak-Priority } },
    @{ Id = 'timer';   Group = 'rec'; Default = $true;  Title = 'Прерывания системного таймера';
       Desc = 'SerializeTimerExpiration = 1.';
       Run = { Invoke-Tweak-Timer } },
    @{ Id = 'mmcss';   Group = 'rec'; Default = $true;  Title = 'MMCSS (по типу драйвера сетевой карты)';
       Desc = 'NDIS: оптимизированные параметры. NetAdapterCx: служба MMCSS отключается. Определяется автоматически.';
       Run = { Invoke-Tweak-Mmcss } },
    @{ Id = 'net';     Group = 'rec'; Default = $true;  Title = 'Сетевой адаптер (Ethernet)';
       Desc = 'Оптимизация параметров карты и отключение энергосбережения. Путь в реестре определяется сам. Wi-Fi не затрагивается.';
       Run = { Invoke-Tweak-Network } },
    @{ Id = 'gamebar'; Group = 'rec'; Default = $true;  Title = 'Game Bar и игровой режим';
       Desc = 'Отключает запись игр, Game Bar и автоматический игровой режим.';
       Run = { Invoke-Tweak-GameBar } },
    @{ Id = 'fse';     Group = 'rec'; Default = $true;  Title = 'Полноэкранный режим: FSE (эксклюзивный)';
       Desc = 'Отключает полноэкранные оптимизации. Взаимоисключается с FSO ниже.';
       Run = { Invoke-Tweak-Fse } },
    @{ Id = 'devpow';  Group = 'rec'; Default = $true;  Title = 'Энергосбережение всех устройств';
       Desc = 'Запрещает отключать устройства для экономии энергии и будить ПК. Откроет окно с отчётом. Не откатывается кнопкой отката.';
       Run = { Invoke-Tweak-DevicePower } },
    @{ Id = 'fso';     Group = 'opt'; Default = $false; Title = 'Полноэкранный режим: FSO (оптимизации включены)';
       Desc = 'Вариант вместо FSE. Включайте только один из двух.';
       Run = { Invoke-Tweak-Fso } },
    @{ Id = 'nvidia';  Group = 'opt'; Default = $false; Title = 'Профиль NVIDIA (XEOKA-OPTIMIZED-V2.nip)';
       Desc = 'Импорт через Nvidia Profile Inspector. Только для видеокарт NVIDIA. Не откатывается кнопкой отката.';
       Run = { Invoke-Tweak-Nvidia } }
)

# ---------------------------------------------------------------- откат
function Invoke-Revert {
    $files = @(Get-ChildItem -Path $script:DataDir -Filter 'run-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) { Write-Log 'Нет сохранённых изменений для отката.' 'warn'; return }
    $f = $files[0]
    $st = Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Log ("Откат изменений от " + $st.Time) 'head'
    $ops = @($st.Ops)
    [array]::Reverse($ops)
    $n = 0
    foreach ($o in $ops) {
        try { Restore-RegOp $o; $n++ } catch { Write-Log ("  не удалось восстановить " + $o.Name + ": " + $_.Exception.Message) 'warn' }
    }
    Write-Log "  восстановлено параметров реестра: $n" 'ok'
    if ($st.Offload) {
        try { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing $st.Offload.Rsc -PacketCoalescingFilter $st.Offload.Pcf; Write-Log '  параметры offload восстановлены' 'ok' }
        catch { Write-Log ('  offload: ' + $_.Exception.Message) 'warn' }
    }
    if ($st.PowerPrev) {
        & powercfg /setactive $st.PowerPrev | Out-Null
        if ($st.PowerNew) { & powercfg /delete $st.PowerNew | Out-Null }
        Write-Log '  схема питания возвращена' 'ok'
    }
    Rename-Item -Path $f.FullName -NewName ($f.Name + '.reverted') -Force
    Write-Log 'Готово. Перезагрузите компьютер.' 'ok'
}

# ================================================================ интерфейс
$cBg      = [System.Drawing.ColorTranslator]::FromHtml('#0D1017')
$cPanel   = [System.Drawing.ColorTranslator]::FromHtml('#151A23')
$cPanel2  = [System.Drawing.ColorTranslator]::FromHtml('#1B2230')
$cLine    = [System.Drawing.ColorTranslator]::FromHtml('#252D3D')
$cText    = [System.Drawing.ColorTranslator]::FromHtml('#E8ECF4')
$cDim     = [System.Drawing.ColorTranslator]::FromHtml('#8B95A8')
$cAccent  = [System.Drawing.ColorTranslator]::FromHtml('#7C5CFF')
$cAccent2 = [System.Drawing.ColorTranslator]::FromHtml('#9A82FF')
$cOk      = [System.Drawing.ColorTranslator]::FromHtml('#3DDC97')
$cWarn    = [System.Drawing.ColorTranslator]::FromHtml('#FFB547')
$cErr     = [System.Drawing.ColorTranslator]::FromHtml('#FF5C6C')

$fontUi    = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$fontSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Black', 24)
$fontBtn   = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$fontMono  = New-Object System.Drawing.Font('Consolas', 9.5)

function Set-Round {
    param($Ctrl, [int]$R)
    $w = $Ctrl.Width; $h = $Ctrl.Height
    if ($w -le 0 -or $h -le 0) { return }
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $gp.AddArc(0, 0, $d, $d, 180, 90)
    $gp.AddArc($w - $d, 0, $d, $d, 270, 90)
    $gp.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $gp.AddArc(0, $h - $d, $d, $d, 90, 90)
    $gp.CloseFigure()
    $Ctrl.Region = New-Object System.Drawing.Region($gp)
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, $Back, $Hover, $Font)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Left = $X; $b.Top = $Y; $b.Width = $W; $b.Height = $H
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Back; $b.ForeColor = $cText
    $b.FlatAppearance.MouseOverBackColor = $Hover
    $b.FlatAppearance.MouseDownBackColor = $Back
    $b.Font = $Font; $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    Set-Round $b 10
    return $b
}

function Open-Url {
    param([string]$Url)
    try { Start-Process $Url } catch { [System.Windows.Forms.MessageBox]::Show("Не удалось открыть ссылку: $Url") | Out-Null }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'XEOKA PACK'
$form.ClientSize = New-Object System.Drawing.Size(960, 680)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'None'
$form.MaximizeBox = $false
$form.BackColor = $cBg
$form.Opacity = 0
$form.ForeColor = $cText
$form.Font = $fontUi

# ---- шапка
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 960, 96); $header.BackColor = $cPanel
$form.Controls.Add($header)

$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Text = 'XEOKA'; $lblLogo.Font = $fontTitle; $lblLogo.AutoSize = $true
$lblLogo.ForeColor = $cText; $lblLogo.Location = New-Object System.Drawing.Point(28, 10)
$header.Controls.Add($lblLogo)
$lblLogo2 = New-Object System.Windows.Forms.Label
$lblLogo2.Text = 'PACK'; $lblLogo2.Font = $fontTitle; $lblLogo2.AutoSize = $true
$lblLogo2.ForeColor = $cAccent2
$lblLogo2.Location = New-Object System.Drawing.Point(($lblLogo.PreferredWidth + 22), 10)
$header.Controls.Add($lblLogo2)
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = ('Оптимизация Windows одной кнопкой   |   v' + $script:Version)
$lblSub.Font = $fontSmall; $lblSub.ForeColor = $cDim; $lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(32, 62)
$header.Controls.Add($lblSub)

$lnkTg = New-Object System.Windows.Forms.LinkLabel
$lnkTg.Text = ('Telegram: ' + $script:TgLabel)
$lnkTg.Font = $fontBold; $lnkTg.AutoSize = $true
$lnkTg.LinkColor = $cAccent2; $lnkTg.ActiveLinkColor = $cText; $lnkTg.VisitedLinkColor = $cAccent2
$lnkTg.LinkBehavior = 'HoverUnderline'; $lnkTg.BackColor = $cPanel
$lnkTg.Location = New-Object System.Drawing.Point(($header.Width - $lnkTg.PreferredWidth - 32), 50)
$lnkTg.Cursor = [System.Windows.Forms.Cursors]::Hand
$lnkTg.Add_LinkClicked({ Open-Url $script:TgUrl })
$header.Controls.Add($lnkTg)

function New-WinButton {
    param([string]$Text, [int]$X, $HoverColor)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.SetBounds($X, 0, 46, 34)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $cPanel; $b.ForeColor = $cDim; $b.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 10)
    $b.FlatAppearance.MouseOverBackColor = $HoverColor; $b.FlatAppearance.MouseDownBackColor = $HoverColor
    $b.UseVisualStyleBackColor = $false; $b.TabStop = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_MouseEnter({ $this.ForeColor = $cText }); $b.Add_MouseLeave({ $this.ForeColor = $cDim })
    return $b
}
$btnMin = New-WinButton ([string][char]0x2014) 868 $cPanel2
$btnMin.Add_Click({ $form.WindowState = 'Minimized' })
$btnClose = New-WinButton ([string][char]0x2715) 914 $cErr
$btnClose.Add_Click({ $form.Close() })
$header.Controls.Add($btnMin); $header.Controls.Add($btnClose)

$script:Drag = $null; $script:DragOrigin = $null
$dragDown = { $script:Drag = [System.Windows.Forms.Control]::MousePosition; $script:DragOrigin = $form.Location }
$dragMove = {
    if ($script:Drag -and ([System.Windows.Forms.Control]::MouseButtons -eq 'Left')) {
        $mp = [System.Windows.Forms.Control]::MousePosition
        $form.Location = New-Object System.Drawing.Point(($script:DragOrigin.X + $mp.X - $script:Drag.X), ($script:DragOrigin.Y + $mp.Y - $script:Drag.Y))
    }
}
$dragUp = { $script:Drag = $null }
foreach ($dc in @($header, $lblLogo, $lblLogo2, $lblSub)) { $dc.Add_MouseDown($dragDown); $dc.Add_MouseMove($dragMove); $dc.Add_MouseUp($dragUp) }

# ---- навигация
$nav = New-Object System.Windows.Forms.Panel
$nav.SetBounds(0, 96, 190, 584); $nav.BackColor = $cPanel
$form.Controls.Add($nav)

$pages = @{}
$navButtons = @{}
function Show-Page {
    param([string]$Name)
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $Name) }
    if ($pages[$Name] -and $form.Visible) { $pages[$Name].Left = 190 + 44; $script:Slide = $pages[$Name] }
    foreach ($k in $navButtons.Keys) {
        if ($k -eq $Name) { $navButtons[$k].BackColor = $cPanel2; $navButtons[$k].ForeColor = $cText }
        else { $navButtons[$k].BackColor = $cPanel; $navButtons[$k].ForeColor = $cDim }
    }
}
function Add-NavButton {
    param([string]$Key, [string]$Text, [int]$Top)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ('   ' + $Text); $b.TextAlign = 'MiddleLeft'
    $b.SetBounds(12, $Top, 166, 44)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $cPanel2; $b.FlatAppearance.MouseDownBackColor = $cPanel2
    $b.BackColor = $cPanel; $b.ForeColor = $cDim; $b.Font = $fontBold
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $Key
    $b.Add_Click({ Show-Page $this.Tag })
    Set-Round $b 8
    $nav.Controls.Add($b)
    $navButtons[$Key] = $b
}
Add-NavButton 'opt'   'Оптимизация' 18
Add-NavButton 'tools' 'Инструменты' 68
Add-NavButton 'about' 'О программе' 118

$lblNavNote = New-Object System.Windows.Forms.Label
$lblNavNote.Text = "Перед применением создаётся`nточка восстановления.`nИзменения можно откатить."
$lblNavNote.ForeColor = $cDim; $lblNavNote.Font = $fontSmall
$lblNavNote.SetBounds(16, 500, 170, 60)
$nav.Controls.Add($lblNavNote)

# ---- страница: оптимизация
$pageOpt = New-Object System.Windows.Forms.Panel
$pageOpt.SetBounds(190, 96, 770, 584); $pageOpt.BackColor = $cBg
$form.Controls.Add($pageOpt); $pages['opt'] = $pageOpt

$lblH1 = New-Object System.Windows.Forms.Label
$lblH1.Text = 'Что применить'; $lblH1.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$lblH1.AutoSize = $true; $lblH1.Location = New-Object System.Drawing.Point(22, 14)
$pageOpt.Controls.Add($lblH1)

$list = New-Object System.Windows.Forms.Panel
$list.SetBounds(16, 54, 738, 330); $list.BackColor = $cBg; $list.AutoScroll = $true
$pageOpt.Controls.Add($list)

$script:Rows = @{}
$y = 0
function Add-GroupLabel {
    param([string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Font = $fontSmall; $l.ForeColor = $cDim; $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(6, ($script:y + 4))
    $list.Controls.Add($l)
    $script:y += 28
}
function Add-TweakRow {
    param($Tw)
    $row = New-Object System.Windows.Forms.Panel
    $row.SetBounds(0, $script:y, 716, 76); $row.BackColor = $cPanel; $row.Tag = @{ T = 0.0; Target = 0 }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = ''; $cb.AutoSize = $false; $cb.Size = New-Object System.Drawing.Size(24, 24)
    $cb.Location = New-Object System.Drawing.Point(14, 26); $cb.Checked = [bool]$Tw.Default
    $cb.FlatStyle = 'Standard'; $cb.BackColor = [System.Drawing.Color]::Transparent
    $row.Controls.Add($cb)
    $lt = New-Object System.Windows.Forms.Label
    $lt.Text = $Tw.Title; $lt.Font = $fontBold; $lt.AutoSize = $false
    $lt.SetBounds(48, 8, 650, 22); $lt.ForeColor = $cText; $lt.BackColor = [System.Drawing.Color]::Transparent
    $row.Controls.Add($lt)
    $ld = New-Object System.Windows.Forms.Label
    $ld.Text = $Tw.Desc; $ld.Font = $fontSmall; $ld.AutoSize = $false
    $ld.SetBounds(48, 31, 650, 40); $ld.ForeColor = $cDim; $ld.BackColor = [System.Drawing.Color]::Transparent
    $row.Controls.Add($ld)
    $toggle = { $cb.Checked = -not $cb.Checked }.GetNewClosure()
    $lt.Add_Click($toggle); $ld.Add_Click($toggle); $row.Add_Click($toggle)
    $row.Add_MouseEnter({ $this.Tag.Target = 1 }); $row.Add_MouseLeave({ $this.Tag.Target = 0 })
    $lt.Add_MouseEnter({ $this.Parent.Tag.Target = 1 }); $ld.Add_MouseEnter({ $this.Parent.Tag.Target = 1 })
    $lt.Cursor = [System.Windows.Forms.Cursors]::Hand; $ld.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-Round $row 8
    $list.Controls.Add($row)
    $script:Rows[$Tw.Id] = $cb
    $script:y += 82
}
Add-GroupLabel 'РЕКОМЕНДУЕМЫЕ'
foreach ($t in $script:Tweaks) { if ($t.Group -eq 'rec') { Add-TweakRow $t } }
Add-GroupLabel 'ДОПОЛНИТЕЛЬНЫЕ'
foreach ($t in $script:Tweaks) { if ($t.Group -eq 'opt') { Add-TweakRow $t } }

# FSE и FSO нельзя вместе
$script:Rows['fse'].Add_CheckedChanged({ if ($script:Rows['fse'].Checked) { $script:Rows['fso'].Checked = $false } })
$script:Rows['fso'].Add_CheckedChanged({ if ($script:Rows['fso'].Checked) { $script:Rows['fse'].Checked = $false } })

# ---- кнопки и прогресс
$btnApply = New-Button 'ОПТИМИЗИРОВАТЬ' 22 396 330 54 $cAccent $cAccent2 $fontBtn
$pageOpt.Controls.Add($btnApply)
$btnRevert = New-Button 'Откатить последнее' 362 396 200 54 $cPanel2 $cLine $fontBold
$pageOpt.Controls.Add($btnRevert)
$btnAll = New-Button 'Все / никакие' 572 396 182 54 $cPanel2 $cLine $fontBold
$pageOpt.Controls.Add($btnAll)

$barBack = New-Object System.Windows.Forms.Panel
$barBack.SetBounds(22, 462, 732, 8); $barBack.BackColor = $cPanel2; $barBack.Visible = $false
$pageOpt.Controls.Add($barBack)
$barFill = New-Object System.Windows.Forms.Panel
$barFill.SetBounds(0, 0, 0, 8); $barFill.BackColor = $cAccent
$barBack.Controls.Add($barFill)
Set-Round $barBack 4

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.SetBounds(22, 482, 732, 88)
$logBox.BackColor = $cPanel; $logBox.ForeColor = $cText; $logBox.Font = $fontMono
$logBox.ReadOnly = $true; $logBox.BorderStyle = 'None'; $logBox.ScrollBars = 'Vertical'
$pageOpt.Controls.Add($logBox)

$script:LogFile = Join-Path $script:DataDir ('log-' + (Get-Date -Format 'yyyyMMdd') + '.txt')
function Write-Log {
    param([string]$Text, [string]$Level = 'info')
    $color = $cText
    switch ($Level) {
        'ok'   { $color = $cOk }
        'warn' { $color = $cWarn }
        'err'  { $color = $cErr }
        'dim'  { $color = $cDim }
        'head' { $color = $cAccent2 }
    }
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionColor = $color
    $logBox.AppendText($Text + "`r`n")
    $logBox.ScrollToCaret()
    try { Add-Content -Path $script:LogFile -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $Text) -Encoding UTF8 } catch { }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Progress {
    param([double]$Fraction)
    $barFill.Width = [int]($barBack.Width * [Math]::Max(0, [Math]::Min(1, $Fraction)))
    [System.Windows.Forms.Application]::DoEvents()
}

$script:Busy = $false
function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    $btnApply.Enabled = -not $On; $btnRevert.Enabled = -not $On; $btnAll.Enabled = -not $On
    if ($On) { $btnApply.Text = 'ПРИМЕНЯЮ...' } else { $btnApply.Text = 'ОПТИМИЗИРОВАТЬ' }
}

$btnAll.Add_Click({
    $any = $false
    foreach ($k in $script:Rows.Keys) { if ($script:Rows[$k].Checked) { $any = $true } }
    foreach ($t in $script:Tweaks) { $script:Rows[$t.Id].Checked = (-not $any) -and [bool]$t.Default }
})

$btnApply.Add_Click({
    if ($script:Busy) { return }
    $sel = @($script:Tweaks | Where-Object { $script:Rows[$_.Id].Checked })
    if ($sel.Count -eq 0) { Write-Log 'Ничего не выбрано.' 'warn'; return }
    $msg = "Будет применено твиков: $($sel.Count).`n`nПеред этим создаётся точка восстановления. Изменения реестра можно откатить кнопкой «Откатить последнее».`n`nПродолжить?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'XEOKA PACK', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    $logBox.Clear(); $barBack.Visible = $true; Set-Progress 0
    try {
        New-RunState
        Write-Log 'Создаю точку восстановления...' 'head'
        try {
            Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description 'XEOKA Pack' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Log '  точка восстановления создана' 'ok'
        } catch {
            Write-Log ('  точку создать не удалось (' + $_.Exception.Message.Split("`n")[0] + '). Продолжаю, откат реестра доступен.') 'warn'
        }
        $i = 0; $okCount = 0; $failCount = 0
        foreach ($t in $sel) {
            Write-Log ('> ' + $t.Title) 'head'
            try { & $t.Run; Write-Log '  готово' 'ok'; $okCount++ }
            catch { Write-Log ('  ошибка: ' + $_.Exception.Message) 'err'; $failCount++ }
            $i++; Set-Progress ($i / $sel.Count)
        }
        $stFile = Join-Path $script:DataDir ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
        ($script:RunState | ConvertTo-Json -Depth 6) | Out-File -FilePath $stFile -Encoding UTF8
        Write-Log ("Итог: успешно $okCount, с ошибками $failCount.") 'head'
        $m = "Готово: успешно $okCount, с ошибками $failCount.`n`nДля применения всех изменений нужна перезагрузка. Перезагрузить сейчас?"
        $rr = [System.Windows.Forms.MessageBox]::Show($m, 'XEOKA PACK', 'YesNo', 'Information')
        if ($rr -eq 'Yes') { Start-Process shutdown.exe -ArgumentList '/r /t 5 /c "XEOKA PACK"' -WindowStyle Hidden }
    } catch {
        Write-Log ('Критическая ошибка: ' + $_.Exception.Message) 'err'
    } finally { Set-Busy $false; $barBack.Visible = $false }
})

$btnRevert.Add_Click({
    if ($script:Busy) { return }
    $r = [System.Windows.Forms.MessageBox]::Show('Вернуть значения реестра, схему питания и параметры сети к состоянию до последнего применения?', 'XEOKA PACK', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    try { Invoke-Revert } catch { Write-Log ('Ошибка отката: ' + $_.Exception.Message) 'err' } finally { Set-Busy $false }
})

# ---- анимации
function Mix-Color {
    param($A, $B, [double]$K)
    $r = [int]($A.R + ($B.R - $A.R) * $K); $g = [int]($A.G + ($B.G - $A.G) * $K); $bl = [int]($A.B + ($B.B - $A.B) * $K)
    return [System.Drawing.Color]::FromArgb($r, $g, $bl)
}
$cRowHover = [System.Drawing.ColorTranslator]::FromHtml('#212A3B')
$cCyan = [System.Drawing.ColorTranslator]::FromHtml('#5CD6FF')
$script:Phase = 0.0
$script:Slide = $null
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 30
$animTimer.Add_Tick({
    $script:Phase += 0.06
    $k = ([Math]::Sin($script:Phase) + 1) / 2
    if ($form.Opacity -lt 1) { $form.Opacity = [Math]::Min(1.0, $form.Opacity + 0.09) }
    if ($btnApply.Enabled) { $btnApply.BackColor = Mix-Color $cAccent $cAccent2 $k }
    $lblLogo2.ForeColor = Mix-Color $cAccent2 $cCyan ($k * 0.7)
    $lnkTg.LinkColor = Mix-Color $cAccent2 $cText ($k * 0.35)
    foreach ($rp in @($list.Controls | Where-Object { $_.Tag -is [hashtable] })) {
        $st = $rp.Tag
        $tgt = [double]$st.Target
        if ([Math]::Abs($st.T - $tgt) -gt 0.001) {
            if ($st.T -lt $tgt) { $st.T = [Math]::Min($tgt, $st.T + 0.18) } else { $st.T = [Math]::Max($tgt, $st.T - 0.18) }
            $rp.BackColor = Mix-Color $cPanel $cRowHover $st.T
        }
    }
    if ($script:Slide) {
        $dx = $script:Slide.Left - 190
        if ($dx -le 1) { $script:Slide.Left = 190; $script:Slide = $null }
        else { $script:Slide.Left = 190 + [int]($dx * 0.62) }
    }
})
$form.Add_FormClosed({ $animTimer.Stop() })

# ---- страница: инструменты
$pageTools = New-Object System.Windows.Forms.Panel
$pageTools.SetBounds(190, 96, 770, 584); $pageTools.BackColor = $cBg; $pageTools.Visible = $false
$form.Controls.Add($pageTools); $pages['tools'] = $pageTools

$lblT = New-Object System.Windows.Forms.Label
$lblT.Text = 'Инструменты пака'; $lblT.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$lblT.AutoSize = $true; $lblT.Location = New-Object System.Drawing.Point(22, 14)
$pageTools.Controls.Add($lblT)
$lblT2 = New-Object System.Windows.Forms.Label
$lblT2.Text = 'Запускаются отдельно. Это то, что нельзя безопасно применить одной кнопкой.'
$lblT2.Font = $fontSmall; $lblT2.ForeColor = $cDim; $lblT2.AutoSize = $true
$lblT2.Location = New-Object System.Drawing.Point(24, 46)
$pageTools.Controls.Add($lblT2)

$tools = @(
    @{ T = 'Windows Defender'; D = 'Переключатель защитника'; P = '6.'; F = 'RUN-WDS.bat' },
    @{ T = 'Обновления Windows'; D = 'Блокировщик обновлений'; P = '7.'; F = 'RUN-WUB.bat' },
    @{ T = 'DEVICE-TWEAKER'; D = 'Аффинити, прерывания, USB'; P = '13.'; F = 'RUN-DEVICE-TWEAKER.bat' },
    @{ T = 'BIOS (SCEWIN)'; D = 'Конфиги BIOS. Читайте инструкцию'; P = '12.'; F = 'SCEWIN-GUI.exe' },
    @{ T = 'Тип драйвера сети'; D = 'NDIS или NetAdapterCx'; P = '15.'; F = 'RUN-CHECK-NIC-DRIVER-TYPE.PS1.bat' },
    @{ T = 'Энергосбережение сети'; D = 'Проверка статуса'; P = '9.'; F = 'RUN-CHECK-POWER-MANAGEMENT.bat' },
    @{ T = 'DDU'; D = 'Удаление драйверов видеокарты'; P = '2.'; F = 'Display Driver Uninstaller.exe' },
    @{ T = 'NVCleanstall'; D = 'Установка драйвера NVIDIA'; P = '2.'; F = 'NVCleanstall_1.19.0.exe' },
    @{ T = 'Profile Inspector'; D = 'Профили NVIDIA'; P = '2.'; F = 'nvidiaProfileInspector.exe' },
    @{ T = 'CRU'; D = 'Настройка разрешений и частот'; P = '3.'; F = 'CRU.exe' },
    @{ T = 'Autoruns'; D = 'Автозагрузка'; P = '8.'; F = 'Autoruns.exe' },
    @{ T = 'Службы (PowerRun)'; D = 'Отключение служб. Осторожно'; P = '10.'; F = 'DISABLE-SERVICES.reg' }
)
$tx = 22; $ty = 78; $col = 0
foreach ($tool in $tools) {
    $path = Find-PackFile $tool.P $tool.F
    $b = New-Button ($tool.T + "`n" + $tool.D) ($tx + $col * 370) $ty 360 54 $cPanel $cPanel2 $fontSmall
    $b.TextAlign = 'MiddleLeft'; $b.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $b.Tag = @{ Path = $path; Name = $tool.T; File = $tool.F }
    if (-not $path) { $b.Enabled = $false; $b.ForeColor = $cDim; $b.Text = ($tool.T + "`nфайл не найден в паке") }
    $b.Add_Click({
        $info = $this.Tag
        $p = $info.Path
        try {
            if ($info.File -eq 'DISABLE-SERVICES.reg') {
                $warn = "Будут отключены службы: DPS, Themes, Spooler (печать), WSearch (поиск), LanmanWorkstation и Netlogon (сетевые папки, домен), SessionEnv (удалённый рабочий стол), edgeupdate, GameInputSvc и другие.`n`nОтключение Themes может испортить внешний вид Windows, без Spooler не будет печати. Откат кнопкой отката не поддерживается.`n`nПродолжить?"
                $r = [System.Windows.Forms.MessageBox]::Show($warn, 'Службы', 'YesNo', 'Warning')
                if ($r -ne 'Yes') { return }
                $pr = Find-PackFile '10.' 'PowerRun_x64.exe'
                if (-not $pr) { [System.Windows.Forms.MessageBox]::Show('PowerRun_x64.exe не найден.') | Out-Null; return }
                Start-Process -FilePath $pr -ArgumentList ('regedit.exe /s "{0}"' -f $p) -WorkingDirectory (Split-Path $pr)
                return
            }
            Start-Process -FilePath $p -WorkingDirectory (Split-Path $p)
        } catch { [System.Windows.Forms.MessageBox]::Show("Не удалось запустить: $($_.Exception.Message)") | Out-Null }
    })
    $pageTools.Controls.Add($b)
    $col++; if ($col -ge 2) { $col = 0; $ty += 62 }
}
$btnFolder = New-Button 'Открыть папку пака' 22 ($ty + 14) 220 42 $cPanel2 $cLine $fontBold
$btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $script:Root + '"') })
if ($col -ne 0) { $btnFolder.Top = $ty + 76 }
$pageTools.Controls.Add($btnFolder)

# ---- страница: о программе
$pageAbout = New-Object System.Windows.Forms.Panel
$pageAbout.SetBounds(190, 96, 770, 584); $pageAbout.BackColor = $cBg; $pageAbout.Visible = $false
$form.Controls.Add($pageAbout); $pages['about'] = $pageAbout

$lblA = New-Object System.Windows.Forms.Label
$lblA.Text = 'О программе'; $lblA.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$lblA.AutoSize = $true; $lblA.Location = New-Object System.Drawing.Point(22, 14)
$pageAbout.Controls.Add($lblA)
$lblA2 = New-Object System.Windows.Forms.Label
$lblA2.Font = $fontUi; $lblA2.ForeColor = $cText; $lblA2.AutoSize = $false
$lblA2.SetBounds(24, 56, 710, 330)
$lblA2.Text = @"
XEOKA PACK собирает в одном окне твики из пака: питание, приоритеты процессов, таймер, MMCSS, сеть, игровые функции и энергосбережение устройств.

Как это работает
  - Перед применением создаётся точка восстановления.
  - Каждое изменение реестра запоминается. Кнопка «Откатить последнее» возвращает прежние значения.
  - Всё, что опасно применять вслепую (Defender, обновления, службы, BIOS), вынесено на вкладку «Инструменты» и запускается отдельно.

Что нужно знать
  - Часть настроек меняет поведение системы: после применения перезагрузитесь и проверьте игры и устройства.
  - Профиль NVIDIA и энергосбережение устройств кнопкой отката не возвращаются.
  - Используйте на свой риск. Автор не отвечает за последствия.
"@
$pageAbout.Controls.Add($lblA2)
$lnkTg2 = New-Object System.Windows.Forms.LinkLabel
$lnkTg2.Text = ('Автор и поддержка в Telegram: ' + $script:TgLabel)
$lnkTg2.Font = $fontBold; $lnkTg2.AutoSize = $true
$lnkTg2.LinkColor = $cAccent2; $lnkTg2.ActiveLinkColor = $cText; $lnkTg2.VisitedLinkColor = $cAccent2
$lnkTg2.Location = New-Object System.Drawing.Point(24, 400)
$lnkTg2.Cursor = [System.Windows.Forms.Cursors]::Hand
$lnkTg2.Add_LinkClicked({ Open-Url $script:TgUrl })
$pageAbout.Controls.Add($lnkTg2)

Show-Page 'opt'
Write-Log 'Выберите твики и нажмите «ОПТИМИЗИРОВАТЬ».' 'dim'
$animTimer.Start()
[void]$form.ShowDialog()
