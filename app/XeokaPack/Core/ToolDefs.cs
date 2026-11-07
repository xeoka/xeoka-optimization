namespace XeokaPack.Core;

public enum ToolKind { File, Ps1, Services, Nvidia, System }

public sealed record ToolDef(string TitleRu, string TitleEn, string DescRu, string DescEn, string Prefix, string File, string Glyph, bool Risk, ToolKind Kind = ToolKind.File)
{
    public string Title => Loc.L(TitleRu, TitleEn);
    public string Desc => Loc.L(DescRu, DescEn);
}

public static class ToolDefs
{
    public static readonly List<ToolDef> All = new()
    {
        new("Windows Defender", "Windows Defender", "Переключатель защитника", "Defender on/off switch", "", "RUN-WDS.bat", "WD", true),
        new("Обновления Windows", "Windows Update", "Блокировщик обновлений", "Windows Update blocker", "", "RUN-WUB.bat", "WU", true),
        new("DEVICE-TWEAKER", "DEVICE-TWEAKER", "Аффинити, прерывания, USB", "Affinity, interrupts, USB", "", "DEVICE-TWEAKER*.ps1", "DT", false, ToolKind.Ps1),
        new("BIOS (SCEWIN)", "BIOS (SCEWIN)", "Конфиги BIOS. Читайте инструкцию", "BIOS configs. Read the guide first", "", "SCEWIN-GUI.exe", "BIOS", true),
        new("Тип драйвера сети", "Network driver type", "NDIS или NetAdapterCx", "NDIS or NetAdapterCx", "", "RUN-CHECK-NIC-DRIVER-TYPE.PS1.bat", "NIC", false),
        new("Энергосбережение сети", "Network power saving", "Проверка статуса", "Status check", "", "RUN-CHECK-POWER-MANAGEMENT.bat", "PWR", false),
        new("DDU", "DDU", "Удаление драйверов видеокарты", "Remove graphics drivers", "", "Display Driver Uninstaller.exe", "DDU", false),
        new("NVCleanstall", "NVCleanstall", "Установка драйвера NVIDIA", "Install the NVIDIA driver", "", "NVCleanstall_1.19.0.exe", "NV", false),
        new("Профиль NVIDIA", "NVIDIA profile", "Откроет .nip в Profile Inspector", "Opens the .nip in Profile Inspector", "", "nvidiaProfileInspector.exe", "NPI", false, ToolKind.Nvidia),
        new("CRU", "CRU", "Настройка разрешений и частот", "Resolutions and refresh rates", "", "CRU.exe", "CRU", false),
        new("Autoruns", "Autoruns", "Автозагрузка", "Startup programs", "", "Autoruns.exe", "AR", false),
        new("Службы (PowerRun)", "Services (PowerRun)", "Отключение служб. Осторожно", "Disable services. Be careful", "", "DISABLE-SERVICES.reg", "SVC", true, ToolKind.Services),

        // Системные: встроены в Windows, файлы пака не нужны — работают даже если скачан только exe.
        new("Отключение UAC", "Disable UAC", "Откроет штатный ползунок контроля учётных записей", "Opens the built-in User Account Control slider", "", "UserAccountControlSettings.exe", "UAC", true, ToolKind.System),
        new("Уведомления", "Notifications", "Откроет настройки уведомлений Windows", "Opens Windows notification settings", "", "ms-settings:notifications", "NTF", false, ToolKind.System),
        new("Удаление программ", "Uninstall programs", "Откроет список установленных программ", "Opens the installed-programs list", "", "appwiz.cpl", "APP", false, ToolKind.System),
    };
}
