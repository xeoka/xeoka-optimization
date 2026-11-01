# ТГ: https://t.me/CMEPT0HOCHbIU

param(
    [ValidateSet("Enable", "Disable")]
    [string]$Action
)

Set-ExecutionPolicy Bypass -Scope Process -Force

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator. Restarting elevated..." -ForegroundColor Red
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Write-Host " - Running as Administrator: OK" -ForegroundColor Green

$ErrorActionPreference = "Continue"

function Write-Status  { param($msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-ErrorMsg{ param($msg) Write-Host "[✗] $msg" -ForegroundColor Red }
function Write-Warn    { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }


$script:CommunityLinks = @(
    [pscustomobject]@{ Label = "XEOKA PACK - TELEGRAM"; Url = "https://t.me/CMEPT0HOCHbIU" }
)

function Test-TerminalHyperlinkSupport {
    try {
        if ([Console]::IsOutputRedirected) { return $false }
    } catch {
        return $false
    }

    try {
        if ($Host -and $Host.UI -and ($null -ne $Host.UI.SupportsVirtualTerminal) -and $Host.UI.SupportsVirtualTerminal) {
            return $true
        }
    } catch { }

    if ($env:WT_SESSION -or $env:TERM_PROGRAM -or ($env:TERM -match 'xterm|screen|tmux|vt100|ansi')) {
        return $true
    }

    return $false
}

function Format-TerminalHyperlink {
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$Url
    )

    if (Test-TerminalHyperlinkSupport) {
        $esc = [char]27
        return "$esc]8;;$Url$esc\$Label$esc]8;;$esc\"
    }

    return "$Label - $Url"
}

function Show-CommunityLinks {
    param([string]$Title = "Community Links")

    Write-Host ""
    Write-Host $Title -ForegroundColor Yellow
    Write-Host "--------------------------------" -ForegroundColor Yellow
    foreach ($link in $script:CommunityLinks) {
        Write-Host "  " -NoNewline
        Write-Host (Format-TerminalHyperlink -Label $link.Label -Url $link.Url) -ForegroundColor Cyan
    }
    Write-Host ""
}

function Enable-TokenPrivilege {
    param([string]$Privilege)
    if (-not ([System.Management.Automation.PSTypeName]'WUB.TokenPriv').Type) {
        Add-Type -Namespace WUB -Name TokenPriv -MemberDefinition @'
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool AdjustTokenPrivileges(
    IntPtr htok, bool disAll, ref TokPriv1Luid newState, int len, IntPtr prev, IntPtr relen);
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
[StructLayout(LayoutKind.Sequential, Pack=1)]
public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
public const int SE_PRIVILEGE_ENABLED  = 0x00000002;
public const int TOKEN_QUERY           = 0x00000008;
public const int TOKEN_ADJUST_PRIVS   = 0x00000020;
public static bool Enable(long processHandle, string privilege) {
    TokPriv1Luid tp; IntPtr htok = IntPtr.Zero;
    bool ok = OpenProcessToken(new IntPtr(processHandle), TOKEN_ADJUST_PRIVS | TOKEN_QUERY, ref htok);
    tp.Count = 1; tp.Luid = 0; tp.Attr = SE_PRIVILEGE_ENABLED;
    ok = LookupPrivilegeValue(null, privilege, ref tp.Luid);
    ok = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    return ok;
}
'@ 
    }
    try {
        $handle = (Get-Process -Id $PID).Handle
        [WUB.TokenPriv]::Enable($handle, $Privilege) | Out-Null
    } catch { }
}

if (-not ([System.Management.Automation.PSTypeName]'WUB.RegAccess').Type) {
    Add-Type -Namespace WUB -Name RegAccess -MemberDefinition @'
[DllImport("advapi32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern int RegOpenKeyEx(
    UIntPtr hKey, string subKey, int ulOptions, int samDesired, out IntPtr phkResult);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegCloseKey(IntPtr hKey);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegSetKeySecurity(
    IntPtr hKey, int SecurityInformation, IntPtr pSecurityDescriptor);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegGetKeySecurity(
    IntPtr hKey, int SecurityInformation,
    IntPtr pSecurityDescriptor, ref uint lpcbSecurityDescriptor);

[DllImport("advapi32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(
    string StringSecurityDescriptor, uint StringSDRevision,
    out IntPtr SecurityDescriptor, out uint SecurityDescriptorSize);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(
    IntPtr SecurityDescriptor, uint RequestedStringSDRevision,
    int SecurityInformation, out IntPtr StringSecurityDescriptor, out uint StringSecurityDescriptorLen);

[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr LocalFree(IntPtr hMem);

public const int OWNER_SECURITY_INFORMATION = 0x00000001;
public const int DACL_SECURITY_INFORMATION  = 0x00000004;
public const int SACL_SECURITY_INFORMATION  = 0x00000008;

public const int REG_OPTION_BACKUP_RESTORE  = 0x00000004;

public const int KEY_READ              = 0x20019;
public const int KEY_WRITE             = 0x20006;
public const int KEY_ALL_ACCESS        = 0xF003F;

public static readonly UIntPtr HKLM = new UIntPtr(0x80000002u);

public static IntPtr OpenWithBypass(string keyPath, int access) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, access, out hKey);
    return (ret == 0) ? hKey : IntPtr.Zero;
}

public static bool SetSddl(IntPtr hKey, string sddl, int siFlags) {
    IntPtr pSd = IntPtr.Zero;
    uint   sdSize = 0;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out pSd, out sdSize))
        return false;
    try {
        return RegSetKeySecurity(hKey, siFlags, pSd) == 0;
    } finally {
        LocalFree(pSd);
    }
}

public static string GetSddl(IntPtr hKey, int siFlags) {
    IntPtr pStr = IntPtr.Zero; uint len = 0;
    if (!ConvertSecurityDescriptorToStringSecurityDescriptor(
            IntPtr.Zero, 1, siFlags, out pStr, out len)) return null;

    LocalFree(pStr);
    return null;
}
'@ 
}

if (-not ([System.Management.Automation.PSTypeName]'WUB.TIHelper').Type) {
    Add-Type -Namespace WUB -Name TIHelper -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);

[DllImport("kernel32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr hObject);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool DuplicateTokenEx(
    IntPtr hExistingToken, uint dwDesiredAccess, IntPtr lpTokenAttributes,
    int ImpersonationLevel, int TokenType, out IntPtr phNewToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ImpersonateLoggedOnUser(IntPtr hToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool RevertToSelf();

[DllImport("advapi32.dll", CharSet=CharSet.Auto, SetLastError=true)]
public static extern int RegOpenKeyEx(
    UIntPtr hKey, string subKey, int ulOptions, int samDesired, out IntPtr phkResult);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegSetValueEx(
    IntPtr hKey, string lpValueName, int Reserved, int dwType, byte[] lpData, int cbData);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegCloseKey(IntPtr hKey);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegSetKeySecurity(
    IntPtr hKey, int SecurityInformation, IntPtr pSecurityDescriptor);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(
    string StringSecurityDescriptor, uint StringSDRevision,
    out IntPtr SecurityDescriptor, out uint SecurityDescriptorSize);

[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr LocalFree(IntPtr hMem);

public static readonly UIntPtr HKLM               = new UIntPtr(0x80000002u);
public const int KEY_ALL_ACCESS                    = 0xF003F;
public const int KEY_SET_VALUE                     = 0x0002;
public const int REG_OPTION_NON_VOLATILE           = 0;
public const int REG_OPTION_BACKUP_RESTORE         = 0x4;
public const int REG_DWORD                         = 4;
public const int OWNER_SECURITY_INFORMATION        = 0x00000001;
public const int DACL_SECURITY_INFORMATION         = 0x00000004;
public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
public const uint PROCESS_QUERY_INFORMATION        = 0x0400;
public const uint TOKEN_ALL_ACCESS                 = 0x000F01FF;
public const uint TOKEN_DUPLICATE                  = 0x0002;
public const uint TOKEN_QUERY                      = 0x0008;
public const uint TOKEN_IMPERSONATE                = 0x0004;
public const int SecurityImpersonation             = 2;
public const int TokenImpersonation                = 2;

public static bool SetRegistryDword(string keyPath, string valueName, int value) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0) return false;
    try {
        byte[] data = BitConverter.GetBytes(value);
        return RegSetValueEx(hKey, valueName, 0, REG_DWORD, data, 4) == 0;
    } finally {
        RegCloseKey(hKey);
    }
}

// Writes raw bytes (REG_BINARY) to a registry value — used to write the service SD directly,
// bypassing SCM access checks that block sc sdset on protected services.
public static bool SetRegistryBinary(string keyPath, string valueName, byte[] data) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0) return false;
    try {
        return RegSetValueEx(hKey, valueName, 0, 3 /*REG_BINARY*/, data, data.Length) == 0;
    } finally {
        RegCloseKey(hKey);
    }
}

// Writes a QWord (REG_QWORD = type 11) to a registry value.
// Tries multiple access modes: normal, backup/restore with full access, backup/restore with minimal access.
public const int REG_QWORD = 11;
public static bool SetRegistryQword(string keyPath, string valueName, long value) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, KEY_SET_VALUE, out hKey);
    if (ret != 0) return false;
    try {
        byte[] data = BitConverter.GetBytes(value);
        return RegSetValueEx(hKey, valueName, 0, REG_QWORD, data, 8) == 0;
    } finally {
        RegCloseKey(hKey);
    }
}

// Converts an SDDL string to the raw binary self-relative security descriptor bytes.
// Returns null on failure.
public static byte[] SddlToBytes(string sddl) {
    IntPtr pSd = IntPtr.Zero; uint sdSize = 0;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out pSd, out sdSize))
        return null;
    try {
        byte[] bytes = new byte[(int)sdSize];
        System.Runtime.InteropServices.Marshal.Copy(pSd, bytes, 0, (int)sdSize);
        return bytes;
    } finally {
        LocalFree(pSd);
    }
}

// Reads the raw binary SD from a service's Security registry value and returns it as SDDL.
// Returns empty string on failure.
[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegQueryValueEx(
    IntPtr hKey, string lpValueName, IntPtr lpReserved,
    out int lpType, byte[] lpData, ref int lpcbData);

[DllImport("advapi32.dll", CharSet=CharSet.Auto, SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(
    byte[] pSecurityDescriptor, uint RequestedStringSDRevision,
    int SecurityInformation, out IntPtr StringSecurityDescriptor,
    out uint StringSecurityDescriptorLen);

public static string ReadServiceSddl(string keyPath) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_NON_VOLATILE, 0x20019 /*KEY_READ*/, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, 0x20019, out hKey);
    if (ret != 0) return "";
    try {
        int    cbData = 0; int dwType = 0;
        RegQueryValueEx(hKey, "Security", IntPtr.Zero, out dwType, null, ref cbData);
        if (cbData <= 0) return "";
        byte[] buf = new byte[cbData];
        if (RegQueryValueEx(hKey, "Security", IntPtr.Zero, out dwType, buf, ref cbData) != 0) return "";
        IntPtr pStr = IntPtr.Zero; uint len = 0;
        if (!ConvertSecurityDescriptorToStringSecurityDescriptor(
                buf, 1, 0x4 /*DACL_SECURITY_INFORMATION*/, out pStr, out len)) return "";
        try   { return System.Runtime.InteropServices.Marshal.PtrToStringUni(pStr); }
        finally { LocalFree(pStr); }
    } finally {
        RegCloseKey(hKey);
    }
}

public static bool ApplySddl(string keyPath, string sddl, int siFlags) {
    IntPtr hKey;
    int ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0)
        ret = RegOpenKeyEx(HKLM, keyPath, REG_OPTION_BACKUP_RESTORE, KEY_ALL_ACCESS, out hKey);
    if (ret != 0) return false;
    try {
        IntPtr pSd; uint sdSize;
        if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out pSd, out sdSize))
            return false;
        try { return RegSetKeySecurity(hKey, siFlags, pSd) == 0; }
        finally { LocalFree(pSd); }
    } finally {
        RegCloseKey(hKey);
    }
}

// ── SCM APIs: used to set the service DACL in SCM memory directly (bypasses sc sdset subprocess)
[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr OpenSCManager(string lpMachineName, string lpDatabaseName, uint dwDesiredAccess);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr OpenService(IntPtr hSCManager, string lpServiceName, uint dwDesiredAccess);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool CloseServiceHandle(IntPtr hSCObject);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool SetServiceObjectSecurity(IntPtr hService, int SecurityInformation, IntPtr pSecurityDescriptor);

// Sets the SCM in-memory DACL for a service AND updates the registry Security value.
// When called from a TI-impersonated thread, OpenService succeeds for PPL-protected services
// because TI has SERVICE_ALL_ACCESS on every service object.
// sddl may be a full SDDL or DACL-only — only the DACL portion is applied.
public static bool SetServiceDacl(string serviceName, string sddl) {
    IntPtr pSd = IntPtr.Zero; uint sdSize = 0;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl, 1, out pSd, out sdSize))
        return false;
    try {
        // Try SC_MANAGER_ALL_ACCESS first, fall back to SC_MANAGER_CONNECT
        uint[] managerAccesses = { 0xF003Fu, 0x0001u };
        // Try SERVICE_ALL_ACCESS first, fall back to WRITE_DAC | READ_CONTROL
        uint[] serviceAccesses = { 0xF01FFu, 0x00040000u | 0x00020000u };
        foreach (uint ma in managerAccesses) {
            IntPtr hScm = OpenSCManager(null, null, ma);
            if (hScm == IntPtr.Zero) continue;
            try {
                foreach (uint sa in serviceAccesses) {
                    IntPtr hSvc = OpenService(hScm, serviceName, sa);
                    if (hSvc == IntPtr.Zero) continue;
                    try {
                        // 0x4 = DACL_SECURITY_INFORMATION
                        bool ok = SetServiceObjectSecurity(hSvc, 0x4, pSd);
                        if (ok) return true;
                    } finally { CloseServiceHandle(hSvc); }
                }
            } finally { CloseServiceHandle(hScm); }
        }
        return false;
    } finally { LocalFree(pSd); }
}
'@ 
}

function Test-ServiceDaclLocked {
    param([string]$ServiceName)

    $sysDenyPattern = '\(D;[^;]*;[^;]+;;;SY\)'

    $sddlRaw = Get-ServiceSddl -ServiceName $ServiceName
    if ($sddlRaw -match $sysDenyPattern) { return $true }

    $regPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"
    try {
        $regSddl = [WUB.TIHelper]::ReadServiceSddl($regPath)
        if ($regSddl -and $regSddl -match $sysDenyPattern) { return $true }
    } catch {}

    try {
        $psPath = "HKLM:\$regPath"
        $secBytes = (Get-ItemProperty -Path $psPath -Name "Security" -ErrorAction Stop).Security
        if ($secBytes -and $secBytes.Length -gt 0) {
            try {
                $pStr = [IntPtr]::Zero
                $len  = 0u
                $ok = [WUB.TIHelper]::ConvertSecurityDescriptorToStringSecurityDescriptor(
                    $secBytes, 1, 4, [ref]$pStr, [ref]$len)   
                if ($ok -and $pStr -ne [IntPtr]::Zero) {
                    try {
                        $sddlStr = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($pStr)
                        if ($sddlStr -match $sysDenyPattern) { return $true }
                    } finally {
                        [WUB.TIHelper]::LocalFree($pStr) | Out-Null
                    }
                }
            } catch {}
        }
    } catch {}

    return $false
}

function Enable-RegistryPrivileges {
    Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
    Enable-TokenPrivilege "SeRestorePrivilege"
    Enable-TokenPrivilege "SeBackupPrivilege"
}

function Clear-LastPInvokeError {
    try { [System.Runtime.InteropServices.Marshal]::SetLastPInvokeError(0) } catch {
        try { [System.Runtime.InteropServices.Marshal]::SetLastWin32Error(0) } catch {}
    }
}

function Invoke-AsTrustedInstaller {
    param([scriptblock]$Action)

    Enable-TokenPrivilege "SeDebugPrivilege"
    try {
        $currentProc = [System.Diagnostics.Process]::GetCurrentProcess()
        [WUB.TokenPriv]::Enable($currentProc.Handle.ToInt64(), "SeDebugPrivilege") | Out-Null
    } catch {}

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        $tiSvc = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
        if (-not $tiSvc) {
            Write-Warn "TrustedInstaller service not found — cannot impersonate"
            return $false
        }
        if ($tiSvc.Status -ne 'Running') {
            try {
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $deadline = (Get-Date).AddSeconds(8)
                while ((Get-Service "TrustedInstaller").Status -ne 'Running' -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Milliseconds 100
                }
            } catch {
                Write-Warn "Could not start TrustedInstaller service (attempt $attempt): $_"
                Start-Sleep -Milliseconds 500
                continue
            }
        }

        $tiProc = $null
        $procDeadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $procDeadline) {
            $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($tiProc) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $tiProc) {
            Write-Warn "TrustedInstaller process not found (attempt $attempt) — forcing service restart"
            try {
                Stop-Service "TrustedInstaller" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $procDeadline2 = (Get-Date).AddSeconds(3)
                while ((Get-Date) -lt $procDeadline2) {
                    $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($tiProc) { break }
                    Start-Sleep -Milliseconds 100
                }
            } catch {
                Write-Warn "  Force-restart failed (attempt $attempt): $_"
            }
            if (-not $tiProc) {
                Start-Sleep -Milliseconds 500
                continue
            }
        }

        $winlogonProc = Get-Process -Name "winlogon" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winlogonProc) {
            Write-Warn "winlogon.exe not found (attempt $attempt) — cannot escalate to SYSTEM"
            Start-Sleep -Milliseconds 500
            continue
        }

        Clear-LastPInvokeError
        $hWinlogon = [WUB.TIHelper]::OpenProcess([WUB.TIHelper]::PROCESS_QUERY_INFORMATION, $false, $winlogonProc.Id)
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $hWinlogon = [WUB.TIHelper]::OpenProcess([WUB.TIHelper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $winlogonProc.Id)
        }
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Warn "OpenProcess(winlogon) failed (attempt $attempt) — error $e"
            Start-Sleep -Milliseconds 500
            continue
        }

        $attemptSucceeded = $false
        try {
            $hSysToken = [IntPtr]::Zero
            $sysAccess = [WUB.TIHelper]::TOKEN_DUPLICATE -bor [WUB.TIHelper]::TOKEN_QUERY -bor [WUB.TIHelper]::TOKEN_IMPERSONATE
            Clear-LastPInvokeError
            if (-not [WUB.TIHelper]::OpenProcessToken($hWinlogon, $sysAccess, [ref]$hSysToken)) {
                Clear-LastPInvokeError
                [WUB.TIHelper]::OpenProcessToken($hWinlogon, [WUB.TIHelper]::TOKEN_ALL_ACCESS, [ref]$hSysToken) | Out-Null
            }
            if ($hSysToken -eq [IntPtr]::Zero) {
                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Warn "OpenProcessToken(winlogon/SYSTEM) failed (attempt $attempt) — error $e"
                Start-Sleep -Milliseconds 500
                continue
            }

            try {
                $hSysImpToken = [IntPtr]::Zero
                Clear-LastPInvokeError
                [WUB.TIHelper]::DuplicateTokenEx(
                    $hSysToken,
                    [WUB.TIHelper]::TOKEN_ALL_ACCESS,
                    [IntPtr]::Zero,
                    [WUB.TIHelper]::SecurityImpersonation,
                    [WUB.TIHelper]::TokenImpersonation,
                    [ref]$hSysImpToken) | Out-Null
                if ($hSysImpToken -eq [IntPtr]::Zero) {
                    $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Write-Warn "DuplicateTokenEx(SYSTEM) failed (attempt $attempt) — error $e"
                    continue
                }

                try {
                    if (-not [WUB.TIHelper]::ImpersonateLoggedOnUser($hSysImpToken)) {
                        $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                        Write-Warn "ImpersonateLoggedOnUser(SYSTEM) failed (attempt $attempt) — error $e"
                        continue
                    }

                    $hProc = [WUB.TIHelper]::OpenProcess([WUB.TIHelper]::PROCESS_QUERY_INFORMATION, $false, $tiProc.Id)
                    if ($hProc -eq [IntPtr]::Zero) {
                        $hProc = [WUB.TIHelper]::OpenProcess([WUB.TIHelper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $tiProc.Id)
                    }
                    if ($hProc -eq [IntPtr]::Zero) {
                        $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                        Write-Warn "OpenProcess(TrustedInstaller) failed as SYSTEM (attempt $attempt) — error $e"
                        [WUB.TIHelper]::RevertToSelf() | Out-Null
                        continue
                    }

                    try {
                        $hTIToken = [IntPtr]::Zero
                        $tiAccess = [WUB.TIHelper]::TOKEN_ALL_ACCESS
                        Clear-LastPInvokeError
                        if (-not [WUB.TIHelper]::OpenProcessToken($hProc, $tiAccess, [ref]$hTIToken)) {
                            $tiAccess = [WUB.TIHelper]::TOKEN_DUPLICATE -bor [WUB.TIHelper]::TOKEN_QUERY -bor [WUB.TIHelper]::TOKEN_IMPERSONATE
                            Clear-LastPInvokeError
                            [WUB.TIHelper]::OpenProcessToken($hProc, $tiAccess, [ref]$hTIToken) | Out-Null
                        }
                        if ($hTIToken -eq [IntPtr]::Zero) {
                            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                            Write-Warn "OpenProcessToken(TrustedInstaller) failed as SYSTEM (attempt $attempt) — error $e"
                            [WUB.TIHelper]::RevertToSelf() | Out-Null
                            continue
                        }

                        try {
                            $hImpToken = [IntPtr]::Zero
                            Clear-LastPInvokeError
                            [WUB.TIHelper]::DuplicateTokenEx(
                                $hTIToken,
                                [WUB.TIHelper]::TOKEN_ALL_ACCESS,
                                [IntPtr]::Zero,
                                [WUB.TIHelper]::SecurityImpersonation,
                                [WUB.TIHelper]::TokenImpersonation,
                                [ref]$hImpToken) | Out-Null
                            if ($hImpToken -eq [IntPtr]::Zero) {
                                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                Write-Warn "DuplicateTokenEx(TrustedInstaller) failed (attempt $attempt) — error $e"
                                [WUB.TIHelper]::RevertToSelf() | Out-Null
                                continue
                            }

                            try {
                                [WUB.TIHelper]::RevertToSelf() | Out-Null
                                if (-not [WUB.TIHelper]::ImpersonateLoggedOnUser($hImpToken)) {
                                    $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                    Write-Warn "ImpersonateLoggedOnUser(TrustedInstaller) failed (attempt $attempt) — error $e"
                                    continue
                                }
                                try {
                                    Enable-RegistryPrivileges
                                    & $Action
                                    $attemptSucceeded = $true
                                    return $true
                                } finally {
                                    [WUB.TIHelper]::RevertToSelf() | Out-Null
                                }
                            } finally {
                                [WUB.TIHelper]::CloseHandle($hImpToken) | Out-Null
                            }
                        } finally {
                            [WUB.TIHelper]::CloseHandle($hTIToken) | Out-Null
                        }
                    } finally {
                        [WUB.TIHelper]::CloseHandle($hProc) | Out-Null
                        if (-not $attemptSucceeded) {
                            [WUB.TIHelper]::RevertToSelf() | Out-Null
                        }
                    }

                } finally {
                    [WUB.TIHelper]::CloseHandle($hSysImpToken) | Out-Null
                }
            } finally {
                [WUB.TIHelper]::CloseHandle($hSysToken) | Out-Null
            }
        } finally {
            [WUB.TIHelper]::CloseHandle($hWinlogon) | Out-Null
        }
    } 

    Write-Warn "All $maxAttempts TrustedInstaller impersonation attempts failed"
    return $false
}

function Test-RegistrySystemDeny {
    param([string]$KeyPath)   
    try {
        $acl = Get-Acl "HKLM:\$KeyPath" -ErrorAction Stop
        foreach ($ace in $acl.Access) {
            if ($ace.IdentityReference -match "SYSTEM" -and
                $ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
                return $true
            }
        }
        return $false
    } catch { return $false }
}

function Test-TaskFileDeny {
    param([string]$TaskPath)  
    $fp = Join-Path "$env:SystemRoot\System32\Tasks" $TaskPath.TrimStart('\')
    if (-not (Test-Path $fp)) { return $false }
    try {
        $acl = Get-Acl $fp -ErrorAction Stop
        $hasSysDeny = $false
        $hasTiDeny  = $false
        foreach ($ace in $acl.Access) {
            if ($ace.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
                if ($ace.IdentityReference -match "SYSTEM")             { $hasSysDeny = $true }
                if ($ace.IdentityReference -match "TrustedInstaller")   { $hasTiDeny  = $true }
            }
        }
        return ($hasSysDeny -and $hasTiDeny)
    } catch { return $false }
}

function Ensure-TaskFileSystemDeny {
    param([string]$TaskPath)  

    $taskFilePath = Join-Path "$env:SystemRoot\System32\Tasks" $TaskPath.TrimStart('\')
    if (-not (Test-Path $taskFilePath)) { return $false }

    try {
        Enable-TokenPrivilege "SeTakeOwnershipPrivilege"

        & takeown.exe /F $taskFilePath 2>&1 | Out-Null
        & icacls.exe  $taskFilePath /grant "Administrators:(F)" 2>&1 | Out-Null

        try {
            $xmlContent = Get-Content -Path $taskFilePath -Raw -ErrorAction Stop
            if ($xmlContent -match '<Enabled>true</Enabled>') {
                $xmlContent = $xmlContent -replace '<Enabled>true</Enabled>', '<Enabled>false</Enabled>'
                Set-Content -Path $taskFilePath -Value $xmlContent -Encoding UTF8 -Force -ErrorAction Stop
            }
        } catch { }

        & icacls.exe $taskFilePath /remove:d "SYSTEM"                      2>&1 | Out-Null
        & icacls.exe $taskFilePath /remove:d "NT SERVICE\TrustedInstaller" 2>&1 | Out-Null

        & icacls.exe $taskFilePath /deny "SYSTEM:(M)"                      2>&1 | Out-Null
        $out = & icacls.exe $taskFilePath /deny "NT SERVICE\TrustedInstaller:(M)" 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}


function Test-TaskFileSystemDeny {
    param([string]$TaskPath)

    $taskFilePath = Join-Path "$env:SystemRoot\System32\Tasks" $TaskPath.TrimStart('\')
    if (-not (Test-Path $taskFilePath)) { return $false }

    try {
        $aclText = (& icacls.exe $taskFilePath 2>$null | Out-String)
        $sysDenied = $aclText -match 'SYSTEM:\(DENY\)'
        $tiDenied  = $aclText -match 'TrustedInstaller:\(DENY\)'
        return ($sysDenied -and $tiDenied)
    } catch {
        return $false
    }
}


function Grant-RegistryKeyAccess {
    param([string]$KeyPath)   
    try {
        Enable-RegistryPrivileges

        $hKey = [WUB.RegAccess]::OpenWithBypass($KeyPath, [WUB.RegAccess]::KEY_ALL_ACCESS)
        if ($hKey -ne [IntPtr]::Zero) {
            $sddl    = "O:BAD:PAI(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)"
            $siFlags = [WUB.RegAccess]::OWNER_SECURITY_INFORMATION -bor `
                       [WUB.RegAccess]::DACL_SECURITY_INFORMATION
            $ok = [WUB.RegAccess]::SetSddl($hKey, $sddl, $siFlags)
            [WUB.RegAccess]::RegCloseKey($hKey) | Out-Null
            if ($ok) { return $true }
        }

        try {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                $KeyPath,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                [System.Security.AccessControl.RegistryRights]::TakeOwnership)
            if ($key) {
                $admins = [System.Security.Principal.NTAccount]"BUILTIN\Administrators"
                $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
                $acl.SetOwner($admins); $key.SetAccessControl($acl); $key.Close()
                $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    $KeyPath,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions)
                $acl2 = $key.GetAccessControl()
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $admins,
                    [System.Security.AccessControl.RegistryRights]::FullControl,
                    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                     [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow)
                $acl2.SetAccessRule($rule); $key.SetAccessControl($acl2); $key.Close()
                return $true
            }
        } catch { }
    } catch {
    }

    Write-Warn "Attempting TrustedInstaller token impersonation for key: $KeyPath"
    $script:tiOk = $false
    $tiRan = Invoke-AsTrustedInstaller {
        $sddl    = "O:BAD:PAI(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)"
        $siFlags = [WUB.TIHelper]::OWNER_SECURITY_INFORMATION -bor [WUB.TIHelper]::DACL_SECURITY_INFORMATION
        $script:tiOk = [WUB.TIHelper]::ApplySddl($KeyPath, $sddl, $siFlags)
    }
    if ($tiRan -and $script:tiOk) {
        Write-Success "TrustedInstaller impersonation succeeded — Admins now own: $KeyPath"
        return $true
    }
    Write-Warn "TrustedInstaller impersonation did not succeed for: $KeyPath"
    return $false
}

function Add-RegistrySystemDeny {
    param(
        [string]$KeyPath,
        [string]$ExtraServiceSid = ""
    )

    $denySddl = $script:DENY_SDDL
    if ($ExtraServiceSid -ne "") {
        $denySddl += "(D;OICI;KA;;;$ExtraServiceSid)"
    }

    $siFlags   = [WUB.RegAccess]::OWNER_SECURITY_INFORMATION -bor `
                 [WUB.RegAccess]::DACL_SECURITY_INFORMATION

    try {
        Enable-RegistryPrivileges
        $hKey = [WUB.RegAccess]::OpenWithBypass($KeyPath, [WUB.RegAccess]::KEY_ALL_ACCESS)
        if ($hKey -ne [IntPtr]::Zero) {
            $ok = [WUB.RegAccess]::SetSddl($hKey, $denySddl, $siFlags)
            [WUB.RegAccess]::RegCloseKey($hKey) | Out-Null
            if ($ok) { return $true }
        }
    } catch { }

    try {
        $granted = Grant-RegistryKeyAccess -KeyPath $KeyPath
        if ($granted) {
            Enable-RegistryPrivileges
            $hKey2 = [WUB.RegAccess]::OpenWithBypass($KeyPath, [WUB.RegAccess]::KEY_ALL_ACCESS)
            if ($hKey2 -ne [IntPtr]::Zero) {
                $ok2 = [WUB.RegAccess]::SetSddl($hKey2, $denySddl, $siFlags)
                [WUB.RegAccess]::RegCloseKey($hKey2) | Out-Null
                if ($ok2) { return $true }
            }
        }
    } catch { }

    $script:tiDenyOk = $false
    try {
        $capturedSddl = $denySddl   
        $tiRan = Invoke-AsTrustedInstaller {
            $tiSiFlags = [WUB.TIHelper]::OWNER_SECURITY_INFORMATION -bor `
                         [WUB.TIHelper]::DACL_SECURITY_INFORMATION
            $script:tiDenyOk = [WUB.TIHelper]::ApplySddl($KeyPath, $capturedSddl, $tiSiFlags)
        }
        if ($tiRan -and $script:tiDenyOk) { return $true }
    } catch { }

    return $false
}


function Test-RegistrySystemDeny {
    param([string]$KeyPath)
    try {
        $acl = Get-Acl -Path ("Registry::HKEY_LOCAL_MACHINE\" + $KeyPath) -ErrorAction Stop
        $sddl = $acl.Sddl
        $sysDenied = $sddl -match '\(D;[^)]*;;;SY\)'
        $tiEscaped = [regex]::Escape($script:TI_SID)
        $tiDenied  = $sddl -match "\(D;[^)]*;;;$tiEscaped\)"
        return ($sysDenied -and $tiDenied)
    } catch {
        return $false
    }
}


function Remove-RegistrySystemDeny {
    param([string]$KeyPath)

    $allowSddl = $script:ALLOW_SDDL   
    $siFlags   = [WUB.RegAccess]::OWNER_SECURITY_INFORMATION -bor `
                 [WUB.RegAccess]::DACL_SECURITY_INFORMATION

    try {
        Enable-RegistryPrivileges
        $hKey = [WUB.RegAccess]::OpenWithBypass($KeyPath, [WUB.RegAccess]::KEY_ALL_ACCESS)
        if ($hKey -ne [IntPtr]::Zero) {
            $ok = [WUB.RegAccess]::SetSddl($hKey, $allowSddl, $siFlags)
            [WUB.RegAccess]::RegCloseKey($hKey) | Out-Null
            if ($ok) { return $true }
        }
    } catch { }

    try {
        $granted = Grant-RegistryKeyAccess -KeyPath $KeyPath
        if ($granted) {
            Enable-RegistryPrivileges
            $hKey2 = [WUB.RegAccess]::OpenWithBypass($KeyPath, [WUB.RegAccess]::KEY_ALL_ACCESS)
            if ($hKey2 -ne [IntPtr]::Zero) {
                $ok2 = [WUB.RegAccess]::SetSddl($hKey2, $allowSddl, $siFlags)
                [WUB.RegAccess]::RegCloseKey($hKey2) | Out-Null
                if ($ok2) { return $true }
            }
        }
    } catch { }

    $script:tiRemOk = $false
    try {
        $tiRan = Invoke-AsTrustedInstaller {
            $tiSiFlags = [WUB.TIHelper]::OWNER_SECURITY_INFORMATION -bor `
                         [WUB.TIHelper]::DACL_SECURITY_INFORMATION
            $script:tiRemOk = [WUB.TIHelper]::ApplySddl($KeyPath, "O:BAD:PAI(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)", $tiSiFlags)
        }
        if ($tiRan -and $script:tiRemOk) { return $true }
    } catch { }

    return $false
}

$script:TI_SID = "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"

$script:DENY_SDDL  = "O:BAD:PAI(A;OICI;KA;;;BA)" +
                     "(D;OICI;KA;;;SY)" +
                     "(D;OICI;KA;;;$script:TI_SID)" +
                     "(D;OICI;KA;;;LS)" +
                     "(D;OICI;KA;;;NS)"
$script:ALLOW_SDDL = "O:BAD:PAI(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)"

function Get-ServiceSid {
    param([string]$ServiceName)
    $bytes = [Text.Encoding]::Unicode.GetBytes($ServiceName.ToUpper())
    $sha1  = [Security.Cryptography.SHA1]::Create()
    $hash  = $sha1.ComputeHash($bytes)
    $sha1.Dispose()
    $rids  = New-Object UInt32[] 5
    [Buffer]::BlockCopy($hash, 0, $rids, 0, 20)
    return "S-1-5-80-{0}-{1}-{2}-{3}-{4}" -f $rids[0],$rids[1],$rids[2],$rids[3],$rids[4]
}

$script:SvcSids = @{
    wuauserv     = Get-ServiceSid "wuauserv"
    BITS         = Get-ServiceSid "BITS"
    WaaSMedicSvc = Get-ServiceSid "WaaSMedicSvc"
    UsoSvc       = Get-ServiceSid "UsoSvc"
    DoSvc        = Get-ServiceSid "DoSvc"
}

$script:SvcDaclBackupKey = "HKLM:\SOFTWARE\WUBlocker\ServiceSDDL"

$script:TriggerBackupKey = "HKLM:\SOFTWARE\WUBlocker\TriggerBackup"
$script:FailureBackupKey = "HKLM:\SOFTWARE\WUBlocker\FailureBackup"

function Export-RegistrySubtree {
    param([string]$PSPath)  
    try {
        if (-not (Test-Path $PSPath)) { return $null }
        $tmpFile = [IO.Path]::GetTempFileName()
        $regPath = $PSPath -replace '^HKLM:\\', 'HKLM\'
        $r = & reg.exe export $regPath $tmpFile /y 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpFile)) {
            $content = Get-Content $tmpFile -Raw -ErrorAction Stop
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
            return $content
        }
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    } catch {}
    return $null
}

function Remove-ServiceTriggerInfo {
    param([string]$ServiceName)

    if (-not (Test-Path $script:TriggerBackupKey)) {
        try { New-Item -Path $script:TriggerBackupKey -Force | Out-Null } catch {}
    }

    $allPaths = Get-AllControlSetPaths -ServiceName $ServiceName
    $backupDone = $false

    foreach ($relPath in $allPaths) {
        $triggerPath = "HKLM:\$relPath\TriggerInfo"
        if (-not (Test-Path $triggerPath)) { continue }

        if (-not $backupDone) {
            $export = Export-RegistrySubtree -PSPath $triggerPath
            if ($export) {
                try {
                    New-ItemProperty -Path $script:TriggerBackupKey -Name $ServiceName -Value $export -PropertyType String -Force | Out-Null
                    $backupDone = $true
                } catch {}
            }
        }

        try {
            Enable-RegistryPrivileges
            Grant-RegistryKeyAccess -KeyPath "$relPath\TriggerInfo" | Out-Null
        } catch {}

        try {
            Remove-Item -Path $triggerPath -Recurse -Force -ErrorAction Stop
            Write-Success "  Deleted TriggerInfo subkey: $relPath\TriggerInfo"
        } catch {
            $regRelPath = $relPath -replace '\\', '\'
            & reg.exe delete "HKLM\$regRelPath\TriggerInfo" /f 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  Deleted TriggerInfo (reg.exe): $relPath\TriggerInfo"
            } else {
                $tiDelOk = $false
                $captured = "$relPath\TriggerInfo"
                Invoke-AsTrustedInstaller {
                    try {
                        Remove-Item -Path "HKLM:\$captured" -Recurse -Force -ErrorAction Stop
                        $script:tiDelOk = $true
                    } catch {
                        & reg.exe delete "HKLM\$($captured -replace '\\','\')" /f 2>&1 | Out-Null
                        $script:tiDelOk = ($LASTEXITCODE -eq 0)
                    }
                } | Out-Null
                if ($tiDelOk) {
                    Write-Success "  Deleted TriggerInfo (TI): $relPath\TriggerInfo"
                } else {
                    Write-Warn   "  Could not delete TriggerInfo: $relPath\TriggerInfo"
                }
            }
        }
    }

    $r = & sc.exe triggerinfo $ServiceName delete 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  Cleared SCM triggers (sc triggerinfo delete): $ServiceName"
    }
}

function Restore-ServiceTriggerInfo {
    param([string]$ServiceName)
    $export = $null
    try { $export = (Get-ItemProperty -Path $script:TriggerBackupKey -Name $ServiceName -ErrorAction Stop).$ServiceName } catch {}
    if (-not $export) { return }

    $tmpFile = [IO.Path]::GetTempFileName() + ".reg"
    try {
        Set-Content -Path $tmpFile -Value $export -Encoding Unicode -Force
        $r = & reg.exe import $tmpFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  Restored TriggerInfo from backup: $ServiceName"
            Remove-ItemProperty -Path $script:TriggerBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue
        } else {
            Write-Warn "  Could not restore TriggerInfo: $ServiceName"
        }
    } catch {
        Write-Warn "  TriggerInfo restore failed: $ServiceName — $_"
    } finally {
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

function Neutralize-ServiceRecovery {
    param([string]$ServiceName)

    if (-not (Test-Path $script:FailureBackupKey)) {
        try { New-Item -Path $script:FailureBackupKey -Force | Out-Null } catch {}
    }

    $allPaths = Get-AllControlSetPaths -ServiceName $ServiceName
    $backupDone = $false

    foreach ($relPath in $allPaths) {
        $psPath = "HKLM:\$relPath"
        if (-not (Test-Path $psPath)) { continue }

        if (-not $backupDone) {
            try {
                $fa = (Get-ItemProperty -Path $psPath -Name "FailureActions" -ErrorAction Stop).FailureActions
                if ($fa -and $fa.Length -gt 0) {
                    $b64 = [Convert]::ToBase64String($fa)
                    New-ItemProperty -Path $script:FailureBackupKey -Name $ServiceName -Value $b64 -PropertyType String -Force | Out-Null
                    $backupDone = $true
                }
            } catch {}
        }

        $zeroFA = New-Object byte[] 36
        try {
            Set-ItemProperty -Path $psPath -Name "FailureActions" -Value $zeroFA -Type Binary -Force -ErrorAction Stop
        } catch {
            $capturedPath = $relPath
            Invoke-AsTrustedInstaller {
                [WUB.TIHelper]::SetRegistryBinary($capturedPath, "FailureActions", (New-Object byte[] 36)) | Out-Null
            } | Out-Null
        }

        try { Remove-ItemProperty -Path $psPath -Name "FailureCommand" -Force -ErrorAction SilentlyContinue } catch {}
    }

    & sc.exe failure $ServiceName reset= 0 actions= "///" 2>&1 | Out-Null
    & sc.exe failureflag $ServiceName 0 2>&1 | Out-Null

    Write-Success "  Neutralised recovery/FailureActions: $ServiceName"
}

function Restore-ServiceRecovery {
    param([string]$ServiceName)
    $b64 = $null
    try { $b64 = (Get-ItemProperty -Path $script:FailureBackupKey -Name $ServiceName -ErrorAction Stop).$ServiceName } catch {}
    if (-not $b64) { return }

    try {
        $fa = [Convert]::FromBase64String($b64)
        $psPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        Set-ItemProperty -Path $psPath -Name "FailureActions" -Value $fa -Type Binary -Force -ErrorAction Stop
        Write-Success "  Restored FailureActions from backup: $ServiceName"
        Remove-ItemProperty -Path $script:FailureBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warn "  FailureActions restore failed: $ServiceName — $_"
    }
}

$script:WaaSMedicBackupSuffix = ".wublocker.bak"

function Harden-WaaSMedicBinaries {
    Write-Status "Hardening WaaSMedicSvc binaries (rename + deny)..."

    $sys32 = "$env:SystemRoot\System32"
    $targets = @(
        "$sys32\WaaSMedicSvc.dll",
        "$sys32\WaaSMedic.exe",
        "$sys32\WaaSMedicAgent.exe",
        "$sys32\WaaSMedicCapsule.dll",
        "$sys32\WaaSMedicPS.dll"
    )

    foreach ($filePath in $targets) {
        if (-not (Test-Path $filePath)) { continue }

        $bakPath = $filePath + $script:WaaSMedicBackupSuffix

        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $filePath /A 2>&1 | Out-Null
            & icacls.exe $filePath /grant "Administrators:(F)" 2>&1 | Out-Null

            if (-not (Test-Path $bakPath)) {
                Rename-Item -Path $filePath -NewName (Split-Path $bakPath -Leaf) -Force -ErrorAction Stop
                Write-Success "  Renamed: $(Split-Path $filePath -Leaf) → $(Split-Path $bakPath -Leaf)"
            } else {
                Remove-Item -Path $filePath -Force -ErrorAction Stop
                Write-Success "  Removed duplicate: $(Split-Path $filePath -Leaf) (backup already exists)"
            }

            if (Test-Path $bakPath) {
                & icacls.exe $bakPath /deny "SYSTEM:(F)" 2>&1 | Out-Null
                & icacls.exe $bakPath /deny "NT SERVICE\TrustedInstaller:(F)" 2>&1 | Out-Null
                Write-Success "  Deny ACL applied: $(Split-Path $bakPath -Leaf)"
            }
        } catch {
            Write-Warn "  Could not harden $(Split-Path $filePath -Leaf): $_"
            try {
                if (Test-Path $filePath) {
                    & icacls.exe $filePath /deny "SYSTEM:(F)" 2>&1 | Out-Null
                    & icacls.exe $filePath /deny "NT SERVICE\TrustedInstaller:(F)" 2>&1 | Out-Null
                    Write-Success "  In-place deny ACL applied: $(Split-Path $filePath -Leaf)"
                }
            } catch {
                Write-Warn "  In-place deny also failed: $(Split-Path $filePath -Leaf)"
            }
        }
    }
}

function Restore-WaaSMedicBinaries {
    Write-Status "Restoring WaaSMedicSvc binaries..."

    $sys32 = "$env:SystemRoot\System32"
    $targets = @(
        "$sys32\WaaSMedicSvc.dll",
        "$sys32\WaaSMedic.exe",
        "$sys32\WaaSMedicAgent.exe",
        "$sys32\WaaSMedicCapsule.dll",
        "$sys32\WaaSMedicPS.dll"
    )

    foreach ($filePath in $targets) {
        $bakPath = $filePath + $script:WaaSMedicBackupSuffix
        if (-not (Test-Path $bakPath)) { continue }

        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $bakPath /A 2>&1 | Out-Null
            & icacls.exe $bakPath /grant "Administrators:(F)" 2>&1 | Out-Null
            & icacls.exe $bakPath /remove:d "SYSTEM" 2>&1 | Out-Null
            & icacls.exe $bakPath /remove:d "NT SERVICE\TrustedInstaller" 2>&1 | Out-Null

            if (-not (Test-Path $filePath)) {
                Rename-Item -Path $bakPath -NewName (Split-Path $filePath -Leaf) -Force -ErrorAction Stop
                Write-Success "  Restored: $(Split-Path $filePath -Leaf)"
            } else {
                Remove-Item -Path $bakPath -Force -ErrorAction SilentlyContinue
                Write-Success "  Original already present, removed backup: $(Split-Path $bakPath -Leaf)"
            }
        } catch {
            Write-Warn "  Could not restore $(Split-Path $filePath -Leaf): $_"
        }
    }
}

function Set-WaaSMedicImagePathNull {
    Write-Status "Nullifying WaaSMedicSvc ImagePath across all ControlSets..."

    $csPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
    if (Test-Path $csPath) {
        try {
            $origImgPath = (Get-ItemProperty -Path $csPath -Name "ImagePath" -ErrorAction Stop).ImagePath
            if ($origImgPath -and $origImgPath -ne "" -and $origImgPath -notmatch "WUBlockerNullified") {
                $backupKey = "HKLM:\SOFTWARE\WUBlocker"
                if (-not (Test-Path $backupKey)) { New-Item -Path $backupKey -Force | Out-Null }
                Set-ItemProperty -Path $backupKey -Name "WaaSMedicImagePathBackup" -Value $origImgPath -Type String -Force
            }
        } catch {}
    }

    $allPaths = Get-AllControlSetPaths -ServiceName "WaaSMedicSvc"
    foreach ($path in $allPaths) {
        $label = ($path -split '\\')[1]
        $nullPath = "%SystemRoot%\System32\svchost.exe -k WUBlockerNullified"
        try {
            Set-ItemProperty -Path "HKLM:\$path" -Name "ImagePath" -Value $nullPath -Type ExpandString -Force -ErrorAction SilentlyContinue
        } catch {}
        $capturedPath = $path
        $capturedNull = $nullPath
        try {
            Invoke-AsTrustedInstaller {
                $strBytes = [Text.Encoding]::Unicode.GetBytes($capturedNull + "`0")
                $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Default')
                $sk = $hklm.OpenSubKey(($capturedPath), $true)
                if ($sk) { $sk.SetValue("ImagePath", $capturedNull, 'ExpandString'); $sk.Close() }
                $hklm.Close()
            } | Out-Null
        } catch {}
        Write-Success "  [$label] ImagePath nullified: WaaSMedicSvc"
    }
}

function Restore-WaaSMedicImagePath {
    Write-Status "Restoring WaaSMedicSvc ImagePath..."
    $backupKey = "HKLM:\SOFTWARE\WUBlocker"
    $origImgPath = $null
    try {
        $origImgPath = (Get-ItemProperty -Path $backupKey -Name "WaaSMedicImagePathBackup" -ErrorAction Stop).WaaSMedicImagePathBackup
    } catch {}

    if (-not $origImgPath) {
        $origImgPath = "%SystemRoot%\system32\svchost.exe -k wusvcs -p"
        Write-Warn "  No ImagePath backup found, using default: $origImgPath"
    }

    $allPaths = Get-AllControlSetPaths -ServiceName "WaaSMedicSvc"
    foreach ($path in $allPaths) {
        $label = ($path -split '\\')[1]
        try {
            Set-ItemProperty -Path "HKLM:\$path" -Name "ImagePath" -Value $origImgPath -Type ExpandString -Force -ErrorAction SilentlyContinue
        } catch {}
        Write-Success "  [$label] ImagePath restored: WaaSMedicSvc"
    }

    try { Remove-ItemProperty -Path $backupKey -Name "WaaSMedicImagePathBackup" -Force -ErrorAction SilentlyContinue } catch {}
}

$script:UpfcBackupSuffix = ".wublocker.bak"

function Harden-UpfcAndWaaSXml {
    Write-Status "Hardening upfc.exe + SIHClient.exe (rename + deny)..."

    $sys32 = "$env:SystemRoot\System32"
    $upfcTargets = @(
        "$sys32\upfc.exe",
        "$sys32\SIHClient.exe"
    )

    foreach ($filePath in $upfcTargets) {
        if (-not (Test-Path $filePath)) {
            $bakTest = $filePath + $script:UpfcBackupSuffix
            if (Test-Path $bakTest) {
                Write-Success "  Already hardened: $(Split-Path $filePath -Leaf)"
            } else {
                Write-Warn "  Not found (skipped): $(Split-Path $filePath -Leaf)"
            }
            continue
        }

        $bakPath = $filePath + $script:UpfcBackupSuffix
        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $filePath /A 2>&1 | Out-Null
            & icacls.exe $filePath /grant "Administrators:(F)" 2>&1 | Out-Null

            if (-not (Test-Path $bakPath)) {
                Rename-Item -Path $filePath -NewName (Split-Path $bakPath -Leaf) -Force -ErrorAction Stop
                Write-Success "  Renamed: $(Split-Path $filePath -Leaf) → $(Split-Path $bakPath -Leaf)"
            } else {
                Remove-Item -Path $filePath -Force -ErrorAction Stop
                Write-Success "  Removed duplicate: $(Split-Path $filePath -Leaf) (backup already exists)"
            }

            if (Test-Path $bakPath) {
                & icacls.exe $bakPath /deny "SYSTEM:(F)" 2>&1 | Out-Null
                & icacls.exe $bakPath /deny "NT SERVICE\TrustedInstaller:(F)" 2>&1 | Out-Null
                Write-Success "  Deny ACL applied: $(Split-Path $bakPath -Leaf)"
            }
        } catch {
            Write-Warn "  Could not rename $(Split-Path $filePath -Leaf): $_ — applying in-place deny"
            try {
                if (Test-Path $filePath) {
                    & icacls.exe $filePath /deny "SYSTEM:(F)" 2>&1 | Out-Null
                    & icacls.exe $filePath /deny "NT SERVICE\TrustedInstaller:(F)" 2>&1 | Out-Null
                    Write-Success "  In-place deny ACL applied: $(Split-Path $filePath -Leaf)"
                }
            } catch {
                Write-Warn "  In-place deny also failed: $(Split-Path $filePath -Leaf)"
            }
        }
    }

    Write-Status "Patching WaaS XML service definitions to declare disabled state..."

    $waasDir = "$env:SystemRoot\WaaS\Services"
    if (Test-Path $waasDir) {
        $xmlFiles = Get-ChildItem -Path $waasDir -Filter "*.xml" -ErrorAction SilentlyContinue
        foreach ($xmlFile in $xmlFiles) {
            $capturedXmlPath = $xmlFile.FullName
            $capturedBakPath = $xmlFile.FullName + $script:UpfcBackupSuffix

            $adminOk = $false
            try {
                Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
                Enable-TokenPrivilege "SeRestorePrivilege"
                & takeown.exe /F $capturedXmlPath /A 2>&1 | Out-Null
                & icacls.exe $capturedXmlPath /grant "Administrators:(F)" 2>&1 | Out-Null

                $content = [System.IO.File]::ReadAllText($capturedXmlPath)
                $modified = $false

                if (-not (Test-Path $capturedBakPath)) {
                    [System.IO.File]::Copy($capturedXmlPath, $capturedBakPath, $false) 2>$null
                }

                if ($content -match 'start\s*=\s*"(demand|auto|delayedAuto)"') {
                    $content = $content -replace 'start\s*=\s*"(demand|auto|delayedAuto)"', 'start="disabled"'
                    $modified = $true
                }
                if ($content -match '<enabled>\s*true\s*</enabled>') {
                    $content = $content -replace '<enabled>\s*true\s*</enabled>', '<enabled>false</enabled>'
                    $modified = $true
                }

                if ($modified) {
                    [System.IO.File]::WriteAllText($capturedXmlPath, $content)
                    Write-Success "  Patched XML (admin): $($xmlFile.Name)"
                    $adminOk = $true
                } else {
                    Write-Success "  XML already patched: $($xmlFile.Name)"
                    $adminOk = $true
                }
            } catch {
                Write-Warn "  Admin-level XML patch failed for $($xmlFile.Name): $_ — escalating to TI"
            }

            if (-not $adminOk) {
                try {
                    $script:tiXmlOk = $false
                    Invoke-AsTrustedInstaller {
                        try {
                            $cnt = [System.IO.File]::ReadAllText($capturedXmlPath)

                            if (-not [System.IO.File]::Exists($capturedBakPath)) {
                                [System.IO.File]::Copy($capturedXmlPath, $capturedBakPath, $false)
                            }

                            $mod = $false
                            if ($cnt -match 'start\s*=\s*"(demand|auto|delayedAuto)"') {
                                $cnt = $cnt -replace 'start\s*=\s*"(demand|auto|delayedAuto)"', 'start="disabled"'
                                $mod = $true
                            }
                            if ($cnt -match '<enabled>\s*true\s*</enabled>') {
                                $cnt = $cnt -replace '<enabled>\s*true\s*</enabled>', '<enabled>false</enabled>'
                                $mod = $true
                            }
                            if ($mod) {
                                [System.IO.File]::WriteAllText($capturedXmlPath, $cnt)
                            }
                            $script:tiXmlOk = $true
                        } catch { }
                    } | Out-Null
                    if ($script:tiXmlOk) {
                        Write-Success "  Patched XML (TI): $($xmlFile.Name)"
                    } else {
                        Write-Warn "  TI XML patch returned false for $($xmlFile.Name)"
                    }
                } catch {
                    Write-Warn "  TI XML patch failed for $($xmlFile.Name): $_"
                }
            }
        }

        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $waasDir /A 2>&1 | Out-Null
            & icacls.exe $waasDir /grant "Administrators:(OI)(CI)(F)" /T 2>&1 | Out-Null
            & icacls.exe $waasDir /deny "SYSTEM:(OI)(CI)(W,D)" 2>&1 | Out-Null
            & icacls.exe $waasDir /deny "NT SERVICE\TrustedInstaller:(OI)(CI)(W,D)" 2>&1 | Out-Null
            Write-Success "  Deny write ACL on WaaS\Services folder applied"
        } catch {
            Write-Warn "  Could not deny write on WaaS\Services folder"
        }
    } else {
        Write-Warn "  WaaS\Services directory not found (may not exist on this build)"
    }
}

function Restore-UpfcAndWaaSXml {
    Write-Status "Restoring upfc.exe + SIHClient.exe..."

    $sys32 = "$env:SystemRoot\System32"
    $upfcTargets = @(
        "$sys32\upfc.exe",
        "$sys32\SIHClient.exe"
    )

    foreach ($filePath in $upfcTargets) {
        $bakPath = $filePath + $script:UpfcBackupSuffix
        if (-not (Test-Path $bakPath)) { continue }

        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $bakPath /A 2>&1 | Out-Null
            & icacls.exe $bakPath /grant "Administrators:(F)" 2>&1 | Out-Null
            & icacls.exe $bakPath /remove:d "SYSTEM" 2>&1 | Out-Null
            & icacls.exe $bakPath /remove:d "NT SERVICE\TrustedInstaller" 2>&1 | Out-Null

            if (-not (Test-Path $filePath)) {
                Rename-Item -Path $bakPath -NewName (Split-Path $filePath -Leaf) -Force -ErrorAction Stop
                Write-Success "  Restored: $(Split-Path $filePath -Leaf)"
            } else {
                Remove-Item -Path $bakPath -Force -ErrorAction SilentlyContinue
                Write-Success "  Original already present, removed backup: $(Split-Path $bakPath -Leaf)"
            }
        } catch {
            Write-Warn "  Could not restore $(Split-Path $filePath -Leaf): $_"
        }
    }

    Write-Status "Restoring WaaS XML service definitions..."
    $waasDir = "$env:SystemRoot\WaaS\Services"
    if (Test-Path $waasDir) {
        try {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            Enable-TokenPrivilege "SeRestorePrivilege"
            & takeown.exe /F $waasDir /R /D Y /A 2>&1 | Out-Null
            & icacls.exe $waasDir /grant "Administrators:(OI)(CI)(F)" /T 2>&1 | Out-Null
            & icacls.exe $waasDir /remove:d "SYSTEM" /T 2>&1 | Out-Null
            & icacls.exe $waasDir /remove:d "NT SERVICE\TrustedInstaller" /T 2>&1 | Out-Null
        } catch {}

        $bakFiles = Get-ChildItem -Path $waasDir -Filter "*$($script:UpfcBackupSuffix)" -ErrorAction SilentlyContinue
        foreach ($bakFile in $bakFiles) {
            $origPath = $bakFile.FullName -replace [regex]::Escape($script:UpfcBackupSuffix), ''
            $capturedBak  = $bakFile.FullName
            $capturedOrig = $origPath

            $restored = $false
            try {
                Copy-Item -Path $capturedBak -Destination $capturedOrig -Force -ErrorAction Stop
                Remove-Item -Path $capturedBak -Force -ErrorAction SilentlyContinue
                Write-Success "  Restored XML: $(Split-Path $origPath -Leaf)"
                $restored = $true
            } catch {}

            if (-not $restored) {
                try {
                    $script:tiRestXmlOk = $false
                    Invoke-AsTrustedInstaller {
                        try {
                            [System.IO.File]::Copy($capturedBak, $capturedOrig, $true)
                            [System.IO.File]::Delete($capturedBak)
                            $script:tiRestXmlOk = $true
                        } catch { }
                    } | Out-Null
                    if ($script:tiRestXmlOk) {
                        Write-Success "  Restored XML (TI): $(Split-Path $origPath -Leaf)"
                    } else {
                        Write-Warn "  Could not restore XML $(Split-Path $origPath -Leaf)"
                    }
                } catch {
                    Write-Warn "  Could not restore XML $(Split-Path $origPath -Leaf): $_"
                }
            }
        }
    }
}

function Get-ServiceSddl {
    param([string]$ServiceName)
    try {
        $output = & sc.exe sdshow $ServiceName 2>&1
        $sddlLine = ($output | Where-Object {
            $_ -ne $null -and $_.Trim() -ne "" -and
            $_ -notmatch '^\[SC\]' -and
            $_ -notmatch '^SERVICE_NAME' -and
            $_ -notmatch '^DESCRIPTION' -and
            ($_ -match 'D:\(' -or $_ -match 'D:P\(' -or $_ -match 'D:AI\(' -or $_ -match 'D:PAI\(' -or $_ -match '^D:')
        }) | Select-Object -Last 1
        if (-not $sddlLine) {
            $sddlLine = ($output | Where-Object { $_.Trim() -ne "" -and $_ -notmatch '^\[SC\]' -and $_ -notmatch 'SUCCESS' }) | Select-Object -Last 1
        }
        return if ($sddlLine) { $sddlLine.Trim() } else { "" }
    } catch { return "" }
}

function Lock-ServiceDacl {
    param([string]$ServiceName, [string]$ExtraSid = "")

    if (-not (Test-Path $script:SvcDaclBackupKey)) {
        try { New-Item -Path $script:SvcDaclBackupKey -Force | Out-Null } catch {}
    }

    $alreadySaved = $false
    try { $alreadySaved = $null -ne (Get-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -ErrorAction Stop).$ServiceName } catch {}
    if (-not $alreadySaved) {
        $existingSddl = Get-ServiceSddl -ServiceName $ServiceName
        if (-not ($existingSddl -and $existingSddl -match 'D:')) {
            $svcRegPath  = "SYSTEM\CurrentControlSet\Services\$ServiceName"
            $existingSddl = [WUB.TIHelper]::ReadServiceSddl($svcRegPath)
        }
        if ($existingSddl -and $existingSddl -match 'D:') {
            try { New-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -Value $existingSddl -PropertyType String -Force | Out-Null } catch {}
        }
    }
    $savedSddl = try { (Get-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -ErrorAction SilentlyContinue).$ServiceName } catch { "" }
    if (-not $savedSddl) { $savedSddl = Get-ServiceSddl -ServiceName $ServiceName }

    $dr       = "DCRPWPWDWO"
    $denyAces = "(D;;$dr;;;SY)(D;;$dr;;;$($script:TI_SID))(D;;$dr;;;LS)(D;;$dr;;;NS)"
    if ($ExtraSid -ne "") { $denyAces += "(D;;$dr;;;$ExtraSid)" }

    $newSddl = if ($savedSddl -match '^(O:[^D]*)(D:(?:P|AI|PAI|NO_ACCESS_CONTROL)?)\(') {
        "$($Matches[1])$($Matches[2])$denyAces" + ($savedSddl -replace '^O:[^D]*D:(?:P|AI|PAI|NO_ACCESS_CONTROL)?', '')
    } elseif ($savedSddl -match '^(D:(?:P|AI|PAI|NO_ACCESS_CONTROL)?)\(') {
        "$($Matches[1])$denyAces" + ($savedSddl -replace '^D:(?:P|AI|PAI|NO_ACCESS_CONTROL)?', '')
    } elseif ($savedSddl -and $savedSddl -match 'D:') {
        $savedSddl -replace '(D:(?:P|AI|PAI|NO_ACCESS_CONTROL)?)', "`$1$denyAces"
    } else {
        "D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)$denyAces"
    }

    $r = & sc.exe sdset $ServiceName $newSddl 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Locked service DACL via sc sdset: $ServiceName"

        $sdBytesL1 = [WUB.TIHelper]::SddlToBytes($newSddl)
        if ($sdBytesL1) {
            $svcRegPathL1   = "SYSTEM\CurrentControlSet\Services\$ServiceName"
            $capturedBytesL1 = $sdBytesL1
            $capturedRegL1   = $svcRegPathL1
            try {
                Set-ItemProperty -Path "HKLM:\$svcRegPathL1" -Name "Security" -Value $sdBytesL1 -Type Binary -Force -ErrorAction SilentlyContinue
            } catch { }
            try {
                Invoke-AsTrustedInstaller {
                    [WUB.TIHelper]::SetRegistryBinary($capturedRegL1, "Security", $capturedBytesL1) | Out-Null
                } | Out-Null
            } catch { }
        }
        return $true
    }

    $script:tiSdOk = $false
    $capturedSddl2 = $newSddl
    $capturedSvc2  = $ServiceName
    try {
        $tiRan = Invoke-AsTrustedInstaller {
            $script:tiSdOk = [WUB.TIHelper]::SetServiceDacl($capturedSvc2, $capturedSddl2)
        }
        if ($tiRan -and $script:tiSdOk) {
            Write-Success "Locked service DACL via SetServiceObjectSecurity (TI): $ServiceName"
            return $true
        }
    } catch {}

    $sdBytes = [WUB.TIHelper]::SddlToBytes($newSddl)
    if ($sdBytes) {
        $svcRegPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"

        try {
            Set-ItemProperty -Path "HKLM:\$svcRegPath" -Name "Security" -Value $sdBytes -Type Binary -Force -ErrorAction Stop
            Write-Success "Locked service Security value (Admin registry): $ServiceName"
            return $true
        } catch {}

        $script:tiOk = $false
        $capturedBytes   = $sdBytes
        $capturedRegPath = $svcRegPath
        try {
            $tiRan2 = Invoke-AsTrustedInstaller {
                $script:tiOk = [WUB.TIHelper]::SetRegistryBinary($capturedRegPath, "Security", $capturedBytes)
            }
            if ($tiRan2 -and $script:tiOk) {
                Write-Success "Locked service Security value (TI registry): $ServiceName"
                return $true
            }
        } catch {}
    } else {
        Write-Warn "  SddlToBytes failed for $ServiceName — SDDL may be malformed"
    }

    Write-Warn "  All lock methods failed for $ServiceName — registry+file denies still active"
    return $false
}

function Unlock-ServiceDacl {
    param([string]$ServiceName)
    $savedSddl = $null
    try { $savedSddl = (Get-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -ErrorAction Stop).$ServiceName } catch {}

    $ourDenyPattern = '\(D;;DCRPWPWDWO;;;SY\)'
    if ($savedSddl -and ($savedSddl -match $ourDenyPattern)) {
        Write-Warn "  Saved SDDL for $ServiceName appears to be a LOCKED descriptor — ignoring backup"
        $savedSddl = $null
    }

    if (-not $savedSddl) {
        $defaults = @{
            wuauserv     = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)"
            BITS         = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPDTLOCRRC;;;PU)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)"
            UsoSvc       = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)"
            WaaSMedicSvc = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"
            DoSvc        = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)"
            uhssvc       = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"
        }
        $savedSddl = if ($defaults.ContainsKey($ServiceName)) { $defaults[$ServiceName] } else {
            "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"
        }
        Write-Warn "  No saved SDDL for $ServiceName — restoring permissive default"
    }

    $r = & sc.exe sdset $ServiceName $savedSddl 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Restored service DACL via sc sdset: $ServiceName"
        Start-Sleep -Milliseconds 150
        if (-not (Test-ServiceDaclLocked -ServiceName $ServiceName)) {
            try { Remove-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
            return $true
        }
        Write-Warn "  DACL still appears locked after sc sdset — escalating to TrustedInstaller"
    }

    $sdBytes = [WUB.TIHelper]::SddlToBytes($savedSddl)
    if ($sdBytes) {
        $svcRegPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"
        try {
            Set-ItemProperty -Path "HKLM:\$svcRegPath" -Name "Security" -Value $sdBytes -Type Binary -Force -ErrorAction Stop
            Write-Success "Restored service DACL via registry Security value (Admin): $ServiceName"
            Start-Sleep -Milliseconds 150
            if (-not (Test-ServiceDaclLocked -ServiceName $ServiceName)) {
                try { Remove-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
                return $true
            }
            Write-Warn "  DACL still appears locked after registry restore — escalating to TrustedInstaller"
        } catch {}

        $script:tiOk = $false
        $capturedBytes   = $sdBytes
        $capturedRegPath = $svcRegPath
        try {
            $tiRan = Invoke-AsTrustedInstaller {
                $script:tiOk = [WUB.TIHelper]::SetRegistryBinary($capturedRegPath, "Security", $capturedBytes)
            }
            if ($tiRan -and $script:tiOk) {
                Write-Success "Restored service DACL via registry Security value (TI): $ServiceName"
                Start-Sleep -Milliseconds 150
                if (-not (Test-ServiceDaclLocked -ServiceName $ServiceName)) {
                    try { Remove-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
                    return $true
                }
                Write-Warn "  DACL still appears locked after TI registry restore — escalating to SetServiceObjectSecurity"
            }
        } catch {}
    }

    try {
        $script:tiSdOk = $false
        $capturedSvc   = $ServiceName
        $capturedSddl  = $savedSddl
        $tiRan3 = Invoke-AsTrustedInstaller {
            $script:tiSdOk = [WUB.TIHelper]::SetServiceDacl($capturedSvc, $capturedSddl)
        }
        if ($tiRan3 -and $script:tiSdOk) {
            Write-Success "Restored service DACL via SetServiceObjectSecurity (TI): $ServiceName"
            try { Remove-ItemProperty -Path $script:SvcDaclBackupKey -Name $ServiceName -Force -ErrorAction SilentlyContinue } catch {}
            return $true
        }
    } catch {}

    Write-Warn "  sc sdset restore failed for $ServiceName — all methods exhausted"
    return $false
}

function Get-AllControlSetPaths {
    param([string]$ServiceName)
    $paths = [System.Collections.Generic.List[string]]::new()
    try {
        $csNames = (Get-Item "HKLM:\SYSTEM" -ErrorAction SilentlyContinue).GetSubKeyNames() |
                   Where-Object { $_ -match '^ControlSet\d+$' }
        foreach ($cs in $csNames) {
            $p = "SYSTEM\$cs\Services\$ServiceName"
            if (Test-Path "HKLM:\$p") { $paths.Add($p) | Out-Null }
        }
    } catch {}
    $cc = "SYSTEM\CurrentControlSet\Services\$ServiceName"
    if ((Test-Path "HKLM:\$cc") -and (-not $paths.Contains($cc))) { $paths.Add($cc) | Out-Null }
    return $paths.ToArray() | Select-Object -Unique
}

function Set-AllControlSetServiceDisabled {
    param([string]$ServiceName)
    $extraSid = if ($script:SvcSids.ContainsKey($ServiceName)) { $script:SvcSids[$ServiceName] } else { "" }

    $dr        = "DCRPWPWDWO"
    $svcDenyAces = "(D;;$dr;;;SY)(D;;$dr;;;$($script:TI_SID))(D;;$dr;;;LS)(D;;$dr;;;NS)"
    if ($extraSid -ne "") { $svcDenyAces += "(D;;$dr;;;$extraSid)" }
    $svcSecSddl = "D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)$svcDenyAces"
    $svcSecBytes = [WUB.TIHelper]::SddlToBytes($svcSecSddl)

    $allPaths  = Get-AllControlSetPaths -ServiceName $ServiceName
    foreach ($path in $allPaths) {
        $label = ($path -split '\\')[1]   

        try { Set-ItemProperty -Path "HKLM:\$path" -Name "Start" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue } catch {}
        [WUB.TIHelper]::SetRegistryDword($path, "Start", 4) | Out-Null

        try { Set-ItemProperty -Path "HKLM:\$path" -Name "DelayedAutoStart" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue } catch {}
        [WUB.TIHelper]::SetRegistryDword($path, "DelayedAutoStart", 0) | Out-Null

        if ($svcSecBytes) {
            try { Set-ItemProperty -Path "HKLM:\$path" -Name "Security" -Value $svcSecBytes -Type Binary -Force -ErrorAction SilentlyContinue } catch {}
            $capturedBytes = $svcSecBytes
            $capturedPath  = $path
            try {
                Invoke-AsTrustedInstaller {
                    [WUB.TIHelper]::SetRegistryBinary($capturedPath, "Security", $capturedBytes) | Out-Null
                } | Out-Null
            } catch {}
        }

        $triggerPath = "HKLM:\$path\TriggerInfo"
        if (Test-Path $triggerPath) {
            try { Grant-RegistryKeyAccess -KeyPath "$path\TriggerInfo" | Out-Null } catch {}
            try { Remove-Item -Path $triggerPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
            $regRelPath = $path -replace '\\', '\'
            & reg.exe delete "HKLM\$regRelPath\TriggerInfo" /f 2>&1 | Out-Null
        }

        $ok = Add-RegistrySystemDeny -KeyPath $path -ExtraServiceSid $extraSid
        if ($ok) {
            Write-Success "  [$label] Start=4, DelayedAutoStart=0, Security locked, DENY applied: $ServiceName"
        } else {
            Write-Warn   "  [$label] Start=4 written but DENY failed: $ServiceName"
        }
    }
}

function Remove-AllControlSetServiceDeny {
    param([string]$ServiceName)
    $allPaths = Get-AllControlSetPaths -ServiceName $ServiceName
    foreach ($path in $allPaths) {
        $label = ($path -split '\\')[1]
        $ok = Remove-RegistrySystemDeny -KeyPath $path
        if ($ok) {
            Write-Success "  [$label] DENY removed: $ServiceName"
        } else {
            Write-Warn   "  [$label] DENY remove failed (may not have been set): $ServiceName"
        }
    }
}

$UpdateServices = @(
    "wuauserv",      
    "UsoSvc",        
    "BITS",          
    "WaaSMedicSvc",  
    "DoSvc"          
)

$OptionalServices = @(
    "uhssvc"         
)

function Set-ServiceStartType {
    param(
        [string]$ServiceName,
        [string]$ScMode,    
        [int]   $RegValue   
    )

    $relativeRegPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"
    $psRegPath       = "HKLM:\$relativeRegPath"

    $result = sc.exe config $ServiceName start= $ScMode 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($RegValue -eq 4) {
            $extraSid = if ($script:SvcSids.ContainsKey($ServiceName)) { $script:SvcSids[$ServiceName] } else { "" }
            $denyOk = Add-RegistrySystemDeny -KeyPath $relativeRegPath -ExtraServiceSid $extraSid
            if ($denyOk) { return @{ ok=$true; method="sc+deny" } }
        }
        return @{ ok=$true; method="sc" }
    }

    if ($result -match "access is denied|1072|5\b") {
        if (Test-Path $psRegPath) {
            try {
                Set-ItemProperty -Path $psRegPath -Name "Start" -Value $RegValue `
                    -Type DWord -Force -ErrorAction Stop

                if ($RegValue -eq 4) {
                    $extraSid2 = if ($script:SvcSids.ContainsKey($ServiceName)) { $script:SvcSids[$ServiceName] } else { "" }
                    $denyOk = Add-RegistrySystemDeny -KeyPath $relativeRegPath -ExtraServiceSid $extraSid2
                    if ($denyOk) { return @{ ok=$true; method="registry+deny" } }
                }
                return @{ ok=$true; method="registry" }
            } catch { }

            Write-Warn "Attempting registry key ownership takeover for: $ServiceName"
            $owned = Grant-RegistryKeyAccess -KeyPath $relativeRegPath
            if ($owned) {
                try {
                    Set-ItemProperty -Path $psRegPath -Name "Start" -Value $RegValue `
                        -Type DWord -Force -ErrorAction Stop
                    if ($RegValue -eq 4) {
                        $extraSid3 = if ($script:SvcSids.ContainsKey($ServiceName)) { $script:SvcSids[$ServiceName] } else { "" }
                        $denied = Add-RegistrySystemDeny -KeyPath $relativeRegPath -ExtraServiceSid $extraSid3
                        if ($denied) {
                            return @{ ok=$true; method="registry-ownership+deny" }
                        }
                    }
                    return @{ ok=$true; method="registry-ownership" }
                } catch {
                    return @{ ok=$false; method="registry-ownership"; error=$_ }
                }
            }
            return @{ ok=$false; method="registry-ownership"; error="Ownership takeover failed for $ServiceName" }
        }
        return @{ ok=$false; method="registry"; error="Path not found: $psRegPath" }
    }

    Write-Warn "Attempting TrustedInstaller direct write for service: $ServiceName"
    $script:tiWriteOk = $false
    $capturedDenySddl = $script:DENY_SDDL
    $svcExtraSid = if ($script:SvcSids.ContainsKey($ServiceName)) { $script:SvcSids[$ServiceName] } else { "" }
    if ($svcExtraSid -ne "") { $capturedDenySddl += "(D;OICI;KA;;;$svcExtraSid)" }

    $tiRan2 = Invoke-AsTrustedInstaller {
        $wrote = [WUB.TIHelper]::SetRegistryDword($relativeRegPath, "Start", $RegValue)
        if ($wrote) {
            $siFlags = [WUB.TIHelper]::OWNER_SECURITY_INFORMATION -bor [WUB.TIHelper]::DACL_SECURITY_INFORMATION
            [WUB.TIHelper]::ApplySddl($relativeRegPath, $script:ALLOW_SDDL, $siFlags) | Out-Null
            if ($RegValue -eq 4) {
                [WUB.TIHelper]::ApplySddl($relativeRegPath, $capturedDenySddl, $siFlags) | Out-Null
            }
            $script:tiWriteOk = $true
        }
    }
    if ($tiRan2 -and $script:tiWriteOk) {
        return @{ ok=$true; method="TrustedInstaller-impersonation" }
    }

    return @{ ok=$false; method="all-methods-exhausted"; error="Could not set $ServiceName start type — even TI impersonation failed" }
}

function Stop-UpdateServices {
    Write-Status "Stopping Windows Update services..."
    foreach ($svc in ($UpdateServices + $OptionalServices)) {
        try {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if (-not $service) { continue }
            if ($service.Status -eq "Running") {
                Stop-Service -Name $svc -Force -ErrorAction Stop
                Write-Success "Stopped service: $svc"
            } else {
                Write-Status "Service already stopped: $svc"
            }
        } catch {
            Write-Warn "Could not stop service: $svc — $_"
        }
    }
    Write-Success "Stop pass complete."
}

function Disable-UpdateServices {
    Write-Status "Disabling Windows Update services..."
    foreach ($svc in ($UpdateServices + $OptionalServices)) {
        $exists = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $exists) {
            Write-Status "Service not present, skipping: $svc"
            continue
        }

        $extraSid = if ($script:SvcSids.ContainsKey($svc)) { $script:SvcSids[$svc] } else { "" }
        $daclOk = Lock-ServiceDacl -ServiceName $svc -ExtraSid $extraSid
        if (-not $daclOk) {
            Write-Warn "  Service DACL lock skipped/failed for: $svc (reg+file denies still active)"
        }

        $r = Set-ServiceStartType -ServiceName $svc -ScMode "disabled" -RegValue 4
        if ($r.ok) {
            Write-Success "Disabled service ($($r.method)): $svc"
        } else {
            Write-Warn "Failed to disable service [$($r.method)]: $svc — $($r.error)"
        }

        Write-Status "  Hardening all ControlSet copies for: $svc"
        Set-AllControlSetServiceDisabled -ServiceName $svc

        Write-Status "  Removing service triggers: $svc"
        Remove-ServiceTriggerInfo -ServiceName $svc

        Write-Status "  Neutralising recovery actions: $svc"
        Neutralize-ServiceRecovery -ServiceName $svc
    }

    if (Get-Service -Name "WaaSMedicSvc" -ErrorAction SilentlyContinue) {
        Harden-WaaSMedicBinaries
        Set-WaaSMedicImagePathNull
    }

    Harden-UpfcAndWaaSXml

    Write-Success "Disable pass complete."
}

function Enable-UpdateServices {
    Write-Status "Enabling Windows Update services..."

    Write-Status "Step 0: Reversing WaaSMedicSvc anti-resurrection hardening..."
    Restore-WaaSMedicBinaries
    Restore-WaaSMedicImagePath
    Restore-UpfcAndWaaSXml

    Write-Status "Step 1: Restoring service SCM DACLs (SC-deny removal)..."
    foreach ($svc in ($UpdateServices + $OptionalServices)) {
        if (-not (Get-Service -Name $svc -ErrorAction SilentlyContinue)) { continue }
        $unlocked = Unlock-ServiceDacl -ServiceName $svc
        if (-not $unlocked) {
            Write-Warn "  Could not restore DACL for $svc — attempting force via default SDDL"
        }
    }

    Write-Status "Step 2: Removing registry DENY from ALL ControlSets..."
    foreach ($svc in ($UpdateServices + $OptionalServices)) {
        if (-not (Get-Service -Name $svc -ErrorAction SilentlyContinue)) { continue }
        Remove-AllControlSetServiceDeny -ServiceName $svc
        $regPath = "SYSTEM\CurrentControlSet\Services\$svc"
        if (Test-Path "HKLM:\$regPath") {
            $removed = Remove-RegistrySystemDeny -KeyPath $regPath
            if ($removed) { Write-Success "  Removed SYSTEM/TI deny (CurrentControlSet): $svc" }
        }
    }

    $configs = @{
        wuauserv     = @{ ScMode = "demand";       RegValue = 3 }
        UsoSvc       = @{ ScMode = "demand";       RegValue = 3 }
        BITS         = @{ ScMode = "delayed-auto"; RegValue = 2 }
        WaaSMedicSvc = @{ ScMode = "demand";       RegValue = 3 }
        DoSvc        = @{ ScMode = "demand";       RegValue = 3 }
        uhssvc       = @{ ScMode = "auto";         RegValue = 2 }
    }

    Write-Status "Step 3: Restoring service start types..."
    foreach ($svc in ($UpdateServices + $OptionalServices)) {
        if (-not $configs.ContainsKey($svc)) { continue }
        $exists = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $exists) {
            Write-Status "Service not present, skipping: $svc"
            continue
        }

        Restore-ServiceTriggerInfo -ServiceName $svc
        Restore-ServiceRecovery -ServiceName $svc

        $cfg = $configs[$svc]
        $r   = Set-ServiceStartType -ServiceName $svc -ScMode $cfg.ScMode -RegValue $cfg.RegValue
        if ($r.ok) {
            Write-Success "Enabled service ($($r.method)): $svc [$($cfg.ScMode)]"
        } else {
            Write-Warn "Failed to enable service [$($r.method)]: $svc — $($r.error)"
        }

        if ($svc -eq "BITS") {
            try {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\BITS" `
                    -Name "DelayedAutoStart" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }
    Write-Success "Enable pass complete."
}

function Set-UpdateRegistryBlock {
    Write-Status "Setting registry keys to block updates..."

    try {
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auPath = "$wuPath\AU"

        foreach ($p in @($wuPath, $auPath)) {
            if (!(Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        }

        @{
            NoAutoUpdate          = 1   
            AUOptions             = 1   
            UseWUServer           = 1   
            ScheduledInstallDay   = 0
            ScheduledInstallTime  = 0
        }.GetEnumerator() | ForEach-Object {
            New-ItemProperty -Path $auPath -Name $_.Key -Value $_.Value -PropertyType DWORD -Force | Out-Null
        }
        Write-Success "Set AU policy values (NoAutoUpdate, AUOptions, UseWUServer, schedule)"

        @{
            DisableWindowsUpdateAccess      = 1   
            ExcludeWUDriversInQualityUpdate = 1   
            SetDisableUXWUAccess            = 1   
            SetDisablePauseUpdates          = 1   
        }.GetEnumerator() | ForEach-Object {
            New-ItemProperty -Path $wuPath -Name $_.Key -Value $_.Value -PropertyType DWORD -Force | Out-Null
        }
        Write-Success "Set WindowsUpdate policy values"

        New-ItemProperty -Path $wuPath -Name "WUServer"       -Value "http://localhost" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $wuPath -Name "WUStatusServer" -Value "http://localhost" -PropertyType String -Force | Out-Null
        Write-Success "Set WSUS redirect → localhost"

        $storePath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
        if (!(Test-Path $storePath)) { New-Item -Path $storePath -Force | Out-Null }
        New-ItemProperty -Path $storePath -Name "AutoDownload"          -Value 2 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $storePath -Name "DisableOSUpgrade"      -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Success "Set WindowsStore AutoDownload = 2 (disabled)"

        $legacyAU = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
        if (!(Test-Path $legacyAU)) { New-Item -Path $legacyAU -Force | Out-Null }
        New-ItemProperty -Path $legacyAU -Name "AUOptions"    -Value 1 -PropertyType DWORD  -Force | Out-Null
        New-ItemProperty -Path $legacyAU -Name "IncludeRecommendedUpdates" -Value 0 -PropertyType DWORD -Force | Out-Null
        Write-Success "Set legacy AUOptions = 1"

        $driverSearchPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
        if (!(Test-Path $driverSearchPath)) { New-Item -Path $driverSearchPath -Force | Out-Null }
        New-ItemProperty -Path $driverSearchPath -Name "SearchOrderConfig"       -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $driverSearchPath -Name "DontSearchWindowsUpdate" -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Success "Set DriverSearching: SearchOrderConfig=0, DontSearchWindowsUpdate=1 (driver WU search blocked)"

        $driverPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
        if (!(Test-Path $driverPolicyPath)) { New-Item -Path $driverPolicyPath -Force | Out-Null }
        New-ItemProperty -Path $driverPolicyPath -Name "DriverUpdateWizardWuSearchEnabled" -Value 0 -PropertyType DWORD -Force | Out-Null
        New-ItemProperty -Path $driverPolicyPath -Name "DontPromptForWindowsUpdate"        -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Success "Set DriverSearching policy: WizardWuSearch=0 (Device Manager WU search disabled), DontPrompt=1"

        $deviceMetaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
        if (!(Test-Path $deviceMetaPath)) { New-Item -Path $deviceMetaPath -Force | Out-Null }
        New-ItemProperty -Path $deviceMetaPath -Name "PreventDeviceMetadataFromNetwork" -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Success "Set Device Metadata: PreventDeviceMetadataFromNetwork=1 (metadata blocked from network)"

    } catch {
        Write-ErrorMsg "Failed to set registry blocks: $_"
        return
    }
    Write-Success "All registry blocks applied."
}

function Remove-UpdateRegistryBlock {
    Write-Status "Removing registry blocks..."

    try {
        $wuPath   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auPath   = "$wuPath\AU"
        $storePath= "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
        $legacyAU = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"

        if (Test-Path $auPath) {
            Remove-Item -Path $auPath -Recurse -Force 
            Write-Success "Removed AU policy subkey"
        }

        if (Test-Path $wuPath) {
            $vuToRemove = @(
                "DisableWindowsUpdateAccess", "ExcludeWUDriversInQualityUpdate",
                "SetDisableUXWUAccess", "SetDisablePauseUpdates",
                "WUServer", "WUStatusServer"
            )
            foreach ($v in $vuToRemove) {
                Remove-ItemProperty -Path $wuPath -Name $v -Force 
            }
            $key = Get-Item $wuPath 
            if ($key -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0) {
                Remove-Item -Path $wuPath -Force 
            }
            Write-Success "Removed WindowsUpdate policy values"
        }

        if (Test-Path $storePath) {
            Remove-ItemProperty -Path $storePath -Name "AutoDownload"     -Force 
            Remove-ItemProperty -Path $storePath -Name "DisableOSUpgrade" -Force 
            Write-Success "Removed WindowsStore AutoDownload policy"
        }

        if (Test-Path $legacyAU) {
            Remove-ItemProperty -Path $legacyAU -Name "AUOptions"                 -Force 
            Remove-ItemProperty -Path $legacyAU -Name "IncludeRecommendedUpdates" -Force 
            Write-Success "Removed legacy AU values"
        }

        $driverSearchPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
        if (Test-Path $driverSearchPath) {
            Remove-ItemProperty -Path $driverSearchPath -Name "SearchOrderConfig"       -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $driverSearchPath -Name "DontSearchWindowsUpdate" -Force -ErrorAction SilentlyContinue
            Write-Success "Removed DriverSearching values: SearchOrderConfig & DontSearchWindowsUpdate (default behavior restored)"
        }

        $driverPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
        if (Test-Path $driverPolicyPath) {
            Remove-ItemProperty -Path $driverPolicyPath -Name "DriverUpdateWizardWuSearchEnabled" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $driverPolicyPath -Name "DontPromptForWindowsUpdate"        -Force -ErrorAction SilentlyContinue
            Write-Success "Removed DriverSearching policy: WizardWuSearch & DontPrompt (Device Manager WU search restored)"
        }

        $deviceMetaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
        if (Test-Path $deviceMetaPath) {
            Remove-ItemProperty -Path $deviceMetaPath -Name "PreventDeviceMetadataFromNetwork" -Force -ErrorAction SilentlyContinue
            Write-Success "Removed Device Metadata policy: PreventDeviceMetadataFromNetwork (metadata from network restored)"
        }

    } catch {
        Write-ErrorMsg "Failed to remove registry blocks: $_"
        return
    }
    Write-Success "All registry blocks removed."
}

function Disable-UpdateTasks {
    Write-Status "Disabling Windows Update scheduled tasks..."

    $UpdateTasks = @(
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\WindowsUpdate\UpdatesDeployment",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker",
        "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask",
        "\Microsoft\Windows\UpdateOrchestrator\MusUx_UpdateInterval",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_BAT",
        "\Microsoft\Windows\InstallService\ScanForUpdates",
        "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser",
        "\Microsoft\Windows\WaaSMedic\PerformRemediation",
        "\Microsoft\Windows\WindowsUpdate\sih",
        "\Microsoft\Windows\WindowsUpdate\sihboot"
    )

    foreach ($task in $UpdateTasks) {
        $lastSlash  = $task.LastIndexOf('\')
        $taskFolder = $task.Substring(0, $lastSlash + 1)
        $taskName   = $task.Substring($lastSlash + 1)

        $taskObj = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $taskObj) {
            Write-Status "Task not found (skipping): $task"
            continue
        }

        $isSelfHealingTask = ($task -like "\Microsoft\Windows\WaaSMedic\*") -or ($task -like "\Microsoft\Windows\UpdateOrchestrator\*") -or ($task -like "*\sih") -or ($task -like "*\sihboot")

        if ($isSelfHealingTask) {
            if (Ensure-TaskFileSystemDeny -TaskPath $task) {
                Write-Success "Hardened task (file-ACL deny): $task"
                if (Test-TaskFileSystemDeny -TaskPath $task) {
                    Write-Status "Verified file deny: $task"
                } else {
                    Write-Warn "Could not verify file deny (continuing): $task"
                }
            } else {
                Write-Warn "Failed to apply file-ACL deny (continuing): $task"
            }

            $taskCachePaths = @(
                "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WaaSMedic",
                "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\UpdateOrchestrator"
            )
            $leafKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree" + $task
            $allCachePaths = $taskCachePaths + @($leafKey)

            foreach ($regPath in $allCachePaths) {
                if (-not (Test-Path "HKLM:\$regPath")) { continue }
                $extraSid = if ($regPath -match "WaaSMedic") { $script:SvcSids["WaaSMedicSvc"] } else { "" }
                $ok = Add-RegistrySystemDeny -KeyPath $regPath -ExtraServiceSid $extraSid
                if ($ok) {
                    Write-Success "Hardened TaskCache (registry deny): HKLM:\$regPath"
                    if (Test-RegistrySystemDeny -KeyPath $regPath) {
                        Write-Status "Verified registry deny (SYSTEM+TI): HKLM:\$regPath"
                    } else {
                        Write-Warn "Could not verify full deny (continuing): HKLM:\$regPath"
                    }
                } else {
                    Write-Warn "Failed to harden TaskCache (registry deny): HKLM:\$regPath"
                }
            }
        }

        $disabled = $false
        try {
            Disable-ScheduledTask -TaskPath $taskFolder -TaskName $taskName `
                -ErrorAction Stop | Out-Null
            Write-Success "Disabled task: $task"
            $disabled = $true
        } catch { }

        if ($disabled) {
            if (-not $isSelfHealingTask) {
                if (Ensure-TaskFileSystemDeny -TaskPath $task) {
                    Write-Success "Hardened task (file-ACL deny): $task"
                    if (Test-TaskFileSystemDeny -TaskPath $task) {
                        Write-Status "Verified file deny: $task"
                    } else {
                        Write-Warn "Could not verify file deny (continuing): $task"
                    }
                }
            }

            try {
                $st = (Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue).State
                if ($st -eq "Disabled") {
                    Write-Status "Verified disabled state: $task"
                } else {
                    Write-Warn "Task state is '$st' (expected Disabled): $task"
                }
            } catch { }

            continue
        }

        try {
            $r = & schtasks.exe /Change /TN $task /Disable 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Disabled task (schtasks): $task"
                $disabled = $true
            }
        } catch { }

        if ($disabled) {
            if (Ensure-TaskFileSystemDeny -TaskPath $task) {
                Write-Success "Hardened task (file-ACL deny): $task"
            }
            continue
        }

        $taskFilePath = Join-Path "$env:SystemRoot\System32\Tasks" $task.TrimStart('\')
        if (Test-Path $taskFilePath) {
            try {
                Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
                $takeown = & takeown.exe /F $taskFilePath 2>&1
                $grant   = & icacls.exe $taskFilePath /grant "Administrators:(F)" 2>&1

                try {
                    $xmlContent = Get-Content -Path $taskFilePath -Raw -ErrorAction Stop
                    if ($xmlContent -match '<Enabled>true</Enabled>') {
                        $xmlContent = $xmlContent -replace '<Enabled>true</Enabled>', '<Enabled>false</Enabled>'
                        Set-Content -Path $taskFilePath -Value $xmlContent -Encoding UTF8 -Force -ErrorAction Stop
                    }
                } catch { }  

                & icacls.exe $taskFilePath /remove:d "SYSTEM"                      2>&1 | Out-Null
                & icacls.exe $taskFilePath /remove:d "NT SERVICE\TrustedInstaller" 2>&1 | Out-Null
                $icacls = & icacls.exe $taskFilePath /deny "SYSTEM:(M)" 2>&1
                & icacls.exe $taskFilePath /deny "NT SERVICE\TrustedInstaller:(M)" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Disabled task (file-ACL deny): $task"
                    $disabled = $true
                }
            } catch { }
        }

        if (-not $disabled) {
            Write-Warn "Could not disable task (all methods failed): $task"
        }
    }
    Write-Success "Task disable pass complete."
}

function Enable-UpdateTasks {
    Write-Status "Enabling Windows Update scheduled tasks..."

    $UpdateTasks = @(
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\WindowsUpdate\UpdatesDeployment",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker",
        "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask",
        "\Microsoft\Windows\UpdateOrchestrator\MusUx_UpdateInterval",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_BAT",
        "\Microsoft\Windows\InstallService\ScanForUpdates",
        "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser",
        "\Microsoft\Windows\WaaSMedic\PerformRemediation",
        "\Microsoft\Windows\WindowsUpdate\sih",
        "\Microsoft\Windows\WindowsUpdate\sihboot"
    )

    Write-Status "Removing task file-ACL deny entries (pre-pass)..."
    foreach ($task in $UpdateTasks) {
        $taskFilePath = Join-Path "$env:SystemRoot\System32\Tasks" $task.TrimStart('\')
        if (Test-Path $taskFilePath) {
            Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
            & takeown.exe /F $taskFilePath 2>&1 | Out-Null
            & icacls.exe $taskFilePath /grant "Administrators:(F)" 2>&1 | Out-Null
            & icacls.exe $taskFilePath /remove:d "SYSTEM"                      2>&1 | Out-Null
            & icacls.exe $taskFilePath /remove:d "NT SERVICE\TrustedInstaller" 2>&1 | Out-Null

            try {
                $xmlContent = Get-Content -Path $taskFilePath -Raw -ErrorAction Stop
                if ($xmlContent -match '<Enabled>false</Enabled>') {
                    $xmlContent = $xmlContent -replace '<Enabled>false</Enabled>', '<Enabled>true</Enabled>'
                    Set-Content -Path $taskFilePath -Value $xmlContent -Encoding UTF8 -Force -ErrorAction Stop
                    Write-Success "Patched task XML back to enabled: $task"
                }
            } catch {
                Write-Warn "Could not patch task XML (continuing): $task — $_"
            }

            & icacls.exe $taskFilePath /remove:d "SYSTEM" 2>&1 | Out-Null
        }
    }

    Write-Status "Removing TaskCache registry deny entries (pre-pass)..."
    $taskCachePaths = @(
        "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WaaSMedic",
        "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\UpdateOrchestrator"
    )
    foreach ($task in $UpdateTasks) {
        $leafKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree" + $task
        $taskCachePaths += $leafKey
    }
    foreach ($regPath in ($taskCachePaths | Select-Object -Unique)) {
        if (-not (Test-Path ("Registry::HKEY_LOCAL_MACHINE\" + $regPath))) {
            Write-Status "TaskCache key not present (skipping): HKLM:\$regPath"
            continue
        }
        $ok = Remove-RegistrySystemDeny -KeyPath $regPath
        if ($ok) {
            Write-Success "Restored TaskCache ACL: HKLM:\$regPath"
            if (-not (Test-RegistrySystemDeny -KeyPath $regPath)) {
                Write-Status "Verified registry restore: HKLM:\$regPath"
            } else {
                Write-Warn "Registry still appears denied to SYSTEM: HKLM:\$regPath"
            }
        } else {
            Write-Warn "Failed to restore TaskCache ACL (continuing): HKLM:\$regPath"
        }
    }

    foreach ($task in $UpdateTasks) {
        $lastSlash  = $task.LastIndexOf('\')
        $taskFolder = $task.Substring(0, $lastSlash + 1)
        $taskName   = $task.Substring($lastSlash + 1)

        $taskObj = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $taskObj) {
            Write-Status "Task not found (skipping): $task"
            continue
        }

        $enabled = $false

        try {
            Enable-ScheduledTask -TaskPath $taskFolder -TaskName $taskName `
                -ErrorAction Stop | Out-Null
            Write-Success "Enabled task: $task"
            $enabled = $true
        } catch { }

        if ($enabled) { continue }

        try {
            $r = & schtasks.exe /Change /TN $task /Enable 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Enabled task (schtasks): $task"
                $enabled = $true
            }
        } catch { }

        if ($enabled) { continue }

        try {
            $schedSvc = New-Object -ComObject Schedule.Service
            $schedSvc.Connect()
            $schedFolder = $schedSvc.GetFolder($taskFolder.TrimEnd('\'))
            $existingTask = $schedFolder.GetTask($taskName)
            $taskDef = $existingTask.Definition
            $taskDef.Settings.Enabled = $true
            $schedFolder.RegisterTaskDefinition($taskName, $taskDef, 6, $null, $null, 0) | Out-Null
            $newState = ($schedFolder.GetTask($taskName)).State
            if ($newState -ne 1) {   
                Write-Success "Enabled task (COM re-register): $task"
                $enabled = $true
            }
        } catch { }

        if ($enabled) { continue }

        $isWaaSMedic = ($task -like "\Microsoft\Windows\WaaSMedic\*")
        if (-not $enabled -and $isWaaSMedic) {
            try {
                Write-Warn "Attempting WaaSMedicSvc suspend + XML re-import for: $task"
                $waasRunning = (Get-Service WaaSMedicSvc -ErrorAction SilentlyContinue).Status -eq 'Running'

                if ($waasRunning) {
                    & sc.exe stop WaaSMedicSvc 2>&1 | Out-Null
                    $deadline = (Get-Date).AddSeconds(6)
                    while ((Get-Service WaaSMedicSvc -ErrorAction SilentlyContinue).Status -eq 'Running' `
                           -and (Get-Date) -lt $deadline) {
                        Start-Sleep -Milliseconds 300
                    }
                }

                $taskFilePath = Join-Path "$env:SystemRoot\System32\Tasks" $task.TrimStart('\')
                if (Test-Path $taskFilePath) {
                    Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
                    & takeown.exe /F $taskFilePath 2>&1 | Out-Null
                    & icacls.exe $taskFilePath /grant "Administrators:(F)" 2>&1 | Out-Null

                    $xml = Get-Content $taskFilePath -Raw -ErrorAction Stop
                    $schedSvc2 = New-Object -ComObject Schedule.Service
                    $schedSvc2.Connect()
                    $schedFolder2 = $schedSvc2.GetFolder($taskFolder.TrimEnd('\'))
                    try {
                        $schedFolder2.RegisterTask($taskName, $xml, 6, $null, $null, 0) | Out-Null
                        Write-Success "Enabled task (WaaSMedic XML re-import): $task"
                        $enabled = $true
                    } catch {
                        Write-Warn "WaaSMedic COM re-import failed: $_ — trying schtasks /Create /XML fallback"
                        $r4b = & schtasks.exe /Create /XML $taskFilePath /TN $task /F 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Success "Enabled task (schtasks /Create /XML): $task"
                            $enabled = $true
                        } else {
                            Write-Warn "schtasks /Create /XML also failed ($LASTEXITCODE): $r4b"
                        }
                    }
                }

                if ($waasRunning) {
                    & sc.exe start WaaSMedicSvc 2>&1 | Out-Null
                }
            } catch {
                Write-Warn "WaaSMedic re-import failed: $_"
                try { & sc.exe start WaaSMedicSvc 2>&1 | Out-Null } catch { }
            }
        }

        if ($enabled) { continue }

        if (-not $enabled) {
            try {
                $tcPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree" +
                          $task.Replace('\', '\')
                $tcPSPath = "HKLM:\$tcPath"
                if (Test-Path $tcPSPath) {
                    Set-ItemProperty -Path $tcPSPath -Name "Enabled" -Value 1 -Type DWord -Force -ErrorAction Stop
                    Write-Success "Enabled task (TaskCache registry): $task"
                    $enabled = $true
                }
            } catch {
                try {
                    $tcRelPath = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree" + $task
                    $script:tiEnOk = $false
                    $tiRan3 = Invoke-AsTrustedInstaller {
                        $script:tiEnOk = [WUB.TIHelper]::SetRegistryDword($tcRelPath, "Enabled", 1)
                    }
                    if ($tiRan3 -and $script:tiEnOk) {
                        Write-Success "Enabled task (TaskCache via TI): $task"
                        $enabled = $true
                    }
                } catch { }
            }
        }

        if (-not $enabled) {
            Write-Warn "Could not enable task (all methods failed): $task"
        }
    }
    Write-Success "Task enable pass complete."
}

function Show-CurrentStatus {
    Write-Host "`nCurrent Windows Update Status:" -ForegroundColor Yellow
    Write-Host "--------------------------------" -ForegroundColor Yellow

    $script:cntBlock  = 0
    $script:cntEnable = 0
    $script:cntTotal  = 0

    function Record-Check {
        param([bool]$IsBlocked)   
        $script:cntTotal++
        if ($IsBlocked) { $script:cntBlock++ } else { $script:cntEnable++ }
    }

    function State-Color { param([bool]$IsBlocked)
        if ($IsBlocked) { return 'Red' } else { return 'Green' }
    }

    Write-Status "── Services ────────────────────────────────────────────────────────"

    $AllServices = $UpdateServices + $OptionalServices
    foreach ($svc in $AllServices) {
        $relPath = "SYSTEM\CurrentControlSet\Services\$svc"
        $psPath  = "HKLM:\$relPath"

        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $svcObj) {
            Write-Host "  $svc" -ForegroundColor Gray -NoNewline
            Write-Host " : not installed (skipped)" -ForegroundColor DarkGray
            continue
        }

        $startVal = $null
        try { $startVal = (Get-ItemProperty $psPath -Name "Start" -ErrorAction Stop).Start } catch { }

        $startDesc = switch ($startVal) {
            4 { "Disabled(4)" }    
            3 { "Manual(3)" }
            2 { "Auto(2)" }
            1 { "Boot(1)" }
            0 { "System(0)" }
            default { "Unknown($startVal)" }
        }
        $startBlocked = ($startVal -eq 4)

        $hasDeny = Test-RegistrySystemDeny -KeyPath $relPath
        $denyDesc = if ($hasDeny) { "SYS-DENY=YES" } else { "SYS-DENY=NO" }

        $daclLocked = Test-ServiceDaclLocked -ServiceName $svc
        $daclDesc   = if ($daclLocked) { "SC-DENY=YES" } else { "SC-DENY=NO" }

        $running = ($svcObj.Status -eq 'Running')
        $runDesc = $svcObj.Status

        $triggerPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc\TriggerInfo"
        $hasTriggers = Test-Path $triggerPath
        $triggerDesc = if ($hasTriggers) { "TRIGGERS=YES" } else { "TRIGGERS=NO" }

        $hasRecovery = $false
        try {
            $fa = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "FailureActions" -ErrorAction Stop).FailureActions
            if ($fa -and $fa.Length -gt 16) {
                $cActions = [BitConverter]::ToInt32($fa, 12)
                $hasRecovery = ($cActions -gt 0)
                if ($hasRecovery) {
                    $allNone = $true
                    for ($i = 0; $i -lt $cActions -and (16 + $i * 8 + 4) -le $fa.Length; $i++) {
                        $actionType = [BitConverter]::ToInt32($fa, 16 + $i * 8)
                        if ($actionType -ne 0) { $allNone = $false; break }
                    }
                    if ($allNone) { $hasRecovery = $false }
                }
            }
        } catch {}
        $recoveryDesc = if ($hasRecovery) { "RECOVERY=YES" } else { "RECOVERY=NO" }

        $fullyBlocked  = $startBlocked -and $hasDeny -and $daclLocked -and (-not $hasTriggers)
        $fullyEnabled  = (-not $startBlocked) -and (-not $hasDeny) -and (-not $daclLocked)

        $col = if ($fullyBlocked) { 'Red' } elseif ($fullyEnabled) { 'Green' } else { 'Yellow' }

        $startCol    = if ($startBlocked)   { 'Red' } else { 'Green' }
        $denyCol     = if ($hasDeny)        { 'Red' } else { 'Green' }
        $daclCol     = if ($daclLocked)     { 'Red' } else { 'Green' }
        $triggerCol  = if ($hasTriggers)    { 'Green' } else { 'Red' }    
        $recoveryCol = if ($hasRecovery)    { 'Green' } else { 'Red' }    
        $runCol      = if ($running)        { 'Yellow' } else { 'Cyan' }

        Write-Host ("  {0,-16}" -f $svc) -NoNewline
        Write-Host " Start=$startDesc" -ForegroundColor $startCol -NoNewline
        Write-Host "  $denyDesc"        -ForegroundColor $denyCol -NoNewline
        Write-Host "  $daclDesc"        -ForegroundColor $daclCol -NoNewline
        Write-Host "  $triggerDesc"     -ForegroundColor $triggerCol -NoNewline
        Write-Host "  Status=$runDesc"  -ForegroundColor $runCol

        Record-Check -IsBlocked $startBlocked
        Record-Check -IsBlocked $hasDeny
        Record-Check -IsBlocked $daclLocked
        Record-Check -IsBlocked (-not $hasTriggers)  
    }

    Write-Status "── Registry policies ───────────────────────────────────────────────"

    $wuPath    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auPath    = "$wuPath\AU"
    $storePath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
    $legacyAU  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"

    $regChecks = @(
        @{ Path=$auPath;    Name="NoAutoUpdate";             Expect=1;                     Desc="Auto-updates blocked";                      NotSetDesc="Auto-updates download & install automatically" },
        @{ Path=$auPath;    Name="AUOptions";                Expect=1;                     Desc="AU set to notify-only";                     NotSetDesc="AU uses default behavior (auto-download & install)" },
        @{ Path=$auPath;    Name="UseWUServer";              Expect=1;                     Desc="Redirected to WSUS (localhost)";            NotSetDesc="Uses Microsoft Windows Update servers directly" },
        @{ Path=$wuPath;    Name="DisableWindowsUpdateAccess";      Expect=1;             Desc="WU access blocked";                         NotSetDesc="WU settings accessible to all users" },
        @{ Path=$wuPath;    Name="ExcludeWUDriversInQualityUpdate"; Expect=1;             Desc="Driver updates excluded from quality rolls"; NotSetDesc="Driver updates included in quality update rolls" },
        @{ Path=$wuPath;    Name="SetDisableUXWUAccess";            Expect=1;             Desc="WU UI disabled";                            NotSetDesc="WU UI fully accessible to users" },
        @{ Path=$wuPath;    Name="SetDisablePauseUpdates";          Expect=1;             Desc="Pause-updates button locked";               NotSetDesc="Users can freely pause updates" },
        @{ Path=$wuPath;    Name="WUServer";                        Expect="http://localhost"; Desc="WSUS redirected → localhost";           NotSetDesc="Uses Microsoft WU servers (no WSUS redirect)" },
        @{ Path=$wuPath;    Name="WUStatusServer";                  Expect="http://localhost"; Desc="Status server → localhost";            NotSetDesc="Reports update status to Microsoft servers" },
        @{ Path=$storePath; Name="AutoDownload";             Expect=2;                     Desc="Store auto-download disabled";              NotSetDesc="Store apps auto-download & install enabled" },
        @{ Path=$storePath; Name="DisableOSUpgrade";         Expect=1;                     Desc="OS upgrades blocked";                       NotSetDesc="OS upgrades allowed via Windows Update" },
        @{ Path=$legacyAU;  Name="AUOptions";                Expect=1;                     Desc="Legacy AU set to notify-only";              NotSetDesc="Legacy AU uses default behavior" },
        @{ Path=$legacyAU;  Name="IncludeRecommendedUpdates";Expect=0;                     Desc="Recommended updates excluded";              NotSetDesc="Recommended updates included by default" }
    )

    $driverSearchPath  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
    $driverPolicyPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
    $deviceMetaPath    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
    $driverSearchChecks = @(
        @{ Path=$driverSearchPath; Name="SearchOrderConfig";                 Expect=0; Desc="Driver search order blocked";            NotSetDesc="Windows searches WU automatically for drivers" },
        @{ Path=$driverSearchPath; Name="DontSearchWindowsUpdate";           Expect=1; Desc="WU not searched for drivers";            NotSetDesc="WU searched for drivers when not found locally" },
        @{ Path=$driverPolicyPath; Name="DriverUpdateWizardWuSearchEnabled"; Expect=0; Desc="Device Manager WU search disabled";      NotSetDesc="Device Manager searches WU for drivers on demand" },
        @{ Path=$driverPolicyPath; Name="DontPromptForWindowsUpdate";        Expect=1; Desc="WU driver prompt suppressed";            NotSetDesc="User prompted to search WU when driver not found" },
        @{ Path=$deviceMetaPath;   Name="PreventDeviceMetadataFromNetwork";  Expect=1; Desc="Device metadata blocked from network";   NotSetDesc="Device metadata (icons/apps) downloaded from network" }
    )

    foreach ($chk in $regChecks) {
        if (-not (Test-Path $chk.Path)) {
            Write-Host ("  {0,-40}" -f $chk.Name) -NoNewline
            Write-Host " = (not set)" -ForegroundColor Green -NoNewline
            Write-Host "  ← $($chk.NotSetDesc)" -ForegroundColor DarkGray
            Record-Check -IsBlocked $false
            continue
        }
        $val = (Get-ItemProperty -Path $chk.Path -Name $chk.Name -ErrorAction SilentlyContinue).$($chk.Name)
        $isSet = ($null -ne $val -and "$val" -eq "$($chk.Expect)")
        $current = if ($null -ne $val) { $val } else { "(not set)" }
        $col = if ($isSet) { 'Red' } else { 'Green' }

        Write-Host ("  {0,-40}" -f $chk.Name) -NoNewline
        Write-Host (" = $current") -ForegroundColor $col -NoNewline
        if ($isSet) {
            Write-Host "  ✓ $($chk.Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host "  ← $($chk.NotSetDesc)" -ForegroundColor DarkGray
        }
        Record-Check -IsBlocked $isSet
    }

    Write-Status "── Driver search policy (DriverSearching) ──────────────────────────"

    foreach ($chk in $driverSearchChecks) {
        if (-not (Test-Path $chk.Path)) {
            Write-Host ("  {0,-40}" -f $chk.Name) -NoNewline
            Write-Host " = (not set)" -ForegroundColor Green -NoNewline
            Write-Host "  ← $($chk.NotSetDesc)" -ForegroundColor DarkGray
            Record-Check -IsBlocked $false
            continue
        }
        $val = (Get-ItemProperty -Path $chk.Path -Name $chk.Name -ErrorAction SilentlyContinue).$($chk.Name)
        $isSet = ($null -ne $val -and "$val" -eq "$($chk.Expect)")
        $current = if ($null -ne $val) { $val } else { "(not set)" }
        $col = if ($isSet) { 'Red' } else { 'Green' }

        Write-Host ("  {0,-40}" -f $chk.Name) -NoNewline
        Write-Host (" = $current") -ForegroundColor $col -NoNewline
        if ($isSet) {
            Write-Host "  ✓ $($chk.Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host "  ← $($chk.NotSetDesc)" -ForegroundColor DarkGray
        }
        Record-Check -IsBlocked $isSet
    }

    Write-Status "── Scheduled tasks ─────────────────────────────────────────────────"

    $StatusTasks = @(
        "\Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "\Microsoft\Windows\WindowsUpdate\UpdatesDeployment",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task",
        "\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker",
        "\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask",
        "\Microsoft\Windows\UpdateOrchestrator\MusUx_UpdateInterval",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_AC",
        "\Microsoft\Windows\UpdateOrchestrator\Reboot_BAT",
        "\Microsoft\Windows\InstallService\ScanForUpdates",
        "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser",
        "\Microsoft\Windows\WaaSMedic\PerformRemediation",
        "\Microsoft\Windows\WindowsUpdate\sih",
        "\Microsoft\Windows\WindowsUpdate\sihboot"
    )

    foreach ($task in $StatusTasks) {
        $lastSlash  = $task.LastIndexOf('\')
        $taskFolder = $task.Substring(0, $lastSlash + 1)
        $taskName   = $task.Substring($lastSlash + 1)

        $taskObj = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $taskObj) {
            Write-Host ("  {0,-55}" -f $task) -NoNewline
            Write-Host " not found (skipped)" -ForegroundColor DarkGray
            continue
        }

        $state       = $taskObj.State         
        $isDisabled  = ($state -eq 'Disabled')
        $hasDenyFile = Test-TaskFileDeny -TaskPath $task
        $denyDesc    = if ($hasDenyFile) { "FILE-DENY=YES" } else { "FILE-DENY=NO" }

        $fullyBlocked = $isDisabled -and $hasDenyFile
        $fullyEnabled = (-not $isDisabled) -and (-not $hasDenyFile)
        $stateCol     = if ($isDisabled) { 'Red' } else { 'Green' }
        $denyCol      = if ($hasDenyFile) { 'Red' } else { 'Green' }

        Write-Host ("  {0,-55}" -f $task) -NoNewline
        Write-Host " $state" -ForegroundColor $stateCol -NoNewline
        Write-Host "  $denyDesc" -ForegroundColor $denyCol

        Record-Check -IsBlocked $isDisabled
        Record-Check -IsBlocked $hasDenyFile
    }

    Write-Status "── WaaSMedic anti-resurrection hardening ─────────────────────────"
    $sys32 = "$env:SystemRoot\System32"
    $dllMissing = -not (Test-Path "$sys32\WaaSMedicSvc.dll")
    $dllBak     = Test-Path ("$sys32\WaaSMedicSvc.dll" + $script:WaaSMedicBackupSuffix)
    $binHardened = $dllMissing -and $dllBak
    $binDesc = if ($binHardened) { "DLL renamed + denied" } elseif ($dllMissing -and -not $dllBak) { "DLL missing (no backup)" } else { "DLL present (not hardened)" }
    $binCol  = if ($binHardened) { 'Red' } else { 'Green' }
    Write-Host ("  {0,-55}" -f "WaaSMedicSvc.dll") -NoNewline
    Write-Host " $binDesc" -ForegroundColor $binCol
    Record-Check -IsBlocked $binHardened

    $imgNulled = $false
    try {
        $imgVal = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "ImagePath" -ErrorAction Stop).ImagePath
        $imgNulled = ($imgVal -match "WUBlockerNullified")
    } catch {}
    $imgDesc = if ($imgNulled) { "ImagePath nullified" } else { "ImagePath original" }
    $imgCol  = if ($imgNulled) { 'Red' } else { 'Green' }
    Write-Host ("  {0,-55}" -f "WaaSMedicSvc ImagePath") -NoNewline
    Write-Host " $imgDesc" -ForegroundColor $imgCol
    Record-Check -IsBlocked $imgNulled

    Write-Status "── UPFC + SIH anti-resurrection hardening ──────────────────────────"

    $upfcMissing = -not (Test-Path "$sys32\upfc.exe")
    $upfcBak     = Test-Path ("$sys32\upfc.exe" + $script:UpfcBackupSuffix)
    $upfcHardened = $upfcMissing -and $upfcBak
    $upfcDesc = if ($upfcHardened) { "Renamed + denied" } elseif ($upfcMissing -and -not $upfcBak) { "Missing (no backup)" } elseif (-not $upfcMissing) { "Present (NOT hardened)" } else { "Unknown" }
    $upfcCol  = if ($upfcHardened -or ($upfcMissing -and -not $upfcBak)) { 'Red' } else { 'Green' }
    Write-Host ("  {0,-55}" -f "upfc.exe") -NoNewline
    Write-Host " $upfcDesc" -ForegroundColor $upfcCol
    Record-Check -IsBlocked ($upfcMissing)

    $sihMissing = -not (Test-Path "$sys32\SIHClient.exe")
    $sihBak     = Test-Path ("$sys32\SIHClient.exe" + $script:UpfcBackupSuffix)
    $sihHardened = $sihMissing -and $sihBak
    $sihDesc = if ($sihHardened) { "Renamed + denied" } elseif ($sihMissing -and -not $sihBak) { "Missing (no backup)" } elseif (-not $sihMissing) { "Present (NOT hardened)" } else { "Unknown" }
    $sihCol  = if ($sihHardened -or ($sihMissing -and -not $sihBak)) { 'Red' } else { 'Green' }
    Write-Host ("  {0,-55}" -f "SIHClient.exe") -NoNewline
    Write-Host " $sihDesc" -ForegroundColor $sihCol
    Record-Check -IsBlocked ($sihMissing)

    $waasDir = "$env:SystemRoot\WaaS\Services"
    $xmlPatched = $false
    if (Test-Path $waasDir) {
        $xmlFiles = Get-ChildItem -Path $waasDir -Filter "*.xml" -ErrorAction SilentlyContinue
        if ($xmlFiles) {
            $anyDemand = $false
            foreach ($xf in $xmlFiles) {
                try {
                    $xContent = Get-Content -Path $xf.FullName -Raw -ErrorAction SilentlyContinue
                    if ($xContent -match 'start\s*=\s*"(demand|auto|delayedAuto)"') { $anyDemand = $true; break }
                } catch {}
            }
            $xmlPatched = -not $anyDemand
        } else {
            $xmlPatched = $true  
        }
    }
    $xmlDesc = if ($xmlPatched) { "Patched (disabled state)" } else { "Original" }
    $xmlCol  = if ($xmlPatched) { 'Red' } else { 'Green' }
    Write-Host ("  {0,-55}" -f "WaaS XML service definitions") -NoNewline
    Write-Host " $xmlDesc" -ForegroundColor $xmlCol
    Record-Check -IsBlocked $xmlPatched

    Write-Host ""
    Write-Host ("  Checks: {0} total — {1} blocked-state / {2} enabled-state" -f $script:cntTotal, $script:cntBlock, $script:cntEnable)
    Write-Host ""

    if ($script:cntBlock -eq $script:cntTotal -and $script:cntTotal -gt 0) {
        Write-Host "  Overall Status: ██ UPDATES ARE FULLY BLOCKED ██" -ForegroundColor Red
    } elseif ($script:cntEnable -eq $script:cntTotal -and $script:cntTotal -gt 0) {
        Write-Host "  Overall Status: ██ UPDATES ARE FULLY ENABLED ██" -ForegroundColor Green
    } elseif ($script:cntBlock -gt $script:cntEnable) {
        Write-Host "  Overall Status: MOSTLY BLOCKED ($script:cntBlock/$script:cntTotal items in blocked state)" -ForegroundColor Yellow
    } elseif ($script:cntEnable -gt $script:cntBlock) {
        Write-Host "  Overall Status: MOSTLY ENABLED ($script:cntEnable/$script:cntTotal items in enabled state)" -ForegroundColor Yellow
    } else {
        Write-Host "  Overall Status: PARTIALLY BLOCKED ($script:cntBlock/$script:cntTotal blocked, $script:cntEnable/$script:cntTotal enabled)" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Get-UserAction {
    Write-Host "Choose action:" -ForegroundColor Yellow
    Write-Host "  [D] Disable Windows Updates"
    Write-Host "  [E] Enable Windows Updates"
    $choice = Read-Host "Enter D or E"
    switch ($choice.ToUpper()) {
        'D' { return 'Disable' }
        'E' { return 'Enable'  }
        default {
            Write-Host "Invalid choice. Please enter D or E." -ForegroundColor Red
            return Get-UserAction
        }
    }
}

function Start-ServiceSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$TimeoutSec = 25
    )

    try {
        Start-Service -Name $Name -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    } catch {
        try {
            if ((Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running') { return $true }
        } catch {}
        throw
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $s = Get-Service -Name $Name -ErrorAction Stop
            if ($s.Status -eq 'Running') { return $true }
            if ($s.Status -eq 'Stopped') { break }
        } catch { break }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "                    Windows Update Blocker - PowerShell Edition               " -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

Show-CommunityLinks -Title "Community Links"
Show-CurrentStatus

if (-not $Action) { $Action = Get-UserAction }

try {
    if ($Action -eq "Disable") {
        Write-Host ""
        Write-Host "ACTION: DISABLE WINDOWS UPDATES" -ForegroundColor Red
        Show-CommunityLinks -Title "Community Links"

        Stop-UpdateServices
        Disable-UpdateServices
        Set-UpdateRegistryBlock
        Disable-UpdateTasks

        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Red
        Write-Host "                    WINDOWS UPDATES HAVE BEEN DISABLED                        " -ForegroundColor Red
        Write-Host "==============================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "To re-enable updates, run this script again and choose Enable." -ForegroundColor Yellow
        Show-CommunityLinks -Title "Community Links"

    } elseif ($Action -eq "Enable") {
        Write-Host ""
        Write-Host "ACTION: ENABLE WINDOWS UPDATES" -ForegroundColor Green
        Show-CommunityLinks -Title "Community Links"

        Enable-UpdateServices
        Remove-UpdateRegistryBlock
        Enable-UpdateTasks

        Write-Status "Starting Windows Update services..."
        foreach ($svc in @("BITS", "wuauserv", "UsoSvc")) {
            try {
                if (Start-ServiceSafe -Name $svc -TimeoutSec 35) {
                    Write-Success "Started service: $svc"
                } else {
                    Write-Warn "Service start timed out (still not Running): $svc"
                }
            } catch {
                Write-Warn "Could not start service: $svc — $_"
            }
        }

        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Green
        Write-Host "                    WINDOWS UPDATES HAVE BEEN ENABLED                         " -ForegroundColor Green
        Write-Host "==============================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "To disable updates again, run this script and choose Disable." -ForegroundColor Yellow
        Show-CommunityLinks -Title "Community Links"
    }
} catch {
    Write-ErrorMsg "An unexpected error occurred: $_"
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    Write-Host ""
    Write-Warn "Some steps may have partially applied. Check the output above for details."
    Write-Warn "Individual warnings ([!]) above are non-fatal — the script continued past them."
}

Write-Host "Script completed. A system restart is recommended for all changes to take full effect." -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
