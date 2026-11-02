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

$script:Version  = '2.2'
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

# ---------------------------------------------------------------- поиск пака и файлов
$script:FileCache = @{}

function Test-PackRoot {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $n = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.' }).Count
    return ($n -ge 5)
}

function Find-PackDirs {
    param([string]$Base, [int]$Depth, $Acc, $Sw)
    if ($Depth -le 0 -or $Sw.ElapsedMilliseconds -gt 6000) { return }
    foreach ($d in @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue)) {
        if ($Sw.ElapsedMilliseconds -gt 6000) { return }
        if ($d.Name -match '^\$|^Windows$|^Program|^System Volume|^Recovery|^AppData$|^node_modules$') { continue }
        if ($d.Name -match 'xeoka|pack|llc|optimi') { [void]$Acc.Add($d.FullName) }
        if ($Depth -gt 1) { Find-PackDirs -Base $d.FullName -Depth ($Depth - 1) -Acc $Acc -Sw $Sw }
    }
}

function Resolve-PackRoot {
    param([string]$Start)
    $cands = New-Object System.Collections.ArrayList
    [void]$cands.Add($Start)
    $par = $null
    try { $par = Split-Path -Parent $Start } catch { }
    if ($par) { [void]$cands.Add($par) }
    foreach ($b in @($Start, $par)) {
        if (-not $b) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'xeoka|pack|llc|optimi' })) { [void]$cands.Add($d.FullName) }
    }
    $saved = Join-Path $script:DataDir 'root.txt'
    if (Test-Path $saved) { try { [void]$cands.Add(((Get-Content -Path $saved -Raw -Encoding UTF8).Trim())) } catch { } }
    foreach ($c in $cands) { if (Test-PackRoot $c) { return $c } }
    # широкий поиск: рабочий стол, загрузки, документы, корни дисков
    $bases = New-Object System.Collections.ArrayList
    foreach ($b in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'),
                     (Join-Path $env:USERPROFILE 'Downloads'), $env:USERPROFILE,
                     (Join-Path $env:USERPROFILE 'OneDrive\Desktop'))) { if ($b -and (Test-Path $b)) { [void]$bases.Add($b) } }
    foreach ($dr in @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) { [void]$bases.Add($dr.RootDirectory.FullName) }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $found = New-Object System.Collections.ArrayList
    foreach ($b in $bases) { Find-PackDirs -Base $b -Depth 3 -Acc $found -Sw $sw }
    foreach ($c in $found) { if (Test-PackRoot $c) { return $c } }
    return $Start
}
$script:Root = Resolve-PackRoot $script:Root

function Find-PackFile {
    param([string]$FolderPrefix, [string]$FileName)
    $key = $script:Root + '|' + $FolderPrefix + '|' + $FileName
    if ($script:FileCache.ContainsKey($key) -and $script:FileCache[$key] -and (Test-Path -LiteralPath $script:FileCache[$key])) { return $script:FileCache[$key] }
    $res = $null
    $dirs = @(Get-ChildItem -LiteralPath $script:Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$FolderPrefix*" })
    foreach ($d in $dirs) {
        $hit = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $res = $hit.FullName; break }
    }
    if (-not $res) {
        $hit = Get-ChildItem -LiteralPath $script:Root -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { $res = $hit.FullName }
    }
    $script:FileCache[$key] = $res
    return $res
}

# ---------------------------------------------------------------- реестр: разбор .reg, запись, журнал
function Read-RegText {
    param([string]$Text)
    $ops = New-Object System.Collections.ArrayList
    $hive = $null; $sub = $null
    foreach ($raw in ($Text -split "`r?`n")) {
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

function Read-RegFile {
    param([string]$Path)
    $sr = New-Object System.IO.StreamReader($Path, $true)
    try { $text = $sr.ReadToEnd() } finally { $sr.Close() }
    return ,(Read-RegText -Text $text)
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

function Invoke-RegOps {
    param($Ops, [string]$NetSubKey)
    $done = 0
    foreach ($op in $Ops) {
        if ($op.Kind -eq 'Unsupported') { Write-Log ("  пропущено (тип значения не поддерживается): " + $op.Name) 'warn'; continue }
        if ($NetSubKey) {
            $op.Sub = [regex]::Replace($op.Sub, '(?i)(Control\\Class\\\{4D36E972-E325-11CE-BFC1-08002BE10318\})\\\d{4}$', ('$1\' + $NetSubKey))
        }
        try { Write-RegOp -Op $op; $done++ }
        catch { Write-Log ("  ошибка записи " + $op.Name + ": " + $_.Exception.Message) 'warn' }
    }
    Write-Log ("  записано параметров: $done из $($Ops.Count)") 'dim'
}

# .reg из пака; если файла нет (другая версия пака), берётся встроенная копия
$script:Embedded = @{
'Win32PrioritySeparation-18.reg' = @'
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl]
"Win32PrioritySeparation"=dword:00000018
'@
'SerializeTimerExpiration-1.reg' = @'
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel]
"SerializeTimerExpiration"=dword:00000001
'@
'FSE.reg' = @'
[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000001
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000002
"GameDVR_FSEBehavior"=dword:00000002
"GameDVR_DSEBehavior"=dword:00000002
'@
'FSO.reg' = @'
[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000000
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehavior"=dword:00000000
"GameDVR_DSEBehavior"=dword:00000000
'@
'DISABLE-MMCSS.reg' = @'
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MMCSS]
"Start"=dword:00000004
'@
'XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg' = @'
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile]
"NoLazyMode"=dword:00000000
"NetworkThrottlingIndex"=dword:0000000a
"LazyModeTimeout"=dword:ffffffff
"SchedulerPeriod"=dword:000f4240
"IdleDetectionCycles"=dword:00000001
"SchedulerTimerResolution"=dword:00002710

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio]
"Priority"=dword:00000001
"Scheduling Category"="Medium"
"Priority When Yielded"=dword:00000010

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio]
"Priority"=dword:00000001
"Scheduling Category"="Medium"
"Priority When Yielded"=dword:00000010

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Playback]
"Priority"=dword:00000001
"Scheduling Category"="Medium"
"Priority When Yielded"=dword:00000010
'@
}

function Invoke-PackReg {
    param([string]$Prefix, [string]$Name, [string]$NetSubKey)
    $p = Find-PackFile $Prefix $Name
    if ($p) {
        $ops = Read-RegFile -Path $p
    } elseif ($script:Embedded.ContainsKey($Name)) {
        Write-Log ("  файл $Name не найден, использую встроенную копию") 'dim'
        $ops = Read-RegText -Text $script:Embedded[$Name]
    } else {
        throw "Файл $Name не найден в паке."
    }
    Invoke-RegOps -Ops $ops -NetSubKey $NetSubKey
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

# ---------------------------------------------------------------- питание
function Invoke-Powercfg {
    param([string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& powercfg @Arguments 2>&1 | ForEach-Object { [string]$_ }) -join "`n"; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = $out }
}

function Get-GuidFromText {
    param([string]$Text)
    if ($Text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1] }
    return $null
}

function New-BuiltinPowerPlan {
    # Запасной вариант: свой план на базе "Максимальная производительность" / "Высокая производительность"
    $src = @('e9a42b02-d5df-448d-aa00-03f14749eb61', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')
    $guid = $null
    foreach ($s in $src) {
        $r = Invoke-Powercfg @('-duplicatescheme', $s)
        $g = Get-GuidFromText $r.Out
        if ($r.Code -eq 0 -and $g) { $guid = $g; break }
    }
    if (-not $guid) { throw 'Не удалось создать схему питания.' }
    [void](Invoke-Powercfg @('-changename', $guid, 'XEOKA Performance', 'План питания XEOKA PACK'))
    $sets = @(
        @('54533251-82be-4824-96c1-47b60b740d00', '893dee8e-2bef-41e0-89c6-b55d0929964c', 100),  # мин. состояние процессора
        @('54533251-82be-4824-96c1-47b60b740d00', 'bc5038f7-23e0-4960-96da-33abaf5935ec', 100),  # макс. состояние процессора
        @('54533251-82be-4824-96c1-47b60b740d00', '0cc5b647-c1df-4637-891a-dec35c318583', 100),  # парковка ядер: мин. число ядер
        @('54533251-82be-4824-96c1-47b60b740d00', 'be337238-0d82-4146-a960-4f3749d470c7', 2),    # режим буста: агрессивный
        @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0),    # USB selective suspend: выкл
        @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0),    # PCIe ASPM: выкл
        @('0012ee47-9041-4b5d-9b77-535fba8b1442', '6738e2c4-e8a5-4a42-b16a-e040e769756e', 0),    # отключение диска: никогда
        @('19cbb8fa-5279-450e-9fac-8a3d5fedd0c1', '12bbebe6-58d6-4636-95bb-3217ef867c1a', 0)     # Wi-Fi: максимальная производительность
    )
    foreach ($x in $sets) {
        [void](Invoke-Powercfg @('-setacvalueindex', $guid, $x[0], $x[1], [string]$x[2]))
        [void](Invoke-Powercfg @('-setdcvalueindex', $guid, $x[0], $x[1], [string]$x[2]))
    }
    return $guid
}

# ---------------------------------------------------------------- твики
function Invoke-Tweak-Power {
    $cur = Invoke-Powercfg @('/getactivescheme')
    $script:RunState.PowerPrev = Get-GuidFromText $cur.Out
    $guid = $null
    $pow = Find-PackFile '4.' 'xeoka.pow'
    if ($pow) {
        $r = Invoke-Powercfg @('/import', $pow)
        $guid = Get-GuidFromText $r.Out
        if ($r.Code -ne 0 -or -not $guid) {
            Write-Log '  xeoka.pow не открывается (файл повреждён). Создаю схему XEOKA Performance встроенным способом' 'warn'
            $guid = $null
        }
    } else {
        Write-Log '  xeoka.pow не найден. Создаю схему XEOKA Performance встроенным способом' 'warn'
    }
    if (-not $guid) { $guid = New-BuiltinPowerPlan }
    $r2 = Invoke-Powercfg @('/setactive', $guid)
    if ($r2.Code -ne 0) { throw ('powercfg /setactive: ' + $r2.Out) }
    $script:RunState.PowerNew = $guid
    Write-Log ("  схема питания $guid активирована") 'dim'
}

function Invoke-Tweak-Priority { Invoke-PackReg '17.' 'Win32PrioritySeparation-18.reg' }
function Invoke-Tweak-Timer    { Invoke-PackReg '14.' 'SerializeTimerExpiration-1.reg' }

function Invoke-Tweak-Mmcss {
    $type = 'NDIS'
    $ad = Get-PrimaryAdapter
    if ($ad) {
        $sub = Get-NetClassSubKey $ad
        if ($sub) { $type = Get-NicDriverType $sub }
    }
    Write-Log ("  тип драйвера сетевой карты: $type") 'dim'
    if ($type -eq 'NetAdapterCx') { Invoke-PackReg '15.' 'DISABLE-MMCSS.reg' }
    else { Invoke-PackReg '15.' 'XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg' }
}

function Invoke-Tweak-Network {
    $ad = Get-PrimaryAdapter
    if (-not $ad) { throw 'Не найден активный сетевой адаптер.' }
    if ($ad.PhysicalMediaType -ne '802.3') { throw 'Активное подключение не Ethernet (Wi-Fi пропущен для безопасности).' }
    $sub = Get-NetClassSubKey $ad
    if (-not $sub) { throw 'Не удалось определить ключ реестра адаптера.' }
    Write-Log ("  адаптер: " + $ad.Name + " (" + $ad.InterfaceDescription + "), ключ $sub") 'dim'
    Invoke-PackReg '9.' 'OPTIMIZE-NETWORKING.reg' $sub
    Invoke-PackReg '9.' 'DISABLE-POWERSAVING.reg' $sub
    try {
        $g = Get-NetOffloadGlobalSetting
        $script:RunState.Offload = [ordered]@{ Rsc = [string]$g.ReceiveSegmentCoalescing; Pcf = [string]$g.PacketCoalescingFilter }
        Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -PacketCoalescingFilter Disabled
    } catch { Write-Log ('  Set-NetOffloadGlobalSetting: ' + $_.Exception.Message) 'warn' }
    Write-Log '  изменения вступят в силу после перезагрузки' 'dim'
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

function Invoke-Tweak-Fse { Invoke-PackReg '16.' 'FSE.reg' }
function Invoke-Tweak-Fso { Invoke-PackReg '16.' 'FSO.reg' }

function Invoke-Tweak-Nvidia {
    $npi = Find-PackFile '2.' 'nvidiaProfileInspector.exe'
    $nip = Find-PackFile '2.' 'XEOKA-OPTIMIZED-V2.nip'
    if (-not $nip) { $nip = Find-PackFile '2.' 'LLC-OPTIMIZED-V2.nip' }
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

$script:Tweaks = @(
    @{ Id = 'power';   Group = 'rec'; Default = $true;  Title = 'План питания XEOKA';
       Desc = 'Включает схему питания XEOKA Performance. Прежняя схема запоминается для отката.';
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
        [void](Invoke-Powercfg @('/setactive', $st.PowerPrev))
        if ($st.PowerNew) { [void](Invoke-Powercfg @('/delete', $st.PowerNew)) }
        Write-Log '  схема питания возвращена' 'ok'
    }
    Rename-Item -Path $f.FullName -NewName ($f.Name + '.reverted') -Force
    Write-Log 'Готово. Перезагрузите компьютер.' 'ok'
}

# ================================================================ интерфейс
function C { param([string]$Hex) return [System.Drawing.ColorTranslator]::FromHtml($Hex) }
$cBg       = C '#080511'
$cPanel    = C '#120B22'
$cPanel2   = C '#1A1030'
$cLine     = C '#2E2152'
$cText     = C '#EEE8FF'
$cDim      = C '#9D92BE'
$cAccent   = C '#8B5CF6'
$cAccent2  = C '#A78BFA'
$cMagenta  = C '#C084FC'
$cRowHover = C '#22163F'
$cHeadA    = C '#26124D'
$cHeadB    = C '#080511'
$cNavA     = C '#160B2D'
$cNavB     = C '#07040E'
$cTgA      = C '#46C3FF'
$cTgB      = C '#1E8FD8'
$cPill1    = C '#38197F'
$cPill2    = C '#1A0D3A'
$cAmberA   = C '#FFC15A'
$cAmberB   = C '#F2711C'
$cOk       = C '#3DDC97'
$cWarn     = C '#FFB547'
$cErr      = C '#FF5C6C'
$cWhite    = [System.Drawing.Color]::White
$cClear    = [System.Drawing.Color]::Transparent

$fontUi    = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$fontSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$fontTiny  = New-Object System.Drawing.Font('Segoe UI', 8)
$fontRow   = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$fontDesc  = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fontGroup = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Black', 24)
$fontBtn   = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$fontMono  = New-Object System.Drawing.Font('Consolas', 9.5)
$fontH1    = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$fontHero  = New-Object System.Drawing.Font('Segoe UI Black', 28)
$fontBig   = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$fontGlyph = New-Object System.Drawing.Font('Segoe UI Black', 9)

$tfL    = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix, NoPadding'
$tfLT   = [System.Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, EndEllipsis, NoPrefix, NoPadding'
$tfWrap = [System.Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, NoPrefix, NoPadding'
$tfC    = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, NoPrefix, NoPadding'
$tfMeas = [System.Windows.Forms.TextFormatFlags]'Left, Top, SingleLine, NoPrefix, NoPadding'

$script:Sec = 0.0
$script:PaintErr = $null

# ---------------------------------------------------------------- рисование: помощники
function Mix-Color {
    param($A, $B, [double]$K)
    if ($K -lt 0) { $K = 0 } elseif ($K -gt 1) { $K = 1 }
    $r = [int]($A.R + ($B.R - $A.R) * $K); $g = [int]($A.G + ($B.G - $A.G) * $K); $bl = [int]($A.B + ($B.B - $A.B) * $K)
    return [System.Drawing.Color]::FromArgb($r, $g, $bl)
}
function Alpha-Color {
    param($Col, [double]$A)
    $a = [int][Math]::Max(0, [Math]::Min(255, $A))
    return [System.Drawing.Color]::FromArgb($a, $Col.R, $Col.G, $Col.B)
}
function Enable-DoubleBuffer {
    param($Ctrl)
    try {
        $p = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance')
        $p.SetValue($Ctrl, $true, $null)
    } catch { }
}
function New-RoundPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R)
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [single]([Math]::Min($R * 2, [Math]::Min($W, $H)))
    if ($d -le 0.5) {
        $gp.AddRectangle((New-Object System.Drawing.RectangleF($X, $Y, $W, $H)))
        return $gp
    }
    $gp.AddArc($X, $Y, $d, $d, 180, 90)
    $gp.AddArc(($X + $W - $d), $Y, $d, $d, 270, 90)
    $gp.AddArc(($X + $W - $d), ($Y + $H - $d), $d, $d, 0, 90)
    $gp.AddArc($X, ($Y + $H - $d), $d, $d, 90, 90)
    $gp.CloseFigure()
    return $gp
}
function Draw-Round {
    param($G, $Fill, $Line, [double]$LineW, [double]$X, [double]$Y, [double]$W, [double]$H, [double]$R)
    if ($W -lt 1 -or $H -lt 1) { return }
    $p = New-RoundPath $X $Y $W $H $R
    if ($null -ne $Fill) { $b = New-Object System.Drawing.SolidBrush($Fill); $G.FillPath($b, $p); $b.Dispose() }
    if ($null -ne $Line) { $pn = New-Object System.Drawing.Pen($Line, [single]$LineW); $G.DrawPath($pn, $p); $pn.Dispose() }
    $p.Dispose()
}
function Fill-RoundGrad {
    param($G, $C1, $C2, [double]$X, [double]$Y, [double]$W, [double]$H, [double]$R, [double]$Angle)
    if ($W -lt 2 -or $H -lt 2) { return }
    $rect = New-Object System.Drawing.RectangleF([single]$X, [single]$Y, [single]$W, [single]$H)
    $p = New-RoundPath $X $Y $W $H $R
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $C1, $C2, [single]$Angle)
    $G.FillPath($b, $p); $b.Dispose(); $p.Dispose()
}
function Draw-Text {
    param($G, [string]$T, $Font, $Color, [double]$X, [double]$Y, [double]$W, [double]$H, $Flags)
    if ($W -lt 2 -or $H -lt 2) { return }
    $r = New-Object System.Drawing.Rectangle([int]$X, [int]$Y, [int]$W, [int]$H)
    [System.Windows.Forms.TextRenderer]::DrawText($G, $T, $Font, $r, $Color, $Flags)
}
function Measure-W {
    param([string]$T, $Font)
    return [System.Windows.Forms.TextRenderer]::MeasureText($T, $Font, (New-Object System.Drawing.Size(2000, 100)), $tfMeas).Width
}
function Ease-To {
    param([double]$Cur, [double]$Tgt, [double]$K)
    $d = $Tgt - $Cur
    if ([Math]::Abs($d) -lt 0.004) { return $Tgt }
    return $Cur + $d * $K
}
function Open-Url {
    param([string]$Url)
    try { Start-Process $Url } catch { [System.Windows.Forms.MessageBox]::Show("Не удалось открыть ссылку: $Url") | Out-Null }
}

# бумажный самолётик Telegram (координаты в системе 448x512)
$script:PlaneBody = @( @(16,252), @(432,70), @(370,420), @(265,342), @(200,395), @(207,290), @(117,284) )
$script:PlaneFlap = @( @(200,395), @(207,290), @(265,342) )
function Get-PlanePoints {
    param($Pts, [double]$Cx, [double]$Cy, [double]$K)
    $out = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($pt in $Pts) {
        $out.Add((New-Object System.Drawing.PointF([single]($Cx + ($pt[0] - 231) * $K), [single]($Cy + ($pt[1] - 243) * $K))))
    }
    return ,$out.ToArray()
}
function Draw-TgBadge {
    param($G, [double]$Cx, [double]$Cy, [double]$D)
    $brect = New-Object System.Drawing.RectangleF([single]($Cx - $D / 2), [single]($Cy - $D / 2), [single]$D, [single]$D)
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($brect, $cTgA, $cTgB, [single]55)
    $G.FillEllipse($gb, $brect); $gb.Dispose()
    $rp = New-Object System.Drawing.Pen((Alpha-Color $cWhite 80), [single]1)
    $G.DrawEllipse($rp, $brect); $rp.Dispose()
    $k = ($D * 0.52) / 430.0
    $pts = Get-PlanePoints $script:PlaneBody ($Cx - 0.8) ($Cy + 0.4) $k
    $G.FillPolygon([System.Drawing.Brushes]::White, [System.Drawing.PointF[]]$pts)
    $fl = Get-PlanePoints $script:PlaneFlap ($Cx - 0.8) ($Cy + 0.4) $k
    $fb = New-Object System.Drawing.SolidBrush((Mix-Color $cWhite $cTgA 0.38))
    $G.FillPolygon($fb, [System.Drawing.PointF[]]$fl); $fb.Dispose()
}

# ---------------------------------------------------------------- колесо мыши (необязательно)
$script:WheelFilter = $null
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
public class XeokaWheelFilter : IMessageFilter {
    public Control Host1;
    public Action<int> On1;
    public bool PreFilterMessage(ref Message m) {
        if (m.Msg != 0x020A) return false;
        int delta = (short)(((long)m.WParam >> 16) & 0xFFFF);
        Point p = Cursor.Position;
        Control c = Host1;
        if (c == null || c.IsDisposed || !c.IsHandleCreated || !c.Visible) return false;
        if (!c.RectangleToScreen(c.ClientRectangle).Contains(p)) return false;
        if (On1 != null) On1(delta);
        return true;
    }
}
'@
    $script:WheelFilter = New-Object XeokaWheelFilter
} catch { $script:WheelFilter = $null }

# ---------------------------------------------------------------- звук и прокрутка журнала
$script:SndSwipe = $null; $script:SndTick = $null
function New-WavPlayer {
    param([double]$F1, [double]$F2, [double]$Dur, [double]$Vol)
    $rate = 22050; $n = [int]($rate * $Dur)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $n * 2))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
    $bw.Write([int]$rate); $bw.Write([int]($rate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]($n * 2))
    $ph = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / [double]$n
        $f = $F1 + ($F2 - $F1) * $t * $t
        $ph += 2 * [Math]::PI * $f / $rate
        $env = [Math]::Sin([Math]::PI * [Math]::Pow($t, 0.45)) * [Math]::Exp(-2.2 * $t)
        $v = ([Math]::Sin($ph) + 0.35 * [Math]::Sin(2 * $ph) + 0.12 * [Math]::Sin(3 * $ph)) / 1.47
        $bw.Write([int16]($v * $env * $Vol * 32000))
    }
    $bw.Flush(); $ms.Position = 0
    $pl = New-Object System.Media.SoundPlayer($ms)
    $pl.Load()
    return $pl
}
try { $script:SndSwipe = New-WavPlayer 420 980 0.32 0.32 } catch { $script:SndSwipe = $null }
try { $script:SndTick = New-WavPlayer 1180 1500 0.09 0.22 } catch { $script:SndTick = $null }
function Play-Snd {
    param($Pl)
    if ($Pl) { try { $Pl.Play() } catch { } }
}
$script:Win32Ok = $false
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class XeokaNative {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
}
'@
    $script:Win32Ok = $true
} catch { }

# ---------------------------------------------------------------- переливающийся фон
function Paint-Bg {
    param($G, $Ctrl)
    try {
        $o = $Ctrl.PointToScreen([System.Drawing.Point]::Empty)
        $f = $form.PointToScreen([System.Drawing.Point]::Empty)
        $ox = $o.X - $f.X; $oy = $o.Y - $f.Y
        $W = [double]$form.ClientSize.Width; $H = [double]$form.ClientSize.Height
        $t = $script:Sec
        $G.SmoothingMode = 'AntiAlias'
        $G.Clear($cBg)
        $blobs = @(
            @{ X = 0.25 + 0.20 * [Math]::Sin($t * 0.21);       Y = 0.30 + 0.25 * [Math]::Cos($t * 0.17); R = 0.55; C = $cAccent;   A = 46 },
            @{ X = 0.78 + 0.16 * [Math]::Cos($t * 0.19 + 1.0); Y = 0.70 + 0.20 * [Math]::Sin($t * 0.23 + 2.0); R = 0.60; C = $cMagenta;  A = 34 },
            @{ X = 0.55 + 0.30 * [Math]::Sin($t * 0.13 + 3.0); Y = 0.15 + 0.15 * [Math]::Cos($t * 0.29 + 0.5); R = 0.45; C = (C '#5B21B6'); A = 50 }
        )
        foreach ($b in $blobs) {
            $rad = $b.R * [Math]::Max($W, $H)
            $cx = $b.X * $W - $ox; $cy = $b.Y * $H - $oy
            $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
            $gp.AddEllipse([single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2))
            $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($gp)
            $pg.CenterColor = Alpha-Color $b.C $b.A
            $pg.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, $b.C.R, $b.C.G, $b.C.B))
            $G.FillPath($pg, $gp); $pg.Dispose(); $gp.Dispose()
        }
    } catch { $script:PaintErr = $_.Exception.Message }
}

# ---------------------------------------------------------------- окно
$form = New-Object System.Windows.Forms.Form
$form.Text = 'XEOKA PACK'
$form.ClientSize = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(980, 640)
$form.StartPosition = 'Manual'
$form.FormBorderStyle = 'None'
$form.BackColor = $cBg
$form.ForeColor = $cText
$form.Font = $fontUi
$form.Opacity = 0
$form.KeyPreview = $true
Enable-DoubleBuffer $form

$script:LayoutReady = $false
$script:Mode = 'max'
function Set-Mode {
    param([string]$M)
    $scr = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
    $script:Mode = $M
    if ($M -eq 'max') {
        $form.TopMost = $false
        $form.Bounds = $scr.WorkingArea
    } elseif ($M -eq 'full') {
        $form.Bounds = $scr.Bounds
        $form.TopMost = $true
    } else {
        $form.TopMost = $false
        $wa = $scr.WorkingArea
        $w = [Math]::Min(1240, $wa.Width - 80); $h = [Math]::Min(800, $wa.Height - 80)
        $form.Bounds = New-Object System.Drawing.Rectangle(($wa.X + [int](($wa.Width - $w) / 2)), ($wa.Y + [int](($wa.Height - $h) / 2)), $w, $h)
    }
    $header.Invalidate()
}

# ---------------------------------------------------------------- шапка
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 1180, 96); $header.BackColor = $cHeadB
Enable-DoubleBuffer $header
$form.Controls.Add($header)

$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Text = 'XEOKA'; $lblLogo.Font = $fontTitle; $lblLogo.AutoSize = $true
$lblLogo.ForeColor = $cText; $lblLogo.BackColor = $cClear; $lblLogo.Location = New-Object System.Drawing.Point(28, 10)
$header.Controls.Add($lblLogo)
$lblLogo2 = New-Object System.Windows.Forms.Label
$lblLogo2.Text = 'PACK'; $lblLogo2.Font = $fontTitle; $lblLogo2.AutoSize = $true
$lblLogo2.ForeColor = $cAccent2; $lblLogo2.BackColor = $cClear
$lblLogo2.Location = New-Object System.Drawing.Point(($lblLogo.PreferredWidth + 22), 10)
$header.Controls.Add($lblLogo2)
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = ('Оптимизация Windows одной кнопкой   |   v' + $script:Version)
$lblSub.Font = $fontSmall; $lblSub.ForeColor = $cDim; $lblSub.AutoSize = $true; $lblSub.BackColor = $cClear
$lblSub.Location = New-Object System.Drawing.Point(32, 62)
$header.Controls.Add($lblSub)

# кнопки окна (рисуются в шапке)
$script:WinBtn = @( @{ T = 0.0; Target = 0 }, @{ T = 0.0; Target = 0 }, @{ T = 0.0; Target = 0 } )
function Get-WinBtnRect {
    param([int]$I)
    return New-Object System.Drawing.Rectangle(($header.Width - 46 * (3 - $I)), 0, 46, 38)
}

# значок Telegram: кружок со свечением, при наведении раскрывается в капсулу
$script:TgP = 0.0; $script:TgTarget = 0
$script:TgL1 = 'Автор в Telegram'
$script:TgL2 = $script:TgLabel
$script:TgTextW = [Math]::Max((Measure-W $script:TgL1 $fontTiny), (Measure-W $script:TgL2 $fontBold))
function Get-TgRect {
    $e = $script:TgP; $e = $e * $e * (3 - 2 * $e)
    $full = 52 + $script:TgTextW + 34
    $w = 52 + ($full - 52) * $e
    return New-Object System.Drawing.RectangleF([single]($header.Width - 26 - $w), [single]42, [single]$w, [single]50)
}
function Paint-Telegram {
    param($G)
    $r = Get-TgRect
    $p = $script:TgP; $e = $p * $p * (3 - 2 * $p)
    $pulse = ([Math]::Sin($script:Sec * 2.2) + 1) / 2
    $cx = $r.Right - 26; $cy = $r.Y + 25
    for ($i = 3; $i -ge 1; $i--) {
        $a = (12 + 30 * $pulse) * (1 - 0.75 * $e) / $i * 1.5
        $rad = 22 + $i * 3.5 + 1.5 * $pulse
        $pen = New-Object System.Drawing.Pen((Alpha-Color $cAccent2 $a), [single]2)
        $G.DrawEllipse($pen, [single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2))
        $pen.Dispose()
    }
    if ($e -gt 0.01) {
        $path = New-RoundPath $r.X $r.Y $r.Width $r.Height ($r.Height / 2)
        $c1 = Mix-Color $cHeadB $cPill1 $e; $c2 = Mix-Color $cHeadB $cPill2 $e
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $c1, $c2, [single]0)
        $G.FillPath($br, $path); $br.Dispose()
        $pen = New-Object System.Drawing.Pen((Mix-Color $cLine $cAccent2 $e), [single]1.4)
        $G.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
    }
    if ($e -gt 0.5) {
        $a = ($e - 0.5) / 0.5
        $bgc = Mix-Color $cHeadB $cPill1 0.7
        $G.SetClip((New-Object System.Drawing.RectangleF(($r.X + 14), $r.Y, ($r.Width - 14 - 58), $r.Height)))
        Draw-Text $G $script:TgL1 $fontTiny (Mix-Color $bgc $cAccent2 $a) ($r.X + 24) ($r.Y + 9) ($script:TgTextW + 6) 14 $tfL
        Draw-Text $G $script:TgL2 $fontBold (Mix-Color $bgc $cText $a) ($r.X + 24) ($r.Y + 24) ($script:TgTextW + 8) 20 $tfL
        $G.ResetClip()
    }
    Draw-TgBadge $G $cx $cy (38 + 3 * $e)
}

$header.Add_Paint({
    try {
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $rc = $this.ClientRectangle
        if ($rc.Width -le 0 -or $rc.Height -le 0) { return }
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc, $cHeadA, $cHeadB, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillRectangle($br, $rc); $br.Dispose()
        $lineRc = New-Object System.Drawing.Rectangle(0, ($rc.Height - 2), $rc.Width, 2)
        $lb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($lineRc, $cAccent, $cHeadB, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillRectangle($lb, $lineRc); $lb.Dispose()
        for ($i = 0; $i -lt 3; $i++) {
            $r = Get-WinBtnRect $i; $b = $script:WinBtn[$i]
            if ($b.T -gt 0.01) {
                $hc = $cLine; if ($i -eq 2) { $hc = $cErr }
                Draw-Round $g (Alpha-Color $hc (190 * $b.T)) $null 0 ($r.X + 5) ($r.Y + 6) ($r.Width - 10) ($r.Height - 12) 9
            }
            $pen = New-Object System.Drawing.Pen((Mix-Color $cDim $cWhite $b.T), [single]1.4)
            $cx = $r.X + 23; $cy = $r.Y + 19
            if ($i -eq 0) { $g.DrawLine($pen, ($cx - 5), $cy, ($cx + 5), $cy) }
            elseif ($i -eq 1) {
                if ($script:Mode -eq 'win') { $g.DrawRectangle($pen, ($cx - 5), ($cy - 5), 10, 10) }
                else {
                    $g.DrawRectangle($pen, ($cx - 5), ($cy - 2), 8, 8)
                    $g.DrawLine($pen, ($cx - 2), ($cy - 2), ($cx - 2), ($cy - 5))
                    $g.DrawLine($pen, ($cx - 2), ($cy - 5), ($cx + 5), ($cy - 5))
                    $g.DrawLine($pen, ($cx + 5), ($cy - 5), ($cx + 5), ($cy + 2))
                    $g.DrawLine($pen, ($cx + 5), ($cy + 2), ($cx + 3), ($cy + 2))
                }
            } else {
                $g.DrawLine($pen, ($cx - 5), ($cy - 5), ($cx + 5), ($cy + 5))
                $g.DrawLine($pen, ($cx + 5), ($cy - 5), ($cx - 5), ($cy + 5))
            }
            $pen.Dispose()
        }
        Paint-Telegram $g
    } catch { $script:PaintErr = $_.Exception.Message }
})

$script:Closing = $false
$script:Drag = $null; $script:DragOrigin = $null
$headDown = {
    $e = $_
    if ($this -eq $header) {
        for ($i = 0; $i -lt 3; $i++) {
            if ((Get-WinBtnRect $i).Contains($e.Location)) {
                if ($i -eq 0) { $form.WindowState = 'Minimized' }
                elseif ($i -eq 1) { if ($script:Mode -eq 'win') { Set-Mode 'max' } else { Set-Mode 'win' } }
                else { $script:Closing = $true }
                return
            }
        }
        $tr = [System.Drawing.RectangleF]::Inflate((Get-TgRect), 6, 6)
        if ($tr.Contains([single]$e.X, [single]$e.Y)) { Open-Url $script:TgUrl; return }
    }
    if ($script:Mode -eq 'win' -and $e.Button -eq 'Left') {
        $script:Drag = [System.Windows.Forms.Control]::MousePosition; $script:DragOrigin = $form.Location
    }
}
$headMove = {
    $e = $_
    if ($this -eq $header) {
        for ($i = 0; $i -lt 3; $i++) { $script:WinBtn[$i].Target = [int]((Get-WinBtnRect $i).Contains($e.Location)) }
        $tr = [System.Drawing.RectangleF]::Inflate((Get-TgRect), 6, 6)
        $onTg = $tr.Contains([single]$e.X, [single]$e.Y)
        $script:TgTarget = [int]$onTg
        $anyWin = ($script:WinBtn[0].Target + $script:WinBtn[1].Target + $script:WinBtn[2].Target) -gt 0
        if ($onTg -or $anyWin) { $header.Cursor = [System.Windows.Forms.Cursors]::Hand } else { $header.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    if ($script:Drag -and ([System.Windows.Forms.Control]::MouseButtons -eq 'Left')) {
        $mp = [System.Windows.Forms.Control]::MousePosition
        $form.Location = New-Object System.Drawing.Point(($script:DragOrigin.X + $mp.X - $script:Drag.X), ($script:DragOrigin.Y + $mp.Y - $script:Drag.Y))
    }
}
$headUp = { $script:Drag = $null }
$headLeave = {
    if ($this -eq $header) {
        for ($i = 0; $i -lt 3; $i++) { $script:WinBtn[$i].Target = 0 }
        $script:TgTarget = 0; $header.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}
foreach ($dc in @($header, $lblLogo, $lblLogo2, $lblSub)) {
    $dc.Add_MouseDown($headDown); $dc.Add_MouseMove($headMove); $dc.Add_MouseUp($headUp); $dc.Add_MouseLeave($headLeave)
}
$header.Add_DoubleClick({
    $p = $header.PointToClient([System.Windows.Forms.Control]::MousePosition)
    $tr = [System.Drawing.RectangleF]::Inflate((Get-TgRect), 6, 6)
    if ($p.X -lt ($header.Width - 150) -and -not $tr.Contains([single]$p.X, [single]$p.Y)) {
        if ($script:Mode -eq 'win') { Set-Mode 'max' } else { Set-Mode 'win' }
    }
})

$form.Add_KeyDown({
    if ($_.KeyCode -eq 'F11') { if ($script:Mode -eq 'full') { Set-Mode 'max' } else { Set-Mode 'full' } }
    elseif ($_.KeyCode -eq 'Escape' -and $script:Mode -eq 'full') { Set-Mode 'max' }
})

# ---------------------------------------------------------------- боковое меню (рисуется целиком)
$script:NavItems = @(
    @{ Key = 'opt';   Text = 'Оптимизация'; T = 0.0; Target = 0 },
    @{ Key = 'tools'; Text = 'Инструменты'; T = 0.0; Target = 0 },
    @{ Key = 'about'; Text = 'О программе'; T = 0.0; Target = 0 }
)
$script:NavSel = 'opt'
$script:NavIndY = 18.0
$script:PackOk = $false
function Get-NavRect {
    param([int]$I)
    return New-Object System.Drawing.RectangleF(12, (18 + 54 * $I), 166, 46)
}
function Paint-NavIcon {
    param($G, [string]$Key, [double]$X, [double]$Y, $Col)
    $br = New-Object System.Drawing.SolidBrush($Col)
    $pen = New-Object System.Drawing.Pen($Col, [single]1.7)
    if ($Key -eq 'opt') {
        $pts = @( (New-Object System.Drawing.PointF([single]($X + 10), [single]$Y)), (New-Object System.Drawing.PointF([single]($X + 2), [single]($Y + 10.5))),
                  (New-Object System.Drawing.PointF([single]($X + 8), [single]($Y + 10.5))), (New-Object System.Drawing.PointF([single]($X + 6), [single]($Y + 18))),
                  (New-Object System.Drawing.PointF([single]($X + 16), [single]($Y + 7))), (New-Object System.Drawing.PointF([single]($X + 10), [single]($Y + 7))) )
        $G.FillPolygon($br, [System.Drawing.PointF[]]$pts)
    } elseif ($Key -eq 'tools') {
        Draw-Round $G $Col $null 0 $X $Y 7.5 7.5 2.2
        Draw-Round $G $Col $null 0 ($X + 10.5) $Y 7.5 7.5 2.2
        Draw-Round $G $Col $null 0 $X ($Y + 10.5) 7.5 7.5 2.2
        Draw-Round $G $Col $null 0 ($X + 10.5) ($Y + 10.5) 7.5 7.5 2.2
    } else {
        $G.DrawEllipse($pen, [single]($X + 0.8), [single]($Y + 0.8), [single]16.4, [single]16.4)
        $G.FillEllipse($br, [single]($X + 7.7), [single]($Y + 4.2), [single]2.6, [single]2.6)
        $G.DrawLine($pen, [single]($X + 9), [single]($Y + 8.4), [single]($X + 9), [single]($Y + 13.4))
    }
    $br.Dispose(); $pen.Dispose()
}

$nav = New-Object System.Windows.Forms.Panel
$nav.SetBounds(0, 96, 190, 664); $nav.BackColor = $cNavB
Enable-DoubleBuffer $nav
$nav.Add_Paint({
    try {
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $rc = $this.ClientRectangle
        if ($rc.Width -le 0 -or $rc.Height -le 0) { return }
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc, $cNavA, $cNavB, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillRectangle($br, $rc); $br.Dispose()
        $pen = New-Object System.Drawing.Pen($cLine, [single]1)
        $g.DrawLine($pen, ($rc.Width - 1), 0, ($rc.Width - 1), $rc.Height); $pen.Dispose()
        $iy = $script:NavIndY
        Fill-RoundGrad $g (Alpha-Color $cAccent 70) (Alpha-Color $cPanel2 230) 12 $iy 166 46 13 0
        Draw-Round $g $null (Alpha-Color $cAccent2 90) 1 12.5 ($iy + 0.5) 165 45 13
        Draw-Round $g $cAccent2 $null 0 12 ($iy + 11) 3.5 24 1.75
        for ($i = 0; $i -lt $script:NavItems.Count; $i++) {
            $it = $script:NavItems[$i]; $r = Get-NavRect $i
            $sel = ($it.Key -eq $script:NavSel)
            if (-not $sel -and $it.T -gt 0.02) { Draw-Round $g (Alpha-Color $cPanel2 (170 * $it.T)) $null 0 $r.X $r.Y $r.Width $r.Height 13 }
            $col = Mix-Color $cDim $cText $it.T
            if ($sel) { $col = $cText }
            $ic = $col; if ($sel) { $ic = $cAccent2 }
            Paint-NavIcon $g $it.Key ($r.X + 20) ($r.Y + 14) $ic
            Draw-Text $g $it.Text $fontBold $col ($r.X + 52) $r.Y 110 $r.Height $tfL
        }
        $ch = 96; $cy = $this.Height - $ch - 14
        Draw-Text $g 'F11  -  на весь экран' $fontTiny $cDim 20 ($cy - 26) 160 16 $tfL
        Draw-Round $g $cPanel $cLine 1 12 $cy 166 $ch 13
        $dc = $cWarn; if ($script:PackOk) { $dc = $cOk }
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($dc)), [single]26, [single]($cy + 15), [single]9, [single]9)
        $st = 'Пак не найден'; if ($script:PackOk) { $st = 'Пак найден' }
        Draw-Text $g $st $fontBold $cText 42 ($cy + 9) 128 20 $tfL
        Draw-Text $g ([string]$script:Root) $fontTiny $cDim 24 ($cy + 36) 142 ($ch - 44) $tfLT
    } catch { $script:PaintErr = $_.Exception.Message }
})
$nav.Add_MouseMove({
    $e = $_; $hit = $false
    for ($i = 0; $i -lt $script:NavItems.Count; $i++) {
        $on = (Get-NavRect $i).Contains([single]$e.X, [single]$e.Y)
        $script:NavItems[$i].Target = [int]$on
        if ($on) { $hit = $true }
    }
    if ($hit) { $nav.Cursor = [System.Windows.Forms.Cursors]::Hand } else { $nav.Cursor = [System.Windows.Forms.Cursors]::Default }
})
$nav.Add_MouseLeave({ foreach ($it in $script:NavItems) { $it.Target = 0 } })
$nav.Add_MouseDown({
    $e = $_
    for ($i = 0; $i -lt $script:NavItems.Count; $i++) {
        if ((Get-NavRect $i).Contains([single]$e.X, [single]$e.Y)) { Show-Page $script:NavItems[$i].Key; return }
    }
})
$form.Controls.Add($nav)

$pages = @{}
$script:Slide = $null
function Show-Page {
    param([string]$Name)
    if ($script:NavSel -ne $Name -or -not $form.Visible) { if ($form.Visible) { Play-Snd $script:SndSwipe } }
    $script:NavSel = $Name
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $Name) }
    if ($pages[$Name] -and $form.Visible) { $pages[$Name].Left = 190 + 48; $script:Slide = $pages[$Name] }
    $nav.Invalidate()
}
function New-Page {
    $pg = New-Object System.Windows.Forms.Panel
    $pg.SetBounds(190, 96, 990, 664); $pg.BackColor = $cBg
    Enable-DoubleBuffer $pg
    $pg.Add_Paint({ Paint-Bg $_.Graphics $this })
    $form.Controls.Add($pg)
    return $pg
}

# ---------------------------------------------------------------- кнопки-«пилюли» (рисуются сами)
$script:Pills = New-Object System.Collections.ArrayList
function Paint-Pill {
    param($Ctrl, $G)
    $st = $Ctrl.Tag
    $G.SmoothingMode = 'AntiAlias'
    $w = $Ctrl.Width; $h = $Ctrl.Height
    $t = $st.T
    $off = 0; if ($st.Down) { $off = 1 }
    if ($st.Kind -eq 'primary' -and $st.Enabled) {
        $pm = $st.Pulse
        for ($i = 1; $i -le 3; $i++) {
            $a = (22 + 48 * $pm + 40 * $t) / $i
            $pen = New-Object System.Drawing.Pen((Alpha-Color $cAccent2 $a), [single]1.5)
            $gp = New-RoundPath (4 - $i) (4 - $i) ($w - 8 + 2 * $i) ($h - 8 + 2 * $i) (15 + $i)
            $G.DrawPath($pen, $gp); $gp.Dispose(); $pen.Dispose()
        }
        $c1 = Mix-Color $cAccent $cAccent2 ($pm * 0.55 + $t * 0.4)
        $c2 = Mix-Color $cMagenta $cAccent ((1 - $pm) * 0.55)
        Fill-RoundGrad $G $c1 $c2 4 4 ($w - 8) ($h - 8) 15 0
        Draw-Text $G $st.Text $fontBtn $cWhite 4 (4 + $off) ($w - 8) ($h - 8) $tfC
    } elseif ($st.Kind -eq 'primary') {
        Draw-Round $G $cPanel2 $cLine 1 4 4 ($w - 8) ($h - 8) 15
        Draw-Text $G $st.Text $fontBtn $cDim 4 4 ($w - 8) ($h - 8) $tfC
    } else {
        $fill = Mix-Color $cPanel $cRowHover $t
        $line = Mix-Color $cLine $cAccent2 ($t * 0.9)
        $tc = $cText; if (-not $st.Enabled) { $tc = $cDim; $fill = $cPanel }
        Draw-Round $G $fill $line 1.2 1.5 1.5 ($w - 3) ($h - 3) 14
        Draw-Text $G $st.Text $st.Font $tc 1 $off ($w - 2) $h $tfC
    }
}
function New-Pill {
    param([string]$Text, [string]$Kind, [scriptblock]$OnClick, $Font)
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = $cClear
    Enable-DoubleBuffer $p
    $p.Cursor = [System.Windows.Forms.Cursors]::Hand
    $p.Tag = @{ Text = $Text; Kind = $Kind; Font = $Font; T = 0.0; Target = 0; Enabled = $true; Pulse = 0.0; Down = $false; OnClick = $OnClick }
    $p.Add_Paint({ try { Paint-Pill $this $_.Graphics } catch { $script:PaintErr = $_.Exception.Message } })
    $p.Add_MouseEnter({ if ($this.Tag.Enabled) { $this.Tag.Target = 1 } })
    $p.Add_MouseLeave({ $this.Tag.Target = 0; $this.Tag.Down = $false; $this.Invalidate() })
    $p.Add_MouseDown({ if ($this.Tag.Enabled) { $this.Tag.Down = $true; $this.Invalidate() } })
    $p.Add_MouseUp({
        $e = $_
        $wasDown = $this.Tag.Down; $this.Tag.Down = $false; $this.Invalidate()
        if ($wasDown -and $this.Tag.Enabled -and $this.ClientRectangle.Contains($e.Location)) { $cb = $this.Tag.OnClick; & $cb }
    })
    [void]$script:Pills.Add($p)
    return $p
}

# ---------------------------------------------------------------- страница: оптимизация
$pageOpt = New-Page; $pages['opt'] = $pageOpt

$lblH1 = New-Object System.Windows.Forms.Label
$lblH1.Text = 'Что применить'; $lblH1.Font = $fontH1; $lblH1.ForeColor = $cText; $lblH1.BackColor = $cClear
$lblH1.AutoSize = $true; $lblH1.Location = New-Object System.Drawing.Point(22, 14)
$pageOpt.Controls.Add($lblH1)

$script:Sel = @{}
foreach ($t in $script:Tweaks) { $script:Sel[$t.Id] = [bool]$t.Default }
$script:ListItems = New-Object System.Collections.ArrayList
$script:Scroll = 0.0; $script:ScrollT = 0.0; $script:ScrollMax = 0.0; $script:ContentH = 0.0
$script:SbT = 0.0; $script:SbTarget = 0; $script:SbDrag = $false; $script:SbGrab = 0.0
$script:Thumb = @{ X = 0.0; Y = 0.0; H = 0.0 }

$listHost = New-Object System.Windows.Forms.Panel
$listHost.SetBounds(22, 54, 940, 400); $listHost.BackColor = $cClear
Enable-DoubleBuffer $listHost
$pageOpt.Controls.Add($listHost)

[void]$script:ListItems.Add(@{ Kind = 'group'; Text = 'РЕКОМЕНДУЕМЫЕ'; X = 0.0; Y = 0.0; W = 0.0; H = 30.0 })
foreach ($t in $script:Tweaks) {
    if ($t.Group -eq 'rec') { [void]$script:ListItems.Add(@{ Kind = 'row'; Tw = $t; X = 0.0; Y = 0.0; W = 0.0; H = 96.0; T = 0.0; Target = 0; K = [double][int]$script:Sel[$t.Id]; KT = [double][int]$script:Sel[$t.Id] }) }
}
[void]$script:ListItems.Add(@{ Kind = 'group'; Text = 'ДОПОЛНИТЕЛЬНЫЕ'; X = 0.0; Y = 0.0; W = 0.0; H = 30.0 })
foreach ($t in $script:Tweaks) {
    if ($t.Group -eq 'opt') { [void]$script:ListItems.Add(@{ Kind = 'row'; Tw = $t; X = 0.0; Y = 0.0; W = 0.0; H = 96.0; T = 0.0; Target = 0; K = [double][int]$script:Sel[$t.Id]; KT = [double][int]$script:Sel[$t.Id] }) }
}

function Layout-List {
    $W = $listHost.ClientSize.Width - 16
    $gap = 12.0
    $cols = 1; if ($W -ge 960) { $cols = 2 }
    $cw = ($W - ($cols - 1) * $gap) / $cols
    $y = 0.0; $col = 0
    foreach ($it in $script:ListItems) {
        if ($it.Kind -eq 'group') {
            if ($col -ne 0) { $col = 0; $y += 96.0 + $gap }
            $it.X = 0.0; $it.Y = $y; $it.W = [double]$W; $it.H = 30.0; $y += 36.0
        } else {
            $it.X = $col * ($cw + $gap); $it.Y = $y; $it.W = $cw; $it.H = 96.0
            $col++
            if ($col -ge $cols) { $col = 0; $y += 96.0 + $gap }
        }
    }
    if ($col -ne 0) { $y += 96.0 + $gap }
    $script:ContentH = $y
    $script:ScrollMax = [Math]::Max(0.0, $y - $listHost.ClientSize.Height)
    if ($script:ScrollT -gt $script:ScrollMax) { $script:ScrollT = $script:ScrollMax }
    if ($script:Scroll -gt $script:ScrollMax) { $script:Scroll = $script:ScrollMax }
    $listHost.Invalidate()
}

function Set-Sel {
    param([string]$Id, [bool]$On)
    $script:Sel[$Id] = $On
    if ($On -and $Id -eq 'fse') { $script:Sel['fso'] = $false }
    if ($On -and $Id -eq 'fso') { $script:Sel['fse'] = $false }
    foreach ($it in $script:ListItems) { if ($it.Kind -eq 'row') { $it.KT = [double][int]$script:Sel[$it.Tw.Id] } }
}

function Paint-Toggle {
    param($G, [double]$X, [double]$Y, [double]$K)
    Draw-Round $G (Mix-Color $cPanel2 $cAccent $K) (Mix-Color $cLine $cAccent2 $K) 1.2 $X $Y 48 26 13
    $kx = $X + 4 + 22 * $K
    $br = New-Object System.Drawing.SolidBrush((Mix-Color $cDim $cWhite $K))
    $G.FillEllipse($br, [single]$kx, [single]($Y + 4), [single]18, [single]18); $br.Dispose()
}

function Paint-Row {
    param($G, $It, [double]$Y)
    $x = $It.X; $w = $It.W; $h = $It.H; $k = $It.K; $t = $It.T
    $fill = Mix-Color $cPanel $cRowHover $t
    $line = Mix-Color (Mix-Color $cLine $cAccent ($k * 0.8)) $cAccent2 ($t * 0.55)
    Draw-Round $G $fill $line 1.2 ($x + 0.5) ($Y + 0.5) ($w - 1) ($h - 1) 14
    if ($k -gt 0.03) { Draw-Round $G (Alpha-Color $cAccent2 (255 * $k)) $null 0 ($x + 1) ($Y + 22) 3.5 ($h - 44) 1.75 }
    Paint-Toggle $G ($x + 22) ($Y + ($h - 26) / 2) $k
    Draw-Text $G $It.Tw.Title $fontRow $cText ($x + 90) ($Y + 11) ($w - 90 - 18) 24 $tfL
    Draw-Text $G $It.Tw.Desc $fontDesc (Mix-Color $cDim $cText ($t * 0.25)) ($x + 90) ($Y + 38) ($w - 90 - 18) ($h - 38 - 8) $tfLT
}

$listHost.Add_Paint({
    try {
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $vh = $this.ClientSize.Height
        foreach ($it in $script:ListItems) {
            $y = $it.Y - $script:Scroll
            if (($y + $it.H) -lt 0 -or $y -gt $vh) { continue }
            if ($it.Kind -eq 'group') {
                Draw-Text $g $it.Text $fontGroup $cAccent2 ($it.X + 4) $y 400 $it.H $tfL
                $tw = Measure-W $it.Text $fontGroup
                $pen = New-Object System.Drawing.Pen($cLine, [single]1)
                $g.DrawLine($pen, [single]($it.X + $tw + 20), [single]($y + $it.H / 2), [single]($it.X + $it.W), [single]($y + $it.H / 2)); $pen.Dispose()
            } else { Paint-Row $g $it $y }
        }
        if ($script:ScrollMax -gt 1) {
            $trackH = $vh - 8.0
            $thumbH = [Math]::Max(44.0, $trackH * $vh / $script:ContentH)
            $thumbY = 4.0 + ($trackH - $thumbH) * ($script:Scroll / $script:ScrollMax)
            $script:Thumb.X = $this.ClientSize.Width - 10.0; $script:Thumb.Y = $thumbY; $script:Thumb.H = $thumbH
            Draw-Round $g (Alpha-Color $cLine 120) $null 0 ($this.ClientSize.Width - 8) 4 4 $trackH 2
            Draw-Round $g (Mix-Color $cLine $cAccent2 (0.35 + 0.65 * $script:SbT)) $null 0 ($this.ClientSize.Width - 9) $thumbY 6 $thumbH 3
        }
    } catch { $script:PaintErr = $_.Exception.Message }
})

function Set-ScrollTarget {
    param([double]$V)
    $script:ScrollT = [Math]::Max(0.0, [Math]::Min($script:ScrollMax, $V))
}
function Get-ListHit {
    param([double]$X, [double]$Y)
    foreach ($it in $script:ListItems) {
        if ($it.Kind -ne 'row') { continue }
        $iy = $it.Y - $script:Scroll
        if ($X -ge $it.X -and $X -le ($it.X + $it.W) -and $Y -ge $iy -and $Y -le ($iy + $it.H)) { return $it }
    }
    return $null
}
$listHost.Add_MouseMove({
    $e = $_
    if ($script:SbDrag) {
        $trackH = $this.ClientSize.Height - 8.0
        $range = $trackH - $script:Thumb.H
        if ($range -gt 1) {
            $ratio = ($e.Y - 4.0 - $script:SbGrab) / $range
            Set-ScrollTarget ($ratio * $script:ScrollMax)
            $script:Scroll = $script:ScrollT
            $this.Invalidate()
        }
        return
    }
    $onThumb = ($script:ScrollMax -gt 1 -and $e.X -ge ($this.ClientSize.Width - 18) -and $e.Y -ge $script:Thumb.Y -and $e.Y -le ($script:Thumb.Y + $script:Thumb.H))
    $script:SbTarget = [int]$onThumb
    $hit = Get-ListHit $e.X $e.Y
    foreach ($it in $script:ListItems) { if ($it.Kind -eq 'row') { $it.Target = [int]([object]::ReferenceEquals($it, $hit)) } }
    if ($hit -or $onThumb) { $this.Cursor = [System.Windows.Forms.Cursors]::Hand } else { $this.Cursor = [System.Windows.Forms.Cursors]::Default }
})
$listHost.Add_MouseLeave({
    foreach ($it in $script:ListItems) { if ($it.Kind -eq 'row') { $it.Target = 0 } }
    $script:SbTarget = 0; $this.Cursor = [System.Windows.Forms.Cursors]::Default
})
$listHost.Add_MouseDown({
    $e = $_
    if ($e.Button -ne 'Left') { return }
    if ($script:ScrollMax -gt 1 -and $e.X -ge ($this.ClientSize.Width - 18)) {
        if ($e.Y -ge $script:Thumb.Y -and $e.Y -le ($script:Thumb.Y + $script:Thumb.H)) {
            $script:SbDrag = $true; $script:SbGrab = $e.Y - $script:Thumb.Y
        } elseif ($e.Y -lt $script:Thumb.Y) { Set-ScrollTarget ($script:ScrollT - $this.ClientSize.Height * 0.8) }
        else { Set-ScrollTarget ($script:ScrollT + $this.ClientSize.Height * 0.8) }
        return
    }
    $hit = Get-ListHit $e.X $e.Y
    if ($hit) { Play-Snd $script:SndTick; Set-Sel $hit.Tw.Id (-not $script:Sel[$hit.Tw.Id]) }
})
$listHost.Add_MouseUp({ $script:SbDrag = $false })
$listHost.Add_MouseWheel({ Set-ScrollTarget ($script:ScrollT - $_.Delta * 0.7) })

# главные кнопки
$script:Busy = $false
$btnApply = New-Pill 'ОПТИМИЗИРОВАТЬ' 'primary' { Invoke-Apply } $fontBtn
$btnRevert = New-Pill 'Откатить последнее' 'ghost' { Invoke-RevertClick } $fontBold
$btnAll = New-Pill 'Все / никакие' 'ghost' { Invoke-ToggleAll } $fontBold
foreach ($b in @($btnApply, $btnRevert, $btnAll)) { $pageOpt.Controls.Add($b) }

# прогресс
$script:ProgCur = 0.0; $script:ProgTarget = 0.0
$barHost = New-Object System.Windows.Forms.Panel
$barHost.SetBounds(22, 520, 940, 10); $barHost.BackColor = $cClear; $barHost.Visible = $false
Enable-DoubleBuffer $barHost
$barHost.Add_Paint({
    try {
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $w = $this.Width; $h = $this.Height
        Draw-Round $g $cPanel2 $null 0 0 0 $w $h 5
        $fw = [Math]::Max(0.0, ($w * $script:ProgCur))
        if ($fw -gt 6) { Fill-RoundGrad $g $cAccent $cMagenta 0 0 $fw $h 5 0 }
    } catch { $script:PaintErr = $_.Exception.Message }
})
$pageOpt.Controls.Add($barHost)

# журнал
$logHost = New-Object System.Windows.Forms.Panel
$logHost.SetBounds(22, 540, 940, 100); $logHost.BackColor = $cClear
Enable-DoubleBuffer $logHost
$logHost.Add_Paint({
    try {
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        Draw-Round $g $cPanel $cLine 1.2 0.5 0.5 ($this.Width - 1) ($this.Height - 1) 14
    } catch { $script:PaintErr = $_.Exception.Message }
})
$pageOpt.Controls.Add($logHost)
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.SetBounds(16, 10, 908, 80)
$logBox.BackColor = $cPanel; $logBox.ForeColor = $cText; $logBox.Font = $fontMono
$logBox.ReadOnly = $true; $logBox.BorderStyle = 'None'; $logBox.ScrollBars = 'None'
$logBox.Add_MouseEnter({ $this.Focus() })
$logBox.Add_MouseWheel({
    if ($script:Win32Ok) {
        $lines = [int](-[Math]::Sign($_.Delta) * 3)
        [void][XeokaNative]::SendMessage($this.Handle, 0x00B6, [IntPtr]0, [IntPtr]$lines)
    }
})
$logHost.Controls.Add($logBox)

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
    $script:ProgTarget = [Math]::Max(0, [Math]::Min(1, $Fraction))
    [System.Windows.Forms.Application]::DoEvents()
}
function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    foreach ($b in @($btnApply, $btnRevert, $btnAll)) { $b.Tag.Enabled = (-not $On); if ($On) { $b.Tag.Target = 0 }; $b.Invalidate() }
    if ($On) { $btnApply.Tag.Text = 'ПРИМЕНЯЮ...' } else { $btnApply.Tag.Text = 'ОПТИМИЗИРОВАТЬ' }
}
function Invoke-ToggleAll {
    $any = $false
    foreach ($k in @($script:Sel.Keys)) { if ($script:Sel[$k]) { $any = $true } }
    foreach ($tw in $script:Tweaks) { Set-Sel $tw.Id ((-not $any) -and [bool]$tw.Default) }
}
function Invoke-Apply {
    if ($script:Busy) { return }
    if (-not (Test-PackRoot $script:Root)) {
        [System.Windows.Forms.MessageBox]::Show("Папка пака не найдена. Нажмите «Указать папку пака» или положите XEOKA-PACK.ps1 в корень пака (рядом с папками «1. База», «2. Драйверы» и т.д.).", 'XEOKA PACK', 'OK', 'Warning') | Out-Null
        return
    }
    $sel = @($script:Tweaks | Where-Object { $script:Sel[$_.Id] })
    if ($sel.Count -eq 0) { Write-Log 'Ничего не выбрано.' 'warn'; return }
    $msg = "Будет применено твиков: $($sel.Count).`n`nПеред этим создаётся точка восстановления. Изменения реестра можно откатить кнопкой «Откатить последнее».`n`nПродолжить?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'XEOKA PACK', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    $logBox.Clear(); $barHost.Visible = $true; $script:ProgCur = 0.0; Set-Progress 0
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
        foreach ($tw in $sel) {
            Write-Log ('> ' + $tw.Title) 'head'
            try { & $tw.Run; Write-Log '  готово' 'ok'; $okCount++ }
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
    } finally { Set-Busy $false; $barHost.Visible = $false }
}
function Invoke-RevertClick {
    if ($script:Busy) { return }
    $r = [System.Windows.Forms.MessageBox]::Show('Вернуть значения реестра, схему питания и параметры сети к состоянию до последнего применения?', 'XEOKA PACK', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    try { Invoke-Revert } catch { Write-Log ('Ошибка отката: ' + $_.Exception.Message) 'err' } finally { Set-Busy $false }
}

# выбор папки пака
$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = 'Папка пака не найдена'
$lblWarn.Font = $fontSmall; $lblWarn.ForeColor = $cWarn; $lblWarn.BackColor = $cClear; $lblWarn.AutoSize = $false
$lblWarn.TextAlign = 'MiddleRight'; $lblWarn.SetBounds(400, 14, 280, 30)
$pageOpt.Controls.Add($lblWarn)
$btnPick = New-Pill 'Указать папку пака' 'ghost' { Invoke-PickFolder } $fontSmall
$btnPick.SetBounds(690, 10, 230, 38)
$pageOpt.Controls.Add($btnPick)

# ---------------------------------------------------------------- страница: инструменты
$pageTools = New-Page; $pageTools.Visible = $false; $pages['tools'] = $pageTools
$lblT = New-Object System.Windows.Forms.Label
$lblT.Text = 'Инструменты пака'; $lblT.Font = $fontH1; $lblT.ForeColor = $cText; $lblT.BackColor = $cClear
$lblT.AutoSize = $true; $lblT.Location = New-Object System.Drawing.Point(22, 14)
$pageTools.Controls.Add($lblT)
$lblT2 = New-Object System.Windows.Forms.Label
$lblT2.Text = 'Запускаются отдельно: то, что нельзя безопасно применить одной кнопкой.'
$lblT2.Font = $fontSmall; $lblT2.ForeColor = $cDim; $lblT2.BackColor = $cClear; $lblT2.AutoSize = $true
$lblT2.Location = New-Object System.Drawing.Point(24, 46)
$pageTools.Controls.Add($lblT2)

$tools = @(
    @{ T = 'Windows Defender'; D = 'Переключатель защитника'; P = '6.'; F = 'RUN-WDS.bat'; G = 'WD'; Risk = $true },
    @{ T = 'Обновления Windows'; D = 'Блокировщик обновлений'; P = '7.'; F = 'RUN-WUB.bat'; G = 'WU'; Risk = $true },
    @{ T = 'DEVICE-TWEAKER'; D = 'Аффинити, прерывания, USB'; P = '13.'; F = 'RUN-DEVICE-TWEAKER.bat'; G = 'DT'; Risk = $false },
    @{ T = 'BIOS (SCEWIN)'; D = 'Конфиги BIOS. Читайте инструкцию'; P = '12.'; F = 'SCEWIN-GUI.exe'; G = 'BIOS'; Risk = $true },
    @{ T = 'Тип драйвера сети'; D = 'NDIS или NetAdapterCx'; P = '15.'; F = 'RUN-CHECK-NIC-DRIVER-TYPE.PS1.bat'; G = 'NIC'; Risk = $false },
    @{ T = 'Энергосбережение сети'; D = 'Проверка статуса'; P = '9.'; F = 'RUN-CHECK-POWER-MANAGEMENT.bat'; G = 'PWR'; Risk = $false },
    @{ T = 'DDU'; D = 'Удаление драйверов видеокарты'; P = '2.'; F = 'Display Driver Uninstaller.exe'; G = 'DDU'; Risk = $false },
    @{ T = 'NVCleanstall'; D = 'Установка драйвера NVIDIA'; P = '2.'; F = 'NVCleanstall_1.19.0.exe'; G = 'NV'; Risk = $false },
    @{ T = 'Profile Inspector'; D = 'Профили NVIDIA'; P = '2.'; F = 'nvidiaProfileInspector.exe'; G = 'NPI'; Risk = $false },
    @{ T = 'CRU'; D = 'Настройка разрешений и частот'; P = '3.'; F = 'CRU.exe'; G = 'CRU'; Risk = $false },
    @{ T = 'Autoruns'; D = 'Автозагрузка'; P = '8.'; F = 'Autoruns.exe'; G = 'AR'; Risk = $false },
    @{ T = 'Службы (PowerRun)'; D = 'Отключение служб. Осторожно'; P = '10.'; F = 'DISABLE-SERVICES.reg'; G = 'SVC'; Risk = $true }
)

function Invoke-ToolCard {
    param($Tool)
    $p = Find-PackFile $Tool.P $Tool.F
    if (-not $p) {
        [System.Windows.Forms.MessageBox]::Show("Файл «$($Tool.F)» не найден в паке.", 'XEOKA PACK', 'OK', 'Warning') | Out-Null
        return
    }
    try {
        if ($Tool.F -eq 'DISABLE-SERVICES.reg') {
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
}

$script:ToolItems = New-Object System.Collections.ArrayList
foreach ($tl in $tools) { [void]$script:ToolItems.Add(@{ Tool = $tl; X = 0.0; Y = 0.0; W = 0.0; H = 80.0; T = 0.0; Target = 0; Path = $null }) }

$toolsHost = New-Object System.Windows.Forms.Panel
$toolsHost.SetBounds(22, 84, 940, 440); $toolsHost.BackColor = $cClear
Enable-DoubleBuffer $toolsHost
$pageTools.Controls.Add($toolsHost)

function Layout-Tools {
    $W = $toolsHost.ClientSize.Width
    $gap = 12.0
    $cols = 2; if ($W -ge 1200) { $cols = 3 } elseif ($W -lt 700) { $cols = 1 }
    $cw = ($W - ($cols - 1) * $gap) / $cols
    $i = 0; $y = 30.0
    foreach ($ti in $script:ToolItems) {
        $col = $i % $cols
        $ti.X = $col * ($cw + $gap); $ti.Y = $y; $ti.W = $cw; $ti.H = 80.0
        $i++
        if ($col -eq ($cols - 1)) { $y += 80.0 + $gap }
    }
    if (($i % $cols) -ne 0) { $y += 80.0 + $gap }
    $script:ToolsH = $y
    $toolsHost.Invalidate()
}
$script:ToolsH = 0.0

$toolsHost.Add_Paint({
    try {
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($cAmberB)), [single]4, [single]9, [single]9, [single]9)
        Draw-Text $g 'янтарные значки: меняют защиту или стабильность системы, запускайте внимательно' $fontSmall $cDim 20 3 700 22 $tfL
        foreach ($ti in $script:ToolItems) {
            $x = $ti.X; $y = $ti.Y; $w = $ti.W; $h = $ti.H; $t = $ti.T
            $has = [bool]$ti.Path
            Draw-Round $g (Mix-Color $cPanel $cRowHover $t) (Mix-Color $cLine $cAccent2 ($t * 0.7)) 1.2 ($x + 0.5) ($y + 0.5) ($w - 1) ($h - 1) 14
            $c1 = $cAccent; $c2 = $cMagenta
            if ($ti.Tool.Risk) { $c1 = $cAmberA; $c2 = $cAmberB }
            if (-not $has) { $c1 = $cLine; $c2 = $cPanel2 }
            Fill-RoundGrad $g $c1 $c2 ($x + 18) ($y + 18) 44 44 22 50
            $gt = $ti.Tool.G
            Draw-Text $g $gt $fontGlyph $cWhite ($x + 18) ($y + 18) 44 44 $tfC
            $tc = $cText; if (-not $has) { $tc = $cDim }
            Draw-Text $g $ti.Tool.T $fontRow $tc ($x + 76) ($y + 15) ($w - 76 - 40) 24 $tfL
            if ($has) { Draw-Text $g $ti.Tool.D $fontSmall $cDim ($x + 76) ($y + 42) ($w - 76 - 40) 22 $tfL }
            else { Draw-Text $g 'файл не найден: укажите папку пака' $fontSmall $cWarn ($x + 76) ($y + 42) ($w - 76 - 40) 22 $tfL }
            $pen = New-Object System.Drawing.Pen((Mix-Color $cLine $cAccent2 $t), [single]1.8)
            $ax = $x + $w - 30 + 5 * $t; $ay = $y + $h / 2
            $g.DrawLine($pen, [single]$ax, [single]($ay - 6), [single]($ax + 6), [single]$ay)
            $g.DrawLine($pen, [single]($ax + 6), [single]$ay, [single]$ax, [single]($ay + 6)); $pen.Dispose()
        }
    } catch { $script:PaintErr = $_.Exception.Message }
})
function Get-ToolHit {
    param([double]$X, [double]$Y)
    foreach ($ti in $script:ToolItems) {
        if ($X -ge $ti.X -and $X -le ($ti.X + $ti.W) -and $Y -ge $ti.Y -and $Y -le ($ti.Y + $ti.H)) { return $ti }
    }
    return $null
}
$toolsHost.Add_MouseMove({
    $e = $_
    $hit = Get-ToolHit $e.X $e.Y
    foreach ($ti in $script:ToolItems) { $ti.Target = [int]([object]::ReferenceEquals($ti, $hit)) }
    if ($hit) { $this.Cursor = [System.Windows.Forms.Cursors]::Hand } else { $this.Cursor = [System.Windows.Forms.Cursors]::Default }
})
$toolsHost.Add_MouseLeave({ foreach ($ti in $script:ToolItems) { $ti.Target = 0 }; $this.Cursor = [System.Windows.Forms.Cursors]::Default })
$toolsHost.Add_MouseDown({
    $e = $_
    if ($e.Button -ne 'Left') { return }
    $hit = Get-ToolHit $e.X $e.Y
    if ($hit) { Invoke-ToolCard $hit.Tool }
})

$btnFolder = New-Pill 'Открыть папку пака' 'ghost' { Start-Process explorer.exe -ArgumentList ('"' + $script:Root + '"') } $fontBold
$btnFolder.SetBounds(22, 540, 240, 46)
$pageTools.Controls.Add($btnFolder)

$lblWarn2 = New-Object System.Windows.Forms.Label
$lblWarn2.Text = 'Папка пака не найдена'
$lblWarn2.Font = $fontSmall; $lblWarn2.ForeColor = $cWarn; $lblWarn2.BackColor = $cClear; $lblWarn2.AutoSize = $false
$lblWarn2.TextAlign = 'MiddleRight'; $lblWarn2.SetBounds(400, 14, 280, 30)
$pageTools.Controls.Add($lblWarn2)
$btnPick2 = New-Pill 'Указать папку пака' 'ghost' { Invoke-PickFolder } $fontSmall
$btnPick2.SetBounds(690, 10, 230, 38)
$pageTools.Controls.Add($btnPick2)

function Update-PackState {
    $script:FileCache = @{}
    $ok = Test-PackRoot $script:Root
    $script:PackOk = $ok
    foreach ($c in @($lblWarn, $btnPick, $lblWarn2, $btnPick2)) { $c.Visible = (-not $ok) }
    foreach ($ti in $script:ToolItems) { $ti.Path = Find-PackFile $ti.Tool.P $ti.Tool.F }
    $nav.Invalidate(); $toolsHost.Invalidate()
}
function Invoke-PickFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Выберите корневую папку пака (где лежат папки «1. База», «2. Драйверы» и т.д.)'
    if ($dlg.ShowDialog() -eq 'OK') {
        if (Test-PackRoot $dlg.SelectedPath) {
            $script:Root = $dlg.SelectedPath
            try { Set-Content -Path (Join-Path $script:DataDir 'root.txt') -Value $script:Root -Encoding UTF8 } catch { }
            Update-PackState
        } else {
            [System.Windows.Forms.MessageBox]::Show('В этой папке не найдены папки пака (1. База, 2. Драйверы ...).', 'XEOKA PACK', 'OK', 'Warning') | Out-Null
        }
    }
}

# ---------------------------------------------------------------- страница: о программе
$pageAbout = New-Page; $pageAbout.Visible = $false; $pages['about'] = $pageAbout
$lblA = New-Object System.Windows.Forms.Label
$lblA.Text = 'О программе'; $lblA.Font = $fontH1; $lblA.ForeColor = $cText; $lblA.BackColor = $cClear
$lblA.AutoSize = $true; $lblA.Location = New-Object System.Drawing.Point(22, 14)
$pageAbout.Controls.Add($lblA)

$script:AboutCards = @(
    @{ Title = 'Безопасно'; Icon = 'check'; Warn = $false; P = @(
        'Перед применением создаётся точка восстановления Windows.',
        'Каждое изменение реестра записывается в журнал.',
        'Кнопка «Откатить последнее» возвращает прежние значения.') },
    @{ Title = 'Отдельно от кнопки'; Icon = 'grid'; Warn = $false; P = @(
        'Defender, обновления Windows, службы и BIOS меняют защиту и стабильность системы.',
        'Поэтому они вынесены на вкладку «Инструменты» и запускаются вручную.') },
    @{ Title = 'Что нужно знать'; Icon = 'bang'; Warn = $true; P = @(
        'После применения перезагрузите ПК и проверьте игры и устройства.',
        'Профиль NVIDIA и энергосбережение устройств кнопкой отката не возвращаются.',
        'Используйте на свой риск. Автор не отвечает за последствия.') }
)
$script:AboutL = $null
function Get-AboutLayout {
    param([int]$W)
    $L = @{}
    $m = 22; $cw = $W - 2 * $m
    $L.Hero = New-Object System.Drawing.RectangleF($m, 56, $cw, 132)
    $cols = 1; if ($cw -ge 900) { $cols = 3 }
    $gap = 14
    $cardW = ($cw - ($cols - 1) * $gap) / $cols
    $textW = [int]($cardW - 56)
    $cards = New-Object System.Collections.ArrayList
    $maxH = 0
    foreach ($c in $script:AboutCards) {
        $hs = New-Object System.Collections.ArrayList
        $hh = 74
        foreach ($ptxt in $c.P) {
            $sz = [System.Windows.Forms.TextRenderer]::MeasureText($ptxt, $fontDesc, (New-Object System.Drawing.Size($textW, 0)), $tfWrap)
            [void]$hs.Add($sz.Height); $hh += $sz.Height + 10
        }
        $hh += 14
        if ($hh -gt $maxH) { $maxH = $hh }
        [void]$cards.Add(@{ Card = $c; Hs = $hs; H = $hh })
    }
    $y = 188 + 16.0; $i = 0
    foreach ($cd in $cards) {
        $col = $i % $cols
        $ch = $maxH; if ($cols -eq 1) { $ch = $cd.H }
        $cd.R = New-Object System.Drawing.RectangleF(($m + $col * ($cardW + $gap)), $y, $cardW, $ch)
        $i++
        if ($col -eq ($cols - 1)) { $y += $ch + $gap }
    }
    $L.Cards = $cards
    $L.Banner = New-Object System.Drawing.RectangleF($m, ($y + 2), $cw, 100)
    $L.FooterY = $y + 2 + 100 + 16
    $L.M = $m; $L.CW = $cw
    return $L
}
function Draw-Chip {
    param($G, [string]$Text, [double]$X, [double]$Y)
    $w = (Measure-W $Text $fontSmall) + 38
    Draw-Round $G (Alpha-Color $cAccent 46) (Alpha-Color $cAccent2 120) 1 $X $Y $w 28 14
    $G.FillEllipse((New-Object System.Drawing.SolidBrush($cOk)), [single]($X + 12), [single]($Y + 10), [single]8, [single]8)
    Draw-Text $G $Text $fontSmall $cText ($X + 26) $Y ($w - 30) 28 $tfL
    return $w
}
function Paint-AboutIcon {
    param($G, [string]$Kind, [double]$X, [double]$Y, [bool]$Warn)
    $c1 = $cAccent; $c2 = $cMagenta
    if ($Warn) { $c1 = $cAmberA; $c2 = $cAmberB }
    Fill-RoundGrad $G $c1 $c2 $X $Y 36 36 18 50
    $pen = New-Object System.Drawing.Pen($cWhite, [single]2.2)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $cx = $X + 18; $cy = $Y + 18
    if ($Kind -eq 'check') {
        $G.DrawLines($pen, [System.Drawing.PointF[]]@( (New-Object System.Drawing.PointF([single]($cx - 7), [single]$cy)), (New-Object System.Drawing.PointF([single]($cx - 2), [single]($cy + 5))), (New-Object System.Drawing.PointF([single]($cx + 7), [single]($cy - 5))) ))
    } elseif ($Kind -eq 'grid') {
        foreach ($o in @(@(-7,-7), @(1,-7), @(-7,1), @(1,1))) { Draw-Round $G $cWhite $null 0 ($cx + $o[0]) ($cy + $o[1]) 6 6 1.8 }
    } else {
        $G.DrawLine($pen, [single]$cx, [single]($cy - 7), [single]$cx, [single]($cy + 2))
        $G.FillEllipse([System.Drawing.Brushes]::White, [single]($cx - 1.6), [single]($cy + 5), [single]3.2, [single]3.2)
    }
    $pen.Dispose()
}

$aboutHost = New-Object System.Windows.Forms.Panel
$aboutHost.SetBounds(0, 0, 990, 664); $aboutHost.BackColor = $cClear
Enable-DoubleBuffer $aboutHost
$pageAbout.Controls.Add($aboutHost)
$lblA.BringToFront()
$aboutHost.Add_Paint({
    try {
        $L = $script:AboutL
        if (-not $L) { return }
        $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'
        # --- hero
        $h = $L.Hero
        $hp = New-RoundPath $h.X $h.Y $h.Width $h.Height 20
        $hb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($h, (C '#3A1A7C'), (C '#120A29'), [single]0)
        $g.FillPath($hb, $hp); $hb.Dispose()
        $g.SetClip($hp)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush((Alpha-Color $cAccent2 26))), [single]($h.Right - 250), [single]($h.Y - 90), [single]340, [single]340)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush((Alpha-Color $cMagenta 20))), [single]($h.Right - 120), [single]($h.Y + 40), [single]200, [single]200)
        $g.ResetClip()
        $hpn = New-Object System.Drawing.Pen((Alpha-Color $cAccent2 130), [single]1.2)
        $g.DrawPath($hpn, $hp); $hpn.Dispose(); $hp.Dispose()
        $xw = (Measure-W 'XEOKA' $fontHero)
        Draw-Text $g 'XEOKA' $fontHero $cText ($h.X + 30) ($h.Y + 14) 260 46 $tfL
        Draw-Text $g 'PACK' $fontHero (Mix-Color $cAccent2 $cMagenta 0.5) ($h.X + 30 + $xw - 4) ($h.Y + 14) 220 46 $tfL
        Draw-Text $g ('Оптимизация Windows одной кнопкой   -   версия ' + $script:Version) $fontDesc $cDim ($h.X + 32) ($h.Y + 62) ($h.Width - 64) 22 $tfL
        $cx = $h.X + 32
        foreach ($chip in @('Точка восстановления', 'Откат изменений', 'Автопоиск пака')) { $cwid = Draw-Chip $g $chip $cx ($h.Y + 90); $cx += $cwid + 10 }
        # --- карточки
        foreach ($cd in $L.Cards) {
            $r = $cd.R
            Draw-Round $g $cPanel $cLine 1.2 ($r.X + 0.5) ($r.Y + 0.5) ($r.Width - 1) ($r.Height - 1) 18
            Paint-AboutIcon $g $cd.Card.Icon ($r.X + 20) ($r.Y + 20) $cd.Card.Warn
            Draw-Text $g $cd.Card.Title $fontRow $cText ($r.X + 68) ($r.Y + 20) ($r.Width - 90) 36 $tfL
            $py = $r.Y + 74
            for ($i = 0; $i -lt $cd.Card.P.Count; $i++) {
                $g.FillEllipse((New-Object System.Drawing.SolidBrush($cAccent2)), [single]($r.X + 22), [single]($py + 6), [single]5, [single]5)
                Draw-Text $g $cd.Card.P[$i] $fontDesc $cDim ($r.X + 36) $py ($r.Width - 56) ($cd.Hs[$i] + 4) $tfWrap
                $py += $cd.Hs[$i] + 10
            }
        }
        # --- баннер Telegram
        $b = $L.Banner
        $bp = New-RoundPath $b.X $b.Y $b.Width $b.Height 20
        $bb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($b, (C '#142A55'), (C '#2A1260'), [single]0)
        $g.FillPath($bb, $bp); $bb.Dispose()
        $bpn = New-Object System.Drawing.Pen((Alpha-Color $cTgA 110), [single]1.2)
        $g.DrawPath($bpn, $bp); $bpn.Dispose(); $bp.Dispose()
        $pulse = ([Math]::Sin($script:Sec * 2.2) + 1) / 2
        for ($i = 2; $i -ge 1; $i--) {
            $pen = New-Object System.Drawing.Pen((Alpha-Color $cTgA ((20 + 30 * $pulse) / $i)), [single]2)
            $rad = 30 + $i * 4
            $g.DrawEllipse($pen, [single]($b.X + 54 - $rad), [single]($b.Y + 50 - $rad), [single]($rad * 2), [single]($rad * 2)); $pen.Dispose()
        }
        Draw-TgBadge $g ($b.X + 54) ($b.Y + 50) 56
        Draw-Text $g 'АВТОР И ПОДДЕРЖКА В TELEGRAM' $fontTiny $cTgA ($b.X + 100) ($b.Y + 22) 420 16 $tfL
        Draw-Text $g $script:TgLabel $fontBig $cText ($b.X + 100) ($b.Y + 40) 460 34 $tfL
        Draw-Text $g ('Журнал и откат: ' + $script:DataDir) $fontTiny $cDim $L.M $L.FooterY ($L.CW - 440) 20 $tfL
    } catch { $script:PaintErr = $_.Exception.Message }
})
$btnTg = New-Pill 'Открыть Telegram' 'primary' { Open-Url $script:TgUrl } $fontBtn
$btnTg.SetBounds(700, 70, 230, 58)
$aboutHost.Controls.Add($btnTg)
$btnLogs = New-Pill 'Открыть журнал' 'ghost' { if (Test-Path $script:DataDir) { Start-Process explorer.exe -ArgumentList ('"' + $script:DataDir + '"') } } $fontSmall
$aboutHost.Controls.Add($btnLogs)
$btnPackFolder = New-Pill 'Открыть папку пака' 'ghost' { Start-Process explorer.exe -ArgumentList ('"' + $script:Root + '"') } $fontSmall
$aboutHost.Controls.Add($btnPackFolder)

# ---------------------------------------------------------------- адаптивная раскладка
function Update-Layout {
    if (-not $script:LayoutReady) { return }
    $W = $form.ClientSize.Width; $H = $form.ClientSize.Height
    if ($W -lt 700 -or $H -lt 450) { return }
    $header.SetBounds(0, 0, $W, 96)
    $nav.SetBounds(0, 96, 190, ($H - 96))
    $pw = $W - 190; $ph = $H - 96
    foreach ($pg in @($pageOpt, $pageTools, $pageAbout)) {
        $pg.Top = 96; $pg.Width = $pw; $pg.Height = $ph
        if ($script:Slide -ne $pg) { $pg.Left = 190 }
    }
    # --- оптимизация
    $logH = [Math]::Max(100, [int]($ph * 0.15))
    $logHost.SetBounds(22, ($ph - $logH - 18), ($pw - 44), $logH)
    $logBox.SetBounds(16, 10, ($logHost.Width - 32), ($logHost.Height - 20))
    $barHost.SetBounds(22, ($logHost.Top - 18), ($pw - 44), 10)
    $btnY = $logHost.Top - 18 - 10 - 10 - 62
    $inner = $pw - 44
    $w1 = [int]($inner * 0.42); $w2 = [int]($inner * 0.30); $w3 = $inner - $w1 - $w2 - 24
    $btnApply.SetBounds(18, $btnY, ($w1 + 8), 62)
    $btnRevert.SetBounds((22 + $w1 + 12), ($btnY + 4), $w2, 54)
    $btnAll.SetBounds((22 + $w1 + $w2 + 24), ($btnY + 4), $w3, 54)
    $listHost.SetBounds(22, 54, ($pw - 44), ($btnY - 54 - 8))
    Layout-List
    $btnPick.Left = $pw - 252; $lblWarn.Left = $pw - 252 - 290
    $btnPick2.Left = $pw - 252; $lblWarn2.Left = $pw - 252 - 290
    # --- инструменты
    $toolsHost.SetBounds(22, 84, ($pw - 44), ($ph - 84 - 76))
    Layout-Tools
    $btnFolder.SetBounds(22, ($ph - 62), 240, 46)
    # --- о программе
    $aboutHost.SetBounds(0, 0, $pw, $ph)
    $script:AboutL = Get-AboutLayout $pw
    $L = $script:AboutL
    $btnTg.SetBounds([int]($L.Banner.Right - 250), [int]($L.Banner.Y + 21), 234, 58)
    $btnPackFolder.SetBounds([int]($L.Banner.Right - 200), [int]$L.FooterY, 200, 40)
    $btnLogs.SetBounds([int]($L.Banner.Right - 200 - 12 - 180), [int]$L.FooterY, 180, 40)
    $aboutHost.Invalidate()
    $nav.Invalidate(); $header.Invalidate()
}
$form.Add_Resize({ Update-Layout })

# ---------------------------------------------------------------- анимации (по времени, ~60 кадров/с)
$script:BgTick = 0
$script:Sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:LastMs = 0
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 15
$animTimer.Add_Tick({
    try {
        $now = $script:Sw.ElapsedMilliseconds
        $dt = ($now - $script:LastMs) / 1000.0
        $script:LastMs = $now
        if ($dt -gt 0.1) { $dt = 0.1 }
        $script:Sec = $now / 1000.0
        $sec = $script:Sec
        $kHover = 1 - [Math]::Exp(-$dt * 13)
        $kSlow  = 1 - [Math]::Exp(-$dt * 8)

        if ($script:Closing) {
            $form.Opacity = [Math]::Max(0.0, $form.Opacity - $dt * 4.5)
            if ($form.Opacity -le 0.03) { $animTimer.Stop(); $form.Close(); return }
        } elseif ($form.Opacity -lt 1) {
            $o = $form.Opacity + (1.0 - $form.Opacity) * $kSlow + 0.004
            if ($o -ge 0.995) { $o = 1.0 }
            $form.Opacity = $o
        }

        $pk = ([Math]::Sin($sec * 2.1) + 1) / 2
        $lblLogo2.ForeColor = Mix-Color $cAccent2 $cMagenta (([Math]::Sin($sec * 1.3) + 1) / 2)
        if ($btnApply.Visible) { $btnApply.Tag.Pulse = $pk; if ($btnApply.Tag.Enabled) { $btnApply.Invalidate() } }

        # Telegram и кнопки окна
        $tp = [double]$script:TgP; $tt = [double]$script:TgTarget
        if ([Math]::Abs($tp - $tt) -gt 0.002) {
            $tp = $tp + ($tt - $tp) * (1 - [Math]::Exp(-$dt * 9.5))
            if ([Math]::Abs($tp - $tt) -le 0.002) { $tp = $tt }
            $script:TgP = $tp
        }
        $maxW = 52 + $script:TgTextW + 34
        $header.Invalidate((New-Object System.Drawing.Rectangle(($header.Width - 26 - $maxW - 10), 30, ($maxW + 40), 64)))
        for ($i = 0; $i -lt 3; $i++) {
            $b = $script:WinBtn[$i]
            $n = Ease-To $b.T $b.Target $kHover
            if ($n -ne $b.T) { $b.T = $n; $header.Invalidate((Get-WinBtnRect $i)) }
        }

        # боковое меню
        $chNav = $false
        for ($i = 0; $i -lt $script:NavItems.Count; $i++) {
            $it = $script:NavItems[$i]
            $n = Ease-To $it.T $it.Target $kHover
            if ($n -ne $it.T) { $it.T = $n; $chNav = $true }
            if ($it.Key -eq $script:NavSel) {
                $ty = 18 + 54 * $i
                $ny = $script:NavIndY + ($ty - $script:NavIndY) * (1 - [Math]::Exp(-$dt * 14))
                if ([Math]::Abs($ny - $ty) -lt 0.2) { $ny = $ty }
                if ($ny -ne $script:NavIndY) { $script:NavIndY = $ny; $chNav = $true }
            }
        }
        if ($chNav) { $nav.Invalidate() }

        # список твиков
        if ($pageOpt.Visible) {
            $chList = $false
            foreach ($it in $script:ListItems) {
                if ($it.Kind -ne 'row') { continue }
                $n = Ease-To $it.T $it.Target $kHover; if ($n -ne $it.T) { $it.T = $n; $chList = $true }
                $n = Ease-To $it.K $it.KT (1 - [Math]::Exp(-$dt * 16)); if ($n -ne $it.K) { $it.K = $n; $chList = $true }
            }
            $n = Ease-To $script:SbT $script:SbTarget $kHover; if ($n -ne $script:SbT) { $script:SbT = $n; $chList = $true }
            if (-not $script:SbDrag -and [Math]::Abs($script:ScrollT - $script:Scroll) -gt 0.4) {
                $script:Scroll = $script:Scroll + ($script:ScrollT - $script:Scroll) * (1 - [Math]::Exp(-$dt * 16)); $chList = $true
            } elseif (-not $script:SbDrag -and $script:Scroll -ne $script:ScrollT) { $script:Scroll = $script:ScrollT; $chList = $true }
            if ($chList) { $listHost.Invalidate() }
            if ($barHost.Visible) {
                $script:ProgCur = $script:ProgCur + ($script:ProgTarget - $script:ProgCur) * (1 - [Math]::Exp(-$dt * 7))
                $barHost.Invalidate()
            }
        }

        # инструменты
        if ($pageTools.Visible) {
            $chT = $false
            foreach ($ti in $script:ToolItems) { $n = Ease-To $ti.T $ti.Target $kHover; if ($n -ne $ti.T) { $ti.T = $n; $chT = $true } }
            if ($chT) { $toolsHost.Invalidate() }
        }
        if ($pageAbout.Visible) { $aboutHost.Invalidate((New-Object System.Drawing.Rectangle(0, 0, 200, 200))); if ($script:AboutL) { $aboutHost.Invalidate([System.Drawing.Rectangle]::Round($script:AboutL.Banner)) } }

        # переливание фона (медленно, ~12 кадров/с)
        $script:BgTick++
        if (($script:BgTick % 5) -eq 0) {
            foreach ($pg in @($pageOpt, $pageTools, $pageAbout)) { if ($pg.Visible) { $pg.Invalidate($true) } }
        }

        # кнопки-пилюли
        foreach ($pl in $script:Pills) {
            $st = $pl.Tag
            $n = Ease-To $st.T $st.Target $kHover
            if ($n -ne $st.T) { $st.T = $n; $pl.Invalidate() }
        }

        if ($script:Slide) {
            $dx = $script:Slide.Left - 190
            if ($dx -le 1) { $script:Slide.Left = 190; $script:Slide = $null }
            else { $script:Slide.Left = 190 + [int]($dx * [Math]::Exp(-$dt * 11)) }
        }
    } catch { $script:PaintErr = $_.Exception.Message }
})
$form.Add_FormClosed({
    $animTimer.Stop()
    if ($script:WheelFilter) { try { [System.Windows.Forms.Application]::RemoveMessageFilter($script:WheelFilter) } catch { } }
})

# колесо мыши для списка
if ($script:WheelFilter) {
    $script:WheelFilter.Host1 = $listHost
    $script:WheelFilter.On1 = [Action[int]]{ param($d) Set-ScrollTarget ($script:ScrollT - $d * 0.7) }
    [System.Windows.Forms.Application]::AddMessageFilter($script:WheelFilter)
}

$script:LayoutReady = $true
Set-Mode 'max'
Update-Layout
Update-PackState
Show-Page 'opt'
$script:NavIndY = 18.0
Write-Log 'Выберите твики и нажмите «ОПТИМИЗИРОВАТЬ».' 'dim'
$animTimer.Start()
[void]$form.ShowDialog()
