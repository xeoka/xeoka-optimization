# ТГ: https://t.me/CMEPT0HOCHbIU

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Resolve-DriverImagePath {
    param([string]$ImagePath)

    if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }

    $p = $ImagePath.Trim()

    if ($p -like '\SystemRoot*') {
        $p = $p -replace '^\\SystemRoot', $env:SystemRoot
    } elseif ($p -like 'System32*') {
        $p = Join-Path $env:SystemRoot $p
    } elseif ($p -match '^\\\?\?\\') {
        $p = $p -replace '^\\\?\?\\', ''
    }

    $p = $p -replace '%SystemRoot%', $env:SystemRoot

    $candidate = $null

    if ($p -match '(".*?\.sys")') {
        $candidate = $Matches[1].Trim('"')
    } elseif ($p -match '([A-Za-z]:\\.*?\.sys)') {
        $candidate = $Matches[1]
    } elseif ($p -match '(\\.*?\.sys)') {
        $candidate = $Matches[1]
    } else {
        $candidate = $p.Trim('"')
    }

    if (Test-Path $candidate) { return $candidate }

    try {
        $alt = Join-Path $env:SystemRoot ($candidate.TrimStart('\'))
        if (Test-Path $alt) { return $alt }
    } catch {}

    return $null
}

function Get-DriverTypeFromBinary {
    param([string]$SysPath)

    if (-not $SysPath -or -not (Test-Path $SysPath)) { return "NDIS" }  

    try {
        $bytes = [System.IO.File]::ReadAllBytes($SysPath)
        $txt   = [System.Text.Encoding]::ASCII.GetString($bytes)

        if ($txt -match 'NetAdapter') { return "NetAdapterCx" }
        if ($txt -match 'NDIS\.SYS')  { return "NDIS" }

        return "Unknown"
    } catch {
        return "NDIS"  
    }
}

function Test-TerminalHyperlinkSupport {
    if ([Console]::IsOutputRedirected) { return $false }

    try {
        if ($Host.UI.SupportsVirtualTerminal) { return $true }
    } catch {}

    if ($env:WT_SESSION) { return $true }
    if ($env:TERM_PROGRAM -match '^(Windows_Terminal|vscode|WezTerm)$') { return $true }

    return $false
}

function New-TerminalHyperlink {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Uri
    )

    $safeText = $Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    $safeUri  = $Uri  -replace '[\x00-\x20\x7F]', ''

    if ([string]::IsNullOrWhiteSpace($safeText) -or [string]::IsNullOrWhiteSpace($safeUri)) {
        return $safeText
    }

    $esc   = [char]27
    $st    = [string]$esc + '\'
    $open  = [string]$esc + ']8;;' + $safeUri + $st
    $close = [string]$esc + ']8;;' + $st
    $style = [string]$esc + '[96;4m'
    $reset = [string]$esc + '[0m'

    return $open + $style + $safeText + $reset + $close
}

function Write-CommunityLinks {
    $links = @(
        [pscustomobject]@{ Text = 'XEOKA PACK - TELEGRAM'; Uri = 'https://t.me/CMEPT0HOCHbIU' }
    )

    Write-Host "Community links:" -ForegroundColor Cyan

    $supportsHyperlinks = Test-TerminalHyperlinkSupport

    foreach ($link in $links) {
        if ($supportsHyperlinks) {
            Write-Host ("  - " + (New-TerminalHyperlink -Text $link.Text -Uri $link.Uri))
        } else {
            Write-Host ("  - " + $link.Text) -ForegroundColor Cyan
        }
    }
}

$results = @()

Get-CimInstance -ClassName Win32_NetworkAdapter |
    Where-Object { $_.PNPDeviceID } |
    ForEach-Object {
        $name = $_.Name
        $pnp  = $_.PNPDeviceID

        $enumKey   = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp"
        $driverKey = (Get-ItemProperty -Path $enumKey -Name "Driver").Driver
        if (-not $driverKey) { return }

        $ndiKey     = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey\Ndi"
        $service    = (Get-ItemProperty -Path $ndiKey -Name "Service").Service
        if (-not $service) { return }
        $service    = $service.TrimEnd('.')

        $svcKey     = "HKLM:\SYSTEM\CurrentControlSet\Services\$service"
        $imagePath  = (Get-ItemProperty -Path $svcKey -Name "ImagePath").ImagePath
        $resolved   = Resolve-DriverImagePath $imagePath
        $type       = Get-DriverTypeFromBinary $resolved

        $results += [pscustomobject]@{
            AdapterName   = $name
            PNPDeviceID   = $pnp
            Service       = $service
            ImagePath     = $imagePath
            ResolvedSys   = $resolved
            DriverType    = $type
        }
    }

if (-not $results -or $results.Count -eq 0) {
    Write-Host "No network adapters found (or registry/service info not accessible)." -ForegroundColor Yellow
} else {
    $results |
        Sort-Object AdapterName |
        Format-Table AdapterName, DriverType, Service, ResolvedSys -AutoSize
}

Write-Host ""
Write-CommunityLinks
Write-Host ""
Read-Host "Press Enter to exit"