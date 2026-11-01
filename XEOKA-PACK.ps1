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

$script:Version  = '2.0'
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
       Desc = 'Импортирует и включает схему питания xeoka.pow (если файл повреждён, создаётся встроенная схема XEOKA Performance). Прежняя схема запоминается для отката.';
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
$cTgBlue   = C '#2AABEE'
$cOk       = C '#3DDC97'
$cWarn     = C '#FFB547'
$cErr      = C '#FF5C6C'
$cClear    = [System.Drawing.Color]::Transparent

$fontUi    = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
$fontSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Black', 24)
$fontBtn   = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$fontMono  = New-Object System.Drawing.Font('Consolas', 9.5)
$fontH1    = New-Object System.Drawing.Font('Segoe UI Semibold', 15)

function Mix-Color {
    param($A, $B, [double]$K)
    if ($K -lt 0) { $K = 0 } elseif ($K -gt 1) { $K = 1 }
    $r = [int]($A.R + ($B.R - $A.R) * $K); $g = [int]($A.G + ($B.G - $A.G) * $K); $bl = [int]($A.B + ($B.B - $A.B) * $K)
    return [System.Drawing.Color]::FromArgb($r, $g, $bl)
}

function Enable-DoubleBuffer {
    param($Ctrl)
    try {
        $p = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance')
        $p.SetValue($Ctrl, $true, $null)
    } catch { }
}

function Set-Round {
    param($Ctrl, [int]$R)
    $w = $Ctrl.Width; $h = $Ctrl.Height
    if ($w -le 2 -or $h -le 2) { return }
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $gp.AddArc(0, 0, $d, $d, 180, 90)
    $gp.AddArc(($w - $d), 0, $d, $d, 270, 90)
    $gp.AddArc(($w - $d), ($h - $d), $d, $d, 0, 90)
    $gp.AddArc(0, ($h - $d), $d, $d, 90, 90)
    $gp.CloseFigure()
    $Ctrl.Region = New-Object System.Drawing.Region($gp)
    $gp.Dispose()
}

function Set-RoundAuto {
    param($Ctrl, [int]$R)
    Set-Round $Ctrl $R
    $Ctrl.Add_Resize({ param($s, $e) Set-Round $s $R }.GetNewClosure())
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
    Set-RoundAuto $b 10
    return $b
}

function Open-Url {
    param([string]$Url)
    try { Start-Process $Url } catch { [System.Windows.Forms.MessageBox]::Show("Не удалось открыть ссылку: $Url") | Out-Null }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'XEOKA PACK'
$form.ClientSize = New-Object System.Drawing.Size(1120, 720)
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
$script:IsFull = $true
function Set-FullScreen {
    param([bool]$On)
    $script:IsFull = $On
    $scr = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
    if ($On) {
        $form.Bounds = $scr.Bounds
    } else {
        $wa = $scr.WorkingArea
        $w = [Math]::Min(1180, $wa.Width - 60); $h = [Math]::Min(760, $wa.Height - 60)
        $form.Bounds = New-Object System.Drawing.Rectangle(($wa.X + [int](($wa.Width - $w) / 2)), ($wa.Y + [int](($wa.Height - $h) / 2)), $w, $h)
    }
}

# ---- шапка
$header = New-Object System.Windows.Forms.Panel
$header.SetBounds(0, 0, 1120, 96); $header.BackColor = $cHeadB
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

# градиент шапки + кнопка Telegram (рисуется прямо в шапке)
$script:TgP = 0.0; $script:TgTarget = 0
$script:TgTextW = [System.Windows.Forms.TextRenderer]::MeasureText($script:TgLabel, $fontBold).Width
function Get-TgRect {
    $ep = $script:TgP * $script:TgP * (3 - 2 * $script:TgP)
    $w = 44 + [int](($script:TgTextW + 26) * $ep)
    $x = $header.Width - 26 - $w
    return New-Object System.Drawing.Rectangle($x, 46, $w, 44)
}
$header.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $rc = $this.ClientRectangle
    if ($rc.Width -le 0 -or $rc.Height -le 0) { return }
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc, $cHeadA, $cHeadB, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($br, $rc); $br.Dispose()
    $lineRc = New-Object System.Drawing.Rectangle(0, ($rc.Height - 2), $rc.Width, 2)
    $lb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($lineRc, $cAccent, $cHeadB, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $g.FillRectangle($lb, $lineRc); $lb.Dispose()
    # Telegram
    $p = $script:TgP
    $r = Get-TgRect
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r.Height
    $path.AddArc($r.X, $r.Y, $d, $d, 90, 180)
    $path.AddArc(($r.Right - $d), $r.Y, $d, $d, 270, 180)
    $path.CloseFigure()
    $fillC = Mix-Color $cPanel2 $cAccent (0.08 + 0.34 * $p)
    $fb = New-Object System.Drawing.SolidBrush($fillC)
    $g.FillPath($fb, $path); $fb.Dispose()
    $pen = New-Object System.Drawing.Pen((Mix-Color $cLine $cAccent2 $p), 1.4)
    $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
    if ($p -gt 0.3) {
        $a = ($p - 0.3) / 0.7
        $tr = New-Object System.Drawing.Rectangle(($r.X + 16), $r.Y, ($r.Width - 16 - 48), $r.Height)
        $g.SetClip($tr)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $script:TgLabel, $fontBold, $tr, (Mix-Color $fillC $cText $a), ([System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, NoPadding, SingleLine'))
        $g.ResetClip()
    }
    # значок
    $cx = $r.Right - 22; $cy = $r.Y + 22
    $ib = New-Object System.Drawing.SolidBrush((Mix-Color $cTgBlue $cAccent2 ($p * 0.0)))
    $g.FillEllipse($ib, ($cx - 16), ($cy - 16), 32, 32); $ib.Dispose()
    $pts = @(
        (New-Object System.Drawing.PointF(($cx - 7.5), ($cy + 0.5))),
        (New-Object System.Drawing.PointF(($cx + 7.5), ($cy - 6.5))),
        (New-Object System.Drawing.PointF(($cx + 4.5), ($cy + 7))),
        (New-Object System.Drawing.PointF(($cx + 0.5), ($cy + 2.8))),
        (New-Object System.Drawing.PointF(($cx - 2), ($cy + 6))),
        (New-Object System.Drawing.PointF(($cx - 2.6), ($cy + 1.4)))
    )
    $g.FillPolygon([System.Drawing.Brushes]::White, [System.Drawing.PointF[]]$pts)
})

# ---- кнопки окна
function New-WinButton {
    param([string]$Text, $HoverColor)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.SetBounds(0, 0, 46, 34)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $cClear; $b.ForeColor = $cDim; $b.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 10)
    $b.FlatAppearance.MouseOverBackColor = $HoverColor; $b.FlatAppearance.MouseDownBackColor = $HoverColor
    $b.UseVisualStyleBackColor = $false; $b.TabStop = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_MouseEnter({ $this.ForeColor = $cText }); $b.Add_MouseLeave({ $this.ForeColor = $cDim })
    return $b
}
$btnMin = New-WinButton ([string][char]0x2014) $cPanel2
$btnMin.Add_Click({ $form.WindowState = 'Minimized' })
$btnFs = New-WinButton ([string][char]0x25A1) $cPanel2
$btnFs.Add_Click({ Set-FullScreen (-not $script:IsFull) })
$btnClose = New-WinButton ([string][char]0x2715) $cErr
$script:Closing = $false
$btnClose.Add_Click({ $script:Closing = $true })
$header.Controls.Add($btnMin); $header.Controls.Add($btnFs); $header.Controls.Add($btnClose)

$form.Add_KeyDown({
    if ($_.KeyCode -eq 'F11') { Set-FullScreen (-not $script:IsFull) }
    elseif ($_.KeyCode -eq 'Escape' -and $script:IsFull) { Set-FullScreen $false }
})

# перетаскивание за шапку (в оконном режиме) и клики по Telegram
$script:Drag = $null; $script:DragOrigin = $null
$dragDown = {
    $r = Get-TgRect
    if ($r.Contains($_.Location)) { Open-Url $script:TgUrl; return }
    if (-not $script:IsFull) { $script:Drag = [System.Windows.Forms.Control]::MousePosition; $script:DragOrigin = $form.Location }
}
$dragMove = {
    if ($this -eq $header) {
        $r = Get-TgRect
        if ($r.Contains($_.Location)) { $script:TgTarget = 1; $header.Cursor = [System.Windows.Forms.Cursors]::Hand }
        else { $script:TgTarget = 0; $header.Cursor = [System.Windows.Forms.Cursors]::Default }
    }
    if ($script:Drag -and ([System.Windows.Forms.Control]::MouseButtons -eq 'Left')) {
        $mp = [System.Windows.Forms.Control]::MousePosition
        $form.Location = New-Object System.Drawing.Point(($script:DragOrigin.X + $mp.X - $script:Drag.X), ($script:DragOrigin.Y + $mp.Y - $script:Drag.Y))
    }
}
$dragUp = { $script:Drag = $null }
foreach ($dc in @($header, $lblLogo, $lblLogo2, $lblSub)) { $dc.Add_MouseDown($dragDown); $dc.Add_MouseMove($dragMove); $dc.Add_MouseUp($dragUp) }
$header.Add_MouseLeave({ $script:TgTarget = 0; $header.Cursor = [System.Windows.Forms.Cursors]::Default })

# ---- навигация
$nav = New-Object System.Windows.Forms.Panel
$nav.SetBounds(0, 96, 190, 624); $nav.BackColor = $cNavB
Enable-DoubleBuffer $nav
$nav.Add_Paint({
    $rc = $this.ClientRectangle
    if ($rc.Width -le 0 -or $rc.Height -le 0) { return }
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc, $cNavA, $cNavB, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $_.Graphics.FillRectangle($br, $rc); $br.Dispose()
    $pen = New-Object System.Drawing.Pen($cLine, 1)
    $_.Graphics.DrawLine($pen, ($rc.Width - 1), 0, ($rc.Width - 1), $rc.Height); $pen.Dispose()
})
$form.Controls.Add($nav)

$pages = @{}
$navButtons = @{}
$script:Slide = $null
function Show-Page {
    param([string]$Name)
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $Name) }
    if ($pages[$Name] -and $form.Visible) { $pages[$Name].Left = 190 + 48; $script:Slide = $pages[$Name] }
    foreach ($k in $navButtons.Keys) {
        if ($k -eq $Name) { $navButtons[$k].BackColor = $cPanel2; $navButtons[$k].ForeColor = $cText }
        else { $navButtons[$k].BackColor = $cClear; $navButtons[$k].ForeColor = $cDim }
    }
}
function Add-NavButton {
    param([string]$Key, [string]$Text, [int]$Top)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ('   ' + $Text); $b.TextAlign = 'MiddleLeft'
    $b.SetBounds(12, $Top, 166, 44)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $cPanel2; $b.FlatAppearance.MouseDownBackColor = $cPanel2
    $b.BackColor = $cClear; $b.ForeColor = $cDim; $b.Font = $fontBold
    $b.UseVisualStyleBackColor = $false
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
$lblNavNote.Text = "Перед применением создаётся`nточка восстановления.`nИзменения можно откатить.`n`nF11: полный экран / окно"
$lblNavNote.ForeColor = $cDim; $lblNavNote.Font = $fontSmall; $lblNavNote.BackColor = $cClear
$lblNavNote.SetBounds(16, 440, 170, 90)
$nav.Controls.Add($lblNavNote)
$lblPackPath = New-Object System.Windows.Forms.Label
$lblPackPath.Font = $fontSmall; $lblPackPath.ForeColor = $cDim; $lblPackPath.BackColor = $cClear
$lblPackPath.SetBounds(16, 560, 170, 50)
$nav.Controls.Add($lblPackPath)

function New-Page {
    $pg = New-Object System.Windows.Forms.Panel
    $pg.SetBounds(190, 96, 930, 624); $pg.BackColor = $cBg
    Enable-DoubleBuffer $pg
    $form.Controls.Add($pg)
    return $pg
}

# ---- страница: оптимизация
$pageOpt = New-Page; $pages['opt'] = $pageOpt

$lblH1 = New-Object System.Windows.Forms.Label
$lblH1.Text = 'Что применить'; $lblH1.Font = $fontH1
$lblH1.AutoSize = $true; $lblH1.Location = New-Object System.Drawing.Point(22, 14)
$pageOpt.Controls.Add($lblH1)

$list = New-Object System.Windows.Forms.Panel
$list.SetBounds(16, 54, 898, 330); $list.BackColor = $cBg; $list.AutoScroll = $true
Enable-DoubleBuffer $list
$pageOpt.Controls.Add($list)

$script:Rows = @{}
$script:RowPanels = New-Object System.Collections.ArrayList
$y = 0
function Add-GroupLabel {
    param([string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Font = $fontSmall; $l.ForeColor = $cAccent2; $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(6, ($script:y + 4))
    $list.Controls.Add($l)
    $script:y += 28
}
function Add-TweakRow {
    param($Tw)
    $row = New-Object System.Windows.Forms.Panel
    $row.SetBounds(0, $script:y, 860, 76); $row.BackColor = $cPanel
    Enable-DoubleBuffer $row
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = ''; $cb.AutoSize = $false; $cb.Size = New-Object System.Drawing.Size(24, 24)
    $cb.Location = New-Object System.Drawing.Point(16, 26); $cb.Checked = [bool]$Tw.Default
    $cb.FlatStyle = 'Flat'; $cb.BackColor = $cClear
    $cb.FlatAppearance.BorderColor = $cAccent2; $cb.FlatAppearance.BorderSize = 1
    $cb.FlatAppearance.CheckedBackColor = $cAccent; $cb.FlatAppearance.MouseOverBackColor = $cPanel2
    $cb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $row.Controls.Add($cb)
    $lt = New-Object System.Windows.Forms.Label
    $lt.Text = $Tw.Title; $lt.Font = $fontBold; $lt.AutoSize = $false
    $lt.SetBounds(52, 8, 790, 22); $lt.ForeColor = $cText; $lt.BackColor = $cClear
    $row.Controls.Add($lt)
    $ld = New-Object System.Windows.Forms.Label
    $ld.Text = $Tw.Desc; $ld.Font = $fontSmall; $ld.AutoSize = $false
    $ld.SetBounds(52, 31, 790, 40); $ld.ForeColor = $cDim; $ld.BackColor = $cClear
    $row.Controls.Add($ld)
    $row.Tag = @{ T = 0.0; Target = 0; Cb = $cb; Title = $lt; Desc = $ld }
    $toggle = { $cb.Checked = -not $cb.Checked }.GetNewClosure()
    $lt.Add_Click($toggle); $ld.Add_Click($toggle); $row.Add_Click($toggle)
    $row.Add_MouseEnter({ $this.Tag.Target = 1 }); $row.Add_MouseLeave({ $this.Tag.Target = 0 })
    $lt.Add_MouseEnter({ $this.Parent.Tag.Target = 1 }); $ld.Add_MouseEnter({ $this.Parent.Tag.Target = 1 })
    $lt.Cursor = [System.Windows.Forms.Cursors]::Hand; $ld.Cursor = [System.Windows.Forms.Cursors]::Hand
    $row.Add_Paint({
        $st = $this.Tag
        $g = $_.Graphics
        $on = $st.Cb.Checked
        $c = if ($on) { Mix-Color $cLine $cAccent (0.55 + 0.45 * $st.T) } else { Mix-Color $cPanel $cLine (0.4 + 0.6 * $st.T) }
        $b = New-Object System.Drawing.SolidBrush($c)
        $g.FillRectangle($b, 0, 14, 3, ($this.Height - 28)); $b.Dispose()
    })
    $cb.Add_CheckedChanged({ $this.Parent.Invalidate() })
    Set-RoundAuto $row 9
    $list.Controls.Add($row)
    [void]$script:RowPanels.Add($row)
    $script:Rows[$Tw.Id] = $cb
    $script:y += 82
}
Add-GroupLabel 'РЕКОМЕНДУЕМЫЕ'
foreach ($t in $script:Tweaks) { if ($t.Group -eq 'rec') { Add-TweakRow $t } }
Add-GroupLabel 'ДОПОЛНИТЕЛЬНЫЕ'
foreach ($t in $script:Tweaks) { if ($t.Group -eq 'opt') { Add-TweakRow $t } }

$script:Rows['fse'].Add_CheckedChanged({ if ($script:Rows['fse'].Checked) { $script:Rows['fso'].Checked = $false } })
$script:Rows['fso'].Add_CheckedChanged({ if ($script:Rows['fso'].Checked) { $script:Rows['fse'].Checked = $false } })

# ---- кнопки, прогресс, журнал
$btnApply = New-Button 'ОПТИМИЗИРОВАТЬ' 22 396 330 54 $cAccent $cAccent2 $fontBtn
$pageOpt.Controls.Add($btnApply)
$btnRevert = New-Button 'Откатить последнее' 362 396 200 54 $cPanel2 $cLine $fontBold
$pageOpt.Controls.Add($btnRevert)
$btnAll = New-Button 'Все / никакие' 572 396 182 54 $cPanel2 $cLine $fontBold
$pageOpt.Controls.Add($btnAll)

$barBack = New-Object System.Windows.Forms.Panel
$barBack.SetBounds(22, 462, 880, 8); $barBack.BackColor = $cPanel2; $barBack.Visible = $false
$pageOpt.Controls.Add($barBack)
$barFill = New-Object System.Windows.Forms.Panel
$barFill.SetBounds(0, 0, 0, 8); $barFill.BackColor = $cAccent2
$barBack.Controls.Add($barFill)
Set-RoundAuto $barBack 4

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.SetBounds(22, 482, 880, 100)
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

$script:ProgCur = 0.0; $script:ProgTarget = 0.0
function Set-Progress {
    param([double]$Fraction)
    $script:ProgTarget = [Math]::Max(0, [Math]::Min(1, $Fraction))
    [System.Windows.Forms.Application]::DoEvents()
}

$script:Busy = $false
function Set-Busy {
    param([bool]$On)
    $script:Busy = $On
    $btnApply.Enabled = -not $On; $btnRevert.Enabled = -not $On; $btnAll.Enabled = -not $On
    if ($On) { $btnApply.Text = 'ПРИМЕНЯЮ...'; $btnApply.BackColor = $cPanel2 } else { $btnApply.Text = 'ОПТИМИЗИРОВАТЬ' }
}

$btnAll.Add_Click({
    $any = $false
    foreach ($k in $script:Rows.Keys) { if ($script:Rows[$k].Checked) { $any = $true } }
    foreach ($t in $script:Tweaks) { $script:Rows[$t.Id].Checked = (-not $any) -and [bool]$t.Default }
})

$btnApply.Add_Click({
    if ($script:Busy) { return }
    if (-not (Test-PackRoot $script:Root)) {
        [System.Windows.Forms.MessageBox]::Show("Папка пака не найдена. Нажмите «Указать папку пака» или положите XEOKA-PACK.ps1 в корень пака (рядом с папками «1. База», «2. Драйверы» и т.д.).", 'XEOKA PACK', 'OK', 'Warning') | Out-Null
        return
    }
    $sel = @($script:Tweaks | Where-Object { $script:Rows[$_.Id].Checked })
    if ($sel.Count -eq 0) { Write-Log 'Ничего не выбрано.' 'warn'; return }
    $msg = "Будет применено твиков: $($sel.Count).`n`nПеред этим создаётся точка восстановления. Изменения реестра можно откатить кнопкой «Откатить последнее».`n`nПродолжить?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'XEOKA PACK', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    $logBox.Clear(); $barBack.Visible = $true; $script:ProgCur = 0.0; $barFill.Width = 0; Set-Progress 0
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

# ---- страница: инструменты
$pageTools = New-Page; $pageTools.Visible = $false; $pages['tools'] = $pageTools

$lblT = New-Object System.Windows.Forms.Label
$lblT.Text = 'Инструменты пака'; $lblT.Font = $fontH1
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

$script:ToolCards = New-Object System.Collections.ArrayList
foreach ($tool in $tools) {
    $card = New-Object System.Windows.Forms.Panel
    $card.SetBounds(0, 0, 360, 56)
    $card.BackColor = $cPanel; $card.Tag = @{ T = 0.0; Target = 0 }
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand
    Enable-DoubleBuffer $card
    $ct = New-Object System.Windows.Forms.Label
    $ct.Text = $tool.T; $ct.Font = $fontBold; $ct.AutoSize = $false
    $ct.SetBounds(16, 7, 320, 22); $ct.ForeColor = $cText; $ct.BackColor = $cClear
    $cd = New-Object System.Windows.Forms.Label
    $cd.Text = $tool.D; $cd.Font = $fontSmall; $cd.AutoSize = $false
    $cd.SetBounds(16, 30, 320, 22); $cd.ForeColor = $cDim; $cd.BackColor = $cClear
    $card.Controls.Add($ct); $card.Controls.Add($cd)
    $click = { Invoke-ToolCard $tool }.GetNewClosure()
    $card.Add_Click($click); $ct.Add_Click($click); $cd.Add_Click($click)
    $card.Add_MouseEnter({ $this.Tag.Target = 1 }); $card.Add_MouseLeave({ $this.Tag.Target = 0 })
    $ct.Add_MouseEnter({ $this.Parent.Tag.Target = 1 }); $cd.Add_MouseEnter({ $this.Parent.Tag.Target = 1 })
    $ct.Cursor = [System.Windows.Forms.Cursors]::Hand; $cd.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-RoundAuto $card 9
    $pageTools.Controls.Add($card)
    [void]$script:ToolCards.Add(@{ Tool = $tool; Card = $card; Title = $ct; Desc = $cd })
}
$btnFolder = New-Button 'Открыть папку пака' 22 500 220 42 $cPanel2 $cLine $fontBold
$btnFolder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $script:Root + '"') })
$pageTools.Controls.Add($btnFolder)

# ---- выбор папки пака (если авто-поиск не справился)
$lblWarnOpt = New-Object System.Windows.Forms.Label
$lblWarnOpt.Text = 'Папка пака не найдена'
$lblWarnOpt.Font = $fontSmall; $lblWarnOpt.ForeColor = $cWarn; $lblWarnOpt.AutoSize = $false
$lblWarnOpt.TextAlign = 'MiddleRight'; $lblWarnOpt.SetBounds(400, 16, 280, 28)
$pageOpt.Controls.Add($lblWarnOpt)
$btnPickOpt = New-Button 'Указать папку пака' 690 12 204 34 $cPanel2 $cLine $fontSmall
$pageOpt.Controls.Add($btnPickOpt)
$lblWarnTools = New-Object System.Windows.Forms.Label
$lblWarnTools.Text = 'Папка пака не найдена'
$lblWarnTools.Font = $fontSmall; $lblWarnTools.ForeColor = $cWarn; $lblWarnTools.AutoSize = $false
$lblWarnTools.TextAlign = 'MiddleRight'; $lblWarnTools.SetBounds(400, 16, 280, 28)
$pageTools.Controls.Add($lblWarnTools)
$btnPickTools = New-Button 'Указать папку пака' 690 12 204 34 $cPanel2 $cLine $fontSmall
$pageTools.Controls.Add($btnPickTools)

function Update-PackState {
    $script:FileCache = @{}
    $ok = Test-PackRoot $script:Root
    foreach ($c in @($lblWarnOpt, $btnPickOpt, $lblWarnTools, $btnPickTools)) { $c.Visible = (-not $ok) }
    if ($ok) { $lblPackPath.Text = ('Пак найден:' + "`n" + $script:Root); $lblPackPath.ForeColor = $cDim }
    else { $lblPackPath.Text = 'Пак не найден.'; $lblPackPath.ForeColor = $cWarn }
    foreach ($ci in $script:ToolCards) {
        $path = Find-PackFile $ci.Tool.P $ci.Tool.F
        if ($path) { $ci.Desc.Text = $ci.Tool.D; $ci.Desc.ForeColor = $cDim; $ci.Title.ForeColor = $cText }
        else { $ci.Desc.Text = 'файл не найден: укажите папку пака'; $ci.Desc.ForeColor = $cWarn; $ci.Title.ForeColor = $cDim }
    }
}
$pickHandler = {
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
$btnPickOpt.Add_Click($pickHandler); $btnPickTools.Add_Click($pickHandler)

# ---- страница: о программе
$pageAbout = New-Page; $pageAbout.Visible = $false; $pages['about'] = $pageAbout

$lblA = New-Object System.Windows.Forms.Label
$lblA.Text = 'О программе'; $lblA.Font = $fontH1
$lblA.AutoSize = $true; $lblA.Location = New-Object System.Drawing.Point(22, 14)
$pageAbout.Controls.Add($lblA)
$lblA2 = New-Object System.Windows.Forms.Label
$lblA2.Font = $fontUi; $lblA2.ForeColor = $cText; $lblA2.AutoSize = $false
$lblA2.SetBounds(24, 56, 860, 330)
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

# ---- адаптивная раскладка
function Update-Layout {
    if (-not $script:LayoutReady) { return }
    $W = $form.ClientSize.Width; $H = $form.ClientSize.Height
    if ($W -lt 600 -or $H -lt 400) { return }
    $header.SetBounds(0, 0, $W, 96)
    $btnClose.Left = $W - 46; $btnFs.Left = $W - 92; $btnMin.Left = $W - 138
    $nav.SetBounds(0, 96, 190, ($H - 96))
    $lblNavNote.Top = [Math]::Max(200, ($nav.Height - 190)); $lblPackPath.Top = [Math]::Max(300, ($nav.Height - 90))
    $pw = $W - 190; $ph = $H - 96
    foreach ($pg in @($pageOpt, $pageTools, $pageAbout)) {
        $pg.Top = 96; $pg.Width = $pw; $pg.Height = $ph
        if ($script:Slide -ne $pg) { $pg.Left = 190 }
    }
    # оптимизация
    $logH = [Math]::Max(90, [int]($ph * 0.17))
    $logBox.SetBounds(22, ($ph - $logH - 18), ($pw - 44), $logH)
    $barBack.SetBounds(22, ($logBox.Top - 18), ($pw - 44), 8)
    $btnY = $logBox.Top - 18 - 8 - 14 - 54
    $inner = $pw - 44
    $w1 = [int]($inner * 0.42); $w2 = [int]($inner * 0.30); $w3 = $inner - $w1 - $w2 - 20
    $btnApply.SetBounds(22, $btnY, $w1, 54)
    $btnRevert.SetBounds((22 + $w1 + 10), $btnY, $w2, 54)
    $btnAll.SetBounds((22 + $w1 + $w2 + 20), $btnY, $w3, 54)
    $list.SetBounds(16, 54, ($pw - 32), ($btnY - 54 - 14))
    $rw = $list.ClientSize.Width - 8
    foreach ($row in $script:RowPanels) {
        $row.Width = $rw
        $row.Tag.Title.Width = $rw - 70; $row.Tag.Desc.Width = $rw - 70
    }
    $btnPickOpt.Left = $pw - 226; $lblWarnOpt.Left = $pw - 226 - 290
    $btnPickTools.Left = $pw - 226; $lblWarnTools.Left = $pw - 226 - 290
    # инструменты
    $cols = 2; if ($pw -ge 1250) { $cols = 3 }
    $cw = [int](($pw - 44 - ($cols - 1) * 10) / $cols)
    $i = 0; $ty = 78
    foreach ($ci in $script:ToolCards) {
        $col = $i % $cols
        $ci.Card.SetBounds((22 + $col * ($cw + 10)), $ty, $cw, 56)
        $ci.Title.Width = $cw - 32; $ci.Desc.Width = $cw - 32
        $i++
        if ($col -eq ($cols - 1)) { $ty += 64 }
    }
    if (($i % $cols) -ne 0) { $ty += 64 }
    $btnFolder.Top = $ty + 14
    # о программе
    $lblA2.Width = $pw - 60
}
$form.Add_Resize({ Update-Layout })

# ---- анимации (по времени, ~60 кадров/с)
$script:Sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:LastMs = 0
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 15
$animTimer.Add_Tick({
    $now = $script:Sw.ElapsedMilliseconds
    $dt = ($now - $script:LastMs) / 1000.0
    $script:LastMs = $now
    if ($dt -gt 0.1) { $dt = 0.1 }
    $kHover = 1 - [Math]::Exp(-$dt * 13)
    $kSlow  = 1 - [Math]::Exp(-$dt * 8)
    $sec = $now / 1000.0

    # появление / закрытие окна
    if ($script:Closing) {
        $form.Opacity = [Math]::Max(0.0, $form.Opacity - $dt * 4.5)
        if ($form.Opacity -le 0.03) { $animTimer.Stop(); $form.Close(); return }
    } elseif ($form.Opacity -lt 1) {
        $o = $form.Opacity + (1.0 - $form.Opacity) * $kSlow + 0.004
        if ($o -ge 0.995) { $o = 1.0 }
        $form.Opacity = $o
    }

    # пульсация главной кнопки и логотипа
    $pk = ([Math]::Sin($sec * 2.1) + 1) / 2
    if ($btnApply.Enabled) { $btnApply.BackColor = Mix-Color $cAccent $cAccent2 $pk }
    $lblLogo2.ForeColor = Mix-Color $cAccent2 $cMagenta (([Math]::Sin($sec * 1.3) + 1) / 2)

    # плавная кнопка Telegram
    $tp = [double]$script:TgP; $tt = [double]$script:TgTarget
    if ([Math]::Abs($tp - $tt) -gt 0.002) {
        $tp = $tp + ($tt - $tp) * (1 - [Math]::Exp(-$dt * 9.5))
        if ([Math]::Abs($tp - $tt) -le 0.002) { $tp = $tt }
        $script:TgP = $tp
        $maxW = 44 + $script:TgTextW + 26
        $header.Invalidate((New-Object System.Drawing.Rectangle(($header.Width - 26 - $maxW - 6), 36, ($maxW + 40), 60)))
    }

    # подсветка строк и карточек
    foreach ($pnl in @($script:RowPanels) + @($script:ToolCards | ForEach-Object { $_.Card })) {
        $st = $pnl.Tag
        $tgt = [double]$st.Target
        if ([Math]::Abs($st.T - $tgt) -gt 0.004) {
            $st.T = $st.T + ($tgt - $st.T) * $kHover
            if ([Math]::Abs($st.T - $tgt) -le 0.004) { $st.T = $tgt }
            $pnl.BackColor = Mix-Color $cPanel $cRowHover $st.T
            $pnl.Invalidate()
        }
    }

    # въезд страницы
    if ($script:Slide) {
        $dx = $script:Slide.Left - 190
        if ($dx -le 1) { $script:Slide.Left = 190; $script:Slide = $null }
        else { $script:Slide.Left = 190 + [int]($dx * [Math]::Exp(-$dt * 11)) }
    }

    # плавный прогресс
    if ($barBack.Visible) {
        $script:ProgCur = $script:ProgCur + ($script:ProgTarget - $script:ProgCur) * (1 - [Math]::Exp(-$dt * 7))
        $barFill.Width = [int]($barBack.Width * $script:ProgCur)
    }
})
$form.Add_FormClosed({ $animTimer.Stop() })

$script:LayoutReady = $true
Set-FullScreen $true
Update-Layout
Update-PackState
Show-Page 'opt'
Write-Log 'Выберите твики и нажмите «ОПТИМИЗИРОВАТЬ».' 'dim'
$animTimer.Start()
[void]$form.ShowDialog()
