namespace XeokaPack.Core;

public enum ToolKind { File, Ps1, Services, Nvidia }

public sealed record ToolDef(string Title, string Desc, string Prefix, string File, string Glyph, bool Risk, ToolKind Kind = ToolKind.File);

public static class ToolDefs
{
    public static readonly List<ToolDef> All = new()
    {
        new("Windows Defender", "Переключатель защитника", "6.", "RUN-WDS.bat", "WD", true),
        new("Обновления Windows", "Блокировщик обновлений", "7.", "RUN-WUB.bat", "WU", true),
        new("DEVICE-TWEAKER", "Аффинити, прерывания, USB", "1", "DEVICE-TWEAKER*.ps1", "DT", false, ToolKind.Ps1),
        new("BIOS (SCEWIN)", "Конфиги BIOS. Читайте инструкцию", "12.", "SCEWIN-GUI.exe", "BIOS", true),
        new("Тип драйвера сети", "NDIS или NetAdapterCx", "15.", "RUN-CHECK-NIC-DRIVER-TYPE.PS1.bat", "NIC", false),
        new("Энергосбережение сети", "Проверка статуса", "9.", "RUN-CHECK-POWER-MANAGEMENT.bat", "PWR", false),
        new("DDU", "Удаление драйверов видеокарты", "2.", "Display Driver Uninstaller.exe", "DDU", false),
        new("NVCleanstall", "Установка драйвера NVIDIA", "2.", "NVCleanstall_1.19.0.exe", "NV", false),
        new("Профиль NVIDIA", "Откроет .nip в Profile Inspector", "2.", "nvidiaProfileInspector.exe", "NPI", false, ToolKind.Nvidia),
        new("CRU", "Настройка разрешений и частот", "3.", "CRU.exe", "CRU", false),
        new("Autoruns", "Автозагрузка", "8.", "Autoruns.exe", "AR", false),
        new("Службы (PowerRun)", "Отключение служб. Осторожно", "10.", "DISABLE-SERVICES.reg", "SVC", true, ToolKind.Services),
    };
}
