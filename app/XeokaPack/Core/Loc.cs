using System.ComponentModel;
using System.Globalization;

namespace XeokaPack.Core;

/// <summary>Русский / английский интерфейс. Строки XAML берутся через {local:T ключ}, строки кода через Loc.L("рус", "eng").</summary>
public sealed class Loc : INotifyPropertyChanged
{
    public static Loc I { get; } = new();
    public static bool En { get; private set; }
    public static event Action? Changed;
    public event PropertyChangedEventHandler? PropertyChanged;

    public string this[string key] => Strings.All.TryGetValue(key, out var v) ? (En ? v.En : v.Ru) : key;

    public static void Set(string lang)
    {
        bool en = lang == "en" || (lang != "ru" && CultureInfo.CurrentUICulture.TwoLetterISOLanguageName != "ru");
        En = en;
        I.PropertyChanged?.Invoke(I, new PropertyChangedEventArgs("Item[]"));
        Changed?.Invoke();
    }

    public static string L(string ru, string en) => En ? en : ru;
    public static string T(string key) => I[key];
}

public static partial class Strings
{
    public static readonly Dictionary<string, (string Ru, string En)> All = new()
    {
        ["sub_title"] = ("Оптимизация Windows одной кнопкой", "Windows optimization in one click"),
        ["tg_author"] = ("Автор в Telegram", "Author on Telegram"),
        ["nav_opt"] = ("Оптимизация", "Optimization"),
        ["nav_tools"] = ("Инструменты", "Tools"),
        ["nav_about"] = ("О программе", "About"),
        ["snd_on"] = ("Звуки: вкл", "Sounds: on"),
        ["hint_f11"] = ("F11 — на весь экран", "F11 — fullscreen"),
        ["pack_searching"] = ("Ищу пак...", "Looking for the pack..."),
        ["opt_title"] = ("Что применить", "What to apply"),
        ["pack_missing"] = ("Папка пака не найдена", "Pack folder not found"),
        ["pick_pack"] = ("Указать папку пака", "Choose pack folder"),
        ["grp_rec"] = ("РЕКОМЕНДУЕМЫЕ", "RECOMMENDED"),
        ["grp_opt"] = ("ДОПОЛНИТЕЛЬНЫЕ", "OPTIONAL"),
        ["btn_apply"] = ("ОПТИМИЗИРОВАТЬ", "OPTIMIZE"),
        ["btn_revert"] = ("Откатить последнее", "Revert last run"),
        ["btn_all"] = ("Все / никакие", "All / none"),
        ["tools_title"] = ("Инструменты пака", "Pack tools"),
        ["tools_sub"] = ("Запускаются отдельно: то, что нельзя безопасно применить одной кнопкой.", "Run separately: things that cannot be applied safely with one button."),
        ["tools_risk"] = ("розовые значки: меняют защиту или стабильность системы, запускайте внимательно", "pink badges change protection or system stability: run them with care"),
        ["open_pack"] = ("Открыть папку пака", "Open pack folder"),
        ["chip_rp"] = ("Точка восстановления", "Restore point"),
        ["chip_revert"] = ("Откат изменений", "Revert changes"),
        ["chip_auto"] = ("Автопоиск пака", "Auto-detect pack"),
        ["chip_admin"] = ("Права администратора", "Administrator rights"),
        ["c1_title"] = ("Безопасно", "Safe"),
        ["c1_b1"] = ("Перед применением создаётся точка восстановления Windows.", "A Windows restore point is created before applying."),
        ["c1_b2"] = ("Каждое изменение реестра записывается в журнал.", "Every registry change is written to a journal."),
        ["c1_b3"] = ("Кнопка «Откатить последнее» возвращает прежние значения.", "The \"Revert last run\" button restores the previous values."),
        ["c2_title"] = ("Отдельно от кнопки", "Separate from the button"),
        ["c2_b1"] = ("Defender, обновления Windows, службы и BIOS меняют защиту и стабильность системы.", "Defender, Windows updates, services and BIOS change protection and system stability."),
        ["c2_b2"] = ("Поэтому они вынесены на вкладку «Инструменты» и запускаются вручную.", "That is why they live on the \"Tools\" tab and are launched manually."),
        ["c3_title"] = ("Что нужно знать", "Good to know"),
        ["c3_b1"] = ("После применения перезагрузите ПК и проверьте игры и устройства.", "Reboot after applying and check your games and devices."),
        ["c3_b2"] = ("Профиль NVIDIA и энергосбережение устройств кнопкой отката не возвращаются.", "The NVIDIA profile and device power saving are not restored by the revert button."),
        ["c3_b3"] = ("Используйте на свой риск. Автор не отвечает за последствия.", "Use at your own risk. The author is not responsible for the consequences."),
        ["tg_banner_t"] = ("АВТОР И ПОДДЕРЖКА В TELEGRAM", "AUTHOR AND SUPPORT ON TELEGRAM"),
        ["tg_banner_s"] = ("Вопросы, идеи и новые версии пака", "Questions, ideas and new versions of the pack"),
        ["open_tg"] = ("Открыть Telegram", "Open Telegram"),
        ["open_logs"] = ("Открыть журнал", "Open logs"),
        ["dlg_cancel"] = ("Отмена", "Cancel"),
        ["dlg_continue"] = ("Продолжить", "Continue"),
        ["win_min"] = ("Свернуть", "Minimize"),
        ["win_max"] = ("Развернуть", "Maximize"),
        ["win_close"] = ("Закрыть", "Close"),
        ["nav_settings"] = ("Настройки", "Settings"),
        ["sum_title"] = ("Сводка системы", "System summary"),
        ["set_title"] = ("Настройки", "Settings"),
        ["set_lang"] = ("Язык интерфейса", "Interface language"),
        ["set_lang_sub"] = ("Автоматически берётся язык Windows", "Follows the Windows language by default"),
        ["set_theme"] = ("Тема оформления", "Theme"),
        ["set_theme_sub"] = ("Цвет акцентов, фона и свечения", "Accent, background and glow color"),
        ["set_sound"] = ("Звуки интерфейса", "Interface sounds"),
        ["set_sound_sub"] = ("Клики, переходы между вкладками, завершение", "Clicks, tab transitions, completion"),
        ["set_support"] = ("Журнал для поддержки", "Support report"),
        ["set_support_sub"] = ("Соберёт архив со сводкой системы, состоянием твиков и журналами. Отправьте его автору в Telegram.", "Builds an archive with the system summary, tweak states and logs. Send it to the author on Telegram."),
        ["btn_support"] = ("Собрать архив", "Create archive"),
        ["btn_data"] = ("Папка данных", "Data folder"),
        ["lang_auto"] = ("Авто", "Auto"),
        ["tog_on"] = ("Вкл", "On"),
        ["tog_off"] = ("Выкл", "Off"),
        ["fx_working"] = ("Применяю оптимизации", "Applying optimizations"),
        ["fx_done"] = ("Готово", "Done"),
    };
}
