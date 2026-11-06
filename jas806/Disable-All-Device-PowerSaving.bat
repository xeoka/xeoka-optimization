:ТГ: https://t.me/CMEPT0HOCHbIU

@echo off
setlocal EnableExtensions DisableDelayedExpansion
@echo off
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
fsutil dirty query %SystemDrive% >nul 2>&1
if not errorlevel 1 goto :RunScript
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA 2^>nul') do set "LUA=%%A"
if not defined LUA set "LUA=0x1"
if /i "%LUA%"=="0x0" goto :ElevationImpossible
if "%LUA%"=="0" goto :ElevationImpossible
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -Verb RunAs -ArgumentList '/c ""%~f0""' -WindowStyle Normal" >nul 2>&1
exit /b 0

:ElevationImpossible
echo [ERROR] Admin rights required but UAC is disabled (EnableLUA=0).
echo         Run this .bat from an administrator account.
pause
exit /b 1

:RunScript
set "TMPPS=%TEMP%\Disable-All-Device-PowerSaving-%RANDOM%%RANDOM%.ps1"
type nul > "%TMPPS%" 2>nul
if not exist "%TMPPS%" (
  echo [ERROR] Unable to create temporary PowerShell script:
  echo         "%TMPPS%"
  pause
  exit /b 3
)
set "BATCH_SELF=%~f0"
set "TMPPS_PATH=%TMPPS%"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$src=[System.IO.File]::ReadAllLines($env:BATCH_SELF); $marker=':__PSSCRIPT__'; $idx=[Array]::IndexOf($src,$marker); if($idx -lt 0){ exit 2 }; if($src.Length -le ($idx+1)){ exit 4 }; [System.IO.File]::WriteAllLines($env:TMPPS_PATH,$src[($idx+1)..($src.Length-1)])"
if "%ERRORLEVEL%"=="2" (
  echo [ERROR] Embedded PowerShell payload marker not found.
  pause
  exit /b 2
)
if errorlevel 1 (
  echo [ERROR] Failed to extract embedded PowerShell payload.
  pause
  exit /b 4
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%TMPPS%"
set "EC=%ERRORLEVEL%"
del /f /q "%TMPPS%" >nul 2>&1
echo.
if "%EC%"=="0" (
  echo [SUCCESS] Completed without reported failures.
) else if "%EC%"=="10" (
  echo [WARNING] Partial success: at least 75%% of settings were applied. Exit code: %EC%
) else (
  echo [ERROR] Completed with too many failures. Exit code: %EC%
)
call :ShowCommunityLinks
pause
exit /b %EC%

:ShowCommunityLinks
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$esc=[char]27; Write-Host ''; Write-Host 'Community links:' -ForegroundColor DarkCyan; $links=@(,@('xeoka pack - Telegram: https://t.me/CMEPT0HOCHbIU','https://t.me/CMEPT0HOCHbIU','96')); foreach($link in $links){ [Console]::WriteLine(('  ' + $esc + ']8;;' + $link[1] + $esc + '\' + $esc + '[' + $link[2] + 'm' + $link[0] + $esc + '[0m' + $esc + ']8;;' + $esc + '\')) }"
if not errorlevel 1 exit /b 0
echo.
echo Community links:
echo   xeoka pack - Telegram: https://t.me/CMEPT0HOCHbIU
exit /b 0

:__PSSCRIPT__
$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
param([string]$Area,[string]$Target,[bool]$Success,[string]$Message)
$null = $results.Add([pscustomobject]@{Area=$Area;Target=$Target;Success=$Success;Message=$Message})
}
$pnpNameMap = @{}
try {
@(Get-WmiObject -Class Win32_PnPEntity -ErrorAction Stop) | ForEach-Object {
if ($_.PNPDeviceID -and -not $pnpNameMap.ContainsKey($_.PNPDeviceID)) {
if ([string]::IsNullOrWhiteSpace($_.Name)) {
$pnpNameMap[$_.PNPDeviceID] = $_.PNPDeviceID
} else {
$pnpNameMap[$_.PNPDeviceID] = $_.Name
}
}
}
} catch {
Add-Result 'Environment' 'Win32_PnPEntity' $false $_.Exception.Message
}
function Resolve-DeviceLabel {
param([string]$Id)
if ([string]::IsNullOrWhiteSpace($Id)) { return $Id }
if ($pnpNameMap.ContainsKey($Id)) { return $pnpNameMap[$Id] }
if ($Id -match '^(.*)_\d+$') {
if ($pnpNameMap.ContainsKey($matches[1])) { return $pnpNameMap[$matches[1]] }
}
return $Id
}
function Apply-WmiDisable {
param([string]$ClassName,[string]$Area)
try {
$items = @(Get-WmiObject -Namespace root\wmi -Class $ClassName -ErrorAction Stop)
} catch {
Add-Result $Area $ClassName $false ("Query failed: " + $_.Exception.Message)
return
}
if (-not $items -or $items.Count -eq 0) {
Add-Result $Area $ClassName $true 'No applicable devices found.'
return
}
foreach ($item in $items) {
$instanceName = [string]$item.InstanceName
$label = Resolve-DeviceLabel $instanceName
try {
$current = $false
if ($null -ne $item.Enable) { $current = [bool]$item.Enable }
if ($current) {
$item.Enable = $false
$null = $item.Put()
Add-Result $Area $label $true ("Disabled. InstanceName=" + $instanceName)
} else {
Add-Result $Area $label $true ("Already disabled. InstanceName=" + $instanceName)
}
} catch {
Add-Result $Area $label $false ("Failed. InstanceName=" + $instanceName + " Error=" + $_.Exception.Message)
}
}
}
Apply-WmiDisable -ClassName 'MSPower_DeviceEnable' -Area 'Allow turn-off to save power'
Apply-WmiDisable -ClassName 'MSPower_DeviceWakeEnable' -Area 'Allow wake computer'
try {
$wakeDevices = @(& powercfg -devicequery wake_programmable 2>$null | Where-Object { $_ -and $_.Trim() })
if (-not $wakeDevices -or $wakeDevices.Count -eq 0) {
Add-Result 'Wake disable via powercfg' 'wake_programmable' $true 'No wake-programmable devices found.'
} else {
foreach ($deviceName in $wakeDevices) {
try {
$output = @(& powercfg -devicedisablewake "$deviceName" 2>&1)
if ($LASTEXITCODE -eq 0) {
Add-Result 'Wake disable via powercfg' $deviceName $true 'Wake disabled via powercfg.'
} else {
Add-Result 'Wake disable via powercfg' $deviceName $false (($output -join ' ') -replace '\s+',' ')
}
} catch {
Add-Result 'Wake disable via powercfg' $deviceName $false $_.Exception.Message
}
}
}
} catch {
Add-Result 'Wake disable via powercfg' 'powercfg' $false $_.Exception.Message
}
try {
Import-Module NetAdapter -ErrorAction Stop | Out-Null
} catch {
Add-Result 'Network adapter power management' 'NetAdapter module' $false $_.Exception.Message
}
if (Get-Command Disable-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
try {
$adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop)
} catch {
$adapters = @()
Add-Result 'Network adapter power management' 'Get-NetAdapter' $false $_.Exception.Message
}
if (-not $adapters -or $adapters.Count -eq 0) {
Add-Result 'Network adapter power management' 'Adapters' $true 'No network adapters found.'
} else {
foreach ($adapter in $adapters) {
$target = $adapter.Name
if (-not [string]::IsNullOrWhiteSpace($adapter.InterfaceDescription)) {
$target = $adapter.Name + ' | ' + $adapter.InterfaceDescription
}
try {
Disable-NetAdapterPowerManagement -Name $adapter.Name -IncludeHidden -ErrorAction Stop | Out-Null
Add-Result 'Network adapter power management' $target $true 'Disable-NetAdapterPowerManagement applied.'
} catch {
Add-Result 'Network adapter power management' $target $false $_.Exception.Message
}
}
}
} else {
Add-Result 'Network adapter power management' 'Disable-NetAdapterPowerManagement' $false 'Cmdlet not available on this system.'
}
function Format-RegistryValue {
param($Value,[string]$Kind)
if ($null -eq $Value) { return '<missing>' }
$suffix = ''
if (-not [string]::IsNullOrWhiteSpace($Kind)) {
$suffix = ' (' + $Kind + ')'
}
if ($Value -is [byte[]]) {
if ($Value.Length -eq 0) { return '[]' + $suffix }
return ('[' + (($Value | ForEach-Object { $_.ToString('X2') }) -join ' ') + ']') + $suffix
}
if ($Value -is [System.Array]) {
return ('[' + (($Value | ForEach-Object { [string]$_ }) -join ', ') + ']') + $suffix
}
return ([string]$Value) + $suffix
}
function Convert-RegistryValueToInt {
param($Value)
if ($null -eq $Value) { return $null }
if ($Value -is [byte[]]) {
if ($Value.Length -eq 0) { return 0 }
$buffer = New-Object byte[] 4
[Array]::Copy($Value, $buffer, [Math]::Min($Value.Length, 4))
return [BitConverter]::ToInt32($buffer, 0)
}
if ($Value -is [System.Array]) {
if ($Value.Count -eq 0) { return 0 }
try { return [int]$Value[0] } catch { return $null }
}
try { return [int]$Value } catch { return $null }
}
$usbRoots = @(
'HKLM:\SYSTEM\CurrentControlSet\Enum\USB',
'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR',
'HKLM:\SYSTEM\CurrentControlSet\Enum\USBPRINT',
'HKLM:\SYSTEM\CurrentControlSet\Enum\BTHUSB'
)
$usbValueNames = @(
'EnhancedPowerManagementEnabled',
'SelectiveSuspendEnabled',
'EnableSelectiveSuspend',
'AllowIdleIrpInD3'
)
$usbDeviceParamPaths = @()
foreach ($root in $usbRoots) {
if (Test-Path -LiteralPath $root) {
$found = @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'Device Parameters' } | Select-Object -ExpandProperty PSPath)
if ($found.Count -gt 0) {
$usbDeviceParamPaths += $found
} else {
Add-Result 'USB per-device registry' $root $true 'Root present but no Device Parameters keys found.'
}
} else {
Add-Result 'USB per-device registry' $root $true 'Root not present on this system.'
}
}
$usbDeviceParamPaths = @($usbDeviceParamPaths | Sort-Object -Unique)
if (-not $usbDeviceParamPaths -or $usbDeviceParamPaths.Count -eq 0) {
Add-Result 'USB per-device registry' 'USB roots' $true 'No USB Device Parameters keys found.'
} else {
foreach ($path in $usbDeviceParamPaths) {
try {
$keyItem = Get-Item -LiteralPath $path -ErrorAction Stop
$relative = $keyItem.Name -replace '^HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Enum\\',''
$pnpId = $relative -replace '\\Device Parameters$',''
$label = Resolve-DeviceLabel $pnpId
$notes = New-Object System.Collections.Generic.List[string]
$allOk = $true
foreach ($valueName in $usbValueNames) {
try {
$before = $null
$beforeKind = $null
$valueExists = $false
try {
if ($keyItem.GetValueNames() -contains $valueName) {
$valueExists = $true
$beforeKind = [string]$keyItem.GetValueKind($valueName)
$before = $keyItem.GetValue($valueName, $null, 'DoNotExpandEnvironmentNames')
}
} catch {
$valueExists = $false
$before = $null
$beforeKind = $null
}
if (-not $valueExists) {
New-ItemProperty -LiteralPath $path -Name $valueName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
$notes.Add($valueName + '=0 created')
continue
}
if ($beforeKind -ne 'DWord') {
Remove-ItemProperty -LiteralPath $path -Name $valueName -Force -ErrorAction Stop
New-ItemProperty -LiteralPath $path -Name $valueName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
$notes.Add($valueName + ': ' + (Format-RegistryValue -Value $before -Kind $beforeKind) + ' -> 0 (recreated as DWord)')
continue
}
Set-ItemProperty -LiteralPath $path -Name $valueName -Value 0 -ErrorAction Stop
$beforeInt = Convert-RegistryValueToInt -Value $before
if ($null -eq $beforeInt) {
$notes.Add($valueName + ': ' + (Format-RegistryValue -Value $before -Kind $beforeKind) + ' -> 0')
} elseif ($beforeInt -eq 0) {
$notes.Add($valueName + ' already 0')
} else {
$notes.Add($valueName + ': ' + [string]$beforeInt + ' -> 0')
}
} catch {
$allOk = $false
$notes.Add($valueName + ' failed: ' + $_.Exception.Message)
}
}
Add-Result 'USB per-device registry' ($label + ' | ' + $pnpId) $allOk ($notes -join '; ')
} catch {
Add-Result 'USB per-device registry' $path $false $_.Exception.Message
}
}
}
$areaOrder = @(
'Allow turn-off to save power',
'Allow wake computer',
'Wake disable via powercfg',
'Network adapter power management',
'USB per-device registry',
'Environment'
)
$seenAreas = @{}
foreach ($area in $areaOrder) {
$seenAreas[$area] = $true
$group = @($results | Where-Object { $_.Area -eq $area })
if ($group.Count -gt 0) {
Write-Host ''
Write-Host ('=== ' + $area + ' ===')
foreach ($entry in $group | Sort-Object Target) {
if ($entry.Success) {
Write-Host ('[OK] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Green
} else {
Write-Host ('[FAIL] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Red
}
}
}
}
$extraAreas = @($results | Select-Object -ExpandProperty Area -Unique | Where-Object { -not $seenAreas.ContainsKey($_) })
foreach ($area in $extraAreas) {
$group = @($results | Where-Object { $_.Area -eq $area })
if ($group.Count -gt 0) {
Write-Host ''
Write-Host ('=== ' + $area + ' ===')
foreach ($entry in $group | Sort-Object Target) {
if ($entry.Success) {
Write-Host ('[OK] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Green
} else {
Write-Host ('[FAIL] ' + $entry.Target + ' - ' + $entry.Message) -ForegroundColor Red
}
}
}
}
$successCount = @($results | Where-Object { $_.Success }).Count
$failureCount = @($results | Where-Object { -not $_.Success }).Count
$totalCount = $successCount + $failureCount
$successRatio = 0
if ($totalCount -gt 0) {
$successRatio = $successCount / $totalCount
}
Write-Host ''
if ($failureCount -eq 0) {
Write-Host ('[SUCCESS] Success=' + $successCount + ' Failed=' + $failureCount) -ForegroundColor Green
exit 0
} elseif ($totalCount -gt 0 -and $successRatio -ge 0.75) {
Write-Host ('[WARNING] Partial success. Success=' + $successCount + ' Failed=' + $failureCount + ' SuccessRate=' + [math]::Round(($successRatio * 100), 2) + '%') -ForegroundColor Yellow
exit 10
} else {
Write-Host ('[ERROR] Success=' + $successCount + ' Failed=' + $failureCount + ' SuccessRate=' + [math]::Round(($successRatio * 100), 2) + '%') -ForegroundColor Red
exit 1
}
