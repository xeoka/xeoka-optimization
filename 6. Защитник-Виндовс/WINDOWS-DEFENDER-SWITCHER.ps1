# ТГ: https://t.me/CMEPT0HOCHbIU

Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       DEFENDER SWITCHER  —  PowerShell Edition        ║" -ForegroundColor Cyan
Write-Host "║       Disable / Enable Windows Defender               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "[!] Must be run as Administrator. Restarting elevated..." -ForegroundColor Red
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Write-Host " [OK] Running as Administrator" -ForegroundColor Green
Write-Host ""

$ErrorActionPreference = "Continue"

if (-not (Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
}

$script:InSafeMode = $false
try {
    $safeBoot = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Option" -ErrorAction SilentlyContinue).OptionValue
    if ($null -ne $safeBoot) {
        $script:InSafeMode = $true
    } else {
        $smVal = (Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).BootupState
        if ($smVal -match "safe|fail-safe") { $script:InSafeMode = $true }
    }
} catch {}
if (-not $script:InSafeMode) {
    try {
        $sbCtl = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SafeBoot" -ErrorAction SilentlyContinue)
        if ($null -ne $sbCtl) { $script:InSafeMode = $true }
    } catch {}
}

if ($script:InSafeMode) {
    Write-Host " [*] Safe Mode detected — WdFilter.sys and PPL enforcement are NOT loaded." -ForegroundColor Cyan
    Write-Host "     All Disable/Enable operations will succeed regardless of Tamper Protection state." -ForegroundColor Green
    Write-Host ""
}

trap {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  CAUGHT NON-FATAL ERROR (execution continues)               ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "  Exception : $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Category  : $($_.CategoryInfo)" -ForegroundColor Yellow
    Write-Host "  Script    : $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "  Command   : $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
    Write-Host ""
    continue   
}

if (-not ([System.Management.Automation.PSTypeName]'DS.TokenPriv').Type) {
    Add-Type -Namespace DS -Name TokenPriv -MemberDefinition @'
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool AdjustTokenPrivileges(
    IntPtr htok, bool disAll, ref TokPriv1Luid newState, int len, IntPtr prev, IntPtr relen);
[DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
[StructLayout(LayoutKind.Sequential, Pack=1)]
public struct TokPriv1Luid { public int Count; public long Luid; public int Attr; }
public const int SE_PRIVILEGE_ENABLED = 0x00000002;
public const int TOKEN_QUERY          = 0x00000008;
public const int TOKEN_ADJUST_PRIVS   = 0x00000020;
public static bool Enable(long processHandle, string privilege) {
    TokPriv1Luid tp; IntPtr htok = IntPtr.Zero;
    bool ok = OpenProcessToken(new IntPtr(processHandle), TOKEN_ADJUST_PRIVS | TOKEN_QUERY, ref htok);
    tp.Count = 1; tp.Luid = 0; tp.Attr = SE_PRIVILEGE_ENABLED;
    LookupPrivilegeValue(null, privilege, ref tp.Luid);
    AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    return ok;
}
'@
}

if (-not ([System.Management.Automation.PSTypeName]'DS.TIHelper').Type) {
    Add-Type -Namespace DS -Name TIHelper -MemberDefinition @'
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

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegOpenKeyExW")]
public static extern int RegOpenKeyExU(UIntPtr hKey, string subKey, int ulOptions, int samDesired, out IntPtr phkResult);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegCreateKeyExW")]
public static extern int RegCreateKeyExU(
    UIntPtr hKey, string lpSubKey, int Reserved, string lpClass,
    int dwOptions, int samDesired, IntPtr lpSecurityAttributes,
    out IntPtr phkResult, out int lpdwDisposition);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegCloseKey(IntPtr hKey);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegSetValueExW")]
public static extern int RegSetValueNamed(IntPtr hKey, string lpValueName, int Reserved, int dwType, byte[] lpData, int cbData);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegSetValueExW")]
public static extern int RegSetValueDefault(IntPtr hKey, IntPtr lpValueName, int Reserved, int dwType, byte[] lpData, int cbData);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegDeleteValueW")]
public static extern int RegDeleteNamed(IntPtr hKey, string lpValueName);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegDeleteValueW")]
public static extern int RegDeleteDefault(IntPtr hKey, IntPtr lpValueName);

[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegDeleteTreeW")]
public static extern int RegDeleteTreeU(UIntPtr hKey, string lpSubKey);

public static readonly UIntPtr HKLM = new UIntPtr(0x80000002u);
public static readonly UIntPtr HKCR = new UIntPtr(0x80000000u);
public static readonly UIntPtr HKU  = new UIntPtr(0x80000003u);

public const int KEY_ALL_ACCESS             = 0xF003F;
public const int REG_OPTION_NON_VOLATILE    = 0;
public const int REG_OPTION_BACKUP_RESTORE  = 0x4;

public const int REG_SZ        = 1;
public const int REG_EXPAND_SZ = 2;
public const int REG_BINARY    = 3;
public const int REG_DWORD     = 4;
public const int REG_MULTI_SZ  = 7;
public const int REG_QWORD     = 11;

public const uint PROCESS_QUERY_INFORMATION         = 0x0400;
public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
public const uint PROCESS_ALL_ACCESS                = 0x001FFFFF;
public const uint TOKEN_ALL_ACCESS                  = 0x000F01FF;
public const uint TOKEN_DUPLICATE                   = 0x0002;
public const uint TOKEN_QUERY                       = 0x0008;
public const uint TOKEN_IMPERSONATE                 = 0x0004;
public const int  SecurityImpersonation             = 2;
public const int  TokenImpersonation                = 2;

// --- Thread token + privilege enabling on any token handle ---
[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentThread();

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool OpenThreadToken(IntPtr hThread, uint desiredAccess, bool openAsSelf, out IntPtr hToken);

[DllImport("advapi32.dll", SetLastError=true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool AdjustTokenPrivileges(
    IntPtr hToken, bool disableAllPrivileges,
    ref LUID_AND_ATTRIBUTES newState, int bufLen, IntPtr prevState, IntPtr returnLen);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

[StructLayout(LayoutKind.Sequential)]
public struct LUID_AND_ATTRIBUTES { public long Luid; public int Attributes; }

public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
public const int  SE_PRIVILEGE_ENABLED    = 0x00000002;

/// <summary>
/// Enable a named privilege on any token handle (process OR thread impersonation token).
/// </summary>
public static bool EnablePrivilegeOnToken(IntPtr hToken, string privilege) {
    LUID_AND_ATTRIBUTES la = new LUID_AND_ATTRIBUTES();
    la.Attributes = SE_PRIVILEGE_ENABLED;
    if (!LookupPrivilegeValue(null, privilege, out la.Luid)) return false;
    return AdjustTokenPrivileges(hToken, false, ref la, 0, IntPtr.Zero, IntPtr.Zero);
}

/// <summary>
/// Enable SeBackupPrivilege + SeRestorePrivilege + SeTakeOwnershipPrivilege
/// on the CURRENT THREAD's impersonation token (or process token if not impersonating).
/// This is required for REG_OPTION_BACKUP_RESTORE to bypass ACL checks.
/// </summary>
public static void EnableRegistryPrivsOnCurrentThread() {
    IntPtr hTok = IntPtr.Zero;
    // Try thread token first (active when impersonating TI)
    if (OpenThreadToken(GetCurrentThread(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, false, out hTok) && hTok != IntPtr.Zero) {
        EnablePrivilegeOnToken(hTok, "SeBackupPrivilege");
        EnablePrivilegeOnToken(hTok, "SeRestorePrivilege");
        EnablePrivilegeOnToken(hTok, "SeTakeOwnershipPrivilege");
        CloseHandle(hTok);
    }
}

// --- Registry ACL helpers (take ownership + grant admin full) ---
[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegGetKeySecurity(IntPtr hKey, uint securityInfo, byte[] pSecurityDescriptor, ref int lpcbSecurityDescriptor);

[DllImport("advapi32.dll", SetLastError=true)]
public static extern int RegSetKeySecurity(IntPtr hKey, uint securityInfo, byte[] pSecurityDescriptor);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(
    string StringSecurityDescriptor, uint StringSDRevision,
    out IntPtr SecurityDescriptor, out int SecurityDescriptorSize);

[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="RegOpenKeyExW")]
public static extern int RegOpenKeyExW2(IntPtr hKey, string subKey, int ulOptions, int samDesired, out IntPtr phkResult);

[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr LocalFree(IntPtr hMem);

public const int  KEY_WRITE            = 0x20006;
public const int  KEY_READ             = 0x20019;
public const int  WRITE_DAC            = 0x00040000;
public const int  WRITE_OWNER         = 0x00080000;
public const int  READ_CONTROL         = 0x00020000;
public const uint DACL_SECURITY_INFO   = 4;
public const uint OWNER_SECURITY_INFO  = 1;
public const uint SDDL_REVISION_1      = 1;

// --- NtRenameKey (ntdll) — rename a key to an orphan name so path-based
//     kernel callbacks no longer match it, then we can delete it freely.  ---
[DllImport("ntdll.dll")]
public static extern int NtRenameKey(IntPtr KeyHandle, ref UNICODE_STRING NewName);

[StructLayout(LayoutKind.Sequential)]
public struct UNICODE_STRING {
    public ushort Length;
    public ushort MaximumLength;
    public IntPtr Buffer;
}

// --- RegEnumKeyExW — enumerate subkeys for recursive DACL reset ----------
[DllImport("advapi32.dll", CharSet=CharSet.Unicode, EntryPoint="RegEnumKeyExW")]
public static extern int RegEnumKeyExW(
    IntPtr hKey, int dwIndex,
    System.Text.StringBuilder lpName, ref int lpcchName,
    IntPtr lpReserved, IntPtr lpClass, IntPtr lpcClass,
    IntPtr lpftLastWriteTime);

public const int KEY_ENUMERATE_SUB_KEYS = 0x0008;
'@
}

function Enable-TokenPrivilege {
    param([string]$Privilege)
    try {
        $handle = (Get-Process -Id $PID).Handle
        [DS.TokenPriv]::Enable($handle, $Privilege) | Out-Null
    } catch { }
}

function Enable-RegistryPrivileges {
    Enable-TokenPrivilege "SeTakeOwnershipPrivilege"
    Enable-TokenPrivilege "SeRestorePrivilege"
    Enable-TokenPrivilege "SeBackupPrivilege"
    try { [DS.TIHelper]::EnableRegistryPrivsOnCurrentThread() } catch {}
}

$script:TI_ImpToken    = [IntPtr]::Zero   
$script:TI_Initialized = $false
$script:TI_UsePrivOnly = $false
$script:TI_CtxLabel    = ""

function script:Clear-LastPInvokeError {
    try   { [System.Runtime.InteropServices.Marshal]::SetLastPInvokeError(0) } catch {
        try { [System.Runtime.InteropServices.Marshal]::SetLastWin32Error(0) } catch {}
    }
}

function Initialize-TrustedInstallerToken {
    Enable-TokenPrivilege "SeDebugPrivilege"

    $tiSvc = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
    if ($tiSvc) {
        if ($tiSvc.Status -ne 'Running') {
            Write-Host " - Starting TrustedInstaller service..." -ForegroundColor Gray
            try   { Start-Service "TrustedInstaller" -ErrorAction Stop }
            catch { & sc.exe start TrustedInstaller 2>&1 | Out-Null }
            $dl = (Get-Date).AddSeconds(10)
            while ((Get-Service "TrustedInstaller" -EA SilentlyContinue).Status -ne 'Running' `
                   -and (Get-Date) -lt $dl) { Start-Sleep -Milliseconds 200 }
        }
        $script:TI_Initialized = $true
        $script:TI_UsePrivOnly = $false
        $script:TI_CtxLabel    = "TrustedInstaller"
        Write-Host " - [OK] TrustedInstaller service ready." -ForegroundColor Green
    } else {
        $script:TI_UsePrivOnly = $true
        $script:TI_CtxLabel    = "Administrator + privilege bypass"
        Write-Host " - [WARN] TrustedInstaller service not found — using privilege bypass." -ForegroundColor Yellow
    }
}

function Cleanup-TrustedInstallerToken {
    if ($script:TI_ImpToken -ne [IntPtr]::Zero) {
        [DS.TIHelper]::CloseHandle($script:TI_ImpToken) | Out-Null
        $script:TI_ImpToken = [IntPtr]::Zero
    }
    $script:TI_Initialized = $false
    $script:TI_UsePrivOnly  = $false
    $script:TI_CtxLabel     = ""
}

function Invoke-AsTrustedInstaller {
    param([scriptblock]$Action)

    Enable-TokenPrivilege "SeDebugPrivilege"
    try {
        $curProc = [System.Diagnostics.Process]::GetCurrentProcess()
        [DS.TokenPriv]::Enable($curProc.Handle.ToInt64(), "SeDebugPrivilege") | Out-Null
    } catch {}

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        $tiSvc = Get-Service "TrustedInstaller" -ErrorAction SilentlyContinue
        if (-not $tiSvc) { break }
        if ($tiSvc.Status -ne 'Running') {
            try {
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $dl = (Get-Date).AddSeconds(8)
                while ((Get-Service "TrustedInstaller").Status -ne 'Running' -and (Get-Date) -lt $dl) {
                    Start-Sleep -Milliseconds 100
                }
            } catch {
                Write-Host "  [WARN] Could not start TrustedInstaller (attempt $attempt): $_" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
                continue
            }
        }

        $tiProc = $null
        $procDl = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $procDl) {
            $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($tiProc) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $tiProc) {
            try {
                Stop-Service "TrustedInstaller" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
                Start-Service "TrustedInstaller" -ErrorAction Stop
                $procDl2 = (Get-Date).AddSeconds(3)
                while ((Get-Date) -lt $procDl2) {
                    $tiProc = Get-Process -Name "TrustedInstaller" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($tiProc) { break }
                    Start-Sleep -Milliseconds 100
                }
            } catch {}
            if (-not $tiProc) { Start-Sleep -Milliseconds 500; continue }
        }

        $winlogonProc = Get-Process -Name "winlogon" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winlogonProc) {
            Write-Host "  [WARN] winlogon.exe not found (attempt $attempt)" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
            continue
        }

        script:Clear-LastPInvokeError
        $hWinlogon = [DS.TIHelper]::OpenProcess([DS.TIHelper]::PROCESS_QUERY_INFORMATION, $false, $winlogonProc.Id)
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $hWinlogon = [DS.TIHelper]::OpenProcess([DS.TIHelper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $winlogonProc.Id)
        }
        if ($hWinlogon -eq [IntPtr]::Zero) {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Host "  [WARN] OpenProcess(winlogon) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
            continue
        }

        $attemptSucceeded = $false
        try {
            $hSysToken = [IntPtr]::Zero
            $sysAccess = [DS.TIHelper]::TOKEN_DUPLICATE -bor [DS.TIHelper]::TOKEN_QUERY -bor [DS.TIHelper]::TOKEN_IMPERSONATE
            script:Clear-LastPInvokeError
            if (-not [DS.TIHelper]::OpenProcessToken($hWinlogon, $sysAccess, [ref]$hSysToken)) {
                script:Clear-LastPInvokeError
                [DS.TIHelper]::OpenProcessToken($hWinlogon, [DS.TIHelper]::TOKEN_ALL_ACCESS, [ref]$hSysToken) | Out-Null
            }
            if ($hSysToken -eq [IntPtr]::Zero) {
                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "  [WARN] OpenProcessToken(winlogon/SYSTEM) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
                continue
            }

            try {
                $hSysImpToken = [IntPtr]::Zero
                script:Clear-LastPInvokeError
                [DS.TIHelper]::DuplicateTokenEx(
                    $hSysToken,
                    [DS.TIHelper]::TOKEN_ALL_ACCESS,
                    [IntPtr]::Zero,
                    [DS.TIHelper]::SecurityImpersonation,
                    [DS.TIHelper]::TokenImpersonation,
                    [ref]$hSysImpToken) | Out-Null
                if ($hSysImpToken -eq [IntPtr]::Zero) {
                    $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Write-Host "  [WARN] DuplicateTokenEx(SYSTEM) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                    continue
                }

                try {
                    if (-not [DS.TIHelper]::ImpersonateLoggedOnUser($hSysImpToken)) {
                        $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                        Write-Host "  [WARN] ImpersonateLoggedOnUser(SYSTEM) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                        continue
                    }

                    $hTIProc = [DS.TIHelper]::OpenProcess([DS.TIHelper]::PROCESS_QUERY_INFORMATION, $false, $tiProc.Id)
                    if ($hTIProc -eq [IntPtr]::Zero) {
                        $hTIProc = [DS.TIHelper]::OpenProcess([DS.TIHelper]::PROCESS_QUERY_LIMITED_INFORMATION, $false, $tiProc.Id)
                    }
                    if ($hTIProc -eq [IntPtr]::Zero) {
                        $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                        Write-Host "  [WARN] OpenProcess(TI) as SYSTEM failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                        [DS.TIHelper]::RevertToSelf() | Out-Null
                        continue
                    }

                    try {
                        $hTIToken = [IntPtr]::Zero
                        $tiAccess = [DS.TIHelper]::TOKEN_ALL_ACCESS
                        script:Clear-LastPInvokeError
                        if (-not [DS.TIHelper]::OpenProcessToken($hTIProc, $tiAccess, [ref]$hTIToken)) {
                            $tiAccess = [DS.TIHelper]::TOKEN_DUPLICATE -bor [DS.TIHelper]::TOKEN_QUERY -bor [DS.TIHelper]::TOKEN_IMPERSONATE
                            script:Clear-LastPInvokeError
                            [DS.TIHelper]::OpenProcessToken($hTIProc, $tiAccess, [ref]$hTIToken) | Out-Null
                        }
                        if ($hTIToken -eq [IntPtr]::Zero) {
                            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                            Write-Host "  [WARN] OpenProcessToken(TI) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                            [DS.TIHelper]::RevertToSelf() | Out-Null
                            continue
                        }

                        try {
                            $hImpToken = [IntPtr]::Zero
                            script:Clear-LastPInvokeError
                            [DS.TIHelper]::DuplicateTokenEx(
                                $hTIToken,
                                [DS.TIHelper]::TOKEN_ALL_ACCESS,
                                [IntPtr]::Zero,
                                [DS.TIHelper]::SecurityImpersonation,
                                [DS.TIHelper]::TokenImpersonation,
                                [ref]$hImpToken) | Out-Null
                            if ($hImpToken -eq [IntPtr]::Zero) {
                                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                Write-Host "  [WARN] DuplicateTokenEx(TI) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                                [DS.TIHelper]::RevertToSelf() | Out-Null
                                continue
                            }

                            try {
                                [DS.TIHelper]::RevertToSelf() | Out-Null
                                if (-not [DS.TIHelper]::ImpersonateLoggedOnUser($hImpToken)) {
                                    $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                                    Write-Host "  [WARN] ImpersonateLoggedOnUser(TI) failed attempt $attempt — Win32 error $e" -ForegroundColor Yellow
                                    continue
                                }
                                try {
                                    Enable-RegistryPrivileges
                                    & $Action
                                    $attemptSucceeded = $true
                                    return $true
                                } catch {
                                    Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red
                                    return $false
                                } finally {
                                    [DS.TIHelper]::RevertToSelf() | Out-Null
                                }
                            } finally {
                                [DS.TIHelper]::CloseHandle($hImpToken) | Out-Null
                            }
                        } finally {
                            [DS.TIHelper]::CloseHandle($hTIToken) | Out-Null
                        }
                    } finally {
                        [DS.TIHelper]::CloseHandle($hTIProc) | Out-Null
                        if (-not $attemptSucceeded) { [DS.TIHelper]::RevertToSelf() | Out-Null }
                    }

                } finally {
                    [DS.TIHelper]::CloseHandle($hSysImpToken) | Out-Null
                }
            } finally {
                [DS.TIHelper]::CloseHandle($hSysToken) | Out-Null
            }
        } finally {
            [DS.TIHelper]::CloseHandle($hWinlogon) | Out-Null
        }
    }

    Write-Host "  [WARN] All $maxAttempts TI impersonation attempts failed — falling back to privilege bypass." -ForegroundColor Yellow
    $script:TI_UsePrivOnly = $true
    $script:TI_CtxLabel    = "Administrator + privilege bypass"
    try {
        Enable-RegistryPrivileges
        & $Action
        return $true
    } catch {
        Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red
        return $false
    }
}

function Invoke-RegContent {
    param([string[]]$Lines)

    $hiveMap = @{
        'HKEY_LOCAL_MACHINE' = [DS.TIHelper]::HKLM
        'HKEY_CLASSES_ROOT'  = [DS.TIHelper]::HKCR
        'HKEY_USERS'         = [DS.TIHelper]::HKU
    }

    $script:rc_currentKey  = [IntPtr]::Zero
    $script:rc_hexBuilder  = $null
    $script:rc_hexValName  = $null
    $script:rc_hexValType  = 0
    $script:rc_inHexCont   = $false

    function script:RC_CloseCurrentKey {
        if ($script:rc_currentKey -ne [IntPtr]::Zero) {
            [DS.TIHelper]::RegCloseKey($script:rc_currentKey) | Out-Null
            $script:rc_currentKey = [IntPtr]::Zero
        }
    }
    function script:RC_OpenOrCreate([UIntPtr]$hive, [string]$subPath) {
        script:RC_CloseCurrentKey
        $hKey = [IntPtr]::Zero; $disp = 0
        $ret = [DS.TIHelper]::RegOpenKeyExU($hive, $subPath,
                    [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                    [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
        if ($ret -ne 0) {
            [DS.TIHelper]::RegCreateKeyExU($hive, $subPath, 0, $null,
                [DS.TIHelper]::REG_OPTION_NON_VOLATILE,
                [DS.TIHelper]::KEY_ALL_ACCESS, [IntPtr]::Zero,
                [ref]$hKey, [ref]$disp) | Out-Null
        }
        $script:rc_currentKey = $hKey
    }
    function script:RC_FlushHex {
        if (-not $script:rc_inHexCont) { return }
        $raw   = ($script:rc_hexBuilder.ToString()) -replace '\s',''
        $parts = $raw.TrimEnd(',') -split ',' | Where-Object { $_ -ne '' }
        [byte[]]$bytes = @()
        if ($parts) { $bytes = $parts | ForEach-Object { [Convert]::ToByte($_, 16) } }
        if ($script:rc_currentKey -ne [IntPtr]::Zero) {
            if ($null -eq $script:rc_hexValName) {
                [DS.TIHelper]::RegSetValueDefault($script:rc_currentKey, [IntPtr]::Zero, 0,
                    $script:rc_hexValType, $bytes, $bytes.Length) | Out-Null
            } else {
                [DS.TIHelper]::RegSetValueNamed($script:rc_currentKey, $script:rc_hexValName, 0,
                    $script:rc_hexValType, $bytes, $bytes.Length) | Out-Null
            }
        }
        $script:rc_inHexCont = $false; $script:rc_hexBuilder = $null
        $script:rc_hexValName = $null; $script:rc_hexValType = 0
    }
    function script:RC_UnescapeName([string]$s) {
        return $s -replace '\\\\','\' -replace '\\"','"'
    }

    foreach ($rawLine in $Lines) {
        $line = $rawLine.TrimEnd()
        if ($script:rc_inHexCont) {
            $isCont  = $line.EndsWith('\')
            $hexPart = ($line.TrimStart()) -replace '\\$',''
            $script:rc_hexBuilder.Append($hexPart) | Out-Null
            if (-not $isCont) { script:RC_FlushHex }
            continue
        }
        if ($line -eq '' -or $line -eq 'Windows Registry Editor Version 5.00' `
            -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[-([A-Z_]+)\\(.+)\]$') {
            $hName = $Matches[1]; $sub = $Matches[2]
            if ($hiveMap.ContainsKey($hName)) {
                script:RC_CloseCurrentKey
                [DS.TIHelper]::RegDeleteTreeU($hiveMap[$hName], $sub) | Out-Null
            }
            continue
        }
        if ($line -match '^\[([A-Z_]+)\\(.+)\]$') {
            $hName = $Matches[1]; $sub = $Matches[2]
            if ($hiveMap.ContainsKey($hName)) {
                script:RC_OpenOrCreate $hiveMap[$hName] $sub
            } else { script:RC_CloseCurrentKey }
            continue
        }
        if ($script:rc_currentKey -eq [IntPtr]::Zero) { continue }
        if ($line -match '^(@|"((?:[^"\\]|\\.)*)")\s*=-\s*$') {
            if ($line.StartsWith('@=')) {
                [DS.TIHelper]::RegDeleteDefault($script:rc_currentKey, [IntPtr]::Zero) | Out-Null
            } else {
                $vn = script:RC_UnescapeName $Matches[2]
                [DS.TIHelper]::RegDeleteNamed($script:rc_currentKey, $vn) | Out-Null
            }
            continue
        }
        if ($line -match '^(@|"((?:[^"\\]|\\.)*)")\s*=\s*dword:([0-9a-fA-F]+)\s*$') {
            $dw   = [Convert]::ToUInt32($Matches[3], 16)
            $data = [BitConverter]::GetBytes($dw)
            if ($line.StartsWith('@=')) {
                [DS.TIHelper]::RegSetValueDefault($script:rc_currentKey, [IntPtr]::Zero, 0,
                    [DS.TIHelper]::REG_DWORD, $data, 4) | Out-Null
            } else {
                $vn = script:RC_UnescapeName $Matches[2]
                [DS.TIHelper]::RegSetValueNamed($script:rc_currentKey, $vn, 0,
                    [DS.TIHelper]::REG_DWORD, $data, 4) | Out-Null
            }
            continue
        }
        if ($line -match '^(@|"((?:[^"\\]|\\.)*)")\s*=\s*"((?:[^"\\]|\\.)*)"\s*$') {
            $sv   = ($Matches[3]) -replace '\\\\','\' -replace '\\"','"'
            $data = [System.Text.Encoding]::Unicode.GetBytes($sv + [char]0)
            if ($line.StartsWith('@=')) {
                [DS.TIHelper]::RegSetValueDefault($script:rc_currentKey, [IntPtr]::Zero, 0,
                    [DS.TIHelper]::REG_SZ, $data, $data.Length) | Out-Null
            } else {
                $vn = script:RC_UnescapeName $Matches[2]
                [DS.TIHelper]::RegSetValueNamed($script:rc_currentKey, $vn, 0,
                    [DS.TIHelper]::REG_SZ, $data, $data.Length) | Out-Null
            }
            continue
        }
        if ($line -match '^(@|"((?:[^"\\]|\\.)*)")\s*=\s*(hex(?:\([0-9a-fA-F]+\))?):(.*?)\\?\s*$') {
            if ($line.StartsWith('@=')) {
                $script:rc_hexValName = $null
            } else {
                $script:rc_hexValName = script:RC_UnescapeName $Matches[2]
            }
            $hexTag = $Matches[3]
            if ($hexTag -match '\(([0-9a-fA-F]+)\)') {
                $script:rc_hexValType = [Convert]::ToInt32($Matches[1], 16)
            } else {
                $script:rc_hexValType = [DS.TIHelper]::REG_BINARY
            }
            $script:rc_hexBuilder = New-Object System.Text.StringBuilder
            $script:rc_hexBuilder.Append($Matches[4]) | Out-Null
            $script:rc_inHexCont = $true
            if (-not $line.TrimEnd().EndsWith('\')) { script:RC_FlushHex }
            continue
        }
    }
    script:RC_FlushHex
    script:RC_CloseCurrentKey
}


function Write-StepLog {
    param(
        [string]$Step,
        [string]$Status,    
        [string]$Detail = ""
    )
    $pad = 70
    $stepPad = if ($Step.Length -ge $pad) { "$Step " } else { $Step.PadRight($pad) }
    switch ($Status) {
        "OK"            { $tag = "[OK]";            $color = "Green"   }
        "FAIL"          { $tag = "[FAIL]";          $color = "Red"     }
        "SKIP"          { $tag = "[SKIP]";          $color = "Gray"    }
        "ACCESS_DENIED" { $tag = "[ACCESS DENIED]"; $color = "Magenta" }
        "INFO"          { $tag = "[INFO]";          $color = "Cyan"    }
        default         { $tag = "[$Status]";       $color = "Yellow"  }
    }
    $msg = "  $stepPad $tag"
    if ($Detail) { $msg += " $Detail" }
    Write-Host $msg -ForegroundColor $color
}

function Set-RegValueTI {
    param(
        [string]$KeyPath,       
        [string]$ValueName,
        [int]$ValueData,
        [string]$Label,
        [UIntPtr]$Hive = [DS.TIHelper]::HKLM
    )
    $script:_regWriteErr = $null
    $ok = Invoke-AsTrustedInstaller {
        $hKey = [IntPtr]::Zero
        $ret = [DS.TIHelper]::RegOpenKeyExU(
            $Hive, $KeyPath,
            [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
            [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
        if ($ret -ne 0) {
            $disp = 0
            $ret = [DS.TIHelper]::RegCreateKeyExU(
                $Hive, $KeyPath, 0, $null,
                [DS.TIHelper]::REG_OPTION_NON_VOLATILE,
                [DS.TIHelper]::KEY_ALL_ACCESS, [IntPtr]::Zero,
                [ref]$hKey, [ref]$disp)
        }
        if ($ret -eq 0 -and $hKey -ne [IntPtr]::Zero) {
            $data = [BitConverter]::GetBytes([uint32]$ValueData)
            $wret = [DS.TIHelper]::RegSetValueNamed($hKey, $ValueName, 0, [DS.TIHelper]::REG_DWORD, $data, 4)
            [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
            if ($wret -ne 0) {
                $errReason = switch ($wret) {
                    5       { "ERROR_ACCESS_DENIED (5) — Tamper Protection is likely ON, or the key is owned by TrustedInstaller/SYSTEM and the token elevation failed" }
                    2       { "ERROR_FILE_NOT_FOUND (2) — the registry key or value path does not exist and could not be created" }
                    1314    { "ERROR_PRIVILEGE_NOT_HELD (1314) — the current token lacks required privileges; try running from an elevated admin prompt" }
                    default { "Win32 error $wret — check https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes for details" }
                }
                $script:_regWriteErr = "RegSetValue FAILED: $errReason"
                throw $script:_regWriteErr
            }
        } else {
            $errReason = switch ($ret) {
                5       { "ERROR_ACCESS_DENIED (5) — key is protected; Tamper Protection may be ON, or ACLs deny access even under TrustedInstaller" }
                2       { "ERROR_FILE_NOT_FOUND (2) — parent key path does not exist: HKLM\$KeyPath" }
                1314    { "ERROR_PRIVILEGE_NOT_HELD (1314) — token lacks SeBackupPrivilege/SeRestorePrivilege" }
                default { "Win32 error $ret — check https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes" }
            }
            $script:_regWriteErr = "RegOpenKey/RegCreateKey FAILED: $errReason"
            throw $script:_regWriteErr
        }
    }
    if ($ok) {
        $hivePrefix = if ($Hive -eq [DS.TIHelper]::HKLM) { "HKLM:" } elseif ($Hive -eq [DS.TIHelper]::HKCR) { "HKCR:" } else { "HKU:" }
        $verifyPath = "${hivePrefix}\$KeyPath"
        $readBack = Get-RegValue $verifyPath $ValueName
        if ($null -ne $readBack -and [int]$readBack -eq $ValueData) {
            Write-StepLog $Label "OK" "(set $ValueName=$ValueData, verified)"
        } else {
            $actualVal = if ($null -eq $readBack) { "null/absent" } else { "$readBack" }
            Write-StepLog $Label "FAIL" "(WRITE SUCCEEDED but VERIFY FAILED: wrote $ValueData, read back $actualVal — Tamper Protection or another process may have reverted the value immediately)"
            return $false
        }
    } else {
        $errDetail = if ($script:_regWriteErr) { $script:_regWriteErr } else { "could not set $ValueName=$ValueData — TrustedInstaller impersonation may have failed (check TI service status)" }
        Write-StepLog $Label "FAIL" "($errDetail)"
    }
    return $ok
}

function Set-RegStringTI {
    param(
        [string]$KeyPath,
        [string]$ValueName,
        [string]$ValueData,
        [string]$Label,
        [UIntPtr]$Hive = [DS.TIHelper]::HKLM
    )
    $script:_regStrWriteErr = $null
    $ok = Invoke-AsTrustedInstaller {
        $hKey = [IntPtr]::Zero
        $ret = [DS.TIHelper]::RegOpenKeyExU(
            $Hive, $KeyPath,
            [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
            [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
        if ($ret -ne 0) {
            $disp = 0
            $ret = [DS.TIHelper]::RegCreateKeyExU(
                $Hive, $KeyPath, 0, $null,
                [DS.TIHelper]::REG_OPTION_NON_VOLATILE,
                [DS.TIHelper]::KEY_ALL_ACCESS, [IntPtr]::Zero,
                [ref]$hKey, [ref]$disp)
        }
        if ($ret -eq 0 -and $hKey -ne [IntPtr]::Zero) {
            $data = [System.Text.Encoding]::Unicode.GetBytes($ValueData + [char]0)
            $wret = [DS.TIHelper]::RegSetValueNamed($hKey, $ValueName, 0, [DS.TIHelper]::REG_SZ, $data, $data.Length)
            [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
            if ($wret -ne 0) {
                $errReason = switch ($wret) {
                    5       { "ERROR_ACCESS_DENIED (5) — Tamper Protection is likely ON, or ACLs deny write access" }
                    1314    { "ERROR_PRIVILEGE_NOT_HELD (1314) — token lacks required privileges" }
                    default { "Win32 error $wret" }
                }
                $script:_regStrWriteErr = "RegSetValue FAILED: $errReason"
                throw $script:_regStrWriteErr
            }
        } else {
            $errReason = switch ($ret) {
                5       { "ERROR_ACCESS_DENIED (5) — key is protected; Tamper Protection may be ON" }
                2       { "ERROR_FILE_NOT_FOUND (2) — parent key path does not exist: HKLM\$KeyPath" }
                default { "Win32 error $ret" }
            }
            $script:_regStrWriteErr = "RegOpenKey/RegCreateKey FAILED: $errReason"
            throw $script:_regStrWriteErr
        }
    }
    if ($ok) {
        $hivePrefix = if ($Hive -eq [DS.TIHelper]::HKLM) { "HKLM:" } elseif ($Hive -eq [DS.TIHelper]::HKCR) { "HKCR:" } else { "HKU:" }
        $verifyPath = "${hivePrefix}\$KeyPath"
        $readBack = Get-RegValue $verifyPath $ValueName
        if ($null -ne $readBack -and "$readBack" -eq "$ValueData") {
            Write-StepLog $Label "OK" "(set $ValueName='$ValueData', verified)"
        } else {
            $actualVal = if ($null -eq $readBack) { "null/absent" } else { "'$readBack'" }
            Write-StepLog $Label "FAIL" "(WRITE SUCCEEDED but VERIFY FAILED: wrote '$ValueData', read back $actualVal — value may have been reverted by Tamper Protection)"
            return $false
        }
    } else {
        $errDetail = if ($script:_regStrWriteErr) { $script:_regStrWriteErr } else { "could not set $ValueName='$ValueData' — TrustedInstaller impersonation may have failed" }
        Write-StepLog $Label "FAIL" "($errDetail)"
    }
    return $ok
}


function Set-RegKeyOwnershipAndWrite {
    param(
        [string]$KeyPath,      
        [string]$ValueName,    
        [int]   $ValueData,    
        [string]$Label
    )

    $psPath = "HKLM:\$KeyPath"
    if (-not (Test-Path $psPath)) {
        Write-StepLog $Label "SKIP" "(key absent — skipping ownership approach)"
        return $false
    }

    $result = Invoke-AsTrustedInstaller {
        $hKey = [IntPtr]::Zero
        $secAccess = [DS.TIHelper]::WRITE_DAC -bor [DS.TIHelper]::WRITE_OWNER -bor [DS.TIHelper]::READ_CONTROL
        $ret = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $KeyPath, 0, $secAccess, [ref]$hKey)
        if ($ret -ne 0) { return $false }
        try {
            $sdStr = "D:(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)(A;OICI;KA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)"
            $sdPtr  = [IntPtr]::Zero
            $sdSize = 0
            if (-not [DS.TIHelper]::ConvertStringSecurityDescriptorToSecurityDescriptor($sdStr, [DS.TIHelper]::SDDL_REVISION_1, [ref]$sdPtr, [ref]$sdSize)) {
                return $false
            }
            $sdBytes = New-Object byte[] $sdSize
            [System.Runtime.InteropServices.Marshal]::Copy($sdPtr, $sdBytes, 0, $sdSize)
            [DS.TIHelper]::LocalFree($sdPtr) | Out-Null
            $r = [DS.TIHelper]::RegSetKeySecurity($hKey, [DS.TIHelper]::DACL_SECURITY_INFO, $sdBytes)
            if ($r -ne 0) { return $false }
        } finally {
            [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
        }

        $hKey2 = [IntPtr]::Zero
        $ret2  = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $KeyPath,
                    [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                    [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey2)
        if ($ret2 -ne 0) { return $false }
        try {
            $data  = [BitConverter]::GetBytes([uint32]$ValueData)
            $wret  = [DS.TIHelper]::RegSetValueNamed($hKey2, $ValueName, 0, [DS.TIHelper]::REG_DWORD, $data, 4)
            return ($wret -eq 0)
        } finally {
            [DS.TIHelper]::RegCloseKey($hKey2) | Out-Null
        }
    }
    return $result
}


function Unlock-RegKeyForDeletion {
    param(
        [string]$HklmSubKey   
    )

    $null = Invoke-AsTrustedInstaller {
        $script:ulrd_sdStr = "D:(A;OICI;KA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;OICI;KA;;;SY)(A;OICI;KA;;;BA)"

        function script:ULRD_ResetNode([string]$sk) {
            $hKN = [IntPtr]::Zero
            $secAcc = [DS.TIHelper]::WRITE_DAC -bor [DS.TIHelper]::WRITE_OWNER -bor
                      [DS.TIHelper]::READ_CONTROL -bor [DS.TIHelper]::KEY_ENUMERATE_SUB_KEYS
            $ret = [DS.TIHelper]::RegOpenKeyExU(
                [DS.TIHelper]::HKLM, $sk,
                [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                $secAcc, [ref]$hKN)
            if ($ret -ne 0 -or $hKN -eq [IntPtr]::Zero) { return }
            try {
                $sdPtr = [IntPtr]::Zero; $sdSz = 0
                if ([DS.TIHelper]::ConvertStringSecurityDescriptorToSecurityDescriptor(
                        $script:ulrd_sdStr, [DS.TIHelper]::SDDL_REVISION_1, [ref]$sdPtr, [ref]$sdSz)) {
                    $sdB = New-Object byte[] $sdSz
                    [System.Runtime.InteropServices.Marshal]::Copy($sdPtr, $sdB, 0, $sdSz)
                    [DS.TIHelper]::LocalFree($sdPtr) | Out-Null
                    [DS.TIHelper]::RegSetKeySecurity(
                        $hKN,
                        ([DS.TIHelper]::DACL_SECURITY_INFO -bor [DS.TIHelper]::OWNER_SECURITY_INFO),
                        $sdB) | Out-Null
                }
                $sb = New-Object System.Text.StringBuilder 512
                $idx = 0
                while ($true) {
                    $nameLen = 512
                    $er = [DS.TIHelper]::RegEnumKeyExW(
                        $hKN, $idx, $sb, [ref]$nameLen,
                        [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
                    if ($er -ne 0) { break }
                    script:ULRD_ResetNode "$sk\$($sb.ToString(0, $nameLen))"
                    $idx++
                }
            } finally {
                [DS.TIHelper]::RegCloseKey($hKN) | Out-Null
            }
        }

        script:ULRD_ResetNode $HklmSubKey
        [DS.TIHelper]::RegDeleteTreeU([DS.TIHelper]::HKLM, $HklmSubKey) | Out-Null
    }
}


function Remove-RegistryKeyHard {
    param([string]$HklmSubKey)

    $checkPath = "HKLM:\$HklmSubKey"
    if (-not (Test-Path $checkPath)) { return $true }

    $null = Invoke-AsTrustedInstaller {
        [DS.TIHelper]::RegDeleteTreeU([DS.TIHelper]::HKLM, $HklmSubKey) | Out-Null
    }
    if (-not (Test-Path $checkPath)) { return $true }

    Unlock-RegKeyForDeletion -HklmSubKey $HklmSubKey
    if (-not (Test-Path $checkPath)) { return $true }

    $script:_rkhd_orphanSub = $null
    $null = Invoke-AsTrustedInstaller {
        $lastSlash = $HklmSubKey.LastIndexOf('\')
        if ($lastSlash -lt 0) { return }
        $parentSub  = $HklmSubKey.Substring(0, $lastSlash)
        $orphanLeaf = "__DEL_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + "__"

        $hKey = [IntPtr]::Zero
        $oRet = [DS.TIHelper]::RegOpenKeyExU(
            [DS.TIHelper]::HKLM, $HklmSubKey,
            [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
            [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
        if ($oRet -ne 0 -or $hKey -eq [IntPtr]::Zero) { return }

        try {
            $nameBytes = [System.Text.Encoding]::Unicode.GetBytes($orphanLeaf)
            $nameBuf   = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($nameBytes.Length + 2)
            [System.Runtime.InteropServices.Marshal]::Copy($nameBytes, 0, $nameBuf, $nameBytes.Length)
            [System.Runtime.InteropServices.Marshal]::WriteInt16($nameBuf, $nameBytes.Length, 0)
            $us = New-Object DS.TIHelper+UNICODE_STRING
            $us.Length        = [ushort]$nameBytes.Length
            $us.MaximumLength = [ushort]($nameBytes.Length + 2)
            $us.Buffer        = $nameBuf
            $ntRet = [DS.TIHelper]::NtRenameKey($hKey, [ref]$us)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($nameBuf)
            if ($ntRet -eq 0) {
                $script:_rkhd_orphanSub = "$parentSub\$orphanLeaf"
            }
        } finally {
            [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
        }
    }
    if ($null -ne $script:_rkhd_orphanSub) {
        $orphanPath = "HKLM:\$script:_rkhd_orphanSub"
        if (Test-Path $orphanPath) {
            $null = Invoke-AsTrustedInstaller {
                [DS.TIHelper]::RegDeleteTreeU([DS.TIHelper]::HKLM, $script:_rkhd_orphanSub) | Out-Null
            }
            if (Test-Path $orphanPath) {
                Unlock-RegKeyForDeletion -HklmSubKey $script:_rkhd_orphanSub
            }
        }
        $script:_rkhd_orphanSub = $null
    }
    if (-not (Test-Path $checkPath)) { return $true }

    & "$env:windir\System32\reg.exe" DELETE "HKLM\$HklmSubKey" /f 2>&1 | Out-Null
    if (-not (Test-Path $checkPath)) { return $true }

    try { Remove-Item -Path $checkPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    return (-not (Test-Path $checkPath))
}

function Set-ServiceStartTI {
    param(
        [string]$ServiceName,
        [int]$StartValue,
        [string]$Label
    )
    $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (-not (Test-Path $svcPath)) {
        Write-StepLog $Label "SKIP" "(service key not found)"
        return $false
    }
    $currentStart = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
    if ($currentStart -eq $StartValue) {
        Write-StepLog $Label "SKIP" "(already Start=$StartValue)"
        return $true
    }
    $keyPath = "SYSTEM\CurrentControlSet\Services\$ServiceName"

    $ok = Set-RegValueTI -KeyPath $keyPath -ValueName "Start" -ValueData $StartValue -Label $Label
    if ($ok) { return $true }

    $modeMap = @{0="boot";1="system";2="auto";3="demand";4="disabled"}
    $mode    = $modeMap[$StartValue]

    $cc1Key  = "SYSTEM\ControlSet001\Services\$ServiceName"
    $cc1Path = "HKLM:\$cc1Key"
    if (Test-Path $cc1Path) {
        Write-Host "    [CC1] Trying ControlSet001 direct path for $ServiceName ..." -ForegroundColor DarkYellow
        $okCC1 = Set-RegValueTI -KeyPath $cc1Key -ValueName "Start" -ValueData $StartValue -Label "$Label (ControlSet001)"
        if ($okCC1) {
            $verify = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($verify -eq $StartValue) {
                Write-StepLog $Label "OK" "(ControlSet001 path succeeded, CurrentControlSet reflects change)"
                return $true
            } else {
                Write-StepLog $Label "INFO" "(ControlSet001 written; will reflect in CurrentControlSet after reboot)"
                return $true
            }
        }
    }

    if ($mode) {
        Write-Host "    [TI-SC] Trying sc.exe under TrustedInstaller for $ServiceName ..." -ForegroundColor DarkYellow
        $null = Invoke-AsTrustedInstaller {
            & sc.exe config $ServiceName start= $mode 2>&1 | Out-Null
        }
        $verify = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($verify -eq $StartValue) {
            Write-StepLog $Label "OK" "(sc.exe TI fallback: Start=$StartValue)"
            return $true
        }

        Write-Host "    [TI-REG] Trying reg.exe ADD under TrustedInstaller for $ServiceName ..." -ForegroundColor DarkYellow
        $null = Invoke-AsTrustedInstaller {
            & reg.exe ADD "HKLM\SYSTEM\CurrentControlSet\Services\$ServiceName" `
                /v Start /t REG_DWORD /d $StartValue /f 2>&1 | Out-Null
        }
        $verify = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($verify -eq $StartValue) {
            Write-StepLog $Label "OK" "(reg.exe TI fallback: Start=$StartValue, verified)"
            return $true
        }

        Write-Host "    [OWN] Trying ownership+DACL unlock for $ServiceName ..." -ForegroundColor DarkYellow
        $okOwn = Set-RegKeyOwnershipAndWrite -KeyPath $keyPath -ValueName "Start" -ValueData $StartValue -Label $Label
        if ($okOwn) {
            $verify = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($verify -eq $StartValue) {
                Write-StepLog $Label "OK" "(ownership+DACL unlock succeeded, Start=$StartValue verified)"
                return $true
            }
        }

        $verify    = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
        $actualVal = if ($null -eq $verify) { "null" } else { "$verify" }
        $modeNames = @{0="Boot";1="System";2="Auto";3="Manual";4="Disabled"}
        $expName   = $modeNames[$StartValue]
        $actName   = if ($null -ne $verify) { $modeNames[[int]$verify] } else { "?" }
        Write-StepLog $Label "FAIL" "(ALL 5 METHODS FAILED for $ServiceName — wanted Start=$StartValue [$expName], got Start=$actualVal [$actName])"
        Write-Host "      ROOT CAUSE: WdFilter.sys kernel registry callback is active (independent of TP registry value)." -ForegroundColor DarkYellow
        Write-Host "      SOLUTIONS:" -ForegroundColor DarkYellow
        Write-Host "        A) Disable Tamper Protection in Windows Security UI, REBOOT, then re-run this script." -ForegroundColor DarkYellow
        Write-Host "        B) Boot into Safe Mode (WdFilter does not load), run script, reboot normal." -ForegroundColor DarkYellow
        Write-Host "        NOTE: Policy keys are already applied — Defender scanning is functionally disabled." -ForegroundColor DarkYellow
        return $false
    }
    return $false
}



function Set-TamperProtection {
    param(
        [ValidateSet(4, 5)]
        [int]$Value          
    )

    $label      = if ($Value -eq 4) { "TamperProtection → 4 (OFF)" } else { "TamperProtection → 5 (ON)" }
    $featKeyPath = "SOFTWARE\Microsoft\Windows Defender\Features"

    Write-Host ""
    Write-Host "  [TamperProtection] Setting value=$Value via TrustedInstaller..." -ForegroundColor DarkYellow

    $ok = Set-RegValueTI `
        -KeyPath   $featKeyPath `
        -ValueName "TamperProtection" `
        -ValueData $Value `
        -Label     $label

    if ($ok) {
        Start-Sleep -Milliseconds 600
        return $true
    }

    Write-Host "    [TI-REG] Primary write failed — trying reg.exe under TI..." -ForegroundColor DarkYellow
    Invoke-AsTrustedInstaller {
        & reg.exe ADD "HKLM\SOFTWARE\Microsoft\Windows Defender\Features" `
            /v TamperProtection /t REG_DWORD /d $Value /f 2>&1 | Out-Null
    } | Out-Null

    $verify = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" "TamperProtection"
    if ($verify -eq $Value) {
        Write-StepLog $label "OK" "(reg.exe TI fallback succeeded)"
        Start-Sleep -Milliseconds 600
        return $true
    }

    Write-StepLog $label "FAIL" "(all methods failed — kernel/PPL is blocking writes)"
    Write-Host "    Hint: Disable Tamper Protection manually in Windows Security first." -ForegroundColor DarkYellow
    return $false
}

function Import-RegFileWithStepLog {
    param([string]$Content, [string]$Name)
    Write-Host ""
    Write-Host "  --- $Name ---" -ForegroundColor Yellow

    $allLines  = $Content -split "`r?`n"
    $tiLines   = [System.Collections.Generic.List[string]]::new()
    $hkcuLines = [System.Collections.Generic.List[string]]::new()
    $hkcuLines.Add('Windows Registry Editor Version 5.00')
    $hkcuLines.Add('')
    $inHkcu = $false

    $keyCount = 0
    $valCount = 0
    $deleteCount = 0
    foreach ($ln in $allLines) {
        $t = $ln.TrimEnd()
        if ($t -match '^\[(-?)([A-Z_]+)\\') {
            $inHkcu = ($Matches[2] -eq 'HKEY_CURRENT_USER')
            if ($Matches[1] -eq '-') { $deleteCount++ } else { $keyCount++ }
        }
        if ($t -match '^(@|"[^"]*")\s*=') { $valCount++ }
        if ($inHkcu) { $hkcuLines.Add($t) } else { $tiLines.Add($t) }
    }

    $tiLinesCopy = $tiLines.ToArray()
    $ok = Invoke-AsTrustedInstaller { Invoke-RegContent -Lines $tiLinesCopy }

    $ctxLabel = if ($script:TI_CtxLabel) { "($($script:TI_CtxLabel))" } else { "(elevated)" }
    if ($ok) {
        Write-StepLog "$Name (HKLM: ~$keyCount keys, ~$valCount vals, ~$deleteCount deletes)" "OK" $ctxLabel
    } else {
        Write-StepLog "$Name (HKLM)" "FAIL" "(registry import had issues — TI impersonation may have failed; Tamper Protection or ACL restrictions likely blocking writes. Context: $ctxLabel)"
    }

    if ($hkcuLines.Count -gt 2) {
        $tmpFile = Join-Path $env:TEMP "DS_hkcu_$(Get-Random).reg"
        try {
            ($hkcuLines -join "`r`n") | Set-Content -Path $tmpFile -Encoding Unicode
            $regOutput = & reg.exe import $tmpFile 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-StepLog "$Name (HKCU)" "OK" "(reg.exe import)"
            } else {
                Write-StepLog "$Name (HKCU)" "FAIL" "(reg.exe exit $LASTEXITCODE — $($regOutput.Trim()) — possible cause: key protected by policy or permissions)"
            }
        } catch {
            Write-StepLog "$Name (HKCU)" "FAIL" "(exception: $_ — the HKCU hive may be locked or the .reg temp file could not be written)"
        } finally {
            Remove-Item $tmpFile -ErrorAction SilentlyContinue
        }
    }
    return $ok
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

function Get-RegKeyExists {
    param([string]$Path)
    return (Test-Path $Path)
}

function Test-TamperProtectionEnabled {
    $tp = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" "TamperProtection"
    if ($null -eq $tp) { return $true }
    return ($tp -eq 5 -or $tp -eq 1)
}

$script:DS_TouchedServices = @(
    @{N="WdBoot";               Def=0; Label="Defender Boot Driver"},
    @{N="WdFilter";             Def=0; Label="Defender Mini-Filter Driver"},
    @{N="WdNisDrv";             Def=3; Label="Defender Network Inspection Driver"},
    @{N="WdNisSvc";             Def=3; Label="Defender Network Inspection Service"},
    @{N="WinDefend";            Def=2; Label="Windows Defender Antivirus"},
    @{N="Sense";                Def=3; Label="Advanced Threat Protection (Sense)"},
    @{N="SecurityHealthService";Def=3; Label="Windows Security Health Service"},
    @{N="wscsvc";               Def=2; Label="Security Center (wscsvc)"},
    @{N="MsSecCore";            Def=0; Label="Microsoft Security Core"},
    @{N="MsSecFlt";             Def=0; Label="Microsoft Security Filter"},
    @{N="MsSecWfp";             Def=3; Label="Microsoft Security WFP"},
    @{N="SgrmAgent";            Def=0; Label="System Guard Runtime Monitor Agent"},
    @{N="SgrmBroker";           Def=2; Label="System Guard Runtime Monitor Broker"},
    @{N="webthreatdefsvc";      Def=3; Label="Web Threat Defense Service"},
    @{N="webthreatdefusersvc";  Def=3; Label="Web Threat Defense User Service"},
    @{N="MDCoreSvc";            Def=3; Label="Microsoft Defender Core Service"},
    @{N="MDDlpSvc";            Def=3; Label="Microsoft Defender DLP Service"},
    @{N="MpsSvc";               Def=2; Label="Windows Defender Firewall (MpsSvc)"},
    @{N="WdDevFlt";             Def=0; Label="Defender Device Filter Driver"}
)

$script:DS_TouchedTasks = @(
    "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
    "Microsoft\Windows\Windows Defender\Windows Defender Cleanup",
    "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
    "Microsoft\Windows\Windows Defender\Windows Defender Verification",
    "Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh",
    "Microsoft\Windows\MicrosoftAntimalware\MpIdleTask",
    "Microsoft\Windows\MicrosoftAntimalware\MpMpTasks"
)

function Get-TaskStateString {
    param([string]$TaskPath)
    try {
        $parts      = $TaskPath -split '\\'
        $taskName   = $parts[-1]
        $folderPath = '\' + ($parts[0..($parts.Length - 2)] -join '\')
        $t = Get-ScheduledTask -TaskPath $folderPath -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $t) { return $null }
        switch ([int]$t.State) {
            1 { return "Disabled" }
            2 { return "Queued"   }
            3 { return "Ready"    }
            4 { return "Running"  }
            default { return "Unknown" }
        }
    } catch {
        $localeDisabled = @(
            'Disabled',       
            'Отключено',      
            'Deaktiviert',    
            'Désactivé',      
            'Deshabilitado',  
            'Disabilitato',   
            'Deaktiveret',    
            'Inaktiverad',    
            'Disabled',       
            '無効',            
            '사용 안 함'        
        )
        $localeReady = @(
            'Ready', 'Готово', 'Bereit', 'Prêt', 'Listo', 'Pronto',
            'Klar', 'Klart', 'Pronto', '準備完了', '준비'
        )
        $localeRunning = @(
            'Running', 'Выполняется', 'Wird ausgeführt', 'En cours',
            'Ejecutando', 'In esecuzione', 'Kører', 'Körs', 'A executar', '実行中', '실행 중'
        )
        $localeQueued = @(
            'Queued', 'В очереди', 'In der Warteschlange', 'En file d''attente',
            'En cola', 'In coda', 'I kø', 'I kö', 'Em fila', 'キュー', '대기 중'
        )
        try {
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
            $csv = & schtasks.exe /Query /TN "\$TaskPath" /FO CSV /NH 2>&1
            $ec  = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($ec -ne 0 -or [string]::IsNullOrWhiteSpace($csv)) { return $null }
            $csvLine = ($csv | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('"') }) | Select-Object -First 1
            if (-not $csvLine) { return $null }
            $fields = $csvLine -split '","'
            $raw    = ($fields[-1] -replace '"','').Trim()
            if ($localeDisabled -contains $raw) { return "Disabled" }
            if ($localeReady    -contains $raw) { return "Ready"    }
            if ($localeRunning  -contains $raw) { return "Running"  }
            if ($localeQueued   -contains $raw) { return "Queued"   }
            return $raw   
        } catch { return $null }
    }
}

function Start-ScheduleServiceIfNeeded {
    $svc = Get-Service "Schedule" -ErrorAction SilentlyContinue
    if ($null -eq $svc)                      { return $false }
    if ($svc.Status -eq 'Running')           { return $false }   
    try {
        Write-Host "  [Safe Mode] Starting Task Scheduler service for task management..." -ForegroundColor Cyan
        Start-Service "Schedule" -ErrorAction Stop
        $dl = (Get-Date).AddSeconds(12)
        while ((Get-Service "Schedule" -EA SilentlyContinue).Status -ne 'Running' -and (Get-Date) -lt $dl) {
            Start-Sleep -Milliseconds 200
        }
        if ((Get-Service "Schedule" -EA SilentlyContinue).Status -eq 'Running') {
            Write-Host "  [Safe Mode] Task Scheduler started successfully." -ForegroundColor Green
            return $true
        }
        Write-Host "  [Safe Mode] Task Scheduler did not reach Running state — XML fallback will be used." -ForegroundColor Yellow
        return $false
    } catch {
        Write-Host "  [Safe Mode] Could not start Task Scheduler: $_ — XML fallback will be used." -ForegroundColor Yellow
        return $false
    }
}

function Decode-MitigationOptions {
    param([object]$v)
    if ($null -eq $v)               { return "(not set)" }

    $bytes = $null
    if ($v -is [byte[]]) {
        $bytes = $v
    } elseif ($v -is [System.Array]) {
        try { $bytes = [byte[]]@($v | ForEach-Object { [byte]$_ }) } catch { $bytes = $null }
    }
    if ($null -eq $bytes) { return "(value: $v)" }
    if ($bytes.Length -eq 0) { return "(empty)" }

    $slotNames = @{
        2  = "ForceASLR"          
        3  = "HeapTerminate"      
        4  = "BottomUpASLR"       
        5  = "HighEntropyASLR"    
        6  = "StrictHandleChk"    
        7  = "Win32kSysCallDis"   
        8  = "ExtensionPtDis"     
        9  = "DynamicCode"        
        10 = "CFG"                
        11 = "BinarySig"          
        12 = "FontLoadPrev"       
        13 = "RemoteImgLoad"      
        14 = "LowLabelImgLoad"    
        15 = "PreferSystem32"     

        16 = "LoaderIntegrity"    
        18 = "StrictCFG"          
        19 = "ModuleTampering"    
        20 = "IndBranchPredict"   
        21 = "DynCodeDowngrade"   
        22 = "SpecStoreBypass"    
        23 = "CETShadowStack"     
        24 = "CETContextIPVal"    
        25 = "NonCETBinaries"     
        26 = "XtendedCFG"         
        27 = "PointerAuthUserIP"  
        28 = "CETDynApisOOP"      
        29 = "CETIPValRelaxed"    
        30 = "FsctlSysCallDis"    

    }
    $valMap = @{0="def";1="ON";2="OFF";3="alt"}

    $hex = ([BitConverter]::ToString($bytes)).Replace('-',' ').ToLower()

    $parts    = @()
    $nQWords  = [int][Math]::Floor($bytes.Length / 8)
    if ($nQWords -lt 1 -and $bytes.Length -gt 0) { $nQWords = 1 }  
    for ($q = 0; $q -lt $nQWords; $q++) {
        $qw = [UInt64]0
        for ($i = 0; $i -lt 8; $i++) {
            $byteIdx = ($q * 8) + $i
            if ($byteIdx -lt $bytes.Length) {
                $qw = $qw -bor ([UInt64]$bytes[$byteIdx] -shl ($i * 8))
            }
        }

        if ($q -eq 0) {
            $nib0 = [int]($qw -band 0xF)
            $dep  = if ($nib0 -band 0x1) { "ON" } else { "def" }
            $atl  = if ($nib0 -band 0x2) { "ON" } else { "def" }
            $seh  = if ($nib0 -band 0x4) { "ON" } else { "def" }
            $parts += "DEP=$dep"
            $parts += "DEP_ATL_Thunk=$atl"
            $parts += "SEHOP=$seh"
            if ($nib0 -band 0x8) { $parts += "nib0_bit3=set" }   
        }

        $startIdx = if ($q -eq 0) { 1 } else { 0 }
        for ($i = $startIdx; $i -lt 16; $i++) {
            $nib     = [int](($qw -shr ($i * 4)) -band 0xF)
            $slotIdx = ($q * 16) + $i
            $isNamed = $slotNames.ContainsKey($slotIdx)
            if ($nib -eq 0 -and -not $isNamed) { continue }   
            $name  = if ($isNamed) { $slotNames[$slotIdx] } else { "slot$slotIdx" }
            $label = if ($valMap.ContainsKey($nib)) { $valMap[$nib] } else { "v$nib" }
            $parts += "$name=$label"
        }
    }

    if ($parts.Count -eq 0) { return "(hex: $hex — all defaults)" }
    return "(hex: $hex — " + ($parts -join ', ') + ")"
}

function Decode-BinaryBlob {
    param([object]$v)
    if ($null -eq $v)            { return "(not set)" }

    $bytes = $null
    if ($v -is [byte[]]) {
        $bytes = $v
    } elseif ($v -is [System.Array]) {
        try { $bytes = [byte[]]@($v | ForEach-Object { [byte]$_ }) } catch { $bytes = $null }
    }
    if ($null -eq $bytes)  { return "(value: $v)" }
    if ($bytes.Length -eq 0) { return "(empty)" }

    $hex = ([BitConverter]::ToString($bytes)).Replace('-',' ').ToLower()
    $allZero = $true
    foreach ($b in $bytes) { if ($b -ne 0) { $allZero = $false; break } }
    if ($allZero) { return "(hex: $hex — all zeros = cleared/disabled)" }
    return "(hex: $hex)"
}

function Decode-MinutesOfDay {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    if ($n -lt 0)       { return "(value: $n [negative — anomalous])" }
    if ($n -eq 1440)    { return "(value: 1440 → 24:00 / midnight)" }
    if ($n -lt 1440) {
        $h = [int]([Math]::Floor($n / 60))
        $m = [int]($n % 60)
        return ("(value: $n → {0:D2}:{1:D2})" -f $h, $m)
    }
    $mod = $n % 1440
    $h = [int]([Math]::Floor($mod / 60))
    $m = [int]($mod % 60)
    return ("(value: $n [out-of-spec, >1440; mod-1440 ≈ {0:D2}:{1:D2}])" -f $h, $m)
}

function Decode-CloudBlockLevel {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    $t = switch ($n) { 0{"Default"} 2{"High"} 4{"HighPlus"} 6{"ZeroTolerance"} default {"Custom/Unknown"} }
    return "(value: $n [$t])"
}

function Decode-SubmitSamples {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    $t = switch ($n) { 0{"AlwaysPrompt"} 1{"SendSafeSamples"} 2{"NeverSend"} 3{"SendAllSamples"} default {"Unknown"} }
    return "(value: $n [$t])"
}

function Decode-RTScanDir {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    $t = switch ($n) { 0{"Both"} 1{"Incoming"} 2{"Outgoing"} default {"Unknown"} }
    return "(value: $n [$t])"
}

function Decode-ScanParam {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    $t = switch ($n) { 1{"Quick"} 2{"Full"} default {"Unknown"} }
    return "(value: $n [$t])"
}

function Decode-ScheduleDay {
    param([object]$v)
    if ($null -eq $v) { return "(not set)" }
    $n = [int]$v
    $t = switch ($n) {
        0{"EveryDay"} 1{"Sunday"} 2{"Monday"} 3{"Tuesday"} 4{"Wednesday"}
        5{"Thursday"} 6{"Friday"} 7{"Saturday"} 8{"Never"} default {"Unknown"}
    }
    return "(value: $n [$t])"
}

function Decode-Percent   { param($v) if ($null -eq $v) { "(not set)" } else { "(value: $v [$v`%])" } }
function Decode-Days      { param($v) if ($null -eq $v) { "(not set)" } else { "(value: $v [$v days])" } }
function Decode-Hours     { param($v) if ($null -eq $v) { "(not set)" } else { "(value: $v [every $v h])" } }
function Decode-Seconds   { param($v) if ($null -eq $v) { "(not set)" } else { "(value: $v [$v s])" } }
function Decode-KB        { param($v) if ($null -eq $v) { "(not set)" } else { "(value: $v [$v KB])" } }

function Show-StatusItem {
    param([string]$Label, [string]$State, [string]$Detail = "")
    $pad = 64
    $labelPad = if ($Label.Length -ge $pad) { "$Label " } else { $Label.PadRight($pad) }
    switch ($State) {
        "ENABLED"    { $color = "Green"  }
        "DISABLED"   { $color = "Red"    }
        "MISSING"    { $color = "Gray"   }
        "RENAMED"    { $color = "Red"    }
        "DEFAULT"    { $color = "Cyan"   }
        "SET"        { $color = "DarkYellow" }
        default      { $color = "Yellow" }
    }
    $stateStr = "[$State]"
    if ($Detail) { $stateStr += " $Detail" }
    Write-Host "  $labelPad" -NoNewline
    Write-Host $stateStr -ForegroundColor $color
}

function Show-DefenderStatus {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              DEFENDER STATUS DASHBOARD  —  ACTION-SYNCED VIEW             ║" -ForegroundColor Cyan
    Write-Host "║   Every path / key / value / file / service / task used by Disable/Enable ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  Note: Items marked (read-only) are shown for status only — Disable/Enable never modifies them." -ForegroundColor DarkGray
    Write-Host ""

    $script:_dsDisabled = 0
    $script:_dsEnabled  = 0
    $script:_dsMissing  = 0
    $script:_dsDefault  = 0
    $script:_dsSet      = 0

    function Track { param($s)
        if ($s -eq "DISABLED" -or $s -eq "RENAMED") { $script:_dsDisabled++ }
        elseif ($s -eq "MISSING") { $script:_dsMissing++ }
        elseif ($s -eq "SET") { $script:_dsSet++ }
        elseif ($s -eq "DEFAULT" -or $s -eq "SOURCE" -or $s -eq "UNKNOWN" -or $s -eq "CUSTOM") { $script:_dsDefault++ }
        else { $script:_dsEnabled++ }
    }

    function Fmt { param($v)
        if ($null -eq $v) { return "(not set)" }
        return "(value: $v)"
    }

    function FmtHex { param($v)
        if ($null -eq $v) { return "(not set)" }
        if ($v -is [byte[]]) { return "(binary: $([BitConverter]::ToString($v).Replace('-',' ').ToLower()))" }
        return "(value: $v)"
    }

    Write-Host "  ╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║               TAMPER PROTECTION — LIVE STATUS CHECK                  ║" -ForegroundColor DarkCyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan

    $tpRegVal = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features" "TamperProtection"
    $tpRegState = "UNKNOWN"
    $tpRegDetail = "(not set)"
    if ($null -ne $tpRegVal) {
        $tpRegDetail = "(value: $tpRegVal)"
        if ($tpRegVal -eq 5 -or $tpRegVal -eq 1) { $tpRegState = "ON" }
        elseif ($tpRegVal -eq 0 -or $tpRegVal -eq 4) { $tpRegState = "OFF" }
        else { $tpRegState = "UNKNOWN ($tpRegVal)" }
    }

    $tpLiveState = "UNKNOWN"
    $tpLiveDetail = ""
    $mpStatusAvail = $false
    try {
        $mpStat = Get-MpComputerStatus -ErrorAction Stop
        $mpStatusAvail = $true
        if ($null -ne $mpStat.IsTamperProtected) {
            $tpLiveState = if ($mpStat.IsTamperProtected) { "ON" } else { "OFF" }
            $tpLiveDetail = "(IsTamperProtected=$($mpStat.IsTamperProtected))"
        } else {
            $tpLiveDetail = "(IsTamperProtected property not available)"
        }
        $script:_mpLiveRTP = $mpStat.RealTimeProtectionEnabled
        $script:_mpLiveAV  = $mpStat.AntivirusEnabled
        $script:_mpLiveAS  = $mpStat.AntispywareEnabled
    } catch {
        $tpLiveDetail = "(Get-MpComputerStatus unavailable — Defender service may be stopped)"
        $script:_mpLiveRTP = $null
        $script:_mpLiveAV  = $null
        $script:_mpLiveAS  = $null
    }

    $pplState = "UNKNOWN"
    $pplDetail = ""
    try {
        $mpProc = Get-Process -Name "MsMpEng" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mpProc) {
            $hProc = [DS.TIHelper]::OpenProcess([DS.TIHelper]::PROCESS_ALL_ACCESS, $false, $mpProc.Id)
            if ($hProc -eq [IntPtr]::Zero) {
                $pplState = "YES (PPL)"
                $pplDetail = "(MsMpEng.exe PID=$($mpProc.Id) — protected, kernel blocks access)"
            } else {
                $pplState = "NO"
                $pplDetail = "(MsMpEng.exe PID=$($mpProc.Id) — not PPL-protected)"
                [DS.TIHelper]::CloseHandle($hProc) | Out-Null
            }
        } else {
            $pplState = "N/A"
            $pplDetail = "(MsMpEng.exe not running)"
        }
    } catch {
        $pplDetail = "(check failed: $_)"
    }

    $tpConsensus = "UNKNOWN"
    $tpColor = "Yellow"
    if ($tpRegState -eq "ON" -and $tpLiveState -eq "ON") {
        $tpConsensus = "ACTIVE (registry ON + live ON)"
        $tpColor = "Red"
    } elseif ($tpRegState -eq "ON" -and $tpLiveState -eq "OFF") {
        $tpConsensus = "MISMATCH (registry ON but live OFF — may need reboot)"
        $tpColor = "Yellow"
    } elseif ($tpRegState -eq "OFF" -and $tpLiveState -eq "ON") {
        $tpConsensus = "MISMATCH (registry OFF but live ON — kernel/PPL still enforcing)"
        $tpColor = "Yellow"
    } elseif ($tpRegState -eq "OFF" -and $tpLiveState -eq "OFF") {
        $tpConsensus = "INACTIVE (registry OFF + live OFF)"
        $tpColor = "Green"
    } elseif ($tpRegState -eq "OFF" -and $tpLiveState -eq "UNKNOWN") {
        $tpConsensus = "LIKELY INACTIVE (registry OFF, live status unavailable)"
        $tpColor = "Green"
    } elseif ($tpRegState -eq "ON" -and $tpLiveState -eq "UNKNOWN") {
        $tpConsensus = "LIKELY ACTIVE (registry ON, live status unavailable)"
        $tpColor = "Red"
    } else {
        $tpConsensus = "INDETERMINATE (reg=$tpRegState, live=$tpLiveState)"
        $tpColor = "Yellow"
    }

    $pad = 64
    Write-Host ("  " + "Tamper Protection (registry)".PadRight($pad)) -NoNewline
    $regCol = if ($tpRegState -eq "ON") { "Green" } elseif ($tpRegState -eq "OFF") { "Red" } else { "Yellow" }
    Write-Host "[$tpRegState] $tpRegDetail" -ForegroundColor $regCol
    Write-Host ("  " + "Tamper Protection (live/WMI)".PadRight($pad)) -NoNewline
    $liveCol = if ($tpLiveState -eq "ON") { "Green" } elseif ($tpLiveState -eq "OFF") { "Red" } else { "Yellow" }
    Write-Host "[$tpLiveState] $tpLiveDetail" -ForegroundColor $liveCol
    Write-Host ("  " + "MsMpEng.exe PPL protection".PadRight($pad)) -NoNewline
    $pplCol = if ($pplState -eq "YES (PPL)") { "Green" } elseif ($pplState -eq "NO") { "Red" } else { "Yellow" }
    Write-Host "[$pplState] $pplDetail" -ForegroundColor $pplCol

    if ($mpStatusAvail) {
        $rtpTxt = if ($script:_mpLiveRTP) { "RTP=ON" } else { "RTP=OFF" }
        $avTxt  = if ($script:_mpLiveAV)  { "AV=ON" }  else { "AV=OFF" }
        $asTxt  = if ($script:_mpLiveAS)  { "AS=ON" }  else { "AS=OFF" }
        $rtpCol = if ($script:_mpLiveRTP) { "Green" }  else { "Red" }
        $avCol  = if ($script:_mpLiveAV)  { "Green" }  else { "Red" }
        $asCol  = if ($script:_mpLiveAS)  { "Green" }  else { "Red" }
        Write-Host ("  " + "Live Defender Engine Status".PadRight($pad)) -NoNewline
        Write-Host "[" -NoNewline
        Write-Host $rtpTxt -ForegroundColor $rtpCol -NoNewline
        Write-Host " | " -NoNewline
        Write-Host $avTxt -ForegroundColor $avCol -NoNewline
        Write-Host " | " -NoNewline
        Write-Host $asTxt -ForegroundColor $asCol -NoNewline
        Write-Host "]"
    }

    Write-Host ""
    Write-Host ("  " + ">>> TAMPER PROTECTION VERDICT".PadRight($pad)) -NoNewline
    if ($script:InSafeMode) {
        Write-Host "[SAFE MODE — ALL OPERATIONS WILL SUCCEED]" -ForegroundColor Cyan
        Write-Host "      Running in Safe Mode: WdFilter.sys is NOT loaded, PPL is NOT enforced." -ForegroundColor Cyan
        Write-Host "      Tamper Protection detection is irrelevant — all registry writes will succeed." -ForegroundColor Green
    } else {
        Write-Host "[$tpConsensus]" -ForegroundColor $tpColor
        if ($tpColor -eq "Red") {
            Write-Host "      Disable/Enable operations on Defender-protected keys WILL be blocked." -ForegroundColor Red
            Write-Host "      → Disable Tamper Protection manually: Windows Security > Virus & threat" -ForegroundColor Yellow
            Write-Host "        protection > Virus & threat protection settings > Tamper Protection → OFF" -ForegroundColor Yellow
        } elseif ($tpColor -eq "Green") {
            Write-Host "      Tamper Protection is OFF — Disable/Enable operations on Defender-protected" -ForegroundColor Green
            Write-Host "      keys WILL NOT be blocked by TP. (Note: WdFilter kernel callbacks may still" -ForegroundColor Green
            Write-Host "      protect a few service keys until next reboot — that is independent of TP.)" -ForegroundColor Green
        } else {
            Write-Host "      Verdict is mixed — registry and live state disagree. Disable/Enable may" -ForegroundColor Yellow
            Write-Host "      partially succeed; a reboot usually reconciles the two states." -ForegroundColor Yellow
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [1] SMARTSCREEN EXECUTABLE ──────────────────────────────────────────" -ForegroundColor DarkCyan
    $ssExe  = "C:\Windows\System32\smartscreen.exe"
    $ssExee = "C:\Windows\System32\smartscreen.exee"
    if (Test-Path $ssExe) {
        Show-StatusItem "  C:\Windows\System32\smartscreen.exe" "ENABLED" "(original .exe present)"
        Track "ENABLED"
    } elseif (Test-Path $ssExee) {
        Show-StatusItem "  C:\Windows\System32\smartscreen.exe" "RENAMED" "(renamed to .exee — DISABLED)"
        Track "RENAMED"
    } else {
        Show-StatusItem "  C:\Windows\System32\smartscreen.exe" "MISSING" "(neither .exe nor .exee found)"
        Track "MISSING"
    }
    if (Test-Path $ssExee) {
        Show-StatusItem "  C:\Windows\System32\smartscreen.exee" "RENAMED" "(rename file exists)"
        Track "RENAMED"
    } else {
        Show-StatusItem "  C:\Windows\System32\smartscreen.exee" "DEFAULT" "(rename file absent)"
        Track "ENABLED"
    }
    Write-Host ""

    Write-Host "  ┌─ [2] MITIGATION / EXPLOIT PROTECTION ────────────────────────────────" -ForegroundColor DarkCyan

    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\WindowsMitigation" "UserPreference"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 2) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKLM\...\WindowsMitigation  UserPreference" $s (Fmt $v)
    Track $s

    $kernBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $v = Get-RegValue $kernBase "KernelSEHOPEnabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  kernel  KernelSEHOPEnabled" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $kernBase "MitigationOptions"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  kernel  MitigationOptions (read-only)" $s (Decode-MitigationOptions $v)
    Track $s

    $v = Get-RegValue $kernBase "MitigationAuditOptions"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  kernel  MitigationAuditOptions (read-only)" $s (Decode-MitigationOptions $v)
    Track $s

    $v = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\SCMConfig" "EnableSvchostMitigationPolicy"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0 -or ($v -is [byte[]] -and ($v | ForEach-Object { $_ } | Measure-Object -Sum).Sum -eq 0)) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  SCMConfig  EnableSvchostMitigationPolicy" $s (Decode-BinaryBlob $v)
    Track $s

    $v = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" "VulnerableDriverBlocklistEnable"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  CI\Config  VulnerableDriverBlocklistEnable (read-only)" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  CI\Policy  VerifiedAndReputablePolicyState" $s (Fmt $v)
    Track $s

    $lsaBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $v = Get-RegValue $lsaBase "RunAsPPL"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Lsa  RunAsPPL" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $lsaBase "RunAsPPLBoot"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Lsa  RunAsPPLBoot" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $lsaBase "LsaConfigFlags"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Lsa  LsaConfigFlags" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "RunAsPPL"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Policies\Windows\System  RunAsPPL" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [3] TAMPER PROTECTION & DEFENDER FEATURES ───────────────────────────" -ForegroundColor DarkCyan

    function Get-TamperProtectionStatus {
        param([object]$Value)
        if ($null -eq $Value) { return @{ Status = "UNKNOWN"; Detail = "(not set)" } }
        $i = [int]$Value
        switch ($i) {
            5 { return @{ Status = "ENABLED";  Detail = "(value: 5)" } }
            1 { return @{ Status = "ENABLED";  Detail = "(value: 1)" } }
            0 { return @{ Status = "DISABLED"; Detail = "(value: 0)" } }
            4 { return @{ Status = "DISABLED"; Detail = "(value: 4)" } }
            default { return @{ Status = "CUSTOM"; Detail = "(value: $i)" } }
        }
    }

    function Get-TamperProtectionSourceText {
        param([object]$Value)
        if ($null -eq $Value) { return "(not set)" }
        $i = [int]$Value
        switch ($i) {
            1  { return "Init (default, unchanged)" }
            2  { return "User Interface (GUI)" }
            3  { return "E3" }
            4  { return "E5" }
            5  { return "Signatures" }
            6  { return "MpCmdRun (PowerShell/CMD)" }
            40 { return "Intune or ConfigMgr" }
            41 { return "ATP / MDE" }
            default { return "Unknown source" }
        }
    }

    $featBase = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
    $v = Get-RegValue $featBase "TamperProtection"
    $tp = Get-TamperProtectionStatus $v
    Show-StatusItem "  WD\Features  TamperProtection" $tp.Status ("$($tp.Detail)  [0/4=off  1/5=on]")
    Track $tp.Status

    $v = Get-RegValue $featBase "TamperProtectionSource"
    $srcText = Get-TamperProtectionSourceText $v
    Show-StatusItem "  WD\Features  TamperProtectionSource" "SOURCE" ("$srcText  $(Fmt $v)")

    $v = Get-RegValue $featBase "MpPlatformKillbitsFromEngine"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -is [byte[]] -and ($v | ForEach-Object { $_ } | Measure-Object -Sum).Sum -eq 0) {"DISABLED"} else {"SET"}
    Show-StatusItem "  WD\Features  MpPlatformKillbitsFromEngine" $s (Decode-BinaryBlob $v)
    Track $s

    $v = Get-RegValue $featBase "MpCapability"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -is [byte[]] -and ($v | ForEach-Object { $_ } | Measure-Object -Sum).Sum -eq 0) {"DISABLED"} else {"SET"}
    Show-StatusItem "  WD\Features  MpCapability" $s (Decode-BinaryBlob $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [4] REAL-TIME PROTECTION POLICY ─────────────────────────────────────" -ForegroundColor DarkCyan
    $rtpBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
    $rtpKeyExists = Get-RegKeyExists $rtpBase
    if (-not $rtpKeyExists) {
        Show-StatusItem "  RTP policy key (entire subkey)" "DEFAULT" "(key absent = Windows defaults)"
        Track "ENABLED"
    }
    foreach ($entry in @(
            @{N="DisableRealtimeMonitoring";                  Inv=1},
            @{N="DisableBehaviorMonitoring";                  Inv=1},
            @{N="DisableOnAccessProtection";                  Inv=1},
            @{N="DisableIOAVProtection";                      Inv=1},
            @{N="DisableIntrusionPreventionSystem";            Inv=1},
            @{N="DisableScanOnRealtimeEnable";                Inv=1},
            @{N="DisableInformationProtectionControl";        Inv=1},
            @{N="DisableRawWriteNotification";                Inv=1},
            @{N="DisableScriptScanning";                      Inv=1},
            @{N="IOAVMaxSize";                                Inv=-1},
            @{N="RealtimeScanDirection";                      Inv=-2},
            @{N="LocalSettingOverrideDisableRealtimeMonitoring";   Inv=0},
            @{N="LocalSettingOverrideDisableBehaviorMonitoring";   Inv=0},
            @{N="LocalSettingOverrideDisableOnAccessProtection";   Inv=0},
            @{N="LocalSettingOverrideDisableIOAVProtection";       Inv=0},
            @{N="LocalSettingOverrideDisableIntrusionPreventionSystem"; Inv=0},
            @{N="LocalSettingOverrideRealtimeScanDirection";       Inv=0})) {
        $v = Get-RegValue $rtpBase $entry.N
        if ($entry.Inv -eq -1) {
            $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
        } elseif ($entry.Inv -eq -2) {
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 2) {"DISABLED"} else {"ENABLED"}
        } elseif ($entry.Inv -eq 0) {
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
        } else {
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        }
        $detail = switch ($entry.N) {
            "IOAVMaxSize"           { Decode-KB         $v }
            "RealtimeScanDirection" { Decode-RTScanDir  $v }
            default                 { Fmt               $v }
        }
        Show-StatusItem "  RTP  $($entry.N)" $s $detail
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [5] ANTIVIRUS / DEFENDER POLICY (HKLM\...\Windows Defender) ─────────" -ForegroundColor DarkCyan
    $wdPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    foreach ($entry in @(
            @{N="DisableAntiSpyware";            Dis=1},
            @{N="DisableAntiVirus";              Dis=1},
            @{N="DisableRoutinelyTakingAction";   Dis=1},
            @{N="ServiceKeepAlive";               Dis=0},
            @{N="AllowFastServiceStartup";        Dis=0},
            @{N="DisableSpecialRunningModes";     Dis=1},
            @{N="DisableLocalAdminMerge";         Dis=1},
            @{N="PUAProtection";                  Dis=0},
            @{N="RandomizeScheduleTaskTimes";      Dis=0},
            @{N="DisablePrivacyMode";             Dis=1},
            @{N="HideExclusionsFromLocalAdmins";  Dis=0},
            @{N="DisableRealtimeMonitoring";       Dis=1})) {
        $v = Get-RegValue $wdPol $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WD Policy  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [6] WOW6432NODE DEFENDER POLICY ────────────────────────────────────" -ForegroundColor DarkCyan
    $wowPol = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender"
    foreach ($entry in @(
            @{N="DisableAntiSpyware";        Dis=1},
            @{N="DisableAntiVirus";          Dis=1},
            @{N="DisableSpecialRunningModes"; Dis=1},
            @{N="DisableRoutinelyTakingAction"; Dis=1},
            @{N="ServiceKeepAlive";           Dis=0},
            @{N="AllowFastServiceStartup";    Dis=0})) {
        $v = Get-RegValue $wowPol $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WOW6432Node WD  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [7] MICROSOFT ANTIMALWARE POLICY ────────────────────────────────────" -ForegroundColor DarkCyan
    $amPol = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware"
    foreach ($entry in @(
            @{N="ServiceKeepAlive";          Dis=0},
            @{N="AllowFastServiceStartup";   Dis=0},
            @{N="DisableRoutinelyTakingAction"; Dis=1},
            @{N="DisableAntiSpyware";         Dis=1},
            @{N="DisableAntiVirus";           Dis=1},
            @{N="DisableSpecialRunningModes"; Dis=1})) {
        $v = Get-RegValue $amPol $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  MS Antimalware  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    $amSpyBase = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet"
    $v = Get-RegValue $amSpyBase "SpyNetReporting"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MS Antimalware\SpyNet  SpyNetReporting" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $amSpyBase "LocalSettingOverrideSpyNetReporting"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MS Antimalware\SpyNet  LocalSettingOverrideSpyNetReporting" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [7b] MRT (MALICIOUS SOFTWARE REMOVAL TOOL) POLICY ───────────────────" -ForegroundColor DarkCyan
    $mrtPol = "HKLM:\SOFTWARE\Policies\Microsoft\MRT"
    $v = Get-RegValue $mrtPol "DontOfferThroughWUAU"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MRT Policy  DontOfferThroughWUAU" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $mrtPol "DontRunOnce"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MRT Policy  DontRunOnce" $s (Fmt $v)
    Track $s

    Write-Host "  ┌─ [8] SPYNET / CLOUD PROTECTION ───────────────────────────────────────" -ForegroundColor DarkCyan
    $spyBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
    foreach ($entry in @(
            @{N="DisableBlockAtFirstSeen";              DVal=1; DType="eq"},
            @{N="SpynetReporting";                      DVal=0; DType="eq"},
            @{N="SubmitSamplesConsent";                 DVal=2; DType="eq"},
            @{N="LocalSettingOverrideSpynetReporting";  DVal=0; DType="eq"})) {
        $v = Get-RegValue $spyBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.DVal) {"DISABLED"} else {"ENABLED"}
        $detail = if ($entry.N -eq "SubmitSamplesConsent") { Decode-SubmitSamples $v } else { Fmt $v }
        Show-StatusItem "  Spynet  $($entry.N)" $s $detail
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [9] POLICYMANAGER\DEFAULT\DEFENDER ─────────────" -ForegroundColor DarkCyan
    $pmDef = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Defender"
    $pmEntries = @(
        @{N="AllowBehaviorMonitoring";             EnabledVal=1},
        @{N="AllowIOAVProtection";                 EnabledVal=1},
        @{N="AllowArchiveScanning";                EnabledVal=1},
        @{N="AllowCloudProtection";                EnabledVal=1},
        @{N="AllowEmailScanning";                  EnabledVal=1},
        @{N="AllowFullScanOnMappedNetworkDrives";  EnabledVal=1},
        @{N="AllowFullScanRemovableDriveScanning"; EnabledVal=1},
        @{N="AllowIntrusionPreventionSystem";       EnabledVal=1},
        @{N="AllowOnAccessProtection";             EnabledVal=1},
        @{N="AllowRealtimeMonitoring";             EnabledVal=1},
        @{N="AllowScanningNetworkFiles";           EnabledVal=1},
        @{N="AllowScriptScanning";                 EnabledVal=1},
        @{N="AllowUserUIAccess";                   EnabledVal=1},
        @{N="CheckForSignaturesBeforeRunningScan";  EnabledVal=1},
        @{N="CloudBlockLevel";                     EnabledVal=-1},
        @{N="CloudExtendedTimeout";                EnabledVal=-1},
        @{N="AvgCPULoadFactor";                    EnabledVal=-1},
        @{N="DaysToRetainCleanedMalware";          EnabledVal=-1},
        @{N="DisableCatchupFullScan";              EnabledVal=0},
        @{N="DisableCatchupQuickScan";             EnabledVal=0},
        @{N="EnableControlledFolderAccess";        EnabledVal=1},
        @{N="EnableLowCPUPriority";               EnabledVal=0},
        @{N="EnableNetworkProtection";             EnabledVal=1},
        @{N="PUAProtection";                       EnabledVal=1},
        @{N="RealTimeScanDirection";               EnabledVal=-1},
        @{N="ScanParameter";                       EnabledVal=-1},
        @{N="ScheduleScanDay";                     EnabledVal=-1},
        @{N="ScheduleScanTime";                    EnabledVal=-1},
        @{N="SignatureUpdateInterval";             EnabledVal=-1},
        @{N="SubmitSamplesConsent";                EnabledVal=-1}
    )
    foreach ($entry in $pmEntries) {
        $subPath = "$pmDef\$($entry.N)"
        if (Get-RegKeyExists $subPath) {
            $v = Get-RegValue $subPath "value"
            if ($entry.EnabledVal -eq -1) {
                $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
            } elseif ($entry.EnabledVal -eq 0) {
                $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"ENABLED"} else {"DISABLED"}
            } else {
                $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.EnabledVal) {"ENABLED"} else {"DISABLED"}
            }
            $detail = switch ($entry.N) {
                "CloudBlockLevel"            { Decode-CloudBlockLevel $v }
                "CloudExtendedTimeout"       { Decode-Seconds         $v }
                "AvgCPULoadFactor"           { Decode-Percent         $v }
                "DaysToRetainCleanedMalware" { Decode-Days            $v }
                "RealTimeScanDirection"      { Decode-RTScanDir       $v }
                "ScanParameter"              { Decode-ScanParam       $v }
                "ScheduleScanDay"            { Decode-ScheduleDay     $v }
                "ScheduleScanTime"           { Decode-MinutesOfDay    $v }
                "SignatureUpdateInterval"    { Decode-Hours           $v }
                "SubmitSamplesConsent"       { Decode-SubmitSamples   $v }
                default                      { Fmt                    $v }
            }
            Show-StatusItem "  PMgr\Defender\$($entry.N)" $s $detail
            Track $s
        } else {
            Show-StatusItem "  PMgr\Defender\$($entry.N)" "MISSING" "(subkey absent)"
            Track "MISSING"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [10] MPENGINE POLICY ─────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $mpeBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine"
    foreach ($entry in @(
            @{N="MpEnablePus";              Dis=0},
            @{N="MpCloudBlockLevel";        Dis=0},
            @{N="MpBafsExtendedTimeout";    Dis=0},
            @{N="EnableFileHashComputation"; Dis=0})) {
        $v = Get-RegValue $mpeBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  MpEngine  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [11] NIS / IPS POLICY ────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $nisBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS"
    foreach ($entry in @(
            @{N="ThrottleDetectionEventsRate"; Dis=0},
            @{N="DisableSignatureRetirement";  Dis=1},
            @{N="DisableProtocolRecognition";   Dis=1})) {
        $v = Get-RegValue $nisBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  NIS\IPS  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" "DisableScanningNetworkFiles"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\Policy Manager  DisableScanningNetworkFiles" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [12] SCAN POLICY ──────────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $scanBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan"
    foreach ($entry in @(
            @{N="LowCpuPriority";              Dis=1},
            @{N="DisableRestorePoint";          Dis=1},
            @{N="DisableHeuristics";            Dis=1},
            @{N="DisableReparsePointScanning";  Dis=1},
            @{N="DisableCatchupQuickScan";      Dis=1},
            @{N="DisableCatchupFullScan";       Dis=1},
            @{N="DisableArchiveScanning";       Dis=1},
            @{N="DisableScanningNetworkFiles";  Dis=1},
            @{N="DisableEmailScanning";         Dis=1},
            @{N="DisableRemovableDriveScanning"; Dis=1})) {
        $v = Get-RegValue $scanBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  Scan  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    $v = Get-RegValue $scanBase "ScheduleDay"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 8) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Scan  ScheduleDay" $s (Decode-ScheduleDay $v)
    Track $s
    $v = Get-RegValue $scanBase "ScheduleTime"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  Scan  ScheduleTime" $s (Decode-MinutesOfDay $v)
    Track $s
    $v = Get-RegValue $scanBase "ScheduleQuickScanTime"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  Scan  ScheduleQuickScanTime" $s (Decode-MinutesOfDay $v)
    Track $s

    Write-Host "  ┌─ [12b] REMEDIATION SCAN POLICY ────────────────────────────────────────" -ForegroundColor DarkCyan
    $remBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Remediation"
    $v = Get-RegValue $remBase "Scan_ScheduleDay"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 8) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Remediation  Scan_ScheduleDay" $s (Decode-ScheduleDay $v)
    Track $s
    $v = Get-RegValue $remBase "Scan_ScheduleTime"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  Remediation  Scan_ScheduleTime" $s (Decode-MinutesOfDay $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [13] SIGNATURE UPDATES POLICY ────────────────────────────────────────" -ForegroundColor DarkCyan
    $sigBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates"
    foreach ($entry in @(
            @{N="SignatureDisableNotification";              Dis=1},
            @{N="DisableScanOnUpdate";                       Dis=1},
            @{N="RealtimeSignatureDelivery";                 Dis=0},
            @{N="UpdateOnStartUp";                           Dis=0},
            @{N="DisableUpdateOnStartupWithoutEngine";       Dis=1},
            @{N="ForceUpdateFromMU";                         Dis=0},
            @{N="DisableScheduledSignatureUpdateOnBattery";  Dis=1},
            @{N="SignatureUpdateCatchupInterval";             Dis=-1},
            @{N="ScheduleTime";                              Dis=-1})) {
        $v = Get-RegValue $sigBase $entry.N
        if ($entry.Dis -eq -1) {
            $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
        } else {
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        }
        $detail = switch ($entry.N) {
            "SignatureUpdateCatchupInterval" { Decode-Days         $v }
            "ScheduleTime"                   { Decode-MinutesOfDay $v }
            default                          { Fmt                 $v }
        }
        Show-StatusItem "  SigUpdates  $($entry.N)" $s $detail
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [14] UX CONFIGURATION POLICY ─────────────────────────────────────────" -ForegroundColor DarkCyan
    $uxBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration"
    foreach ($entry in @(
            @{N="SuppressRebootNotification"; Dis=1},
            @{N="UILockdown";                 Dis=1},
            @{N="Notification_Suppress";      Dis=1})) {
        $v = Get-RegValue $uxBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  UX Config  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [15] EXCLUSIONS POLICY ───────────────────────────────────────────────" -ForegroundColor DarkCyan
    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions" "DisableAutoExclusions"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Exclusions  DisableAutoExclusions" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [16] REPORTING POLICY ────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $repBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting"
    foreach ($entry in @(
            @{N="DisableEnhancedNotifications"; Dis=1},
            @{N="DisableGenericRePorts";         Dis=1},
            @{N="WppTracingLevel";               Dis=0},
            @{N="WppTracingComponents";           Dis=0})) {
        $v = Get-RegValue $repBase $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  Reporting  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [17] NETWORK / EXPLOIT GUARD POLICY ─────────────────────────────────" -ForegroundColor DarkCyan
    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection" "EnableNetworkProtection"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  ExploitGuard\Network  EnableNetworkProtection" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access" "EnableControlledFolderAccess"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  ExploitGuard\CFA  EnableControlledFolderAccess" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection" "DisallowExploitProtectionOverride"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  SC\App&Browser  DisallowExploitProtectionOverride" $s (Fmt $v)
    Track $s

    $asrBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR"
    $v = Get-RegValue $asrBase "ExploitGuard_ASR_Rules"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  ExploitGuard\ASR  ExploitGuard_ASR_Rules" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [17b] THREAT SEVERITY DEFAULT ACTION ────────────────────────────────" -ForegroundColor DarkCyan
    $threatBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Threats"
    $v = Get-RegValue $threatBase "Threats_ThreatSeverityDefaultAction"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Threats  Threats_ThreatSeverityDefaultAction" $s "$(Fmt $v)  [1=override-active]"
    Track $s

    $v = Get-RegValue $threatBase "ThreatSeverityDefaultAction"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 6) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Threats  ThreatSeverityDefaultAction" $s "(value: $v  [6=Allow])"
    Track $s

    $tsaBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Threats\ThreatSeverityDefaultAction"
    foreach ($sev in @("1","2","4","5")) {
        $v = Get-RegValue $tsaBase $sev
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq "6") {"DISABLED"} else {"ENABLED"}
        $sevName = switch ($sev) { "1"{"Low"} "2"{"Medium"} "4"{"High"} "5"{"Severe"} }
        Show-StatusItem "  Threats\DefaultAction  Sev=$sev ($sevName)" $s "(value: '$v'  [6=Allow])"
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [17c] WINDOWS FIREWALL STATUS ─────────────────────────────────────" -ForegroundColor DarkCyan
    try {
        foreach ($profile in @("DomainProfile","StandardProfile","PublicProfile")) {
            $fwPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$profile"
            $v = Get-RegValue $fwPath "EnableFirewall"
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
            $pName = $profile -replace 'Profile','' -replace 'Standard','Private'
            Show-StatusItem "  Firewall  $pName Profile" $s (Fmt $v)
            Track $s
        }
    } catch {
        Show-StatusItem "  Firewall status" "DEFAULT" "(could not read firewall registry)"
    }
    Write-Host ""

    Write-Host "  ┌─ [18] SMARTSCREEN — HKLM REGISTRY ────────────────────────────────────" -ForegroundColor DarkCyan
    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq "off") {"DISABLED"} elseif ($v -eq "On") {"ENABLED"} else {"CUSTOM"}
    Show-StatusItem "  Explorer  SmartScreenEnabled" $s "(value: '$v')"
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "EnableSmartScreen"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  Policies\Windows\System  EnableSmartScreen" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "ShellSmartScreenLevel"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq "Warn" -or $v -eq "Block") {"ENABLED"} else {"SET"}
    Show-StatusItem "  Policies\Windows\System  ShellSmartScreenLevel" $s "(value: '$v')"
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen" "value"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  PMgr\Browser  AllowSmartScreen" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell" "value"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  PMgr\SmartScreen  EnableSmartScreenInShell" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl" "value"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  PMgr\SmartScreen  EnableAppInstallControl" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell" "value"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  PMgr\SmartScreen  PreventOverrideForFilesInShell" $s (Fmt $v)
    Track $s

    $wdSS = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen"
    if (Get-RegKeyExists $wdSS) {
        $v = Get-RegValue $wdSS "ConfigureAppInstallControlEnabled"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WD SmartScreen  ConfigureAppInstallControlEnabled" $s (Fmt $v)
        Track $s

        $v = Get-RegValue $wdSS "ConfigureAppInstallControl"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq "Anywhere") {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WD SmartScreen  ConfigureAppInstallControl" $s "(value: '$v')"
        Track $s
    } else {
        Show-StatusItem "  HKLM\...\WD SmartScreen key" "MISSING" "(key absent = defaults)"
        Track "ENABLED"
    }
    Write-Host ""

    Write-Host "  ┌─ [19] SMARTSCREEN — HKCU REGISTRY ────────────────────────────────────" -ForegroundColor DarkCyan
    $edgePF = "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter"
    $v = Get-RegValue $edgePF "EnabledV9"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU Edge\PhishingFilter  EnabledV9" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $edgePF "PreventOverride"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU Edge\PhishingFilter  PreventOverride" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKCU:\Software\Microsoft\Edge" "SmartScreenEnabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU\Edge  SmartScreenEnabled (value)" $s (Fmt $v)
    Track $s

    if (Get-RegKeyExists "HKCU:\Software\Microsoft\Edge\SmartScreenEnabled") {
        Show-StatusItem "  HKCU\Edge\SmartScreenEnabled (subkey)" "DISABLED" "(subkey exists = set by Disable)"
        Track "DISABLED"
    } else {
        Show-StatusItem "  HKCU\Edge\SmartScreenEnabled (subkey)" "DEFAULT" "(subkey absent)"
        Track "ENABLED"
    }

    $v = Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" "EnableWebContentEvaluation"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU\AppHost  EnableWebContentEvaluation" $s (Fmt $v)
    Track $s

    $v = Get-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" "PreventOverride"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU\AppHost  PreventOverride" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [20] NOTIFICATIONS POLICY MANAGER ───────────────────────────────────" -ForegroundColor DarkCyan
    $wdscBase = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter"
    foreach ($entry in @(
            @{N="DisableEnhancedNotifications";             Dis=1},
            @{N="DisableNotifications";                     Dis=1},
            @{N="HideWindowsSecurityNotificationAreaControl"; Dis=1})) {
        $subPath = "$wdscBase\$($entry.N)"
        if (Get-RegKeyExists $subPath) {
            $v = Get-RegValue $subPath "value"
            $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq $entry.Dis) {"DISABLED"} else {"ENABLED"}
        } else {
            $v = $null; $s = "DEFAULT"
        }
        Show-StatusItem "  PMgr\WDSC  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [21] SECURITY CENTER NOTIFICATIONS / POLICY ──────────────────────────" -ForegroundColor DarkCyan
    $notifBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    $v = Get-RegValue $notifBase "DisableNotifications"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD SC Notifications  DisableNotifications" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $notifBase "DisableEnhancedNotifications"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD SC Notifications  DisableEnhancedNotifications" $s (Fmt $v)
    Track $s

    $secCtr = "HKLM:\SOFTWARE\Microsoft\Security Center"
    if (Get-RegKeyExists $secCtr) {
        $v = Get-RegValue $secCtr "AntiVirusOverride"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  Security Center  AntiVirusOverride" $s (Fmt $v)
        Track $s

        $v = Get-RegValue $secCtr "FirewallOverride"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  Security Center  FirewallOverride" $s (Fmt $v)
        Track $s

        $v = Get-RegValue $secCtr "FirstRunDisabled"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  Security Center  FirstRunDisabled" $s (Fmt $v)
        Track $s
    } else {
        Show-StatusItem "  HKLM\...\Security Center key" "DISABLED" "(key deleted by Disable)"
        Track "DISABLED"
    }

    $toastPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance"
    $v = Get-RegValue $toastPath "Enabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU Toast  SecurityAndMaintenance  Enabled" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [21b] SECURITY CENTER UI LOCKDOWN ────────────────────────────────────" -ForegroundColor DarkCyan
    $scUIBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center"
    foreach ($entry in @(
            @{Sub="Virus and threat protection"; N="UILockdown"; L="Virus & threat protection"},
            @{Sub="Firewall and network protection"; N="UILockdown"; L="Firewall & network"},
            @{Sub="App and Browser protection"; N="UILockdown"; L="App & Browser"},
            @{Sub="Device security"; N="UILockdown"; L="Device security"},
            @{Sub="Account protection"; N="UILockdown"; L="UILockdown"},
            @{Sub="Family options"; N="UILockdown"; L="Family options"})) {
        $subPath = "$scUIBase\$($entry.Sub)"
        $v = Get-RegValue $subPath $entry.N
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WDSC\$($entry.L)  $($entry.N)" $s (Fmt $v)
        Track $s
    }
    $v = Get-RegValue "$scUIBase\Virus and threat protection" "HideRansomwareRecovery"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WDSC\V&TP  HideRansomwareRecovery" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [21c] SMART APP CONTROL ──────────────────────────────────────────────" -ForegroundColor DarkCyan
    $sacPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
    $v = Get-RegValue $sacPath "VerifiedAndReputablePolicyState"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} elseif ($v -eq 1) {"ENABLED"} elseif ($v -eq 2) {"ENABLED"} else {"CUSTOM"}
    $sacName = switch ($v) { 0{"Off"} 1{"Enforce"} 2{"Evaluation"} default{"?"} }
    Show-StatusItem "  SmartAppControl  VerifiedAndReputablePolicyState" $s "(value: $v [$sacName])"
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [22] WINDOWS SECURITY HEALTH ────────────────────────────────────────" -ForegroundColor DarkCyan
    $wshHKLM = "HKLM:\SOFTWARE\Microsoft\Windows Security Health"
    if (Get-RegKeyExists $wshHKLM) {
        $regVal = Get-RegValue "$wshHKLM\Platform" "Registered"
        if ($null -ne $regVal -and $regVal -eq 0) {
            Show-StatusItem "  HKLM\...\Windows Security Health (key)" "DISABLED" "(key present, Registered=0)"
            Track "DISABLED"
        } else {
            Show-StatusItem "  HKLM\...\Windows Security Health (key)" "ENABLED" "(key present)"
            Track "ENABLED"
        }
        $v = Get-RegValue "$wshHKLM\Platform" "Registered"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"ENABLED"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WinSecHealth\Platform  Registered" $s (Fmt $v)
        Track $s
        $v = Get-RegValue "$wshHKLM\State" "Disabled"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WinSecHealth\State  Disabled" $s (Fmt $v)
        Track $s
    } else {
        Show-StatusItem "  HKLM\...\Windows Security Health (key)" "MISSING" "(key deleted / absent)"
        Track "MISSING"
    }
    $wshHKCU = "HKCU:\Software\Microsoft\Windows Security Health"
    $wshHKCUExists = Get-RegKeyExists $wshHKCU
    $wshHKCUDisabled = if ($wshHKCUExists) { Get-RegValue "$wshHKCU\State" "Disabled" } else { $null }
    if ($wshHKCUExists -and $null -ne $wshHKCUDisabled -and $wshHKCUDisabled -eq 1) {
        Show-StatusItem "  HKCU\...\Windows Security Health (key)" "DISABLED" "(key present, State\Disabled=1 — set by Disable)"
        Track "DISABLED"
        Show-StatusItem "  HKCU WinSecHealth\State  Disabled" "DISABLED" "(dword:1)"
        Track "DISABLED"
    } elseif ($wshHKCUExists) {
        Show-StatusItem "  HKCU\...\Windows Security Health (key)" "ENABLED" "(key present, Disabled value absent/0 — Enable cleaned up correctly)"
        Track "ENABLED"
        Show-StatusItem "  HKCU WinSecHealth\State  Disabled" "DEFAULT" (Fmt $wshHKCUDisabled)
        Track "ENABLED"
    } else {
        Show-StatusItem "  HKCU\...\Windows Security Health (key)" "DEFAULT" "(key absent)"
        Track "ENABLED"
    }
    $wshStateBase = "HKCU:\Software\Microsoft\Windows Security Health\State"
    $v = Get-RegValue $wshStateBase "AppAndBrowser_StoreAppsSmartScreenOff"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU WinSecHealth\State  StoreAppsSmartScreenOff" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wshStateBase "AppAndBrowser_EdgeSmartScreenOff"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  HKCU WinSecHealth\State  EdgeSmartScreenOff" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [23] REMOVAL TOOLS (MpGears) ─────────────────────────────────────────" -ForegroundColor DarkCyan
    $mpGears = "HKLM:\SOFTWARE\Microsoft\RemovalTools\MpGears"
    $v = Get-RegValue $mpGears "HeartbeatTrackingIndex"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MpGears  HeartbeatTrackingIndex" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $mpGears "SpyNetReportingLocation"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq "0") {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  MpGears  SpyNetReportingLocation" $s "(value: '$v')"
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [24] SETTINGS PAGE VISIBILITY ───────────────────────────────────────" -ForegroundColor DarkCyan
    $v = Get-RegValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -like "*windowsdefender*") {"DISABLED"} else {"CUSTOM"}
    Show-StatusItem "  Policies\Explorer  SettingsPageVisibility" $s "(value: '$v')"
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [25] SERVICES ─────────────────────────────────────────" -ForegroundColor DarkCyan
    $svcList = $script:DS_TouchedServices
    foreach ($svc in $svcList) {
        $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.N)"
        if (Get-RegKeyExists $svcPath) {
            $startVal = Get-RegValue $svcPath "Start"
            $imgPath  = Get-RegValue $svcPath "ImagePath"
            $startName = switch ($startVal) { 0{"Boot"} 1{"System"} 2{"Auto"} 3{"Manual"} 4{"Disabled"} default{"?"} }
            $s = if ($startVal -eq 4) {"DISABLED"} elseif ($null -eq $startVal) {"UNKNOWN"} else {"ENABLED"}
            $defName = switch ($svc.Def) { 0{"Boot"} 1{"System"} 2{"Auto"} 3{"Manual"} 4{"Disabled"} default{"?"} }
            Show-StatusItem "  Svc: $($svc.N) ($($svc.Label))" $s "(Start=$startVal [$startName], default=$($svc.Def) [$defName])"
            Track $s
        } else {
            Show-StatusItem "  Svc: $($svc.N) ($($svc.Label))" "MISSING" "(key deleted / absent)"
            Track "MISSING"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [26] WMI AUTOLOGGER KEYS ─────────────────────────────────────────────" -ForegroundColor DarkCyan
    foreach ($logName in @("DefenderAuditLogger","DefenderApiLogger","DefenderRtpLogger")) {
        $logPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$logName"
        if (Get-RegKeyExists $logPath) {
            $startVal = Get-RegValue $logPath "Start"
            if ($null -eq $startVal) {
                Show-StatusItem "  WMI\Autologger\$logName" "DEFAULT" "(Start not set)"
                Track "DEFAULT"
            } elseif ($startVal -eq 0) {
                Show-StatusItem "  WMI\Autologger\$logName" "DISABLED" "(Start=0)"
                Track "DISABLED"
            } else {
                Show-StatusItem "  WMI\Autologger\$logName" "ENABLED" "(Start=$startVal)"
                Track "ENABLED"
            }
        } else {
            Show-StatusItem "  WMI\Autologger\$logName" "MISSING" "(key deleted / absent)"
            Track "MISSING"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [27] SCHEDULED TASKS ────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $defenderTasks = $script:DS_TouchedTasks
    foreach ($task in $defenderTasks) {
        $shortName = ($task -split '\\')[-1]
        try {
            $taskState = Get-TaskStateString $task
            if ($null -eq $taskState) {
                Show-StatusItem "  Task: $shortName" "MISSING" "(task not found)"
                Track "MISSING"
            } elseif ($taskState -eq 'Disabled') {
                Show-StatusItem "  Task: $shortName" "DISABLED" "(task disabled)"
                Track "DISABLED"
            } elseif ($taskState -match '^(Ready|Running|Queued)$') {
                Show-StatusItem "  Task: $shortName" "ENABLED" "(state: $taskState)"
                Track "ENABLED"
            } else {
                Show-StatusItem "  Task: $shortName" "ENABLED" "(state: $taskState)"
                Track "ENABLED"
            }
        } catch {
            Show-StatusItem "  Task: $shortName" "DEFAULT" "(cannot query: $($_.Exception.Message))"
            Track "DEFAULT"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [28] STARTUP RUN ENTRIES ─────────────────────────────────────────────" -ForegroundColor DarkCyan
    $runChecks = @(
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                                N="Windows Defender"; L="HKCU Run  Windows Defender"},
        @{P="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                                N="SecurityHealth";   L="HKCU Run  SecurityHealth"},
        @{P="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                                N="WindowsDefender";  L="HKLM Run  WindowsDefender"},
        @{P="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                                N="SecurityHealth";   L="HKLM Run  SecurityHealth"}
    )
    foreach ($rc in $runChecks) {
        $v = Get-RegValue $rc.P $rc.N
        if ($null -ne $v) {
            Show-StatusItem "  $($rc.L)" "ENABLED" "(value present: '$v')"
            Track "ENABLED"
        } else {
            Show-StatusItem "  $($rc.L)" "MISSING" "(value deleted / absent)"
            Track "MISSING"
        }
    }
    $startApproved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    foreach ($name in @("Windows Defender","SecurityHealth")) {
        $v = Get-RegValue $startApproved $name
        if ($null -eq $v) {
            $s = "MISSING"; $det = "(absent)"
        } else {
            $saBytes = $null
            if ($v -is [byte[]]) {
                $saBytes = $v
            } elseif ($v -is [System.Array]) {
                try { $saBytes = [byte[]]@($v | ForEach-Object { [byte]$_ }) } catch { $saBytes = $null }
            }
            if ($null -ne $saBytes -and $saBytes.Length -ge 1 -and $saBytes[0] -eq 3) {
                $s = "DISABLED"; $det = "(present, first byte=03 → disabled)"
            } elseif ($null -ne $saBytes -and $saBytes.Length -ge 1 -and ($saBytes[0] -eq 2 -or $saBytes[0] -eq 6)) {
                $s = "ENABLED"; $det = "(present, first byte=$("{0:X2}" -f $saBytes[0]) → enabled)"
            } else {
                $s = "ENABLED"; $det = "(present)"
            }
        }
        Show-StatusItem "  StartupApproved  $name" $s $det
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [29] WEB THREAT DEFENSE ─────────────────────────────────────────────" -ForegroundColor DarkCyan
    $wtdServicePath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense\ServiceEnabled"
    if (Get-RegKeyExists $wtdServicePath) {
        $v = Get-RegValue $wtdServicePath "value"
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  PMgr\WebThreatDefense\ServiceEnabled" $s (Fmt $v)
        Track $s
    } else {
        Show-StatusItem "  PMgr\WebThreatDefense\ServiceEnabled" "MISSING" "(subkey absent)"
        Track "MISSING"
    }

    $wtdsBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components"
    $v = Get-RegValue $wtdsBase "ServiceEnabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WTDS\Components  ServiceEnabled" $s (Fmt $v)
    Track $s

    foreach ($name in @("NotifyPasswordReuse","NotifyMalicious","NotifyUnsafeApp","NotifyPhishing")) {
        $v = Get-RegValue $wtdsBase $name
        $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  WTDS\Components  $name" $s (Fmt $v)
        Track $s
    }
    Write-Host ""

    Write-Host "  ┌─ [30] NON-POLICY DEFENDER CONFIG (direct WD keys) ────────────────────" -ForegroundColor DarkCyan
    $wdDirect = "HKLM:\SOFTWARE\Microsoft\Windows Defender"
    $wdRtpDirect = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    $wdSpyDirect = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Spynet"
    $v = Get-RegValue $wdDirect "DisableAntiSpyware"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  DisableAntiSpyware" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "DisableAntiVirus"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  DisableAntiVirus" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "DisableRoutinelyTakingAction"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  DisableRoutinelyTakingAction" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "ServiceKeepAlive"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  ServiceKeepAlive" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "AllowFastServiceStartup"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  AllowFastServiceStartup" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "DisableSpecialRunningModes"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD (direct)  DisableSpecialRunningModes" $s (Fmt $v)
    Track $s

    $wdFeatures = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
    $v = Get-RegValue $wdFeatures "PackagedScanningDisabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\Features  PackagedScanningDisabled" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableRealtimeMonitoring"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableRealtimeMonitoring" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableBehaviorMonitoring"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableBehaviorMonitoring" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableOnAccessProtection"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableOnAccessProtection" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableIOAVProtection"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableIOAVProtection" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableScanOnRealtimeEnable"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableScanOnRealtimeEnable" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableScriptScanning"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableScriptScanning" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableIntrusionPreventionSystem"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableIntrusionPreventionSystem" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableRawWriteNotification"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableRawWriteNotification" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableInformationProtectionControl"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableInformationProtectionControl" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DisableAntiSpywareRealtimeProtection"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DisableAntiSpywareRealtimeProtection" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdRtpDirect "DpaDisabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\RTP (direct)  DpaDisabled" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdDirect "AllowDevDriveProtection"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} elseif ($v -eq 1) {"ENABLED"} else {"CUSTOM"}
    $detail = if ($null -eq $v) { "(not set — Windows default = ENABLED)" } else { "(value: $v  [0=disabled, 1=enabled, absent=default enabled])" }
    Show-StatusItem "  WD (direct)  AllowDevDriveProtection" $s $detail
    Track $s

    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    foreach ($exeName in @("MsMpEng.exe","MpCmdRun.exe")) {
        $dbg = Get-RegValue "$ifeoBase\$exeName" "Debugger"
        $s   = if ($null -eq $dbg) {"DEFAULT"} elseif ($dbg -eq "NUL") {"DISABLED"} else {"ENABLED"}
        Show-StatusItem "  IFEO\$exeName  Debugger" $s "(value: '$dbg')"
        Track $s
    }

    $v = Get-RegValue $wdSpyDirect "SpynetReporting"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\Spynet (direct)  SpynetReporting" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $wdSpyDirect "SubmitSamplesConsent"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 2) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\Spynet (direct)  SubmitSamplesConsent" $s (Decode-SubmitSamples $v)
    Track $s

    $v = Get-RegValue $wdSpyDirect "DisableBlockAtFirstSeen"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 1) {"DISABLED"} else {"ENABLED"}
    Show-StatusItem "  WD\Spynet (direct)  DisableBlockAtFirstSeen" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [31] DEVICE GUARD / VBS / CREDENTIAL GUARD (read-only) ──────────────" -ForegroundColor DarkCyan
    $dgBase = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    $v = Get-RegValue $dgBase "EnableVirtualizationBasedSecurity"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} elseif ($v -eq 1) {"ENABLED"} else {"CUSTOM"}
    Show-StatusItem "  DeviceGuard  EnableVBS" $s (Fmt $v)
    Track $s

    $v = Get-RegValue $dgBase "RequirePlatformSecurityFeatures"
    $s = if ($null -eq $v) {"DEFAULT"} else {"SET"}
    Show-StatusItem "  DeviceGuard  RequirePlatformSecurityFeatures" $s (Fmt $v)
    Track $s

    $dgScen = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    $v = Get-RegValue $dgScen "Enabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} elseif ($v -eq 1) {"ENABLED"} else {"CUSTOM"}
    Show-StatusItem "  DeviceGuard\HVCI  Enabled" $s (Fmt $v)
    Track $s

    $dgCG = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"
    $v = Get-RegValue $dgCG "Enabled"
    $s = if ($null -eq $v) {"DEFAULT"} elseif ($v -eq 0) {"DISABLED"} elseif ($v -eq 1) {"ENABLED"} else {"CUSTOM"}
    Show-StatusItem "  DeviceGuard\CredentialGuard  Enabled" $s (Fmt $v)
    Track $s
    Write-Host ""

    Write-Host "  ┌─ [32] DEFENDER PROCESS STATUS (live) ──────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  │  Note: Some processes only run on-demand or at specific times and may" -ForegroundColor DarkGray
    Write-Host "  │  NOT be running even when Defender is fully enabled — this is normal." -ForegroundColor DarkGray
    Write-Host "  │  Only MsMpEng (the core engine) is expected to run continuously." -ForegroundColor DarkGray
    $defProcesses = @(
        @{N="MsMpEng";             L="Antimalware Service Executable";       AlwaysRunning=$true;  NotRunningNote="(core engine absent — Defender inactive)"},
        @{N="MpCmdRun";            L="Defender Command Line (on-demand)";    AlwaysRunning=$false; NotRunningNote="(on-demand — normal when Defender is enabled)"},
        @{N="NisSrv";              L="Network Inspection Service";            AlwaysRunning=$false; NotRunningNote="(starts alongside Defender — may be absent on some configurations)"},
        @{N="SecurityHealthHost";  L="Security Health Host (on-demand)";      AlwaysRunning=$false; NotRunningNote="(on-demand — normal when Defender is enabled)"},
        @{N="SecurityHealthSystray";L="Security Health Systray";              AlwaysRunning=$false; NotRunningNote="(starts at logon — may not be running in current session)"},
        @{N="smartscreen";         L="SmartScreen Filter";                    AlwaysRunning=$false; NotRunningNote="(runs on-demand — normal when SmartScreen is idle)"}
    )
    foreach ($proc in $defProcesses) {
        $p = Get-Process -Name $proc.N -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) {
            Show-StatusItem "  Process: $($proc.N) ($($proc.L))" "RUNNING" "(PID=$($p.Id))"
            Track "ENABLED"
        } else {
            if ($proc.AlwaysRunning) {
                Show-StatusItem "  Process: $($proc.N) ($($proc.L))" "NOT RUNNING" $proc.NotRunningNote
                Track "DISABLED"
            } else {
                $pad2 = 64
                Write-Host ("  " + "  Process: $($proc.N) ($($proc.L))".PadRight($pad2)) -NoNewline
                Write-Host "[NOT RUNNING]" -ForegroundColor DarkGray -NoNewline
                Write-Host "  $($proc.NotRunningNote)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""

    $wdMsMpEng = Get-Process -Name "MsMpEng" -ErrorAction SilentlyContinue | Select-Object -First 1
    $wdStatusText  = if ($wdMsMpEng) { "ENABLED"  } else { "DISABLED" }
    $wdStatusColor = if ($wdMsMpEng) { "Green"    } else { "Red"      }
    $wdStatusDetail = if ($wdMsMpEng) { "(MsMpEng.exe running — PID=$($wdMsMpEng.Id))" } else { "(MsMpEng.exe not running)" }

    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "  WINDOWS DEFENDER STATUS: " -NoNewline
    Write-Host $wdStatusText -ForegroundColor $wdStatusColor -NoNewline
    Write-Host "  $wdStatusDetail" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SUMMARY:" -NoNewline

    $disabledCount = $script:_dsDisabled
    $enabledCount  = $script:_dsEnabled
    $missingCount  = $script:_dsMissing
    $defaultCount  = $script:_dsDefault
    $setCount      = $script:_dsSet
    $total = $disabledCount + $enabledCount + $missingCount + $defaultCount + $setCount
    if ($total -eq 0) { $total = 1 }

    $activeTotal = $disabledCount + $enabledCount + $missingCount
    if ($activeTotal -eq 0) { $activeTotal = 1 }

    if ($disabledCount -gt 0 -and $enabledCount -eq 0 -and $missingCount -eq 0) {
        $overall = "FULLY DISABLED"
        $overallColor = "Red"
    } elseif ($disabledCount -eq 0 -and $missingCount -eq 0 -and $enabledCount -gt 0) {
        $overall = "FULLY ENABLED"
        $overallColor = "Green"
    } elseif ($disabledCount -eq 0 -and $missingCount -eq 0 -and $enabledCount -eq 0) {
        $overall = "ALL DEFAULT (not configured)"
        $overallColor = "Green"
    } elseif ($disabledCount -gt 0 -and $enabledCount -gt 0) {
        $overall = "PARTIALLY DISABLED  (mixed)"
        $overallColor = "Yellow"
    } elseif ($missingCount -gt 0 -and $missingCount -ge ($activeTotal * 0.65)) {
        $overall = "MOSTLY MISSING  (components absent)"
        $overallColor = "Gray"
    } else {
        $overall = "MIXED / UNKNOWN"
        $overallColor = "Yellow"
    }

    Write-Host "  $overall" -ForegroundColor $overallColor
    Write-Host "  Checks ($total total):   " -NoNewline
    Write-Host "$enabledCount ENABLED" -ForegroundColor Green -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host "$disabledCount DISABLED/RENAMED" -ForegroundColor Red -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host "$missingCount MISSING/ABSENT" -ForegroundColor Gray -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host "$setCount SET" -ForegroundColor DarkYellow -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host "$defaultCount DEFAULT/NOTSET" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

$reg_DisableMitigation = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsMitigation]
"UserPreference"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel]
"KernelSEHOPEnabled"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SCMConfig]
"EnableSvchostMitigationPolicy"=hex(b):00,00,00,00,00,00,00,00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"MpPlatformKillbitsFromEngine"=hex:00,00,00,00,00,00,00,00
"TamperProtectionSource"=dword:00000002
"MpCapability"=hex:00,00,00,00,00,00,00,00
"TamperProtection"=dword:00000004

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"RunAsPPL"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa]
"LsaConfigFlags"=dword:00000000
"RunAsPPL"=dword:00000000
"RunAsPPLBoot"=dword:00000000
"@

$reg_DisableSmartScreen = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter]
"EnabledV9"=dword:00000000
"PreventOverride"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Edge]
"SmartScreenEnabled"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Edge\SmartScreenEnabled]
@=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer]
"SmartScreenEnabled"="off"

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"EnableSmartScreen"=dword:00000000
"ShellSmartScreenLevel"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell]
"value"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\AppHost]
"EnableWebContentEvaluation"=dword:00000000
"PreventOverride"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen]
"ConfigureAppInstallControlEnabled"=dword:00000001
"ConfigureAppInstallControl"="Anywhere"
"@

$reg_DisableAntivirusProtection = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender]
"DisableRoutinelyTakingAction"=dword:00000001
"ServiceKeepAlive"=dword:00000000
"AllowFastServiceStartup"=dword:00000000
"DisableLocalAdminMerge"=dword:00000001
"DisableSpecialRunningModes"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection]
"LocalSettingOverrideDisableOnAccessProtection"=dword:00000000
"LocalSettingOverrideRealtimeScanDirection"=dword:00000000
"LocalSettingOverrideDisableIOAVProtection"=dword:00000000
"LocalSettingOverrideDisableBehaviorMonitoring"=dword:00000000
"LocalSettingOverrideDisableIntrusionPreventionSystem"=dword:00000000
"LocalSettingOverrideDisableRealtimeMonitoring"=dword:00000000
"DisableIOAVProtection"=dword:00000001
"DisableRealtimeMonitoring"=dword:00000001
"DisableBehaviorMonitoring"=dword:00000001
"DisableOnAccessProtection"=dword:00000001
"DisableScanOnRealtimeEnable"=dword:00000001
"RealtimeScanDirection"=dword:00000002
"DisableInformationProtectionControl"=dword:00000001
"DisableIntrusionPreventionSystem"=dword:00000001
"DisableRawWriteNotification"=dword:00000001
"DisableScriptScanning"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowBehaviorMonitoring]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender]
"DisableAntiSpyware"=dword:00000001
"DisableAntiVirus"=dword:00000001
"DisableSpecialRunningModes"=dword:00000001
"DisableRoutinelyTakingAction"=dword:00000001
"ServiceKeepAlive"=dword:00000000
"AllowFastServiceStartup"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet]
"DisableBlockAtFirstSeen"=dword:00000001
"LocalSettingOverrideSpynetReporting"=dword:00000000
"SpynetReporting"=dword:00000000
"SubmitSamplesConsent"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet]
"SpyNetReporting"=dword:00000000
"LocalSettingOverrideSpyNetReporting"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RemovalTools\MpGears]
"HeartbeatTrackingIndex"=dword:00000000
"SpyNetReportingLocation"="0"
"@

$reg_DisableDefenderandSecurityCenterNotifications = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableEnhancedNotifications]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableNotifications]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\HideWindowsSecurityNotificationAreaControl]
"value"=dword:00000001

[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security Center]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security Center]
"FirstRunDisabled"=dword:00000001
"AntiVirusOverride"=dword:00000001
"FirewallOverride"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications]
"DisableEnhancedNotifications"=dword:00000001
"DisableNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Virus and threat protection]
"UILockdown"=dword:00000001
"HideRansomwareRecovery"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Firewall and network protection]
"UILockdown"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection]
"UILockdown"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security]
"UILockdown"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Account protection]
"UILockdown"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Family options]
"UILockdown"=dword:00000001

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance]
"Enabled"=dword:00000000
"@

$reg_DisableDefenderPolicies = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowIOAVProtection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender]
"PUAProtection"=dword:00000000
"DisableRoutinelyTakingAction"=dword:00000001
"ServiceKeepAlive"=dword:00000000
"AllowFastServiceStartup"=dword:00000000
"DisableLocalAdminMerge"=dword:00000001
"DisableAntiSpyware"=dword:00000001
"DisableAntiVirus"=dword:00000001
"RandomizeScheduleTaskTimes"=dword:00000000
"DisablePrivacyMode"=dword:00000001
"HideExclusionsFromLocalAdmins"=dword:00000000
"DisableSpecialRunningModes"=dword:00000001
; Change 4: Win10 1507/1607 LTSB also reads DisableRealtimeMonitoring from the parent key directly
"DisableRealtimeMonitoring"=dword:00000001

; Change 1: Prevent Windows Update from pushing MRT independently of Defender (all builds incl. 24H2)
[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MRT]
"DontOfferThroughWUAU"=dword:00000001
"DontRunOnce"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowArchiveScanning]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowBehaviorMonitoring]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowCloudProtection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowEmailScanning]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowFullScanOnMappedNetworkDrives]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowFullScanRemovableDriveScanning]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowIntrusionPreventionSystem]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowOnAccessProtection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowRealtimeMonitoring]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowScanningNetworkFiles]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowScriptScanning]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowUserUIAccess]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AvgCPULoadFactor]
"value"=dword:00000032

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CheckForSignaturesBeforeRunningScan]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CloudBlockLevel]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CloudExtendedTimeout]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DaysToRetainCleanedMalware]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DisableCatchupFullScan]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DisableCatchupQuickScan]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableControlledFolderAccess]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableLowCPUPriority]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableNetworkProtection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\PUAProtection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\RealTimeScanDirection]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScanParameter]
"value"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScheduleScanDay]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScheduleScanTime]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\SignatureUpdateInterval]
"value"=dword:00000018

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\SubmitSamplesConsent]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions]
"DisableAutoExclusions"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine]
"MpEnablePus"=dword:00000000
"MpCloudBlockLevel"=dword:00000000
"MpBafsExtendedTimeout"=dword:00000000
"EnableFileHashComputation"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS]
"ThrottleDetectionEventsRate"=dword:00000000
"DisableSignatureRetirement"=dword:00000001
"DisableProtocolRecognition"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager]
"DisableScanningNetworkFiles"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection]
"DisableRealtimeMonitoring"=dword:00000001
"DisableBehaviorMonitoring"=dword:00000001
"DisableOnAccessProtection"=dword:00000001
"DisableScanOnRealtimeEnable"=dword:00000001
"DisableIOAVProtection"=dword:00000001
"LocalSettingOverrideDisableOnAccessProtection"=dword:00000000
"LocalSettingOverrideRealtimeScanDirection"=dword:00000000
"LocalSettingOverrideDisableIOAVProtection"=dword:00000000
"LocalSettingOverrideDisableBehaviorMonitoring"=dword:00000000
"LocalSettingOverrideDisableIntrusionPreventionSystem"=dword:00000000
"LocalSettingOverrideDisableRealtimeMonitoring"=dword:00000000
"RealtimeScanDirection"=dword:00000002
"IOAVMaxSize"=dword:00000512
"DisableInformationProtectionControl"=dword:00000001
"DisableIntrusionPreventionSystem"=dword:00000001
"DisableRawWriteNotification"=dword:00000001
"DisableScriptScanning"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Scan]
"LowCpuPriority"=dword:00000001
"DisableRestorePoint"=dword:00000001
"DisableArchiveScanning"=dword:00000001
"DisableScanningNetworkFiles"=dword:00000001
"DisableCatchupFullScan"=dword:00000001
"DisableCatchupQuickScan"=dword:00000001
"DisableEmailScanning"=dword:00000001
"DisableHeuristics"=dword:00000001
"DisableReparsePointScanning"=dword:00000001
"DisableRemovableDriveScanning"=dword:00000001
"ScheduleDay"=dword:00000008
"ScheduleTime"=dword:00000000
"ScheduleQuickScanTime"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Remediation]
"Scan_ScheduleDay"=dword:00000008
"Scan_ScheduleTime"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates]
"SignatureDisableNotification"=dword:00000001
"RealtimeSignatureDelivery"=dword:00000000
"ForceUpdateFromMU"=dword:00000000
"DisableScheduledSignatureUpdateOnBattery"=dword:00000001
"UpdateOnStartUp"=dword:00000000
"SignatureUpdateCatchupInterval"=dword:00000002
"DisableUpdateOnStartupWithoutEngine"=dword:00000001
"ScheduleTime"=dword:000005A0
"DisableScanOnUpdate"=dword:00000001
; Change 6: Block WSUS/HTTP fallback update channels on managed builds
"CheckAlternateDownloadLocation"=dword:00000000
"CheckAlternateHttpLocation"=dword:00000000
"FallbackOrder"="NoBackgroundUpdates"

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet]
"DisableBlockAtFirstSeen"=dword:00000001
"LocalSettingOverrideSpynetReporting"=dword:00000000
"SpynetReporting"=dword:00000000
"SubmitSamplesConsent"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration]
"SuppressRebootNotification"=dword:00000001
"UILockdown"=dword:00000001
"Notification_Suppress"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access]
"EnableControlledFolderAccess"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection]
"EnableNetworkProtection"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR]
"ExploitGuard_ASR_Rules"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Threats]
"Threats_ThreatSeverityDefaultAction"=dword:00000001
"ThreatSeverityDefaultAction"=dword:00000006

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Threats\ThreatSeverityDefaultAction]
"1"="6"
"2"="6"
"4"="6"
"5"="6"

[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender]
"DisableRoutinelyTakingAction"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware]
"ServiceKeepAlive"=dword:00000000
"AllowFastServiceStartup"=dword:00000000
"DisableRoutinelyTakingAction"=dword:00000001
"DisableAntiSpyware"=dword:00000001
"DisableAntiVirus"=dword:00000001
"DisableSpecialRunningModes"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet]
"SpyNetReporting"=dword:00000000
"LocalSettingOverrideSpyNetReporting"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting]
"DisableEnhancedNotifications"=dword:00000001
"DisableGenericRePorts"=dword:00000001
"WppTracingLevel"=dword:00000000
"WppTracingComponents"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CI\Policy]
"VerifiedAndReputablePolicyState"=dword:00000000
"@

$reg_DisableWindowsSettingsPageVisibility = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]
"SettingsPageVisibility"="hide:windowsdefender;"
"@

$reg_Disable_SecurityComp = @"
Windows Registry Editor Version 5.00

[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Security Health]
[-HKEY_CURRENT_USER\Software\Microsoft\Windows Security Health]

[HKEY_CURRENT_USER\Software\Microsoft\Windows Security Health\State]
"Disabled"=dword:00000001
; Change 3: App & Browser Control panel reads these separately; set to 0 = "off" indicator suppressed
"AppAndBrowser_StoreAppsSmartScreenOff"=dword:00000000
"AppAndBrowser_EdgeSmartScreenOff"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Security Health\Platform]
"Registered"=dword:00000000
"@

$reg_DisableWTDS = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components]
; Change 2: Master enable switch — child Notify* values are meaningless without this gated off (Win11)
"ServiceEnabled"=dword:00000000
"NotifyPasswordReuse"=dword:00000000
"NotifyMalicious"=dword:00000000
"NotifyUnsafeApp"=dword:00000000
"NotifyPhishing"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense\ServiceEnabled]
"value"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection]
"DisallowExploitProtectionOverride"=dword:00000001
"@

$reg_DisableDefenderDirect = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
"DisableAntiSpyware"=dword:00000001
"DisableAntiVirus"=dword:00000001
"DisableRoutinelyTakingAction"=dword:00000001
"ServiceKeepAlive"=dword:00000000
"AllowFastServiceStartup"=dword:00000000
"DisableSpecialRunningModes"=dword:00000001
; Dev Drive Protection — set to 0 to disable file-system filter scanning on Dev Drives
"AllowDevDriveProtection"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"PackagedScanningDisabled"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableRealtimeMonitoring"=dword:00000001
"DisableBehaviorMonitoring"=dword:00000001
"DisableOnAccessProtection"=dword:00000001
"DisableIOAVProtection"=dword:00000001
"DisableScanOnRealtimeEnable"=dword:00000001
"DisableScriptScanning"=dword:00000001
"DisableIntrusionPreventionSystem"=dword:00000001
"DisableRawWriteNotification"=dword:00000001
"DisableInformationProtectionControl"=dword:00000001
; Change 5: Pre-1809 builds also check these two values in this key
"DisableAntiSpywareRealtimeProtection"=dword:00000001
"DpaDisabled"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SpynetReporting"=dword:00000000
"SubmitSamplesConsent"=dword:00000002
"DisableBlockAtFirstSeen"=dword:00000001

; Change 6: IFEO fallback — effective on Win10 pre-1903 where Tamper Protection did not guard IFEO.
; On 1903+ and all Win11 with Tamper Protection active, these keys are themselves protected and only
; take effect if Tamper Protection is already down (which the TI token logic above handles).
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MsMpEng.exe]
"Debugger"="NUL"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MpCmdRun.exe]
"Debugger"="NUL"

; Change 6 (IFEO trifecta): NisSrv.exe — completes pre-1903 fallback; NIS process blocked at launch
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\NisSrv.exe]
"Debugger"="NUL"

; GAP 4: MpDefenderCoreService.exe — MDCoreSvc executable; on newer builds MDCoreSvc can
; restart WinDefend-adjacent functionality. Block at launch as secondary IFEO layer.
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MpDefenderCoreService.exe]
"Debugger"="NUL"
"@

$reg_EnableDefenderDirect = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
"DisableAntiSpyware"=-
"DisableAntiVirus"=-
"DisableRoutinelyTakingAction"=-
"ServiceKeepAlive"=-
"AllowFastServiceStartup"=-
"DisableSpecialRunningModes"=-
; Dev Drive Protection — remove override value to restore Windows default (enabled)
"AllowDevDriveProtection"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"PackagedScanningDisabled"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableRealtimeMonitoring"=-
"DisableBehaviorMonitoring"=-
"DisableOnAccessProtection"=-
"DisableIOAVProtection"=-
"DisableScanOnRealtimeEnable"=-
"DisableScriptScanning"=-
"DisableIntrusionPreventionSystem"=-
"DisableRawWriteNotification"=-
"DisableInformationProtectionControl"=-
"DisableAntiSpywareRealtimeProtection"=-
"DpaDisabled"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SpynetReporting"=-
"SubmitSamplesConsent"=-
"DisableBlockAtFirstSeen"=-

; Change 6 cleanup: remove IFEO Debugger stubs added by Disable path
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MsMpEng.exe]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MpCmdRun.exe]
; Change 6 trifecta cleanup: NisSrv.exe IFEO stub
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\NisSrv.exe]
; GAP 4 cleanup: MpDefenderCoreService.exe IFEO stub
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MpDefenderCoreService.exe]
"@

$reg_DisableFirewall = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile]
"EnableFirewall"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"EnableFirewall"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"EnableFirewall"=dword:00000000
"@

$reg_EnableFirewall = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile]
"EnableFirewall"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"EnableFirewall"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"EnableFirewall"=dword:00000001
"@

$reg_EnableMitigation = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\WindowsMitigation]
"UserPreference"=-

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel]
"KernelSEHOPEnabled"=-

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SCMConfig]
"EnableSvchostMitigationPolicy"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"MpPlatformKillbitsFromEngine"=-
"TamperProtectionSource"=dword:00000002
"MpCapability"=-
"TamperProtection"=dword:00000005

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"RunAsPPL"=-

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa]
"LsaConfigFlags"=-
"RunAsPPL"=-
"RunAsPPLBoot"=-
"@

$reg_EnableSmartScreen = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter]
"EnabledV9"=-
"PreventOverride"=-

; Disable creates HKCU\Software\Microsoft\Edge\SmartScreenEnabled as a KEY (not a value),
; so we must delete the subkey here, then also delete the value from the parent key
[-HKEY_CURRENT_USER\Software\Microsoft\Edge\SmartScreenEnabled]

[HKEY_CURRENT_USER\Software\Microsoft\Edge]
"SmartScreenEnabled"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer]
"SmartScreenEnabled"="On"

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System]
"EnableSmartScreen"=-
"ShellSmartScreenLevel"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen]
"value"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell]
"value"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl]
"value"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell]
"value"=-

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\AppHost]
"EnableWebContentEvaluation"=-
"PreventOverride"=-

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen]
"@

$reg_EnableAntivirusProtection = @"
Windows Registry Editor Version 5.00

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection]

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender]
"DisableRoutinelyTakingAction"=-
"ServiceKeepAlive"=-
"AllowFastServiceStartup"=-
"DisableLocalAdminMerge"=-
"DisableSpecialRunningModes"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowBehaviorMonitoring]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender]
"DisableAntiSpyware"=-
"DisableAntiVirus"=-
"DisableSpecialRunningModes"=-
"DisableRoutinelyTakingAction"=-
"ServiceKeepAlive"=-
"AllowFastServiceStartup"=-

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet]

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RemovalTools\MpGears]
"HeartbeatTrackingIndex"=-
"SpyNetReportingLocation"=-

; GAP 5: Force Defender into passive mode via the official ATP policy key.
; On 24H2 builds where Tamper Protection prevents full service disable, this provides
; a secondary layer of suppression while keeping the service structurally alive.
[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection]
"ForceDefenderPassiveMode"=dword:00000001
"@

$reg_EnableDefenderNotifications = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableEnhancedNotifications]
"value"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableNotifications]
"value"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\HideWindowsSecurityNotificationAreaControl]
"value"=-

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender Security Center]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security Center]
"FirstRunDisabled"=-
"AntiVirusOverride"=-
"FirewallOverride"=-

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance]
"Enabled"=-
"@

$reg_EnableDefenderPolicies = @"
Windows Registry Editor Version 5.00

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Scan]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Remediation]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Threats]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Threats\ThreatSeverityDefaultAction]
; Change 1 cleanup: remove MRT push-block policy set during Disable
[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\MRT]

; GAP 5 cleanup: remove ForceDefenderPassiveMode set during Disable
[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection]
"ForceDefenderPassiveMode"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender]
"PUAProtection"=-
"DisableRoutinelyTakingAction"=-
"ServiceKeepAlive"=-
"AllowFastServiceStartup"=-
"DisableLocalAdminMerge"=-
"DisableAntiSpyware"=-
"DisableAntiVirus"=-
"RandomizeScheduleTaskTimes"=-
"DisablePrivacyMode"=-
"HideExclusionsFromLocalAdmins"=-
"DisableSpecialRunningModes"=-
; Change 4 cleanup: remove DisableRealtimeMonitoring written to the parent WD policy key during Disable
"DisableRealtimeMonitoring"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender]
"DisableAntiSpyware"=-
"DisableAntiVirus"=-
"DisableSpecialRunningModes"=-
"DisableRoutinelyTakingAction"=-
"ServiceKeepAlive"=-
"AllowFastServiceStartup"=-

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CI\Policy]
"VerifiedAndReputablePolicyState"=-

; Restore all PolicyManager\default\Defender subkeys that Disable wrote to
; (these are deleted to return them to Windows defaults)
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowFullScanOnMappedNetworkDrives]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowFullScanRemovableDriveScanning]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowScriptScanning]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AvgCPULoadFactor]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CheckForSignaturesBeforeRunningScan]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CloudBlockLevel]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\CloudExtendedTimeout]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DaysToRetainCleanedMalware]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DisableCatchupFullScan]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\DisableCatchupQuickScan]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableControlledFolderAccess]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableLowCPUPriority]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\EnableNetworkProtection]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\PUAProtection]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\RealTimeScanDirection]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScanParameter]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScheduleScanDay]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\ScheduleScanTime]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\SignatureUpdateInterval]
[-HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\SubmitSamplesConsent]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowIOAVProtection]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowArchiveScanning]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowBehaviorMonitoring]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowCloudProtection]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowEmailScanning]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowIntrusionPreventionSystem]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowOnAccessProtection]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowRealtimeMonitoring]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowScanningNetworkFiles]
"value"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\Defender\AllowUserUIAccess]
"value"=dword:00000001
"@

$reg_EnableWindowsSettingsPageVisibility = @"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]
"SettingsPageVisibility"=-
"@

$reg_Enable_SecurityComp = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Windows Security Health\State]
"Disabled"=-
; Change 3 cleanup: restore App & Browser Control panel SmartScreen state indicators
"AppAndBrowser_StoreAppsSmartScreenOff"=-
"AppAndBrowser_EdgeSmartScreenOff"=-

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Security Health\Platform]
"Registered"=dword:00000001
"@

$reg_EnableWTDS = @"
Windows Registry Editor Version 5.00

[-HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components]

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense\ServiceEnabled]
"value"=dword:00000001
"@


function Invoke-PostActionVerification {
    param(
        [ValidateSet("Disable","Enable")]
        [string]$Mode
    )

    $isDisable = ($Mode -eq "Disable")
    $modeColor = if ($isDisable) { "Red" } else { "Green" }
    $modeLabel = if ($isDisable) { "DISABLE" } else { "ENABLE" }

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $modeColor
    Write-Host "║       POST-ACTION VERIFICATION LOG  —  $($modeLabel.PadRight(7)) MODE                        ║" -ForegroundColor $modeColor
    Write-Host "║  Exhaustive check: every reg key / value / file / service / task touched.   ║" -ForegroundColor $modeColor
    Write-Host "║  PASS = state matches expected.   FAIL = drift or block detected.           ║" -ForegroundColor $modeColor
    Write-Host "║  WARN = likely-correct but may need reboot.  SKIP = item absent on system.  ║" -ForegroundColor $modeColor
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $modeColor
    Write-Host ""

    $script:pav_pass = 0; $script:pav_fail = 0; $script:pav_skip = 0; $script:pav_info = 0

    function pav_line {
        param([string]$Label, [string]$Result, [string]$Detail = "")
        $pad  = 78
        $lpad = if ($Label.Length -ge $pad) { "$Label " } else { $Label.PadRight($pad) }
        switch ($Result) {
            "PASS" { Write-Host "  $lpad [PASS] $Detail" -ForegroundColor Green;   $script:pav_pass++ }
            "FAIL" { Write-Host "  $lpad [FAIL] $Detail" -ForegroundColor Red;     $script:pav_fail++ }
            "SKIP" { Write-Host "  $lpad [SKIP] $Detail" -ForegroundColor Gray;    $script:pav_skip++ }
            "INFO" { Write-Host "  $lpad [INFO] $Detail" -ForegroundColor Cyan;    $script:pav_info++ }
            "WARN" { Write-Host "  $lpad [WARN] $Detail" -ForegroundColor Yellow;  $script:pav_info++ }
        }
    }

    function pav_reg {
        param([string]$L, [string]$P, [string]$N, $Exp, [bool]$ExpAbsent = $false)
        $v = Get-RegValue $P $N
        if ($ExpAbsent) {
            if ($null -eq $v) { pav_line $L "PASS" "(absent — correct)"             }
            else               { pav_line $L "FAIL" "(should be absent; found=$v)"  }
        } else {
            if ($null -eq $v)              { pav_line $L "FAIL" "(not set; expected=$Exp)"         }
            elseif ("$v" -eq "$Exp")       { pav_line $L "PASS" "(=$v)"                            }
            else                           { pav_line $L "FAIL" "(=$v; expected=$Exp)"             }
        }
    }

    function pav_key {
        param([string]$L, [string]$P, [bool]$ShouldExist = $true)
        $exists = Test-Path $P
        if ($ShouldExist) {
            if ($exists)       { pav_line $L "PASS" "(key present)"                              }
            else               { pav_line $L "FAIL" "(key absent; expected present)"             }
        } else {
            if (-not $exists)  { pav_line $L "PASS" "(key absent — correct)"                    }
            else               { pav_line $L "FAIL" "(key still present; should be deleted)"    }
        }
    }

    function pav_file {
        param([string]$L, [string]$Path, [bool]$ShouldExist = $true)
        $exists = Test-Path $Path
        if ($ShouldExist) {
            if ($exists)       { pav_line $L "PASS" "(file present)"                             }
            else               { pav_line $L "FAIL" "(file MISSING; expected present)"           }
        } else {
            if (-not $exists)  { pav_line $L "PASS" "(file absent — correct)"                   }
            else               { pav_line $L "FAIL" "(file present; should be absent)"          }
        }
    }

    Write-Host "  ┌─ [1] FILES ─────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
    $ssExe  = "C:\Windows\System32\smartscreen.exe"
    $ssExee = "C:\Windows\System32\smartscreen.exee"
    if ($isDisable) {
        pav_file "smartscreen.exe   (DISABLE: should be renamed away)"    $ssExe  -ShouldExist $false
        pav_file "smartscreen.exee  (DISABLE: renamed copy should exist)" $ssExee -ShouldExist $true
    } else {
        pav_file "smartscreen.exe   (ENABLE: should be restored)"          $ssExe  -ShouldExist $true
        pav_file "smartscreen.exee  (ENABLE: renamed copy should be gone)" $ssExee -ShouldExist $false
    }
    Write-Host ""

    Write-Host "  ┌─ [2] TAMPER PROTECTION & DEFENDER FEATURES ─────────────────────────────" -ForegroundColor DarkCyan
    $featBase = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
    if ($isDisable) {
        pav_reg "WD\Features  TamperProtection        (exp=4 OFF)"         $featBase "TamperProtection"         4
        pav_reg "WD\Features  TamperProtectionSource  (exp=2 UI-set)"      $featBase "TamperProtectionSource"   2
        $v = Get-RegValue $featBase "MpPlatformKillbitsFromEngine"
        pav_line "WD\Features  MpPlatformKillbitsFromEngine               " "INFO" "(actual=$(if ($null -eq $v){'(not set)'}else{"$v"}))"
        $v = Get-RegValue $featBase "MpCapability"
        pav_line "WD\Features  MpCapability                               " "INFO" "(actual=$(if ($null -eq $v){'(not set)'}else{"$v"}))"
    } else {
        pav_reg "WD\Features  TamperProtection        (exp=5 ON)"          $featBase "TamperProtection"                5
        pav_reg "WD\Features  TamperProtectionSource  (exp=2)"             $featBase "TamperProtectionSource"          2
        pav_reg "WD\Features  MpPlatformKillbitsFromEngine  (exp=absent)"  $featBase "MpPlatformKillbitsFromEngine"    $null -ExpAbsent $true
        pav_reg "WD\Features  MpCapability                  (exp=absent)"  $featBase "MpCapability"                   $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [3] CORE WINDOWS DEFENDER POLICY ──────────────────────────────────────" -ForegroundColor DarkCyan
    $wdPol   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    $wdPol32 = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows Defender"
    if ($isDisable) {
        pav_reg "WD Policy  DisableAntiSpyware           (exp=1)"  $wdPol   "DisableAntiSpyware"           1
        pav_reg "WD Policy  DisableAntiVirus             (exp=1)"  $wdPol   "DisableAntiVirus"             1
        pav_reg "WD Policy  DisableRoutinelyTakingAction (exp=1)"  $wdPol   "DisableRoutinelyTakingAction" 1
        pav_reg "WD Policy  ServiceKeepAlive             (exp=0)"  $wdPol   "ServiceKeepAlive"             0
        pav_reg "WD Policy  AllowFastServiceStartup      (exp=0)"  $wdPol   "AllowFastServiceStartup"      0
        pav_reg "WD Policy  DisableLocalAdminMerge       (exp=1)"  $wdPol   "DisableLocalAdminMerge"       1
        pav_reg "WD Policy  DisableSpecialRunningModes   (exp=1)"  $wdPol   "DisableSpecialRunningModes"   1
        pav_reg "WD Policy  PUAProtection                (exp=0)"  $wdPol   "PUAProtection"                0
        pav_reg "WD Policy  RandomizeScheduleTaskTimes   (exp=0)"  $wdPol   "RandomizeScheduleTaskTimes"   0
        pav_reg "WD Policy  DisablePrivacyMode          (exp=1)"  $wdPol   "DisablePrivacyMode"           1
        pav_reg "WD Policy  HideExclusionsFromLocalAdm  (exp=0)"  $wdPol   "HideExclusionsFromLocalAdmins" 0
        pav_reg "WD Policy  DisableRealtimeMonitoring   (exp=1)"  $wdPol   "DisableRealtimeMonitoring"    1
        pav_reg "WD Wow64   DisableAntiSpyware           (exp=1)"  $wdPol32 "DisableAntiSpyware"           1
        pav_reg "WD Wow64   DisableAntiVirus             (exp=1)"  $wdPol32 "DisableAntiVirus"             1
        pav_reg "WD Wow64   DisableSpecialRunningModes   (exp=1)"  $wdPol32 "DisableSpecialRunningModes"   1
        pav_reg "WD Wow64   DisableRoutinelyTakingAction (exp=1)"  $wdPol32 "DisableRoutinelyTakingAction" 1
        pav_reg "WD Wow64   ServiceKeepAlive             (exp=0)"  $wdPol32 "ServiceKeepAlive"             0
        pav_reg "WD Wow64   AllowFastServiceStartup      (exp=0)"  $wdPol32 "AllowFastServiceStartup"      0
    } else {
        pav_reg "WD Policy  DisableAntiSpyware           (absent)\" $wdPol   "DisableAntiSpyware"           $null -ExpAbsent $true
        pav_reg "WD Policy  DisableAntiVirus             (absent)" $wdPol   "DisableAntiVirus"             $null -ExpAbsent $true
        pav_reg "WD Policy  DisableRoutinelyTakingAction (absent)" $wdPol   "DisableRoutinelyTakingAction" $null -ExpAbsent $true
        pav_reg "WD Policy  ServiceKeepAlive             (absent)" $wdPol   "ServiceKeepAlive"             $null -ExpAbsent $true
        pav_reg "WD Policy  AllowFastServiceStartup      (absent)" $wdPol   "AllowFastServiceStartup"      $null -ExpAbsent $true
        pav_reg "WD Policy  DisableLocalAdminMerge       (absent)" $wdPol   "DisableLocalAdminMerge"       $null -ExpAbsent $true
        pav_reg "WD Policy  DisableSpecialRunningModes   (absent)" $wdPol   "DisableSpecialRunningModes"   $null -ExpAbsent $true
        pav_reg "WD Policy  PUAProtection                (absent)" $wdPol   "PUAProtection"                $null -ExpAbsent $true
        pav_reg "WD Policy  RandomizeScheduleTaskTimes   (absent)" $wdPol   "RandomizeScheduleTaskTimes"   $null -ExpAbsent $true
        pav_reg "WD Policy  DisablePrivacyMode           (absent)" $wdPol   "DisablePrivacyMode"           $null -ExpAbsent $true
        pav_reg "WD Policy  HideExclusionsFromLocalAdm   (absent)" $wdPol   "HideExclusionsFromLocalAdmins" $null -ExpAbsent $true
        pav_reg "WD Policy  DisableRealtimeMonitoring    (absent)" $wdPol   "DisableRealtimeMonitoring"    $null -ExpAbsent $true
        pav_reg "WD Wow64   DisableAntiSpyware           (absent)" $wdPol32 "DisableAntiSpyware"           $null -ExpAbsent $true
        pav_reg "WD Wow64   DisableAntiVirus             (absent)" $wdPol32 "DisableAntiVirus"             $null -ExpAbsent $true
        pav_reg "WD Wow64   DisableSpecialRunningModes   (absent)" $wdPol32 "DisableSpecialRunningModes"   $null -ExpAbsent $true
        pav_reg "WD Wow64   DisableRoutinelyTakingAction (absent)" $wdPol32 "DisableRoutinelyTakingAction" $null -ExpAbsent $true
        pav_reg "WD Wow64   ServiceKeepAlive             (absent)" $wdPol32 "ServiceKeepAlive"             $null -ExpAbsent $true
        pav_reg "WD Wow64   AllowFastServiceStartup      (absent)" $wdPol32 "AllowFastServiceStartup"      $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [4] REAL-TIME PROTECTION POLICY ───────────────────────────────────────" -ForegroundColor DarkCyan
    $rtpBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
    if ($isDisable) {
        pav_reg "RTP  DisableRealtimeMonitoring              (exp=1)"  $rtpBase "DisableRealtimeMonitoring"              1
        pav_reg "RTP  DisableBehaviorMonitoring              (exp=1)"  $rtpBase "DisableBehaviorMonitoring"              1
        pav_reg "RTP  DisableOnAccessProtection              (exp=1)"  $rtpBase "DisableOnAccessProtection"              1
        pav_reg "RTP  DisableScanOnRealtimeEnable            (exp=1)"  $rtpBase "DisableScanOnRealtimeEnable"            1
        pav_reg "RTP  DisableIOAVProtection                  (exp=1)"  $rtpBase "DisableIOAVProtection"                  1
        pav_reg "RTP  DisableIntrusionPreventionSystem       (exp=1)"  $rtpBase "DisableIntrusionPreventionSystem"       1
        pav_reg "RTP  DisableInformationProtectionControl    (exp=1)"  $rtpBase "DisableInformationProtectionControl"    1
        pav_reg "RTP  DisableRawWriteNotification            (exp=1)"  $rtpBase "DisableRawWriteNotification"            1
        pav_reg "RTP  DisableScriptScanning                  (exp=1)"  $rtpBase "DisableScriptScanning"                  1
        pav_reg "RTP  LocalSettingOverrideDisableOnAccessProt(exp=0)"  $rtpBase "LocalSettingOverrideDisableOnAccessProtection"         0
        pav_reg "RTP  LocalSettingOverrideDisableIOAVProt    (exp=0)"  $rtpBase "LocalSettingOverrideDisableIOAVProtection"             0
        pav_reg "RTP  LocalSettingOverrideDisableBehaviorMon (exp=0)"  $rtpBase "LocalSettingOverrideDisableBehaviorMonitoring"         0
        pav_reg "RTP  LocalSettingOverrideDisableRealtimeMon (exp=0)"  $rtpBase "LocalSettingOverrideDisableRealtimeMonitoring"         0
        pav_reg "RTP  LocalSettingOverrideDisableIPS         (exp=0)"  $rtpBase "LocalSettingOverrideDisableIntrusionPreventionSystem"  0
        pav_reg "RTP  LocalSettingOverrideRealtimeScanDir    (exp=0)"  $rtpBase "LocalSettingOverrideRealtimeScanDirection"            0
        pav_reg "RTP  RealtimeScanDirection                  (exp=2)"  $rtpBase "RealtimeScanDirection"                  2
        pav_reg "RTP  IOAVMaxSize                            (exp=0x512=1298)" $rtpBase "IOAVMaxSize"                    0x512
    } else {
        pav_key "RTP key (should be DELETED entirely after Enable)" $rtpBase -ShouldExist $false
    }
    Write-Host ""

    Write-Host "  ┌─ [5] MITIGATION / EXPLOIT PROTECTION ───────────────────────────────────" -ForegroundColor DarkCyan
    $wmitBase   = "HKLM:\SOFTWARE\Microsoft\WindowsMitigation"
    $kernBase   = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $scmBase    = "HKLM:\SYSTEM\CurrentControlSet\Control\SCMConfig"
    $ciBase     = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config"
    $ciPolBase  = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
    $lsaBase    = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $polSysBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if ($isDisable) {
        pav_reg "WindowsMitigation  UserPreference          (exp=2)"  $wmitBase   "UserPreference"                  2
        pav_reg "kernel  KernelSEHOPEnabled                 (exp=0)"  $kernBase   "KernelSEHOPEnabled"              0
        $v = Get-RegValue $kernBase "MitigationOptions";      pav_line "kernel  MitigationOptions                           " "INFO" $(if ($null -eq $v) {"(not set)"} else {"(set — binary)"})
        $v = Get-RegValue $kernBase "MitigationAuditOptions"; pav_line "kernel  MitigationAuditOptions                      " "INFO" $(if ($null -eq $v) {"(not set)"} else {"(set — binary)"})
        $v = Get-RegValue $scmBase  "EnableSvchostMitigationPolicy"; pav_line "SCMConfig  EnableSvchostMitigationPolicy          " "INFO" $(if ($null -eq $v) {"(not set)"} else {"(set)"})
        $v = Get-RegValue $ciBase   "VulnerableDriverBlocklistEnable"; pav_line "CI\Config  VulnerableDriverBlocklistEnable (read-only)" "INFO" $(if ($null -eq $v) {"(not set)"} else {"(value: $v)"})
        pav_reg "CI\Policy  VerifiedAndReputablePolicyState  (exp=0)"  $ciPolBase  "VerifiedAndReputablePolicyState"  0
        pav_reg "Lsa  RunAsPPL                               (exp=0)"  $lsaBase    "RunAsPPL"                        0
        pav_reg "Lsa  RunAsPPLBoot                           (exp=0)"  $lsaBase    "RunAsPPLBoot"                    0
        pav_reg "Lsa  LsaConfigFlags                         (exp=0)"  $lsaBase    "LsaConfigFlags"                  0
        pav_reg "Policies\Windows\System  RunAsPPL           (exp=0)"  $polSysBase "RunAsPPL"                        0
    } else {
        pav_reg "WindowsMitigation  UserPreference          (absent)" $wmitBase   "UserPreference"                  $null -ExpAbsent $true
        pav_reg "kernel  KernelSEHOPEnabled                 (absent)" $kernBase   "KernelSEHOPEnabled"              $null -ExpAbsent $true
        $v = Get-RegValue $kernBase "MitigationOptions";      pav_line "kernel  MitigationOptions              (read-only)" "INFO" $(if ($null -eq $v) {"(not set)"} else {"(set — binary)"})
        $v = Get-RegValue $kernBase "MitigationAuditOptions"; pav_line "kernel  MitigationAuditOptions         (read-only)" "INFO" $(if ($null -eq $v) {"(not set)"} else {"(set — binary)"})
        pav_reg "SCMConfig  EnableSvchostMitigationPolicy   (absent)" $scmBase    "EnableSvchostMitigationPolicy"   $null -ExpAbsent $true
        $v = Get-RegValue $ciBase   "VulnerableDriverBlocklistEnable"; pav_line "CI\Config  VulnerableDriverBlocklistEnable (read-only)" "INFO" $(if ($null -eq $v) {"(not set)"} else {"(value: $v)"})
        pav_reg "CI\Policy  VerifiedAndReputablePolicyState (absent)" $ciPolBase  "VerifiedAndReputablePolicyState"  $null -ExpAbsent $true
        pav_reg "Lsa  RunAsPPL                              (absent)" $lsaBase    "RunAsPPL"                        $null -ExpAbsent $true
        pav_reg "Lsa  RunAsPPLBoot                          (absent)" $lsaBase    "RunAsPPLBoot"                    $null -ExpAbsent $true
        pav_reg "Lsa  LsaConfigFlags                        (absent)" $lsaBase    "LsaConfigFlags"                  $null -ExpAbsent $true
        pav_reg "Policies\Windows\System  RunAsPPL          (absent)" $polSysBase "RunAsPPL"                        $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [6] SMARTSCREEN REGISTRY ───────────────────────────────────────────────" -ForegroundColor DarkCyan
    $explBase    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
    $polWinSys   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $pmBrowser   = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Browser\AllowSmartScreen"
    $pmSSShell   = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableSmartScreenInShell"
    $pmSSApp     = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\EnableAppInstallControl"
    $pmSSPrev    = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\SmartScreen\PreventOverrideForFilesInShell"
    $wdSSBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen"
    $edgePF      = "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter"
    $edgeBase    = "HKCU:\Software\Microsoft\Edge"
    $edgeSSSub   = "HKCU:\Software\Microsoft\Edge\SmartScreenEnabled"
    $appHostBase = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost"
    if ($isDisable) {
        pav_reg "Explorer  SmartScreenEnabled              (exp='off')"      $explBase     "SmartScreenEnabled"                "off"
        pav_reg "Policies\System  EnableSmartScreen         (exp=0)"         $polWinSys    "EnableSmartScreen"                  0
        pav_reg "Policies\System  ShellSmartScreenLevel     (exp=absent)"    $polWinSys    "ShellSmartScreenLevel"              $null -ExpAbsent $true
        pav_reg "PMgr\Browser  AllowSmartScreen             (exp=0)"         $pmBrowser    "value"                              0
        pav_reg "PMgr\SS  EnableSmartScreenInShell          (exp=0)"         $pmSSShell    "value"                              0
        pav_reg "PMgr\SS  EnableAppInstallControl           (exp=0)"         $pmSSApp      "value"                              0
        pav_reg "PMgr\SS  PreventOverrideForFilesInShell    (exp=0)"         $pmSSPrev     "value"                              0
        pav_reg "WD\SmartScreen  ConfigureAppInstallControlEnabled (exp=1)"  $wdSSBase     "ConfigureAppInstallControlEnabled"  1
        pav_reg "WD\SmartScreen  ConfigureAppInstallControl  (exp='Anywhere')" $wdSSBase   "ConfigureAppInstallControl"         "Anywhere"
        pav_reg "HKCU Edge\PhishingFilter  EnabledV9         (exp=0)"        $edgePF       "EnabledV9"                          0
        pav_reg "HKCU Edge\PhishingFilter  PreventOverride   (exp=0)"        $edgePF       "PreventOverride"                    0
        pav_reg "HKCU Edge  SmartScreenEnabled               (exp=0)"        $edgeBase     "SmartScreenEnabled"                 0
        pav_key "HKCU Edge\SmartScreenEnabled subkey         (should exist)" $edgeSSSub   -ShouldExist $true
        pav_reg "HKCU AppHost  EnableWebContentEvaluation    (exp=0)"        $appHostBase  "EnableWebContentEvaluation"         0
        pav_reg "HKCU AppHost  PreventOverride               (exp=0)"        $appHostBase  "PreventOverride"                    0
    } else {
        pav_reg "Explorer  SmartScreenEnabled              (exp='On')"       $explBase     "SmartScreenEnabled"                 "On"
        pav_reg "Policies\System  EnableSmartScreen        (absent)"         $polWinSys    "EnableSmartScreen"                  $null -ExpAbsent $true
        pav_reg "Policies\System  ShellSmartScreenLevel    (absent)"         $polWinSys    "ShellSmartScreenLevel"              $null -ExpAbsent $true
        pav_reg "PMgr\Browser  AllowSmartScreen            (absent)"         $pmBrowser    "value"                              $null -ExpAbsent $true
        pav_reg "PMgr\SS  EnableSmartScreenInShell         (absent)"         $pmSSShell    "value"                              $null -ExpAbsent $true
        pav_reg "PMgr\SS  EnableAppInstallControl          (absent)"         $pmSSApp      "value"                              $null -ExpAbsent $true
        pav_reg "PMgr\SS  PreventOverrideForFilesInShell   (absent)"         $pmSSPrev     "value"                              $null -ExpAbsent $true
        pav_key "WD\SmartScreen key                        (should be deleted)" $wdSSBase -ShouldExist $false
        pav_reg "HKCU Edge\PhishingFilter  EnabledV9       (absent)"         $edgePF       "EnabledV9"                          $null -ExpAbsent $true
        pav_reg "HKCU Edge\PhishingFilter  PreventOverride (absent)"         $edgePF       "PreventOverride"                    $null -ExpAbsent $true
        pav_reg "HKCU Edge  SmartScreenEnabled             (absent)"         $edgeBase     "SmartScreenEnabled"                 $null -ExpAbsent $true
        pav_key "HKCU Edge\SmartScreenEnabled subkey       (should be gone)" $edgeSSSub   -ShouldExist $false
        pav_reg "HKCU AppHost  EnableWebContentEvaluation  (absent)"         $appHostBase  "EnableWebContentEvaluation"         $null -ExpAbsent $true
        pav_reg "HKCU AppHost  PreventOverride             (absent)"         $appHostBase  "PreventOverride"                    $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [7] SPYNET / CLOUD PROTECTION / MS ANTIMALWARE ────────────────────────" -ForegroundColor DarkCyan
    $spyBase     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"
    $amBase      = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware"
    $amSpyBase   = "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware\SpyNet"
    $mpGearsBase = "HKLM:\SOFTWARE\Microsoft\RemovalTools\MpGears"
    if ($isDisable) {
        pav_reg "Spynet  DisableBlockAtFirstSeen          (exp=1)"  $spyBase     "DisableBlockAtFirstSeen"             1
        pav_reg "Spynet  SpynetReporting                  (exp=0)"  $spyBase     "SpynetReporting"                    0
        pav_reg "Spynet  SubmitSamplesConsent             (exp=2)"  $spyBase     "SubmitSamplesConsent"                2
        pav_reg "Spynet  LocalSettingOverrideSpynetReport (exp=0)"  $spyBase     "LocalSettingOverrideSpynetReporting" 0
        pav_reg "MSAntiMal  ServiceKeepAlive              (exp=0)"  $amBase      "ServiceKeepAlive"                   0
        pav_reg "MSAntiMal  AllowFastServiceStartup       (exp=0)"  $amBase      "AllowFastServiceStartup"            0
        pav_reg "MSAntiMal  DisableRoutinelyTakingAction  (exp=1)"  $amBase      "DisableRoutinelyTakingAction"        1
        pav_reg "MSAntiMal  DisableAntiSpyware            (exp=1)"  $amBase      "DisableAntiSpyware"                  1
        pav_reg "MSAntiMal  DisableAntiVirus              (exp=1)"  $amBase      "DisableAntiVirus"                    1
        pav_reg "MSAntiMal  DisableSpecialRunningModes    (exp=1)"  $amBase      "DisableSpecialRunningModes"           1
        pav_reg "MSAntiMal\SpyNet  SpyNetReporting        (exp=0)"  $amSpyBase   "SpyNetReporting"                    0
        pav_reg "MSAntiMal\SpyNet  LocalSettingOverride   (exp=0)"  $amSpyBase   "LocalSettingOverrideSpyNetReporting" 0
        pav_reg "MpGears  HeartbeatTrackingIndex          (exp=0)"  $mpGearsBase "HeartbeatTrackingIndex"              0
        pav_reg "MpGears  SpyNetReportingLocation         (exp='0')" $mpGearsBase "SpyNetReportingLocation"            "0"
    } else {
        pav_key "Spynet key                               (should be deleted)" $spyBase   -ShouldExist $false
        pav_key "MSAntimalware key                        (should be deleted)" $amBase    -ShouldExist $false
        pav_key "MSAntimalware\SpyNet key                 (should be deleted)" $amSpyBase -ShouldExist $false
        pav_reg "MpGears  HeartbeatTrackingIndex          (absent)"            $mpGearsBase "HeartbeatTrackingIndex"    $null -ExpAbsent $true
        pav_reg "MpGears  SpyNetReportingLocation         (absent)"            $mpGearsBase "SpyNetReportingLocation"   $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [8] SCAN / SIG UPDATES / MPENGINE / NIS / REPORTING / CFA / NETPROT ──" -ForegroundColor DarkCyan
    $scanBase   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan"
    $sigBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates"
    $mpeBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine"
    $nisBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS"
    $polMgrBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager"
    $excBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions"
    $uxBase     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration"
    $repBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting"
    $cfaBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access"
    $netBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection"
    $asrBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR"
    $threatBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Threats"
    $tsaBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Threats\ThreatSeverityDefaultAction"
    if ($isDisable) {
        pav_reg "Scan  LowCpuPriority              (exp=1)"  $scanBase "LowCpuPriority"              1
        pav_reg "Scan  DisableRestorePoint         (exp=1)"  $scanBase "DisableRestorePoint"          1
        pav_reg "Scan  DisableHeuristics           (exp=1)"  $scanBase "DisableHeuristics"            1
        pav_reg "Scan  DisableReparsePointScanning (exp=1)"  $scanBase "DisableReparsePointScanning"  1
        pav_reg "Scan  DisableCatchupQuickScan     (exp=1)"  $scanBase "DisableCatchupQuickScan"      1
        pav_reg "Scan  DisableCatchupFullScan      (exp=1)"  $scanBase "DisableCatchupFullScan"       1
        pav_reg "Scan  DisableArchiveScanning      (exp=1)"  $scanBase "DisableArchiveScanning"       1
        pav_reg "Scan  DisableScanningNetworkFiles (exp=1)"  $scanBase "DisableScanningNetworkFiles"  1
        pav_reg "Scan  DisableEmailScanning        (exp=1)"  $scanBase "DisableEmailScanning"         1
        pav_reg "Scan  DisableRemovableDriveScanning (exp=1)" $scanBase "DisableRemovableDriveScanning" 1
        pav_reg "Scan  ScheduleDay              (exp=8)"  $scanBase "ScheduleDay"                  8
        pav_reg "Scan  ScheduleTime             (exp=0)"  $scanBase "ScheduleTime"                 0
        pav_reg "Scan  ScheduleQuickScanTime    (exp=0)"  $scanBase "ScheduleQuickScanTime"        0
        $remBase2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Remediation"
        pav_reg "Remediation  Scan_ScheduleDay  (exp=8)"  $remBase2 "Scan_ScheduleDay"             8
        pav_reg "Remediation  Scan_ScheduleTime (exp=0)"  $remBase2 "Scan_ScheduleTime"            0
        $wdFeatBase = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        pav_reg "WD\Features  PackagedScanningDisabled (exp=1)" $wdFeatBase "PackagedScanningDisabled" 1
        pav_reg "SigUpd  SignatureDisableNotification        (exp=1)"  $sigBase "SignatureDisableNotification"              1
        pav_reg "SigUpd  DisableScanOnUpdate                 (exp=1)"  $sigBase "DisableScanOnUpdate"                      1
        pav_reg "SigUpd  RealtimeSignatureDelivery           (exp=0)"  $sigBase "RealtimeSignatureDelivery"                0
        pav_reg "SigUpd  UpdateOnStartUp                     (exp=0)"  $sigBase "UpdateOnStartUp"                          0
        pav_reg "SigUpd  DisableUpdateOnStartupWithoutEngine (exp=1)"  $sigBase "DisableUpdateOnStartupWithoutEngine"      1
        pav_reg "SigUpd  ForceUpdateFromMU                   (exp=0)"  $sigBase "ForceUpdateFromMU"                        0
        pav_reg "SigUpd  DisableScheduledSigUpdateOnBattery  (exp=1)"  $sigBase "DisableScheduledSignatureUpdateOnBattery" 1
        pav_reg "SigUpd  CheckAlternateDownloadLocation      (exp=0)"  $sigBase "CheckAlternateDownloadLocation"           0
        pav_reg "SigUpd  CheckAlternateHttpLocation          (exp=0)"  $sigBase "CheckAlternateHttpLocation"               0
        pav_reg "SigUpd  FallbackOrder                       (exp='NoBackgroundUpdates')" $sigBase "FallbackOrder"         "NoBackgroundUpdates"
        pav_reg "MpEngine  MpEnablePus              (exp=0)"  $mpeBase "MpEnablePus"               0
        pav_reg "MpEngine  MpCloudBlockLevel         (exp=0)"  $mpeBase "MpCloudBlockLevel"         0
        pav_reg "MpEngine  MpBafsExtendedTimeout     (exp=0)"  $mpeBase "MpBafsExtendedTimeout"     0
        pav_reg "MpEngine  EnableFileHashComputation (exp=0)"  $mpeBase "EnableFileHashComputation"  0
        pav_reg "NIS\IPS  ThrottleDetectionEventsRate (exp=0)" $nisBase "ThrottleDetectionEventsRate" 0
        pav_reg "NIS\IPS  DisableSignatureRetirement  (exp=1)" $nisBase "DisableSignatureRetirement"  1
        pav_reg "NIS\IPS  DisableProtocolRecognition  (exp=1)" $nisBase "DisableProtocolRecognition"  1
        pav_reg "PolicyMgr  DisableScanningNetworkFiles (exp=1)" $polMgrBase "DisableScanningNetworkFiles" 1
        pav_reg "Exclusions  DisableAutoExclusions    (exp=1)"  $excBase    "DisableAutoExclusions"    1
        pav_reg "UX Config  SuppressRebootNotification (exp=1)" $uxBase     "SuppressRebootNotification" 1
        pav_reg "UX Config  UILockdown                 (exp=1)" $uxBase     "UILockdown"                 1
        pav_reg "UX Config  Notification_Suppress      (exp=1)" $uxBase     "Notification_Suppress"      1
        pav_reg "Reporting  DisableEnhancedNotifications (exp=1)" $repBase  "DisableEnhancedNotifications" 1
        pav_reg "Reporting  DisableGenericRePorts       (exp=1)"  $repBase  "DisableGenericRePorts"        1
        pav_reg "Reporting  WppTracingLevel             (exp=0)"  $repBase  "WppTracingLevel"              0
        pav_reg "Reporting  WppTracingComponents        (exp=0)"  $repBase  "WppTracingComponents"         0
        pav_reg "CFA  EnableControlledFolderAccess      (exp=0)"  $cfaBase  "EnableControlledFolderAccess" 0
        pav_reg "NetProt  EnableNetworkProtection       (exp=0)"  $netBase  "EnableNetworkProtection"      0
        pav_reg "ASR  ExploitGuard_ASR_Rules             (exp=0)"  $asrBase  "ExploitGuard_ASR_Rules"       0
        $asrRulesVerifyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
        if (Test-Path $asrRulesVerifyPath) {
            $asrGuidsV = Get-Item $asrRulesVerifyPath -EA SilentlyContinue | Select-Object -ExpandProperty Property -EA SilentlyContinue
            if ($asrGuidsV) {
                $asrGuidFail = 0
                foreach ($g in $asrGuidsV) {
                    $gv = Get-RegValue $asrRulesVerifyPath $g
                    if ($null -ne $gv -and "$gv" -ne "0") { $asrGuidFail++ }
                }
                if ($asrGuidFail -eq 0) {
                    pav_line "ASR\Rules per-GUID values ($($asrGuidsV.Count) found)" "PASS" "(all set to 0)"
                } else {
                    pav_line "ASR\Rules per-GUID values ($($asrGuidsV.Count) found)" "FAIL" "($asrGuidFail GUID(s) not zeroed)"
                }
            } else {
                pav_line "ASR\Rules per-GUID values" "SKIP" "(subkey present but no values)"
            }
        } else {
            pav_line "ASR\Rules per-GUID values" "SKIP" "(ASR\Rules subkey absent — no per-GUID entries)"
        }
        $pmAsrVal = Get-RegValue $polMgrBase "ASRRules"
        if ($null -eq $pmAsrVal -or "$pmAsrVal" -eq "") {
            pav_line "PolicyManager  ASRRules                       (exp=absent/empty)" "PASS" "(cleared)"
        } else {
            pav_line "PolicyManager  ASRRules                       (exp=absent/empty)" "FAIL" "(value still set: '$pmAsrVal')"
        }
        foreach ($cc1e in @(
            @{N="WdBoot";   Exp=4},
            @{N="WdFilter"; Exp=4},
            @{N="WdNisDrv"; Exp=4},
            @{N="WdDevFlt"; Exp=4}
        )) {
            $cc1p = "HKLM:\SYSTEM\ControlSet001\Services\$($cc1e.N)"
            if (Test-Path $cc1p) {
                $sv = (Get-ItemProperty -Path $cc1p -Name "Start" -EA SilentlyContinue).Start
                if ($null -eq $sv)         { pav_line "CC1: $($cc1e.N)  Start  (exp=4 disabled)" "FAIL" "(Start value missing)"  }
                elseif ($sv -eq $cc1e.Exp) { pav_line "CC1: $($cc1e.N)  Start  (exp=4 disabled)" "PASS" "(Start=$sv)"            }
                else                       { pav_line "CC1: $($cc1e.N)  Start  (exp=4 disabled)" "FAIL" "(Start=$sv; exp=4)"     }
            } else {
                pav_line "CC1: $($cc1e.N)" "SKIP" "(ControlSet001 key absent on this system)"
            }
        }
        pav_reg "Threats  ThreatSeverityDefaultAction    (exp=1)"  $threatBase "Threats_ThreatSeverityDefaultAction" 1
        pav_reg "TSA  Severity 1 (Low)                   (exp='6')" $tsaBase "1" "6"
        pav_reg "TSA  Severity 2 (Medium)                (exp='6')" $tsaBase "2" "6"
        pav_reg "TSA  Severity 4 (High)                  (exp='6')" $tsaBase "4" "6"
        pav_reg "TSA  Severity 5 (Severe)                (exp='6')" $tsaBase "5" "6"
    } else {
        pav_key "Scan key                      (should be deleted)" $scanBase    -ShouldExist $false
        pav_key "Signature Updates key         (should be deleted)" $sigBase     -ShouldExist $false
        pav_key "MpEngine key                  (should be deleted)" $mpeBase     -ShouldExist $false
        pav_key "NIS\IPS key                   (should be deleted)" $nisBase     -ShouldExist $false
        pav_key "Remediation key               (should be deleted)" "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Remediation" -ShouldExist $false
        $pmKeyExists   = Test-Path $polMgrBase
        $pmHarmfulVal  = Get-RegValue $polMgrBase "DisableScanningNetworkFiles"
        if (-not $pmKeyExists) {
            pav_line "Policy Manager key            (absent or empty = correct)" "PASS" "(key absent)"
        } elseif ($null -eq $pmHarmfulVal) {
            pav_line "Policy Manager key            (absent or empty = correct)" "INFO" "(key present but empty — WinDefend recreated it as empty container at startup; this is the default Windows state and is harmless)"
        } else {
            pav_line "Policy Manager key            (should be absent/empty)"    "FAIL" "(key present with DisableScanningNetworkFiles=$pmHarmfulVal — value was not cleaned up)"
        }
        $pmAsrValE = Get-RegValue $polMgrBase "ASRRules"
        if ($null -eq $pmAsrValE -or "$pmAsrValE" -eq "") {
            pav_line "PolicyManager  ASRRules                       (exp=absent/empty)" "PASS" "(cleared or absent)"
        } else {
            pav_line "PolicyManager  ASRRules                       (exp=absent/empty)" "FAIL" "(still set: '$pmAsrValE')"
        }
        pav_key "Exclusions key                (should be deleted)" $excBase     -ShouldExist $false
        pav_key "UX Configuration key          (should be deleted)" $uxBase      -ShouldExist $false
        pav_key "Reporting key                 (should be deleted)" $repBase     -ShouldExist $false
        pav_key "CFA key                       (should be deleted)" $cfaBase     -ShouldExist $false
        pav_key "Network Protection key        (should be deleted)" $netBase     -ShouldExist $false
        pav_key "ASR key                       (should be deleted)" $asrBase     -ShouldExist $false
        pav_key "Threats key                   (should be deleted)" $threatBase  -ShouldExist $false
        pav_key "ThreatSeverityDefaultAction   (should be deleted)" $tsaBase     -ShouldExist $false
        foreach ($cc1e in @(
            @{N="WdBoot";   Exp=0},
            @{N="WdFilter"; Exp=0},
            @{N="WdNisDrv"; Exp=3},
            @{N="WdDevFlt"; Exp=0}
        )) {
            $cc1p = "HKLM:\SYSTEM\ControlSet001\Services\$($cc1e.N)"
            if (Test-Path $cc1p) {
                $sv = (Get-ItemProperty -Path $cc1p -Name "Start" -EA SilentlyContinue).Start
                if ($null -eq $sv)         { pav_line "CC1: $($cc1e.N)  Start  (exp=$($cc1e.Exp) default)" "FAIL" "(Start value missing)"              }
                elseif ($sv -eq $cc1e.Exp) { pav_line "CC1: $($cc1e.N)  Start  (exp=$($cc1e.Exp) default)" "PASS" "(Start=$sv)"                        }
                else                       { pav_line "CC1: $($cc1e.N)  Start  (exp=$($cc1e.Exp) default)" "FAIL" "(Start=$sv; exp=$($cc1e.Exp))"      }
            } else {
                pav_line "CC1: $($cc1e.N)" "SKIP" "(ControlSet001 key absent on this system)"
            }
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [9] NOTIFICATIONS / SECURITY CENTER / HEALTH / SETTINGS PAGE / WTDS ──" -ForegroundColor DarkCyan
    $pmWdscDen    = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableEnhancedNotifications"
    $pmWdscDn     = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\DisableNotifications"
    $pmWdscHide   = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WindowsDefenderSecurityCenter\HideWindowsSecurityNotificationAreaControl"
    $scNotifBase  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications"
    $secCtrBase   = "HKLM:\SOFTWARE\Microsoft\Security Center"
    $wsHealthBase = "HKLM:\SOFTWARE\Microsoft\Windows Security Health\Platform"
    $wsHealtState = "HKCU:\Software\Microsoft\Windows Security Health\State"
    $toastBase    = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance"
    $settPageBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $wtdsBase     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components"
    $wtdsPmBase   = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WebThreatDefense\ServiceEnabled"
    $wdscAppBase  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection"
    $wdscBase     = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center"
    if ($isDisable) {
        pav_reg "PMgr\WDSC  DisableEnhancedNotifications  (exp=1)"  $pmWdscDen   "value" 1
        pav_reg "PMgr\WDSC  DisableNotifications          (exp=1)"  $pmWdscDn    "value" 1
        pav_reg "PMgr\WDSC  HideWinSecNotifAreaControl    (exp=1)"  $pmWdscHide  "value" 1
        pav_key "SC\Notifications key                     (present)" $scNotifBase -ShouldExist $true
        pav_reg "SC\Notif  DisableEnhancedNotifications   (exp=1)"  $scNotifBase "DisableEnhancedNotifications" 1
        pav_reg "SC\Notif  DisableNotifications           (exp=1)"  $scNotifBase "DisableNotifications"         1
        pav_reg "WDSC\V&TP  UILockdown                   (exp=1)"  "$wdscBase\Virus and threat protection" "UILockdown" 1
        pav_reg "WDSC\V&TP  HideRansomwareRecovery       (exp=1)"  "$wdscBase\Virus and threat protection" "HideRansomwareRecovery" 1
        pav_reg "WDSC\Firewall  UILockdown                (exp=1)"  "$wdscBase\Firewall and network protection" "UILockdown" 1
        pav_reg "WDSC\App&Browser  UILockdown             (exp=1)"  "$wdscBase\App and Browser protection" "UILockdown" 1
        pav_reg "WDSC\DeviceSec  UILockdown               (exp=1)"  "$wdscBase\Device security" "UILockdown" 1
        pav_reg "WDSC\AcctProt  UILockdown                (exp=1)"  "$wdscBase\Account protection" "UILockdown" 1
        pav_reg "WDSC\Family  UILockdown                  (exp=1)"  "$wdscBase\Family options" "UILockdown" 1
        pav_reg "Security Center  AntiVirusOverride       (exp=1)"  $secCtrBase  "AntiVirusOverride"            1
        pav_reg "Security Center  FirewallOverride        (exp=1)"  $secCtrBase  "FirewallOverride"             1
        pav_reg "Security Center  FirstRunDisabled        (exp=1)"  $secCtrBase  "FirstRunDisabled"             1
        pav_reg "WSHealth\Platform  Registered            (exp=0)"  $wsHealthBase "Registered"                  0
        pav_reg "WSHealth\State  Disabled                 (exp=1)"  $wsHealtState "Disabled"                    1
        pav_reg "Toast  Enabled                           (exp=0)"  $toastBase    "Enabled"                     0
        pav_reg "Explorer  SettingsPageVisibility (exp='hide:windowsdefender;')" $settPageBase "SettingsPageVisibility" "hide:windowsdefender;"
        pav_reg "WTDS  NotifyPasswordReuse                (exp=0)"  $wtdsBase    "NotifyPasswordReuse"          0
        pav_reg "WTDS  NotifyMalicious                    (exp=0)"  $wtdsBase    "NotifyMalicious"              0
        pav_reg "WTDS  NotifyUnsafeApp                    (exp=0)"  $wtdsBase    "NotifyUnsafeApp"              0
        pav_reg "WTDS  NotifyPhishing                     (exp=0)"  $wtdsBase    "NotifyPhishing"               0
        pav_reg "WTDS  ServiceEnabled                     (exp=0)"  $wtdsBase    "ServiceEnabled"               0
        pav_reg "PMgr\WebThreatDefense\ServiceEnabled     (exp=0)"  $wtdsPmBase  "value"                        0
        pav_reg "WDSC\App&Browser  DisallowExploitProtOvr (exp=1)" $wdscAppBase "DisallowExploitProtectionOverride" 1
        $mrtPolBase = "HKLM:\SOFTWARE\Policies\Microsoft\MRT"
        pav_reg "MRT Policy  DontOfferThroughWUAU         (exp=1)"  $mrtPolBase  "DontOfferThroughWUAU"         1
        pav_reg "MRT Policy  DontRunOnce                  (exp=1)"  $mrtPolBase  "DontRunOnce"                  1
        $wshStateBasePav = "HKCU:\Software\Microsoft\Windows Security Health\State"
        pav_reg "WSHealth\State  AppAndBrowser_StoreAppsSmartScreenOff (exp=0)"  $wshStateBasePav "AppAndBrowser_StoreAppsSmartScreenOff" 0
        pav_reg "WSHealth\State  AppAndBrowser_EdgeSmartScreenOff      (exp=0)"  $wshStateBasePav "AppAndBrowser_EdgeSmartScreenOff"      0
    } else {
        pav_reg "PMgr\WDSC  DisableEnhancedNotifications  (absent)" $pmWdscDen   "value" $null -ExpAbsent $true
        pav_reg "PMgr\WDSC  DisableNotifications          (absent)" $pmWdscDn    "value" $null -ExpAbsent $true
        pav_reg "PMgr\WDSC  HideWinSecNotifAreaControl    (absent)" $pmWdscHide  "value" $null -ExpAbsent $true
        pav_key "WDSC key (entire tree should be deleted)         " $wdscBase    -ShouldExist $false
        pav_reg "WDSC\App&Browser  DisallowExploitProtOvr (absent)" $wdscAppBase "DisallowExploitProtectionOverride" $null -ExpAbsent $true
        pav_reg "Security Center  AntiVirusOverride       (absent)" $secCtrBase  "AntiVirusOverride" $null -ExpAbsent $true
        pav_reg "Security Center  FirewallOverride        (absent)" $secCtrBase  "FirewallOverride"  $null -ExpAbsent $true
        pav_reg "Security Center  FirstRunDisabled        (absent)" $secCtrBase  "FirstRunDisabled"  $null -ExpAbsent $true
        pav_reg "WSHealth\Platform  Registered            (exp=1)"  $wsHealthBase "Registered"       1
        pav_reg "WSHealth\State  Disabled                 (absent)" $wsHealtState "Disabled"         $null -ExpAbsent $true
        pav_reg "Toast  Enabled                           (absent)" $toastBase    "Enabled"          $null -ExpAbsent $true
        pav_reg "Explorer  SettingsPageVisibility         (absent)" $settPageBase "SettingsPageVisibility" $null -ExpAbsent $true
        pav_key "WTDS key                                 (should be deleted)" $wtdsBase    -ShouldExist $false
        pav_reg "PMgr\WebThreatDefense\ServiceEnabled     (exp=1)"  $wtdsPmBase  "value"             1
        $mrtPolBase = "HKLM:\SOFTWARE\Policies\Microsoft\MRT"
        pav_key "MRT Policy key                           (should be deleted)" $mrtPolBase  -ShouldExist $false
        $wshStateBasePav = "HKCU:\Software\Microsoft\Windows Security Health\State"
        pav_reg "WSHealth\State  AppAndBrowser_StoreAppsSmartScreenOff (absent)" $wshStateBasePav "AppAndBrowser_StoreAppsSmartScreenOff" $null -ExpAbsent $true
        pav_reg "WSHealth\State  AppAndBrowser_EdgeSmartScreenOff      (absent)" $wshStateBasePav "AppAndBrowser_EdgeSmartScreenOff"      $null -ExpAbsent $true
    }
    Write-Host ""

    Write-Host "  ┌─ [9b] DEFENDER DIRECT CONFIG KEYS (non-policy) ──────────────────────────" -ForegroundColor DarkCyan
    $wdDirect    = "HKLM:\SOFTWARE\Microsoft\Windows Defender"
    $wdRtpDirect = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"
    $wdSpyDirect = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Spynet"
    if ($isDisable) {
        pav_reg "WD (direct)  DisableAntiSpyware            (exp=1)"  $wdDirect    "DisableAntiSpyware"           1
        pav_reg "WD (direct)  DisableAntiVirus              (exp=1)"  $wdDirect    "DisableAntiVirus"             1
        pav_reg "WD (direct)  DisableRoutinelyTakingAction  (exp=1)"  $wdDirect    "DisableRoutinelyTakingAction" 1
        pav_reg "WD (direct)  ServiceKeepAlive              (exp=0)"  $wdDirect    "ServiceKeepAlive"             0
        pav_reg "WD (direct)  AllowFastServiceStartup       (exp=0)"  $wdDirect    "AllowFastServiceStartup"      0
        pav_reg "WD (direct)  DisableSpecialRunningModes    (exp=1)"  $wdDirect    "DisableSpecialRunningModes"   1
        $wdFeatBase2 = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        pav_reg "WD\Features  PackagedScanningDisabled      (exp=1)"  $wdFeatBase2 "PackagedScanningDisabled"     1
        pav_reg "WD\RTP (direct)  DisableRealtimeMonitoring (exp=1)"  $wdRtpDirect "DisableRealtimeMonitoring"    1
        pav_reg "WD\RTP (direct)  DisableBehaviorMonitoring (exp=1)"  $wdRtpDirect "DisableBehaviorMonitoring"    1
        pav_reg "WD\RTP (direct)  DisableOnAccessProtection (exp=1)"  $wdRtpDirect "DisableOnAccessProtection"    1
        pav_reg "WD\RTP (direct)  DisableIOAVProtection     (exp=1)"  $wdRtpDirect "DisableIOAVProtection"        1
        pav_reg "WD\RTP (direct)  DisableScanOnRealtimeEnable(exp=1)" $wdRtpDirect "DisableScanOnRealtimeEnable"  1
        pav_reg "WD\RTP (direct)  DisableScriptScanning     (exp=1)"  $wdRtpDirect "DisableScriptScanning"        1
        pav_reg "WD\RTP (direct)  DisableIntrusionPreventSys(exp=1)"  $wdRtpDirect "DisableIntrusionPreventionSystem" 1
        pav_reg "WD\RTP (direct)  DisableRawWriteNotif      (exp=1)"  $wdRtpDirect "DisableRawWriteNotification"  1
        pav_reg "WD\RTP (direct)  DisableInfoProtControl    (exp=1)"  $wdRtpDirect "DisableInformationProtectionControl" 1
        pav_reg "WD\RTP (direct)  DisableAntiSpywareRTProt  (exp=1)"  $wdRtpDirect "DisableAntiSpywareRealtimeProtection" 1
        pav_reg "WD\RTP (direct)  DpaDisabled               (exp=1)"  $wdRtpDirect "DpaDisabled"                         1
        pav_reg "WD\Spynet (direct)  SpynetReporting        (exp=0)"  $wdSpyDirect "SpynetReporting"              0
        pav_reg "WD\Spynet (direct)  SubmitSamplesConsent   (exp=2)"  $wdSpyDirect "SubmitSamplesConsent"         2
        pav_reg "WD\Spynet (direct)  DisableBlockAtFirstSeen(exp=1)"  $wdSpyDirect "DisableBlockAtFirstSeen"      1
        pav_reg "WD (direct)  AllowDevDriveProtection       (exp=0 DISABLED)"  $wdDirect "AllowDevDriveProtection" 0
        $ifeoBasePav = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        pav_reg "IFEO\MsMpEng.exe  Debugger                 (exp='NUL')" "$ifeoBasePav\MsMpEng.exe"  "Debugger" "NUL"
        pav_reg "IFEO\MpCmdRun.exe  Debugger                (exp='NUL')" "$ifeoBasePav\MpCmdRun.exe" "Debugger" "NUL"
        pav_reg "IFEO\NisSrv.exe   Debugger                 (exp='NUL')" "$ifeoBasePav\NisSrv.exe"   "Debugger" "NUL"
    } else {
        pav_reg "WD (direct)  DisableAntiSpyware            (absent)" $wdDirect    "DisableAntiSpyware"           $null -ExpAbsent $true
        pav_reg "WD (direct)  DisableAntiVirus              (absent)" $wdDirect    "DisableAntiVirus"             $null -ExpAbsent $true
        pav_reg "WD (direct)  DisableRoutinelyTakingAction  (absent)" $wdDirect    "DisableRoutinelyTakingAction" $null -ExpAbsent $true
        pav_reg "WD (direct)  ServiceKeepAlive              (absent)" $wdDirect    "ServiceKeepAlive"             $null -ExpAbsent $true
        pav_reg "WD (direct)  AllowFastServiceStartup       (absent)" $wdDirect    "AllowFastServiceStartup"      $null -ExpAbsent $true
        pav_reg "WD (direct)  DisableSpecialRunningModes    (absent)" $wdDirect    "DisableSpecialRunningModes"   $null -ExpAbsent $true
        $wdFeatBase2 = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
        pav_reg "WD\Features  PackagedScanningDisabled      (absent)" $wdFeatBase2 "PackagedScanningDisabled"     $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableRealtimeMonitoring (absent)" $wdRtpDirect "DisableRealtimeMonitoring"    $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableBehaviorMonitoring (absent)" $wdRtpDirect "DisableBehaviorMonitoring"    $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableOnAccessProtection (absent)" $wdRtpDirect "DisableOnAccessProtection"    $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableIOAVProtection     (absent)" $wdRtpDirect "DisableIOAVProtection"        $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableScanOnRealtimeEnable(absent)"$wdRtpDirect "DisableScanOnRealtimeEnable"  $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableScriptScanning     (absent)" $wdRtpDirect "DisableScriptScanning"        $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableIntrusionPreventSys(absent)" $wdRtpDirect "DisableIntrusionPreventionSystem" $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableRawWriteNotif      (absent)" $wdRtpDirect "DisableRawWriteNotification"  $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableInfoProtControl    (absent)" $wdRtpDirect "DisableInformationProtectionControl" $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DisableAntiSpywareRTProt  (absent)" $wdRtpDirect "DisableAntiSpywareRealtimeProtection" $null -ExpAbsent $true
        pav_reg "WD\RTP (direct)  DpaDisabled               (absent)" $wdRtpDirect "DpaDisabled"                         $null -ExpAbsent $true
        pav_reg "WD\Spynet (direct)  SpynetReporting        (absent)" $wdSpyDirect "SpynetReporting"              $null -ExpAbsent $true
        pav_reg "WD\Spynet (direct)  SubmitSamplesConsent   (absent)" $wdSpyDirect "SubmitSamplesConsent"         $null -ExpAbsent $true
        pav_reg "WD\Spynet (direct)  DisableBlockAtFirstSeen(absent)" $wdSpyDirect "DisableBlockAtFirstSeen"      $null -ExpAbsent $true
        pav_reg "WD (direct)  AllowDevDriveProtection       (exp=absent/default=ENABLED)" $wdDirect "AllowDevDriveProtection" $null -ExpAbsent $true
        $ifeoBasePav = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        pav_key "IFEO\MsMpEng.exe key                      (should be deleted)" "$ifeoBasePav\MsMpEng.exe"  -ShouldExist $false
        pav_key "IFEO\MpCmdRun.exe key                     (should be deleted)" "$ifeoBasePav\MpCmdRun.exe" -ShouldExist $false
        pav_key "IFEO\NisSrv.exe key                       (should be deleted)" "$ifeoBasePav\NisSrv.exe"   -ShouldExist $false
    }
    Write-Host ""

    Write-Host "  ┌─ [9c] WINDOWS FIREWALL ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
    foreach ($fwEntry in @(
        @{Profile="DomainProfile";   Name="Domain"},
        @{Profile="StandardProfile"; Name="Private"},
        @{Profile="PublicProfile";   Name="Public"})) {
        $fwPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$($fwEntry.Profile)"
        if ($isDisable) {
            pav_reg "Firewall $($fwEntry.Name)  EnableFirewall  (exp=0)" $fwPath "EnableFirewall" 0
        } else {
            pav_reg "Firewall $($fwEntry.Name)  EnableFirewall  (exp=1)" $fwPath "EnableFirewall" 1
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [10] SERVICES — REGISTRY Start VALUES ─────────────────────────────────" -ForegroundColor DarkCyan
    foreach ($svc in $script:DS_TouchedServices) {
        $svcPath  = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.N)"
        $expStart = if ($isDisable) { 4 } else { $svc.Def }
        $noteMode = if ($isDisable) { "exp=4 disabled" } else { "exp=$($svc.Def) default" }
        if (Test-Path $svcPath) {
            $startVal = (Get-ItemProperty -Path $svcPath -Name "Start" -ErrorAction SilentlyContinue).Start
            $lbl      = "Svc $($svc.N.PadRight(24)) $($svc.Label.PadRight(36)) ($noteMode)"
            if ($null -eq $startVal)        { pav_line $lbl "FAIL" "(Start value missing)"                }
            elseif ($startVal -eq $expStart){ pav_line $lbl "PASS" "(Start=$startVal)"                    }
            else                            { pav_line $lbl "FAIL" "(Start=$startVal; expected=$expStart)" }
        } else {
            pav_line "Svc $($svc.N)" "SKIP" "(service registry key absent on this system)"
        }
    }
    Write-Host ""
    Write-Host "    [Live runtime state via sc.exe query]" -ForegroundColor DarkGray
    foreach ($svcName in @("WinDefend","WdNisSvc","WdFilter","SecurityHealthService","wscsvc","Sense","SgrmBroker","webthreatdefsvc","MDCoreSvc","MpsSvc")) {
        try {
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
            $scOut    = & sc.exe query $svcName 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($exitCode -ne 0 -or $scOut -match "does not exist") {
                pav_line "  Runtime: $($svcName.PadRight(26))" "SKIP" "(not found on this system)"
            } else {
                $running  = $scOut -match "RUNNING"
                $stopped  = $scOut -match "STOPPED"
                $stateStr = if ($running) { "RUNNING" } elseif ($stopped) { "STOPPED" } else { "OTHER" }
                if ($isDisable) {
                    if ($stopped) { pav_line "  Runtime: $($svcName.PadRight(26))" "PASS" "(STOPPED — correct for disabled state)"   }
                    else          { pav_line "  Runtime: $($svcName.PadRight(26))" "WARN" "($stateStr — may need reboot to stop)"    }
                } else {
                    $expectedRunning = $svcName -in @("WinDefend","wscsvc","SecurityHealthService","SgrmBroker","MDCoreSvc","MpsSvc")
                    if ($expectedRunning) {
                        if ($running) { pav_line "  Runtime: $($svcName.PadRight(26))" "PASS" "(RUNNING — correct)"          }
                        else           { pav_line "  Runtime: $($svcName.PadRight(26))" "WARN" "($stateStr — expected RUNNING)" }
                    } else {
                        pav_line "  Runtime: $($svcName.PadRight(26))" "INFO" "($stateStr — demand-start; OK if not running)"
                    }
                }
            }
        } catch {
            pav_line "  Runtime: $($svcName.PadRight(26))" "SKIP" "(query failed: $_)"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [11] WMI AUTOLOGGERS ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
    foreach ($logName in @("DefenderApiLogger","DefenderAuditLogger","DefenderRtpLogger")) {
        $logPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$logName"
        $expStart = if ($isDisable) { 0 } else { 1 }
        $noteMode = if ($isDisable) { "exp=0 disabled" } else { "exp=1 enabled" }
        if (Test-Path $logPath) {
            $startVal = (Get-ItemProperty -Path $logPath -Name "Start" -ErrorAction SilentlyContinue).Start
            $lbl      = "WMI\Autologger\$($logName.PadRight(22)) ($noteMode)"
            if ($null -eq $startVal)         { pav_line $lbl "FAIL" "(Start value absent)"                  }
            elseif ($startVal -eq $expStart) { pav_line $lbl "PASS" "(Start=$startVal)"                     }
            else                             { pav_line $lbl "FAIL" "(Start=$startVal; expected=$expStart)"  }
        } else {
            pav_line "WMI\Autologger\$logName" "SKIP" "(key absent on this system)"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [12] SCHEDULED TASKS ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
    foreach ($task in $script:DS_TouchedTasks) {
        $shortName = ($task -split '\\')[-1]
        try {
            $taskState = Get-TaskStateString $task
            if ($null -eq $taskState) {
                pav_line "Task: $($shortName.PadRight(50))" "SKIP" "(task not found on this system)"
            } else {
                if ($isDisable) {
                    if ($taskState -eq 'Disabled') { pav_line "Task: $($shortName.PadRight(50)) (exp=Disabled)" "PASS" "(Disabled — correct)"                           }
                    else                            { pav_line "Task: $($shortName.PadRight(50)) (exp=Disabled)" "FAIL" "(state=$taskState — should be Disabled)"         }
                } else {
                    if ($taskState -match '^(Ready|Running|Queued)$') { pav_line "Task: $($shortName.PadRight(50)) (exp=Ready)" "PASS" "(state=$taskState — correct)"                    }
                    else                                               { pav_line "Task: $($shortName.PadRight(50)) (exp=Ready)" "WARN" "(state=$taskState — may need reboot to re-enable)" }
                }
            }
        } catch {
            pav_line "Task: $($shortName.PadRight(50))" "SKIP" "(query error: $_)"
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [13] STARTUP RUN ENTRIES ──────────────────────────────────────────────" -ForegroundColor DarkCyan
    $hklmRun      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $hkcuRun      = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $startApproved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    foreach ($valName in @("Windows Defender","WindowsDefender","SecurityHealth")) {
        $hklmV = Get-RegValue $hklmRun $valName
        $hkcuV = Get-RegValue $hkcuRun $valName
        $saMarker = Get-RegValue $startApproved $valName
        $saDisabled = ($null -ne $saMarker -and $saMarker.Length -ge 1 -and ([byte]($saMarker[0])) -eq 0x03)
        if ($isDisable) {
            if ($null -eq $hklmV) {
                pav_line "HKLM\Run  $valName  (should be absent)" "PASS" "(absent — correct)"
            } elseif ($saDisabled) {
                pav_line "HKLM\Run  $valName  (should be absent)" "PASS" "(present but StartupApproved disabled marker is set — Windows will not launch this entry)"
            } else {
                pav_line "HKLM\Run  $valName  (should be absent)" "FAIL" "(present: '$hklmV')"
            }
            if ($null -eq $hkcuV) { pav_line "HKCU\Run  $valName  (should be absent)" "PASS" "(absent — correct)"       }
            else                   { pav_line "HKCU\Run  $valName  (should be absent)" "FAIL" "(present: '$hkcuV')"      }
        } else {
            if ($null -ne $hklmV) { pav_line "HKLM\Run  $valName" "INFO" "(present: '$hklmV')" }
            if ($null -ne $hkcuV) { pav_line "HKCU\Run  $valName" "INFO" "(present: '$hkcuV')" }
        }
    }
    foreach ($valName in @("SecurityHealth","Windows Defender")) {
        $saV = Get-RegValue $startApproved $valName
        if ($isDisable) {
            if ($null -eq $saV) {
                pav_line "StartupApproved  $($valName.PadRight(20)) (absent)"              "INFO" "(absent — OK if entry never existed)"
            } elseif ($saV.Length -ge 1 -and ([byte]($saV[0])) -eq 0x03) {
                pav_line "StartupApproved  $($valName.PadRight(20)) (disabled marker)"     "PASS" "(first byte=03 → disabled)"
            } else {
                $byteStr = try { [BitConverter]::ToString([byte[]]$saV[0..([Math]::Min(11,$saV.Length-1))]) } catch { "$saV" }
                pav_line "StartupApproved  $($valName.PadRight(20)) (should be disabled)"  "FAIL" "(not a disabled marker; bytes=$byteStr)"
            }
        } else {
            if ($null -eq $saV) {
                pav_line "StartupApproved  $($valName.PadRight(20)) (absent)"              "INFO" "(absent — Windows will recreate on service start)"
            } elseif ($saV.Length -ge 1 -and (([byte]($saV[0])) -eq 0x02 -or ([byte]($saV[0])) -eq 0x06)) {
                pav_line "StartupApproved  $($valName.PadRight(20)) (enabled marker)"      "PASS" "(first byte=$("{0:X2}" -f ([byte]($saV[0]))) → enabled)"
            } elseif ($saV.Length -ge 1 -and ([byte]($saV[0])) -eq 0x03) {
                pav_line "StartupApproved  $($valName.PadRight(20)) (still disabled)"      "WARN" "(still disabled — may not auto-launch; check HKLM\Run entry)"
            } else {
                $byteStr = try { [BitConverter]::ToString([byte[]]$saV[0..([Math]::Min(11,$saV.Length-1))]) } catch { "$saV" }
                pav_line "StartupApproved  $($valName.PadRight(20))"                       "INFO" "(bytes=$byteStr)"
            }
        }
    }
    Write-Host ""

    Write-Host "  ┌─ [14] LIVE RUNTIME — MpComputerStatus + MpPreference ───────────────────" -ForegroundColor DarkCyan
    $mpAvail = $true
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        function mpsl { param([string]$L, [bool]$Val, [bool]$ExpTrueWhenEnabled)
            $exp  = if ($isDisable) { -not $ExpTrueWhenEnabled } else { $ExpTrueWhenEnabled }
            $note = if ($Val) { "ACTIVE" } else { "INACTIVE" }
            $expN = if ($exp)  { "ACTIVE" } else { "INACTIVE" }
            if ($Val -eq $exp) { pav_line $L "PASS" "($note — correct)" }
            else                { pav_line $L "INFO" "($note — will be active on next boot)" }
        }
        mpsl "MpComputerStatus  RealTimeProtectionEnabled " $mpStatus.RealTimeProtectionEnabled  $true
        mpsl "MpComputerStatus  AntivirusEnabled          " $mpStatus.AntivirusEnabled            $true
        mpsl "MpComputerStatus  AntispywareEnabled        " $mpStatus.AntispywareEnabled          $true
        mpsl "MpComputerStatus  BehaviorMonitorEnabled    " $mpStatus.BehaviorMonitorEnabled      $true
        mpsl "MpComputerStatus  IoavProtectionEnabled     " $mpStatus.IoavProtectionEnabled       $true
        mpsl "MpComputerStatus  OnAccessProtectionEnabled " $mpStatus.OnAccessProtectionEnabled   $true
        mpsl "MpComputerStatus  NISEnabled                " $mpStatus.NISEnabled                  $true
        mpsl "MpComputerStatus  AMServiceEnabled          " $mpStatus.AMServiceEnabled            $true
        if ($null -ne $mpStatus.IsTamperProtected) {
            $tpLiveExpOff = if ($isDisable) { $false } else { $true }
            if ($mpStatus.IsTamperProtected -eq $tpLiveExpOff) {
                pav_line "MpComputerStatus  IsTamperProtected          " "PASS" "(=$($mpStatus.IsTamperProtected))"
            } else {
                pav_line "MpComputerStatus  IsTamperProtected          " "INFO" "(=$($mpStatus.IsTamperProtected); will be correct on next boot)"
            }
        } else {
            pav_line "MpComputerStatus  IsTamperProtected          " "INFO" "(property not available on this build)"
        }
        $amEngVer = $mpStatus.AMEngineVersion
        $amSigAge = $mpStatus.AntivirusSignatureAge
        pav_line "MpComputerStatus  AMEngineVersion            " "INFO" "(=$amEngVer)"
        pav_line "MpComputerStatus  AntivirusSignatureAge (days)" "INFO" "(=$amSigAge)"
    } catch {
        $mpAvail = $false
        pav_line "MpComputerStatus" "SKIP" "(cmdlet unavailable — normal when Defender is fully stopped)"
    }
    if ($mpAvail) {
        try {
            $mpPref  = Get-MpPreference -ErrorAction Stop
            function mppl { param([string]$L, [bool]$Val, [bool]$ExpTrueWhenDisabled)
                $exp  = if ($isDisable) { $ExpTrueWhenDisabled } else { -not $ExpTrueWhenDisabled }
                if ($Val -eq $exp) { pav_line $L "PASS" "(=$Val)" }
                else                { pav_line $L "WARN" "(=$Val; expected=$exp)" }
            }
            mppl "MpPreference  DisableRealtimeMonitoring     " $mpPref.DisableRealtimeMonitoring    $true
            mppl "MpPreference  DisableBehaviorMonitoring     " $mpPref.DisableBehaviorMonitoring    $true
            mppl "MpPreference  DisableIOAVProtection         " $mpPref.DisableIOAVProtection        $true
            mppl "MpPreference  DisableOnAccessProtection     " $mpPref.DisableOnAccessProtection    $true
            mppl "MpPreference  DisableIntrusionPreventionSys " $mpPref.DisableIntrusionPreventionSystem $true
            mppl "MpPreference  DisableScanningNetworkFiles   " $mpPref.DisableScanningNetworkFiles  $true
            mppl "MpPreference  DisableArchiveScanning        " $mpPref.DisableArchiveScanning       $true
            mppl "MpPreference  DisableEmailScanning          " $mpPref.DisableEmailScanning         $true
            mppl "MpPreference  DisableScriptScanning         " $mpPref.DisableScriptScanning        $true
            mppl "MpPreference  DisableRemovableDriveScanning " $mpPref.DisableRemovableDriveScanning $true
            $puaP = $mpPref.PUAProtection
            pav_line "MpPreference  PUAProtection                 " "INFO" "(=$puaP  [0=disabled, 1=enabled, 2=audit])"
            $smpC = $mpPref.SubmitSamplesConsent
            pav_line "MpPreference  SubmitSamplesConsent           " "INFO" "(=$smpC  [0=always prompt, 1=auto, 2=never])"
            $mpcl = $mpPref.MAPSReporting
            pav_line "MpPreference  MAPSReporting                  " "INFO" "(=$mpcl  [0=disabled])"
        } catch {
            pav_line "MpPreference" "SKIP" "(cmdlet unavailable)"
        }
    }
    Write-Host ""

    $grandTotal = $script:pav_pass + $script:pav_fail + $script:pav_skip + $script:pav_info
    $summColor  = if ($script:pav_fail -eq 0) { "Green" } elseif ($script:pav_fail -le 4) { "Yellow" } else { "Red" }
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "  POST-ACTION VERIFICATION COMPLETE  ($modeLabel mode)" -ForegroundColor $summColor
    Write-Host ""
    Write-Host "  Total checks : $grandTotal" -ForegroundColor Cyan
    Write-Host "  PASS         : $($script:pav_pass)"  -ForegroundColor $(if ($script:pav_pass -gt 0) { "Green" } else { "Gray" })
    Write-Host "  FAIL         : $($script:pav_fail)"  -ForegroundColor $(if ($script:pav_fail -gt 0) { "Red" }   else { "Green" })
    Write-Host "  WARN/INFO    : $($script:pav_info)"  -ForegroundColor Yellow
    Write-Host "  SKIP         : $($script:pav_skip)"  -ForegroundColor Gray
    Write-Host ""
    if ($script:pav_fail -gt 0) {
        Write-Host "  [!] $($script:pav_fail) check(s) FAILED — review RED lines above." -ForegroundColor Red
    } else {
        Write-Host "  [OK] All verifiable checks passed — $modeLabel state confirmed." -ForegroundColor Green
    }
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

function Get-DoubleConfirm {
    param([string]$Action, [string]$Warning = "")
    Write-Host ""

    $prefixLen  = 10  
    $minInner   = 50
    $actionInner = $Action.Length
    $warnInner   = if ($Warning) { $Warning.Length } else { 0 }
    $innerWidth  = [Math]::Max($minInner, [Math]::Max($actionInner, $warnInner))
    $border      = "─" * ($innerWidth + $prefixLen)   

    Write-Host "┌$border┐" -ForegroundColor Yellow
    Write-Host ("│  ACTION: " + $Action.PadRight($innerWidth) + "│") -ForegroundColor Yellow
    if ($Warning) {
        Write-Host ("│  WARN:   " + $Warning.PadRight($innerWidth) + "│") -ForegroundColor Red
    }
    Write-Host "└$border┘" -ForegroundColor Yellow
    Write-Host ""

    $confirm1 = Read-Host "  [CONFIRM 1/2] Type YES to continue"
    if ($confirm1 -ne "YES") {
        Write-Host "  Cancelled." -ForegroundColor Gray
        return $false
    }
    $confirm2 = Read-Host "  [CONFIRM 2/2] Type YES again to proceed"
    if ($confirm2 -ne "YES") {
        Write-Host "  Cancelled." -ForegroundColor Gray
        return $false
    }
    return $true
}

function Invoke-DisableDefender {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║       DISABLING WINDOWS DEFENDER     ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host " Enable restores the script-managed baseline; it does not recover arbitrary pre-existing custom policy." -ForegroundColor Cyan
    Write-Host " SmartScreen will be renamed (.exe → .exee) — rename back to re-enable." -ForegroundColor Cyan
    Write-Host ""

    $stepTotal = 15
    $step = 0

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Pre-stop monitoring services ===" -ForegroundColor Cyan
    Write-Host "  Stopping Defender UI processes and monitoring services..." -ForegroundColor Gray
    try {
        foreach ($procName in @('SecurityHealthHost','SecurityHealthSystray','MpCmdRun','SecurityHealthService')) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 400

        foreach ($svc in @('SecurityHealthService','Sense','wscsvc')) {
            try { & sc.exe stop $svc 2>&1 | Out-Null } catch { }
        }
        Start-Sleep -Milliseconds 500
    } catch { Write-Host "  [ERR] Pre-stop step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Mitigation / Exploit Protection ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableMitigation "Mitigation / Exploit Protection" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Antivirus / Real-Time Protection ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableAntivirusProtection     "Antivirus Protection" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_DisableDefenderPolicies        "Defender Policies (Scan/Sig/MpEngine/NIS/Exclusions/UX/CFA/NetProt/Reporting)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    try {
        $asrRulesPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
        if (Test-Path $asrRulesPath) {
            $asrGuids = Get-Item $asrRulesPath -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Property -ErrorAction SilentlyContinue
            if ($asrGuids) {
                $asrCount = 0
                foreach ($guid in $asrGuids) {
                    $null = Set-RegValueTI `
                        -KeyPath   "SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules" `
                        -ValueName $guid `
                        -ValueData 0 `
                        -Label     "ASR Rule GUID $guid"
                    $asrCount++
                }
                Write-StepLog "ASR per-GUID rule zeroing" "OK" "($asrCount GUID(s) set to 0)"
            } else {
                Write-StepLog "ASR per-GUID rule zeroing" "SKIP" "(no per-GUID values found under ASR\Rules)"
            }
        } else {
            Write-StepLog "ASR per-GUID rule zeroing" "SKIP" "(ASR\Rules subkey absent — no per-GUID values to zero)"
        }
    } catch { Write-Host "  [ERR] ASR GUID zeroing error (continuing): $_" -ForegroundColor Red }

    try {
        $pmAsrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager"
        $existing  = Get-RegValue $pmAsrPath "ASRRules"
        if ($null -ne $existing -and "$existing" -ne "") {
            $null = Set-RegStringTI `
                -KeyPath   "SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" `
                -ValueName "ASRRules" `
                -ValueData "" `
                -Label     "PolicyManager ASRRules clear (MDM/Intune)"
        } else {
            Write-StepLog "PolicyManager ASRRules" "SKIP" "(already absent or empty)"
        }
    } catch { Write-Host "  [ERR] PolicyManager ASRRules clear error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_DisableDefenderandSecurityCenterNotifications "Notifications & Security Center" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: SmartScreen ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableSmartScreen             "SmartScreen (registry)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_DisableWindowsSettingsPageVisibility "Settings Page Visibility" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_Disable_SecurityComp           "Security Center Component" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: WTDS / Web Threat Defense ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableWTDS "Web Threat Defense / SmartScreen App Control" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Windows Firewall ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableFirewall "Windows Firewall (all profiles)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Defender Direct Config Keys ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_DisableDefenderDirect "Defender Direct (non-policy) keys" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Set-MpPreference (live-state override — no reboot needed) ===" -ForegroundColor Cyan
    try {
        $mpOk = 0; $mpFail = 0
        foreach ($mpCall in @(
            { Set-MpPreference -DisableRealtimeMonitoring    $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableBehaviorMonitoring    $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableIOAVProtection        $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableOnAccessProtection    $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableIntrusionPreventionSystem $true -EA SilentlyContinue },
            { Set-MpPreference -DisableScriptScanning        $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableArchiveScanning       $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableEmailScanning         $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableScanningNetworkFiles  $true  -EA SilentlyContinue },
            { Set-MpPreference -DisableRemovableDriveScanning $true -EA SilentlyContinue },
            { Set-MpPreference -DisableBlockAtFirstSeen      $true  -EA SilentlyContinue },
            { Set-MpPreference -MAPSReporting                0      -EA SilentlyContinue },
            { Set-MpPreference -SubmitSamplesConsent         2      -EA SilentlyContinue },
            { Set-MpPreference -PUAProtection                0      -EA SilentlyContinue },
            { Set-MpPreference -EnableControlledFolderAccess Disabled -EA SilentlyContinue },
            { Set-MpPreference -EnableNetworkProtection      Disabled -EA SilentlyContinue },
            { Set-MpPreference -CloudBlockLevel              0      -EA SilentlyContinue },
            { Set-MpPreference -CloudExtendedTimeout         0      -EA SilentlyContinue },
            { Set-MpPreference -DisableScanOnRealtimeEnable  $true  -EA SilentlyContinue }
        )) {
            try { & $mpCall; $mpOk++ } catch { $mpFail++ }
        }
        Write-StepLog "Set-MpPreference (live disable)" "OK" "($mpOk preferences pushed, $mpFail skipped/unsupported on this build)"
    } catch {
        Write-StepLog "Set-MpPreference (live disable)" "INFO" "(cmdlet failed — normal if Defender service stopped: $_)"
    }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] SmartScreen executable ===" -ForegroundColor Cyan
    try {
        $ssExe  = "C:\Windows\System32\smartscreen.exe"
        $ssExee = "C:\Windows\System32\smartscreen.exee"
        if (Test-Path $ssExee) {
            Write-StepLog "smartscreen.exe → .exee" "SKIP" "(already renamed)"
        } elseif (Test-Path $ssExe) {
            Get-Process -Name "smartscreen" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            $ok = Invoke-AsTrustedInstaller {
                & takeown.exe /f "C:\Windows\System32\smartscreen.exe" 2>&1 | Out-Null
                & icacls.exe "C:\Windows\System32\smartscreen.exe" /grant administrators:F 2>&1 | Out-Null
            }
            try {
                Rename-Item -Path $ssExe -NewName "smartscreen.exee" -Force -ErrorAction Stop
                Write-StepLog "smartscreen.exe → .exee" "OK" "(renamed)"
            } catch {
                if ($_.Exception.Message -like "*Access*denied*" -or $_.Exception.Message -like "*Access is denied*") {
                    Write-StepLog "smartscreen.exe → .exee" "ACCESS_DENIED" "($_)"
                } else {
                    Write-StepLog "smartscreen.exe → .exee" "FAIL" "($_)"
                }
                Write-Host "      TIP: Boot to Safe Mode, then: takeown /f `"$ssExe`" && icacls `"$ssExe`" /grant administrators:F" -ForegroundColor DarkYellow
            }
        } else {
            Write-StepLog "smartscreen.exe" "SKIP" "(file not found)"
        }
    } catch { Write-Host "  [ERR] SmartScreen step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Disable Services (set Start=4 via TrustedInstaller) ===" -ForegroundColor Cyan
    Write-Host "  Services protected by Tamper Protection require TI context." -ForegroundColor Gray
    try {
        $disableServices = $script:DS_TouchedServices

        Write-Host "  Stopping services..." -ForegroundColor Gray
        foreach ($svc in @('SecurityHealthService','Sense','wscsvc','SgrmBroker','SgrmAgent','webthreatdefsvc','webthreatdefusersvc','WinDefend','WdNisSvc','MDCoreSvc','MDDlpSvc','MpsSvc')) {
            try { & sc.exe stop $svc 2>&1 | Out-Null } catch { }
        }
        Get-Service -Name "webthreatdefusersvc_*" -ErrorAction SilentlyContinue |
            ForEach-Object { try { & sc.exe stop $_.Name 2>&1 | Out-Null } catch {} }
        Start-Sleep -Milliseconds 500

        Write-Host "  Unlocking TamperProtectionSource → 0 (local) before disabling TP..." -ForegroundColor Gray
        Set-RegValueTI -KeyPath "SOFTWARE\Microsoft\Windows Defender\Features" `
            -ValueName "TamperProtectionSource" -ValueData 0 `
            -Label "TamperProtectionSource → 0 (local)"

        Write-Host "  Setting TamperProtection=4 (disabled) via TrustedInstaller..." -ForegroundColor Gray
        $null = Set-TamperProtection -Value 4

        if (Test-TamperProtectionEnabled) {
            if ($script:InSafeMode) {
                Write-Host "  [Safe Mode] Tamper Protection may still read as enabled in registry, but" -ForegroundColor Cyan
                Write-Host "  WdFilter.sys is not loaded — all writes will succeed regardless." -ForegroundColor Green
            } else {
                Write-Host ""
                Write-Host "  ┌─────────────────────────────────────────────────────────────────────┐" -ForegroundColor Red
                Write-Host "  │  WARNING: Tamper Protection is still ENABLED after our attempt.     │" -ForegroundColor Red
                Write-Host "  │  Service registry writes will be BLOCKED (error 5 = Access Denied). │" -ForegroundColor Red
                Write-Host "  │  Go to: Windows Security > Virus & threat protection settings >     │" -ForegroundColor Red
                Write-Host "  │         Tamper Protection  → toggle OFF, then re-run this script.   │" -ForegroundColor Red
                Write-Host "  │  TamperProtection values:  0/4 = OFF  |  1/5 = ON                  │" -ForegroundColor Yellow
                Write-Host "  └─────────────────────────────────────────────────────────────────────┘" -ForegroundColor Red
                Write-Host ""
            }
        }

        foreach ($svc in $disableServices) {
            try { $null = Set-ServiceStartTI -ServiceName $svc.N -StartValue 4 -Label "Svc: $($svc.N) ($($svc.Label))" }
            catch { Write-StepLog "Svc: $($svc.N) ($($svc.Label))" "FAIL" "(exception: $_)" }
        }

        Write-Host ""
        Write-Host "  [CC1] Writing ControlSet001 Start=4 for boot-start Defender drivers..." -ForegroundColor DarkYellow
        foreach ($cc1Svc in @(
            @{N="WdBoot";   Start=4},
            @{N="WdFilter"; Start=4},
            @{N="WdNisDrv"; Start=4},
            @{N="WdDevFlt"; Start=4}
        )) {
            $cc1Key  = "SYSTEM\ControlSet001\Services\$($cc1Svc.N)"
            $cc1Path = "HKLM:\$cc1Key"
            if (Test-Path $cc1Path) {
                try { $null = Set-RegValueTI -KeyPath $cc1Key -ValueName "Start" -ValueData $cc1Svc.Start -Label "CC1: $($cc1Svc.N) Start=4" }
                catch { Write-StepLog "CC1: $($cc1Svc.N) Start=4" "FAIL" "(exception: $_)" }
            } else {
                Write-StepLog "CC1: $($cc1Svc.N)" "SKIP" "(ControlSet001 key absent on this system)"
            }
        }
    } catch { Write-Host "  [ERR] Services step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Clear Service FailureActions (24H2 auto-restart prevention) ===" -ForegroundColor Cyan
    try {
        foreach ($svcFA in @('WinDefend','WdFilter','MDCoreSvc','WdNisSvc','MDDlpSvc')) {
            $keyPath = "SYSTEM\CurrentControlSet\Services\$svcFA"
            Invoke-AsTrustedInstaller {
                $hKey = [IntPtr]::Zero
                $ret = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $keyPath,
                    [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                    [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
                if ($ret -eq 0 -and $hKey -ne [IntPtr]::Zero) {
                    [DS.TIHelper]::RegDeleteNamed($hKey, "FailureActions")                  | Out-Null
                    [DS.TIHelper]::RegDeleteNamed($hKey, "FailureCommand")                  | Out-Null
                    [DS.TIHelper]::RegDeleteNamed($hKey, "FailureActionsOnNonCrashFailures") | Out-Null
                    [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
                    Write-StepLog "FailureActions\$svcFA" "OK" "(FailureActions/Command/OnNonCrash cleared)"
                } else {
                    Write-StepLog "FailureActions\$svcFA" "SKIP" "(key absent or access error: $ret)"
                }
            }
        }
    } catch { Write-Host "  [ERR] FailureActions step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Disable WMI AutoLogger Sessions ===" -ForegroundColor Cyan
    try {
        foreach ($loggerName in @("DefenderApiLogger","DefenderAuditLogger","DefenderRtpLogger")) {
            try {
                $logPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$loggerName"
                $logKeyTI = "SYSTEM\CurrentControlSet\Control\WMI\Autologger\$loggerName"
                if (Test-Path $logPath) {
                    Set-RegValueTI `
                        -KeyPath   $logKeyTI `
                        -ValueName "Start" -ValueData 0 `
                        -Label     "AutoLogger\$loggerName  Start=0"

                    $guidSubKeys = Get-ChildItem -Path $logPath -ErrorAction SilentlyContinue |
                                   Where-Object { $_.PSChildName -match '^\{[0-9a-fA-F\-]{36}\}$' }
                    if ($guidSubKeys) {
                        foreach ($guidKey in $guidSubKeys) {
                            $guidName = $guidKey.PSChildName
                            $guidTIPath = "$logKeyTI\$guidName"
                            try {
                                Set-RegValueTI `
                                    -KeyPath   $guidTIPath `
                                    -ValueName "Enabled" -ValueData 0 `
                                    -Label     "AutoLogger\$loggerName\$guidName  Enabled=0"
                            } catch {
                                Write-StepLog "AutoLogger\$loggerName\$guidName  Enabled=0" "FAIL" "(exception: $_)"
                            }
                        }
                    } else {
                        Write-StepLog "AutoLogger\$loggerName  GUID sub-keys" "INFO" "(no GUID sub-keys found)"
                    }
                } else {
                    Write-StepLog "AutoLogger\$loggerName" "SKIP" "(key not found)"
                }
            } catch { Write-StepLog "AutoLogger\$loggerName" "FAIL" "(exception: $_)" }
        }
    } catch { Write-Host "  [ERR] AutoLogger step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Disable Scheduled Tasks ===" -ForegroundColor Cyan
    try {
        $script:ScheduleSvcStartedForDisable = $false
        if ($script:InSafeMode) {
            $script:ScheduleSvcStartedForDisable = Start-ScheduleServiceIfNeeded
        }

        $defenderTasks = $script:DS_TouchedTasks
        foreach ($task in $defenderTasks) {
            $shortName = ($task -split '\\')[-1]
            try {
                $queryOut = $null
                $prevEAP = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                $queryOut = & schtasks.exe /Query /TN "$task" 2>&1
                $queryExitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevEAP

                if ($queryExitCode -ne 0) {
                    if ($script:InSafeMode) {
                        $taskFilePath = Join-Path "$env:windir\System32\Tasks" $task
                        if (Test-Path $taskFilePath) {
                            try {
                                $taskXmlDoc = New-Object System.Xml.XmlDocument
                                $taskXmlDoc.PreserveWhitespace = $true
                                $taskXmlDoc.Load($taskFilePath)
                                $nsUri = $taskXmlDoc.DocumentElement.NamespaceURI
                                $nsMgr = New-Object System.Xml.XmlNamespaceManager($taskXmlDoc.NameTable)
                                if ($nsUri) { $nsMgr.AddNamespace("t", $nsUri) }
                                $enabledNode = if ($nsUri) { $taskXmlDoc.SelectSingleNode("//t:Settings/t:Enabled", $nsMgr) } else { $taskXmlDoc.SelectSingleNode("//Settings/Enabled") }
                                if ($null -ne $enabledNode) {
                                    $enabledNode.InnerText = "false"
                                } else {
                                    $settingsNode = if ($nsUri) { $taskXmlDoc.SelectSingleNode("//t:Settings", $nsMgr) } else { $taskXmlDoc.SelectSingleNode("//Settings") }
                                    if ($null -ne $settingsNode) {
                                        $newEnabledNode = $taskXmlDoc.CreateElement("Enabled", $nsUri)
                                        $newEnabledNode.InnerText = "false"
                                        $settingsNode.AppendChild($newEnabledNode) | Out-Null
                                    }
                                }
                                $taskXmlDoc.Save($taskFilePath)
                                Write-StepLog "Task: $shortName" "OK" "(disabled via XML — safe mode fallback; Schedule service unavailable)"
                            } catch {
                                Write-StepLog "Task: $shortName" "FAIL" "(safe mode XML edit failed: $_)"
                            }
                        } else {
                            Write-StepLog "Task: $shortName" "SKIP" "(task not found on this system)"
                        }
                    } else {
                        Write-StepLog "Task: $shortName" "SKIP" "(task not found on this system)"
                    }
                    continue
                }

                $prevEAP2 = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                $out = & schtasks.exe /Change /TN "$task" /Disable 2>&1
                $changeExitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevEAP2

                if ($changeExitCode -eq 0) {
                    Write-StepLog "Task: $shortName" "OK" "(disabled)"
                } else {
                    $errMsg = ($out | Out-String).Trim()
                    Write-StepLog "Task: $shortName" "FAIL" "($errMsg)"
                }
            } catch {
                Write-StepLog "Task: $shortName" "FAIL" "($_)"
            }
        }

        if ($script:ScheduleSvcStartedForDisable) {
            try {
                Write-Host "  [Safe Mode] Stopping Task Scheduler service (was started for task management)..." -ForegroundColor Cyan
                Stop-Service "Schedule" -Force -ErrorAction SilentlyContinue
                $script:ScheduleSvcStartedForDisable = $false
            } catch {}
        }
    } catch { Write-Host "  [ERR] Scheduled Tasks step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Disable Startup Entries ===" -ForegroundColor Cyan
    try {
        Write-Host "  Stopping SecurityHealthService (TI) + killing SecurityHealthHost/Systray..." -ForegroundColor Gray
        $null = Invoke-AsTrustedInstaller {
            & sc.exe stop SecurityHealthService 2>&1 | Out-Null
            & sc.exe stop wscsvc                2>&1 | Out-Null
        }
        Start-Sleep -Milliseconds 600
        foreach ($procName in @('SecurityHealthHost','SecurityHealthSystray','SecurityHealthService')) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 400

        $approvedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        $disabledMarker = [byte[]]@(0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
        foreach ($valName in @("SecurityHealth","Windows Defender")) {
            try {
                if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
                Set-ItemProperty -Path $approvedPath -Name $valName -Value $disabledMarker -ErrorAction Stop
                Write-StepLog "StartupApproved\$valName" "OK" "(disabled marker set)"
            } catch {
                Write-StepLog "StartupApproved\$valName" "FAIL" "($_)"
            }
        }

        $hklmRun  = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        $checkPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        foreach ($valName in @("WindowsDefender","SecurityHealth")) {
            try {
                $existing = Get-RegValue $checkPath $valName
                if ($null -eq $existing) {
                    Write-StepLog "HKLM\Run\$valName" "SKIP" "(not present)"
                    continue
                }
                $null = Invoke-AsTrustedInstaller {
                    $hKey = [IntPtr]::Zero
                    $ret = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $hklmRun,
                        [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                        [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKey)
                    if ($ret -eq 0 -and $hKey -ne [IntPtr]::Zero) {
                        [DS.TIHelper]::RegDeleteNamed($hKey, $valName) | Out-Null
                        [DS.TIHelper]::RegCloseKey($hKey) | Out-Null
                    }
                }
                Start-Sleep -Milliseconds 350
                $still = Get-RegValue $checkPath $valName
                if ($null -eq $still) {
                    Write-StepLog "HKLM\Run\$valName" "OK" "(deleted)"
                } else {
                    Write-StepLog "HKLM\Run\$valName" "OK" "(present but StartupApproved disabled marker prevents launch — systray will not run at logon)"
                }
            } catch { Write-StepLog "HKLM\Run\$valName" "FAIL" "(exception: $_)" }
        }

        foreach ($valName in @("Windows Defender","SecurityHealth")) {
            try {
                $existing = Get-RegValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" $valName
                if ($null -ne $existing) {
                    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $valName -ErrorAction Stop
                    Write-StepLog "HKCU\Run\$valName" "OK" "(deleted)"
                } else {
                    Write-StepLog "HKCU\Run\$valName" "SKIP" "(not present)"
                }
            } catch {
                Write-StepLog "HKCU\Run\$valName" "FAIL" "($_)"
            }
        }
    } catch { Write-Host "  [ERR] Startup Entries step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Post-Action Verification (Exhaustive) ===" -ForegroundColor Cyan
    Invoke-PostActionVerification -Mode "Disable"
}

function Invoke-EnableDefender {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║       ENABLING WINDOWS DEFENDER      ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host " This restores the script-managed baseline for items this script changes." -ForegroundColor Cyan
    Write-Host ""

    $stepTotal = 13
    $step = 0

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore Mitigation / Exploit Protection ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableMitigation "Mitigation (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore Antivirus / Real-Time Protection ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableAntivirusProtection  "Antivirus Protection (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_EnableDefenderPolicies     "Defender Policies (restore all sub-keys)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    try {
        $wdPolPath   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
        $wdPolValue  = "DisableRealtimeMonitoring"
        $wdPolSubKey = "SOFTWARE\Policies\Microsoft\Windows Defender"

        $stillPresent = $null -ne (Get-RegValue $wdPolPath $wdPolValue)
        if ($stillPresent) {
            Write-Host "  [!] $wdPolValue still present in WD Policy key after reg import -- running explicit TI deletion..." -ForegroundColor Yellow

            $null = Invoke-AsTrustedInstaller {
                $hk = [IntPtr]::Zero
                $r = [DS.TIHelper]::RegOpenKeyExU(
                    [DS.TIHelper]::HKLM,
                    $wdPolSubKey,
                    [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                    [DS.TIHelper]::KEY_ALL_ACCESS,
                    [ref]$hk)
                if ($r -eq 0 -and $hk -ne [IntPtr]::Zero) {
                    [DS.TIHelper]::RegDeleteNamed($hk, $wdPolValue) | Out-Null
                    [DS.TIHelper]::RegCloseKey($hk) | Out-Null
                }
            }

            $stillPresent2 = $null -ne (Get-RegValue $wdPolPath $wdPolValue)
            if (-not $stillPresent2) {
                Write-StepLog "WD Policy $wdPolValue explicit TI delete" "OK" "(value deleted via TI P/Invoke)"
            } else {
                $null = Invoke-AsTrustedInstaller {
                    $hkOwn = [IntPtr]::Zero
                    $secAcc = [DS.TIHelper]::WRITE_DAC -bor [DS.TIHelper]::WRITE_OWNER -bor [DS.TIHelper]::READ_CONTROL
                    $r2 = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $wdPolSubKey, 0, $secAcc, [ref]$hkOwn)
                    if ($r2 -eq 0 -and $hkOwn -ne [IntPtr]::Zero) {
                        $sdStr2 = "D:(A;OICI;KA;;;S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464)(A;OICI;KA;;;SY)(A;OICI;KA;;;BA)"
                        $sdPtr2 = [IntPtr]::Zero; $sdSz2 = 0
                        if ([DS.TIHelper]::ConvertStringSecurityDescriptorToSecurityDescriptor($sdStr2, [DS.TIHelper]::SDDL_REVISION_1, [ref]$sdPtr2, [ref]$sdSz2)) {
                            $sdB2 = New-Object byte[] $sdSz2
                            [System.Runtime.InteropServices.Marshal]::Copy($sdPtr2, $sdB2, 0, $sdSz2)
                            [DS.TIHelper]::LocalFree($sdPtr2) | Out-Null
                            [DS.TIHelper]::RegSetKeySecurity($hkOwn, ([DS.TIHelper]::DACL_SECURITY_INFO -bor [DS.TIHelper]::OWNER_SECURITY_INFO), $sdB2) | Out-Null
                        }
                        [DS.TIHelper]::RegCloseKey($hkOwn) | Out-Null
                    }
                    $hk2 = [IntPtr]::Zero
                    $r3 = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $wdPolSubKey,
                              [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE, [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hk2)
                    if ($r3 -eq 0 -and $hk2 -ne [IntPtr]::Zero) {
                        [DS.TIHelper]::RegDeleteNamed($hk2, $wdPolValue) | Out-Null
                        [DS.TIHelper]::RegCloseKey($hk2) | Out-Null
                    }
                }

                $stillPresent3 = $null -ne (Get-RegValue $wdPolPath $wdPolValue)
                if (-not $stillPresent3) {
                    Write-StepLog "WD Policy $wdPolValue explicit TI delete (ownership path)" "OK" "(value deleted after DACL reset)"
                } else {
                    & reg.exe DELETE "HKLM\$wdPolSubKey" /v $wdPolValue /f 2>&1 | Out-Null
                    $stillPresent4 = $null -ne (Get-RegValue $wdPolPath $wdPolValue)
                    if (-not $stillPresent4) {
                        Write-StepLog "WD Policy $wdPolValue explicit TI delete (reg.exe fallback)" "OK" "(deleted via reg.exe)"
                    } else {
                        Write-StepLog "WD Policy $wdPolValue explicit TI delete" "FAIL" "(value still present after all 3 attempts -- Tamper Protection is likely active; disable it first or run in Safe Mode)"
                    }
                }
            }
        } else {
            Write-StepLog "WD Policy $wdPolValue explicit TI delete" "SKIP" "(already absent after reg import -- no fallback needed)"
        }
    } catch { Write-Host "  [ERR] WD Policy DisableRealtimeMonitoring fallback error (continuing): $_" -ForegroundColor Red }

    try { Import-RegFileWithStepLog $reg_EnableDefenderNotifications "Notifications (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    try {
        $polKeysToKill = @(
            "SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Spynet",
            "SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine",
            "SOFTWARE\Policies\Microsoft\Windows Defender\NIS\Consumers\IPS",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Scan",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Signature Updates",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions",
            "SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Reporting",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Threats",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Threats\ThreatSeverityDefaultAction",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection",
            "SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR"
        )
        foreach ($subKey in $polKeysToKill) {
            $checkPath = "HKLM:\$subKey"
            if (-not (Test-Path $checkPath)) {
                Write-StepLog "Delete key: $($subKey.Split('\')[-1])" "SKIP" "(already absent)"
                continue
            }
            $gone = Remove-RegistryKeyHard -HklmSubKey $subKey
            if ($gone) {
                Write-StepLog "Delete key: $($subKey.Split('\')[-1])" "OK" "(deleted)"
            } else {
                Write-StepLog "Delete key: $($subKey.Split('\')[-1])" "FAIL" "(key still present after all methods)"
            }
        }
    } catch { Write-Host "  [ERR] Policy-key fallback deletion error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore SmartScreen ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableSmartScreen                 "SmartScreen (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_EnableWindowsSettingsPageVisibility "Settings Page Visibility (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }
    try { Import-RegFileWithStepLog $reg_Enable_SecurityComp               "Security Center Component (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore WTDS / Web Threat Defense ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableWTDS "Web Threat Defense / SmartScreen App Control (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore Windows Firewall ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableFirewall "Windows Firewall (restore all profiles)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Registry: Restore Defender Direct Config Keys ===" -ForegroundColor Cyan
    try { Import-RegFileWithStepLog $reg_EnableDefenderDirect "Defender Direct (non-policy) keys (restore)" }
    catch { Write-Host "  [ERR] Step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Set-MpPreference (live-state restore — no reboot needed) ===" -ForegroundColor Cyan
    try {
        $mpOk = 0; $mpFail = 0
        foreach ($mpCall in @(
            { Set-MpPreference -DisableRealtimeMonitoring    $false -EA SilentlyContinue },
            { Set-MpPreference -DisableBehaviorMonitoring    $false -EA SilentlyContinue },
            { Set-MpPreference -DisableIOAVProtection        $false -EA SilentlyContinue },
            { Set-MpPreference -DisableOnAccessProtection    $false -EA SilentlyContinue },
            { Set-MpPreference -DisableIntrusionPreventionSystem $false -EA SilentlyContinue },
            { Set-MpPreference -DisableScriptScanning        $false -EA SilentlyContinue },
            { Set-MpPreference -DisableArchiveScanning       $false -EA SilentlyContinue },
            { Set-MpPreference -DisableEmailScanning         $false -EA SilentlyContinue },
            { Set-MpPreference -DisableScanningNetworkFiles  $false -EA SilentlyContinue },
            { Set-MpPreference -DisableRemovableDriveScanning $false -EA SilentlyContinue },
            { Set-MpPreference -DisableBlockAtFirstSeen      $false -EA SilentlyContinue },
            { Set-MpPreference -MAPSReporting                2      -EA SilentlyContinue },
            { Set-MpPreference -SubmitSamplesConsent         1      -EA SilentlyContinue },
            { Set-MpPreference -PUAProtection                1      -EA SilentlyContinue },
            { Set-MpPreference -EnableControlledFolderAccess Enabled -EA SilentlyContinue },
            { Set-MpPreference -EnableNetworkProtection      Enabled -EA SilentlyContinue },
            { Set-MpPreference -CloudBlockLevel              1      -EA SilentlyContinue },
            { Set-MpPreference -CloudExtendedTimeout         50     -EA SilentlyContinue },
            { Set-MpPreference -DisableScanOnRealtimeEnable  $false -EA SilentlyContinue }
        )) {
            try { & $mpCall; $mpOk++ } catch { $mpFail++ }
        }
        Write-StepLog "Set-MpPreference (live enable)" "OK" "($mpOk preferences restored, $mpFail skipped/unsupported on this build)"
    } catch {
        Write-StepLog "Set-MpPreference (live enable)" "INFO" "(cmdlet failed — may need service start/reboot: $_)"
    }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] SmartScreen executable ===" -ForegroundColor Cyan
    try {
        $ssExe  = "C:\Windows\System32\smartscreen.exe"
        $ssExee = "C:\Windows\System32\smartscreen.exee"
        if (Test-Path $ssExe) {
            Write-StepLog "smartscreen.exe" "SKIP" "(already present — no rename needed)"
        } elseif (Test-Path $ssExee) {
            $ok = Invoke-AsTrustedInstaller {
                & takeown.exe /f "C:\Windows\System32\smartscreen.exee" 2>&1 | Out-Null
                & icacls.exe "C:\Windows\System32\smartscreen.exee" /grant administrators:F 2>&1 | Out-Null
            }
            try {
                Rename-Item -Path $ssExee -NewName "smartscreen.exe" -Force -ErrorAction Stop
                Write-StepLog "smartscreen.exee → .exe" "OK" "(restored)"
            } catch {
                if ($_.Exception.Message -like "*Access*denied*" -or $_.Exception.Message -like "*Access is denied*") {
                    Write-StepLog "smartscreen.exee → .exe" "ACCESS_DENIED" "($_)"
                } else {
                    Write-StepLog "smartscreen.exee → .exe" "FAIL" "($_)"
                }
                Write-Host "      TIP: Boot to Safe Mode, then: takeown /f `"$ssExee`" && icacls `"$ssExee`" /grant administrators:F" -ForegroundColor DarkYellow
            }
        } else {
            Write-StepLog "smartscreen.exe" "SKIP" "(neither .exe nor .exee found)"
        }
    } catch { Write-Host "  [ERR] SmartScreen step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Restore Services to default Start values (via TrustedInstaller) ===" -ForegroundColor Cyan
    try {
        $restoreServices = $script:DS_TouchedServices

        foreach ($svc in $restoreServices) {
            try { $null = Set-ServiceStartTI -ServiceName $svc.N -StartValue $svc.Def -Label "Svc: $($svc.N) ($($svc.Label)) → Start=$($svc.Def)" }
            catch { Write-StepLog "Svc: $($svc.N) ($($svc.Label)) → Start=$($svc.Def)" "FAIL" "(exception: $_)" }
        }

        Write-Host ""
        Write-Host "  [CC1] Restoring ControlSet001 Start defaults for boot-start Defender drivers..." -ForegroundColor DarkYellow
        foreach ($cc1Svc in @(
            @{N="WdBoot";   Start=0},
            @{N="WdFilter"; Start=0},
            @{N="WdNisDrv"; Start=3},
            @{N="WdDevFlt"; Start=0}
        )) {
            $cc1Key  = "SYSTEM\ControlSet001\Services\$($cc1Svc.N)"
            $cc1Path = "HKLM:\$cc1Key"
            if (Test-Path $cc1Path) {
                try { $null = Set-RegValueTI -KeyPath $cc1Key -ValueName "Start" -ValueData $cc1Svc.Start -Label "CC1: $($cc1Svc.N) Start=$($cc1Svc.Start) (restore)" }
                catch { Write-StepLog "CC1: $($cc1Svc.N) Start=$($cc1Svc.Start) (restore)" "FAIL" "(exception: $_)" }
            } else {
                Write-StepLog "CC1: $($cc1Svc.N)" "SKIP" "(ControlSet001 key absent on this system)"
            }
        }

        Write-Host ""
        Write-Host "  Setting TamperProtection=5 (enabled) will be done AFTER services start..." -ForegroundColor Gray

    } catch { Write-Host "  [ERR] Services step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Restore WMI AutoLogger Sessions ===" -ForegroundColor Cyan
    try {
        foreach ($loggerName in @("DefenderApiLogger","DefenderAuditLogger","DefenderRtpLogger")) {
            try {
                $logPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$loggerName"
                $logKeyTI = "SYSTEM\CurrentControlSet\Control\WMI\Autologger\$loggerName"
                if (Test-Path $logPath) {
                    Set-RegValueTI `
                        -KeyPath   $logKeyTI `
                        -ValueName "Start" -ValueData 1 `
                        -Label     "AutoLogger\$loggerName → Start=1 (enabled)"

                    $guidSubKeys = Get-ChildItem -Path $logPath -ErrorAction SilentlyContinue |
                                   Where-Object { $_.PSChildName -match '^\{[0-9a-fA-F\-]{36}\}$' }
                    if ($guidSubKeys) {
                        foreach ($guidKey in $guidSubKeys) {
                            $guidName   = $guidKey.PSChildName
                            $guidTIPath = "$logKeyTI\$guidName"
                            try {
                                Set-RegValueTI `
                                    -KeyPath   $guidTIPath `
                                    -ValueName "Enabled" -ValueData 1 `
                                    -Label     "AutoLogger\$loggerName\$guidName  Enabled=1 (restored)"
                            } catch {
                                Write-StepLog "AutoLogger\$loggerName\$guidName  Enabled=1" "FAIL" "(exception: $_)"
                            }
                        }
                    }
                } else {
                    Write-StepLog "AutoLogger\$loggerName" "SKIP" "(key not found — may be absent)"
                }
            } catch { Write-StepLog "AutoLogger\$loggerName" "FAIL" "(exception: $_)" }
        }
    } catch { Write-Host "  [ERR] AutoLogger step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Re-enable Scheduled Tasks ===" -ForegroundColor Cyan
    try {
        $script:ScheduleSvcStartedForEnable = $false
        if ($script:InSafeMode) {
            $script:ScheduleSvcStartedForEnable = Start-ScheduleServiceIfNeeded
        }

        $defenderTasks = $script:DS_TouchedTasks
        foreach ($task in $defenderTasks) {
            $shortName = ($task -split '\\')[-1]
            try {
                $queryOut = $null
                $prevEAP = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                $queryOut = & schtasks.exe /Query /TN "$task" 2>&1
                $queryExitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevEAP

                if ($queryExitCode -ne 0) {
                    if ($script:InSafeMode) {
                        $taskFilePath = Join-Path "$env:windir\System32\Tasks" $task
                        if (Test-Path $taskFilePath) {
                            try {
                                $taskXmlDoc = New-Object System.Xml.XmlDocument
                                $taskXmlDoc.PreserveWhitespace = $true
                                $taskXmlDoc.Load($taskFilePath)
                                $nsUri = $taskXmlDoc.DocumentElement.NamespaceURI
                                $nsMgr = New-Object System.Xml.XmlNamespaceManager($taskXmlDoc.NameTable)
                                if ($nsUri) { $nsMgr.AddNamespace("t", $nsUri) }
                                $enabledNode = if ($nsUri) { $taskXmlDoc.SelectSingleNode("//t:Settings/t:Enabled", $nsMgr) } else { $taskXmlDoc.SelectSingleNode("//Settings/Enabled") }
                                if ($null -ne $enabledNode) {
                                    $enabledNode.InnerText = "true"
                                } else {
                                    $settingsNode = if ($nsUri) { $taskXmlDoc.SelectSingleNode("//t:Settings", $nsMgr) } else { $taskXmlDoc.SelectSingleNode("//Settings") }
                                    if ($null -ne $settingsNode) {
                                        $newEnabledNode = $taskXmlDoc.CreateElement("Enabled", $nsUri)
                                        $newEnabledNode.InnerText = "true"
                                        $settingsNode.AppendChild($newEnabledNode) | Out-Null
                                    }
                                }
                                $taskXmlDoc.Save($taskFilePath)
                                Write-StepLog "Task: $shortName" "OK" "(enabled via XML — safe mode fallback; Schedule service unavailable)"
                            } catch {
                                Write-StepLog "Task: $shortName" "FAIL" "(safe mode XML edit failed: $_)"
                            }
                        } else {
                            Write-StepLog "Task: $shortName" "SKIP" "(task not found — may be absent)"
                        }
                    } else {
                        Write-StepLog "Task: $shortName" "SKIP" "(task not found — may be absent)"
                    }
                    continue
                }

                $prevEAP2 = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                $out = & schtasks.exe /Change /TN "$task" /Enable 2>&1
                $changeExitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevEAP2

                if ($changeExitCode -eq 0) {
                    Write-StepLog "Task: $shortName" "OK" "(enabled)"
                } else {
                    $errMsg = ($out | Out-String).Trim()
                    Write-StepLog "Task: $shortName" "FAIL" "($errMsg)"
                }
            } catch {
                Write-StepLog "Task: $shortName" "FAIL" "($_)"
            }
        }

        if ($script:ScheduleSvcStartedForEnable) {
            try {
                Write-Host "  [Safe Mode] Stopping Task Scheduler service (was started for task management)..." -ForegroundColor Cyan
                Stop-Service "Schedule" -Force -ErrorAction SilentlyContinue
                $script:ScheduleSvcStartedForEnable = $false
            } catch {}
        }
    } catch { Write-Host "  [ERR] Scheduled Tasks step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Restore Startup Entries & Windows Security Health ===" -ForegroundColor Cyan
    try {
        $approvedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        foreach ($valName in @("SecurityHealth","Windows Defender")) {
            try {
                $existing = Get-RegValue $approvedPath $valName
                if ($null -ne $existing) {
                    $enabled = [byte[]]@(0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                    Set-ItemProperty -Path $approvedPath -Name $valName -Value $enabled -ErrorAction Stop
                    Write-StepLog "StartupApproved\$valName" "OK" "(enabled marker set)"
                } else {
                    Write-StepLog "StartupApproved\$valName" "SKIP" "(not present)"
                }
            } catch {
                Write-StepLog "StartupApproved\$valName" "FAIL" "($_)"
            }
        }

        try {
            $hklmRunPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            $secHealthExe = "%ProgramFiles%\Windows Defender\MSASCuiL.exe"
            $secHealthExeAlt = "%windir%\system32\SecurityHealthSystray.exe"
            $existingVal = Get-RegValue $hklmRunPath "SecurityHealth"
            if ($null -eq $existingVal) {
                $actualPath = if (Test-Path "$env:ProgramFiles\Windows Defender\MSASCuiL.exe") { $secHealthExe }
                              elseif (Test-Path "$env:windir\system32\SecurityHealthSystray.exe") { $secHealthExeAlt }
                              else { $secHealthExeAlt }
                try {
                    Set-RegStringTI -KeyPath "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
                        -ValueName "SecurityHealth" -ValueData $actualPath `
                        -Label "HKLM\Run\SecurityHealth"
                } catch {
                    Write-StepLog "HKLM\Run\SecurityHealth" "INFO" "(will be recreated after reboot if Defender starts)"
                }
            } else {
                Write-StepLog "HKLM\Run\SecurityHealth" "SKIP" "(already present)"
            }
        } catch { Write-StepLog "HKLM\Run\SecurityHealth" "FAIL" "(exception: $_)" }

        try {
            if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health")) {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health" -Force | Out-Null
            }
            if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\Platform")) {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\Platform" -Force | Out-Null
            }
            if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\State")) {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\State" -Force | Out-Null
            }
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\Platform" -Name "Registered" -PropertyType DWord -Value 1 -Force | Out-Null
            Write-StepLog "WinSecHealth\Platform Registered=1" "OK" "(restored)"

            if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\State" -Name "Disabled" -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Security Health\State" -Name "Disabled" -ErrorAction SilentlyContinue
            }
            Write-StepLog "WinSecHealth\State Disabled" "OK" "(removed if present)"

            if (Test-Path "HKCU:\Software\Microsoft\Windows Security Health") {
                Remove-Item -Path "HKCU:\Software\Microsoft\Windows Security Health" -Recurse -Force -ErrorAction SilentlyContinue
                Write-StepLog "HKCU WinSecHealth (key)" "OK" "(removed — Windows will recreate on next health event)"
            } else {
                Write-StepLog "HKCU WinSecHealth (key)" "SKIP" "(already absent)"
            }
        } catch {
            Write-StepLog "Windows Security Health registry repair" "FAIL" "($_)"
        }
    } catch { Write-Host "  [ERR] Startup/SecHealth step error (continuing): $_" -ForegroundColor Red }

    $step++
    Write-Host ""
    Write-Host "=== [$step/$stepTotal] Re-register SecHealthUI & Start Services ===" -ForegroundColor Cyan
    try {
        try {
            $pkgs = @(
                Get-AppxPackage -AllUsers -Name "Microsoft.SecHealthUI" -ErrorAction SilentlyContinue
                Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*SecHealthUI*" }
            ) | Where-Object { $_ } | Select-Object -Unique

            if ($pkgs.Count -eq 0) {
                Write-StepLog "SecHealthUI re-register" "SKIP" "(package not found — may be absent)"
            } else {
                foreach ($p in $pkgs) {
                    $manifest = Join-Path $p.InstallLocation "AppXManifest.xml"
                    if (Test-Path $manifest) {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                Write-StepLog "SecHealthUI re-register" "OK" "(re-registered for all users)"
            }
        } catch {
            Write-StepLog "SecHealthUI re-register" "FAIL" "($_)"
        }

        Write-Host ""
        Write-Host "  Starting Defender services..." -ForegroundColor Gray

        Write-Host "  [*] Loading Defender kernel drivers via fltmc.exe (WdFilter, WdNisDrv)..." -ForegroundColor Gray
        foreach ($drvName in @('WdFilter', 'WdNisDrv')) {
            try {
                $fltListBefore = & fltmc.exe filters 2>&1 | Out-String
                if ($fltListBefore -match "(?m)^\s*$drvName[\s\r]") {
                    Write-StepLog "Kernel driver: $drvName" "SKIP" "(already loaded in Filter Manager)"
                    continue
                }

                $fltOut = & fltmc.exe load $drvName 2>&1
                $fltRet = $LASTEXITCODE
                Start-Sleep -Milliseconds 1500

                $fltListAfter = & fltmc.exe filters 2>&1 | Out-String
                $nowInStack   = ($fltListAfter -match "(?m)^\s*$drvName[\s\r]") -or ($fltRet -eq 0) -or ($fltRet -eq 1056)

                if ($nowInStack) {
                    Write-StepLog "Kernel driver: $drvName" "OK" "(loaded via fltmc.exe — confirmed in Filter Manager)"
                } else {
                    $scOut = & sc.exe start $drvName 2>&1
                    $scRet = $LASTEXITCODE
                    Start-Sleep -Milliseconds 1200
                    $fltListFb = & fltmc.exe filters 2>&1 | Out-String
                    if ($fltListFb -match "(?m)^\s*$drvName[\s\r]" -or $scRet -eq 0 -or $scRet -eq 1056) {
                        Write-StepLog "Kernel driver: $drvName" "OK" "(loaded via sc.exe fallback)"
                    } else {
                        Write-StepLog "Kernel driver: $drvName" "INFO" "(fltmc exit=$fltRet; sc.exe exit=$scRet — driver not in filter stack; WinDefend start may still succeed via MpCmdRun)"
                    }
                }
            } catch { Write-StepLog "Kernel driver: $drvName" "INFO" "(load attempt error: $_)" }
        }
        Start-Sleep -Milliseconds 500

        Write-Host "  [*] Final nuclear registry cleanup before WinDefend start..." -ForegroundColor Gray
        $nuclearCleanup = @(
            @{ K="SOFTWARE\Policies\Microsoft\Windows Defender"; V="DisableAntiSpyware"          },
            @{ K="SOFTWARE\Policies\Microsoft\Windows Defender"; V="DisableAntiVirus"             },
            @{ K="SOFTWARE\Policies\Microsoft\Windows Defender"; V="DisableRoutinelyTakingAction" },
            @{ K="SOFTWARE\Policies\Microsoft\Windows Defender"; V="ServiceKeepAlive"             },
            @{ K="SOFTWARE\Policies\Microsoft\Windows Defender"; V="AllowFastServiceStartup"      },
            @{ K="SOFTWARE\Microsoft\Windows Defender"; V="DisableAntiSpyware"                   },
            @{ K="SOFTWARE\Microsoft\Windows Defender"; V="DisableAntiVirus"                      },
            @{ K="SOFTWARE\Microsoft\Windows Defender"; V="DisableRoutinelyTakingAction"          },
            @{ K="SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; V="DisableRealtimeMonitoring"  },
            @{ K="SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; V="DisableBehaviorMonitoring"  },
            @{ K="SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; V="DisableOnAccessProtection"  },
            @{ K="SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; V="DisableIOAVProtection"      },
            @{ K="SOFTWARE\Microsoft\Windows Defender";                        V="PassiveMode"               },
            @{ K="SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection"; V="ForceDefenderPassiveMode" }
        )
        foreach ($nc in $nuclearCleanup) {
            $psPathNC = "HKLM:\$($nc.K)"
            if (-not (Test-Path $psPathNC)) { continue }
            $vNC = Get-RegValue $psPathNC $nc.V
            if ($null -eq $vNC) { continue }
            $ncKey = $nc.K; $ncVal = $nc.V
            $null = Invoke-AsTrustedInstaller {
                $hKN = [IntPtr]::Zero
                $retN = [DS.TIHelper]::RegOpenKeyExU([DS.TIHelper]::HKLM, $ncKey,
                    [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE, [DS.TIHelper]::KEY_ALL_ACCESS, [ref]$hKN)
                if ($retN -eq 0 -and $hKN -ne [IntPtr]::Zero) {
                    [DS.TIHelper]::RegDeleteNamed($hKN, $ncVal) | Out-Null
                    [DS.TIHelper]::RegCloseKey($hKN) | Out-Null
                }
            }
            $v2NC = Get-RegValue $psPathNC $nc.V
            if ($null -ne $v2NC) {
                & reg.exe DELETE "HKLM\$ncKey" /v $ncVal /f 2>&1 | Out-Null
                $v3NC = Get-RegValue $psPathNC $nc.V
                if ($null -ne $v3NC) {
                    Write-StepLog "NuclearClean: $ncVal" "WARN" "(still present in $ncKey — may prevent WinDefend from fully enabling)"
                } else {
                    Write-StepLog "NuclearClean: $ncVal" "OK" "(removed via reg.exe fallback from $ncKey)"
                }
            } else {
                Write-StepLog "NuclearClean: $ncVal" "OK" "(deleted from $ncKey)"
            }
        }
        $pmFinal = "SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager"
        if (Test-Path "HKLM:\$pmFinal") {
            $pmGone = Remove-RegistryKeyHard -HklmSubKey $pmFinal
            if ($pmGone) {
                Write-StepLog "PolicyManager key (final attempt)" "OK" "(key deleted)"
            } else {
                Write-StepLog "PolicyManager key (final attempt)" "WARN" "(key still present — may affect RTP)"
            }
        } else {
            Write-StepLog "PolicyManager key (final attempt)" "SKIP" "(already absent)"
        }
        Write-Host ""

        $expectedRunningSvcs = @("MDCoreSvc","MpsSvc","WinDefend","SecurityHealthService","wscsvc","SgrmBroker")
        $demandStartSvcs     = @("WdNisSvc","Sense","webthreatdefsvc")
        $allSvcs             = $expectedRunningSvcs + $demandStartSvcs

        foreach ($svc in $allSvcs) {
            try {
                $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
                if (-not $svcObj) {
                    Write-StepLog "Start svc: $svc" "SKIP" "(not installed on this system)"
                    continue
                }
                if ($svcObj.Status -eq 'Running') {
                    Write-StepLog "Start svc: $svc" "OK" "(already running)"
                    continue
                }

                $started = $false
                try {
                    Start-Service -Name $svc -ErrorAction Stop
                    $started = $true
                } catch {
                    try {
                        & sc.exe start $svc 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1056) { $started = $true }
                    } catch { }
                }

                if (-not $started) {
                    if ($svc -in $expectedRunningSvcs) {
                        Write-StepLog "Start svc: $svc" "INFO" "(start request did not succeed immediately)"
                    } else {
                        Write-StepLog "Start svc: $svc" "INFO" "(demand-start; will start when triggered)"
                    }
                    continue
                }

                $maxWaitMs = if ($svc -eq 'WinDefend') { 20000 } elseif ($svc -in @('SecurityHealthService','wscsvc','MDCoreSvc','MpsSvc')) { 12000 } else { 8000 }
                $waited    = 0
                $stepMs    = 300
                $svcObj.Refresh()
                while ($svcObj.Status -ne 'Running' -and $waited -lt $maxWaitMs) {
                    Start-Sleep -Milliseconds $stepMs
                    $waited += $stepMs
                    try { $svcObj.Refresh() } catch { }
                }

                if ($svcObj.Status -eq 'Running') {
                    Write-StepLog "Start svc: $svc" "OK" "(running)"
                    if ($svc -eq 'WinDefend') { Start-Sleep -Milliseconds 2000 }
                } else {
                    if ($svc -in $expectedRunningSvcs) {
                        Write-StepLog "Start svc: $svc" "INFO" "(state=$($svcObj.Status) after ${waited}ms)"
                    } else {
                        Write-StepLog "Start svc: $svc" "INFO" "(demand-start; state=$($svcObj.Status))"
                    }
                }
            } catch {
                Write-StepLog "Start svc: $svc" "INFO" "(start attempt error: $_)"
            }
        }

        Write-StepLog "WinDefend activation" "INFO" "(WinDefend may not respond until next boot — all registry changes are staged and will take full effect after reboot)"

        Write-Host ""
        Write-Host "  Setting TamperProtection=5 (enabled) now that WinDefend has started..." -ForegroundColor Gray
        $null = Set-TamperProtection -Value 5
        Start-Sleep -Milliseconds 1500

        try {
            $mpOk2 = 0; $mpFail2 = 0
            foreach ($mpCall in @(
                { Set-MpPreference -DisableRealtimeMonitoring    $false -EA SilentlyContinue },
                { Set-MpPreference -DisableBehaviorMonitoring    $false -EA SilentlyContinue },
                { Set-MpPreference -DisableIOAVProtection        $false -EA SilentlyContinue },
                { Set-MpPreference -DisableOnAccessProtection    $false -EA SilentlyContinue },
                { Set-MpPreference -DisableIntrusionPreventionSystem $false -EA SilentlyContinue },
                { Set-MpPreference -DisableScriptScanning        $false -EA SilentlyContinue },
                { Set-MpPreference -DisableArchiveScanning       $false -EA SilentlyContinue },
                { Set-MpPreference -DisableEmailScanning         $false -EA SilentlyContinue },
                { Set-MpPreference -DisableScanningNetworkFiles  $false -EA SilentlyContinue },
                { Set-MpPreference -DisableRemovableDriveScanning $false -EA SilentlyContinue }
            )) {
                try { & $mpCall; $mpOk2++ } catch { $mpFail2++ }
            }
            Write-StepLog "Set-MpPreference (re-push live)" "OK" "($mpOk2 preferences re-applied to live engine, $mpFail2 skipped)"
        } catch {
            Write-StepLog "Set-MpPreference (re-push live)" "INFO" "(re-push failed: $_)"
        }
        Start-Sleep -Milliseconds 1500

        try {
            $sysTray = Join-Path $env:windir "System32\SecurityHealthSystray.exe"
            if (Test-Path $sysTray) {
                if (-not (Get-Process -Name "SecurityHealthSystray" -ErrorAction SilentlyContinue)) {
                    Start-Process -FilePath $sysTray -ErrorAction SilentlyContinue
                    Write-StepLog "SecurityHealthSystray launch" "OK" "(launched)"
                } else {
                    Write-StepLog "SecurityHealthSystray launch" "SKIP" "(already running)"
                }
            } else {
                Write-StepLog "SecurityHealthSystray launch" "SKIP" "(executable not found)"
            }
        } catch { Write-StepLog "SecurityHealthSystray launch" "INFO" "(launch attempt error: $_)" }

        try {
            $saPath    = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
            $saEnabled = [byte[]](0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
            foreach ($saName in @("SecurityHealth","Windows Defender")) {
                $existing = Get-RegValue $saPath $saName
                if ($null -ne $existing -and $existing.Length -ge 1 -and ([byte]($existing[0])) -eq 0x02) {
                    Write-StepLog "StartupApproved: $saName" "SKIP" "(already enabled)"
                } else {
                    try {
                        if (-not (Test-Path $saPath)) { New-Item -Path $saPath -Force | Out-Null }
                        Set-ItemProperty -Path $saPath -Name $saName -Value $saEnabled -Type Binary -Force
                        Write-StepLog "StartupApproved: $saName" "OK" "(enabled marker written)"
                    } catch {
                        Write-StepLog "StartupApproved: $saName" "INFO" "(write skipped: $_)"
                    }
                }
            }
        } catch { Write-StepLog "StartupApproved write" "INFO" "(error: $_)" }
    } catch { Write-Host "  [ERR] SecHealthUI/Services step error (continuing): $_" -ForegroundColor Red }

    try {
        $pmCleanPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager"
        if (Test-Path $pmCleanPath) {
            $pmDisableScan = Get-RegValue $pmCleanPath "DisableScanningNetworkFiles"
            if ($null -ne $pmDisableScan) {
                $pmCleanGone = Remove-RegistryKeyHard -HklmSubKey "SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager"
                if ($pmCleanGone) {
                    Write-StepLog "PolicyMgr post-start cleanup" "OK" "(key deleted — DisableScanningNetworkFiles removed)"
                } else {
                    $pmCleanKey = [IntPtr]::Zero
                    $null = Invoke-AsTrustedInstaller {
                        $pmRet = [DS.TIHelper]::RegOpenKeyExU(
                            [DS.TIHelper]::HKLM,
                            "SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager",
                            [DS.TIHelper]::REG_OPTION_BACKUP_RESTORE,
                            [DS.TIHelper]::KEY_ALL_ACCESS,
                            [ref]$pmCleanKey)
                        if ($pmRet -eq 0 -and $pmCleanKey -ne [IntPtr]::Zero) {
                            [DS.TIHelper]::RegDeleteNamed($pmCleanKey, "DisableScanningNetworkFiles") | Out-Null
                            [DS.TIHelper]::RegCloseKey($pmCleanKey) | Out-Null
                        }
                    }
                    $pmAfter = Get-RegValue $pmCleanPath "DisableScanningNetworkFiles"
                    if ($null -eq $pmAfter) {
                        Write-StepLog "PolicyMgr post-start cleanup" "OK" "(DisableScanningNetworkFiles value deleted; key container left empty — harmless)"
                    } else {
                        & reg.exe DELETE "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" /v "DisableScanningNetworkFiles" /f 2>&1 | Out-Null
                        $pmAfter2 = Get-RegValue $pmCleanPath "DisableScanningNetworkFiles"
                        if ($null -eq $pmAfter2) {
                            Write-StepLog "PolicyMgr post-start cleanup" "OK" "(DisableScanningNetworkFiles deleted via reg.exe fallback)"
                        } else {
                            Write-StepLog "PolicyMgr post-start cleanup" "WARN" "(DisableScanningNetworkFiles=$pmAfter2 still present; post-verify will show FAIL)"
                        }
                    }
                }
            } else {
                Write-StepLog "PolicyMgr post-start cleanup" "SKIP" "(key exists but DisableScanningNetworkFiles already absent — WinDefend recreated key empty; harmless)"
            }
        } else {
            Write-StepLog "PolicyMgr post-start cleanup" "SKIP" "(key absent — already fully cleaned)"
        }
    } catch {
        Write-StepLog "PolicyMgr post-start cleanup" "INFO" "(error: $_)"
    }

    Write-Host ""
    Write-Host "  --- Post-Action Verification (Exhaustive) ---" -ForegroundColor Yellow
    Invoke-PostActionVerification -Mode "Enable"
}

function Show-CommunityLinks {
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  xeoka pack — Community Links:" -ForegroundColor Cyan
    $links = @(
        @{ Label = "xeoka pack - Telegram: https://t.me/CMEPT0HOCHbIU"; Url = "https://t.me/CMEPT0HOCHbIU" }
    )
    foreach ($link in $links) {
        $esc = [char]27
        $hyperlink = "${esc}]8;;$($link.Url)${esc}\$($link.Label)${esc}]8;;${esc}\"
        Write-Host "    " -NoNewline
        Write-Host $hyperlink -ForegroundColor Cyan
    }
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host ""
}

Write-Host " [*] Acquiring elevated context..." -ForegroundColor Gray
Initialize-TrustedInstallerToken
Write-Host ""

Show-DefenderStatus
Show-CommunityLinks

Write-Host ""
Write-Host "╔═════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          SELECT ACTION                          ║" -ForegroundColor Cyan
Write-Host "╠═════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  [1] DISABLE  — set policy keys, rename SmartScreen             ║" -ForegroundColor Yellow
Write-Host "║                 (restored to script baseline)                   ║" -ForegroundColor Gray
Write-Host "║  [2] ENABLE   — restore script-managed defaults / services      ║" -ForegroundColor Green
Write-Host "║                 (not a backup of prior custom state)            ║" -ForegroundColor Gray
Write-Host "║  [S] STATUS   — refresh status dashboard                        ║" -ForegroundColor Cyan
Write-Host "║  [Q] QUIT     — exit without changes                            ║" -ForegroundColor Gray
Write-Host "╚═════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$choice = Read-Host "Enter choice [1/2/S/Q]"

switch ($choice.ToUpper()) {

    "1" {
        Invoke-DisableDefender
    }

    "2" {
        Invoke-EnableDefender
    }

    "S" {
        Show-DefenderStatus
    }

    "Q" {
        Write-Host " Exiting — no changes made." -ForegroundColor Gray
    }

    default {
        Write-Host " Invalid choice. Exiting." -ForegroundColor Red
    }
}

Cleanup-TrustedInstallerToken

if ($choice -match "^[12]$") {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " Changes applied. Please reboot for everything to take full effect." -ForegroundColor Yellow
}

Show-CommunityLinks

Write-Host ""
pause
