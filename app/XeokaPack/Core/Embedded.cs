namespace XeokaPack.Core;

/// <summary>Встроенные копии небольших .reg на случай, если в паке их нет.</summary>
public static class Embedded
{
    public static readonly Dictionary<string, string> Reg = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Win32PrioritySeparation-18.reg"] = """
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl]
"Win32PrioritySeparation"=dword:00000018
""",
        ["SerializeTimerExpiration-1.reg"] = """
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\kernel]
"SerializeTimerExpiration"=dword:00000001
""",
        ["FSE.reg"] = """
[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000001
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000002
"GameDVR_FSEBehavior"=dword:00000002
"GameDVR_DSEBehavior"=dword:00000002
""",
        ["FSO.reg"] = """
[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000000
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000000
"GameDVR_FSEBehavior"=dword:00000000
"GameDVR_DSEBehavior"=dword:00000000
""",
        ["DISABLE-MMCSS.reg"] = """
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MMCSS]
"Start"=dword:00000004
""",
        ["XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg"] = """
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
""",
    };
}
