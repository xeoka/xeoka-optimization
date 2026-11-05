using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace XeokaPack.Core;

public sealed class TweakContext
{
    public required Logger Log { get; init; }
    public required PackLocator Pack { get; init; }
    public required RunState State { get; init; }

    static readonly Regex NetKey = new(@"(Control\\Class\\\{4D36E972-E325-11CE-BFC1-08002BE10318\})\\\d{4}$", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    List<RegOp> LoadOps(string prefix, string file, out bool embedded)
    {
        embedded = false;
        var p = Pack.Find(prefix, file);
        if (p != null) return RegFile.ParseFile(p);
        if (Embedded.Reg.TryGetValue(file, out var txt)) { embedded = true; return RegFile.Parse(txt); }
        throw new FileNotFoundException(Loc.L("Файл " + file + " не найден в паке.", "File " + file + " was not found in the pack."));
    }

    /// <summary>Применяет .reg из пака (или встроенную копию). netSub подменяет номер ключа сетевой карты.</summary>
    public void Reg(string prefix, string file, string? netSub = null)
    {
        var ops = LoadOps(prefix, file, out var embedded);
        if (embedded) Log.Dim(Loc.L("  файл " + file + " не найден, использую встроенную копию", "  " + file + " not found, using the built-in copy"));
        int done = 0;
        foreach (var op in ops)
        {
            if (op.Kind == RegKind.Unsupported) { Log.Warn(Loc.L("  пропущено (тип значения не поддерживается): ", "  skipped (unsupported value type): ") + op.Name); continue; }
            if (netSub != null) op.Sub = NetKey.Replace(op.Sub, "$1\\" + netSub);
            try { State.Apply(op); done++; }
            catch (Exception e) { Log.Warn(Loc.L("  ошибка записи ", "  write error ") + op.Name + ": " + e.Message); }
        }
        Log.Dim(Loc.L($"  записано параметров: {done} из {ops.Count}", $"  values written: {done} of {ops.Count}"));
    }

    /// <summary>Сколько значений из .reg уже совпадают с текущими в реестре.</summary>
    public (int Match, int Total) RegMatch(string prefix, string file, string? netSub = null)
    {
        var ops = LoadOps(prefix, file, out _);
        int m = 0, t = 0;
        foreach (var op in ops)
        {
            if (op.Kind == RegKind.Unsupported) continue;
            if (netSub != null) op.Sub = NetKey.Replace(op.Sub, "$1\\" + netSub);
            t++;
            try { if (RunState.Matches(op)) m++; } catch { }
        }
        return (m, t);
    }

    public static TweakState ToState(int match, int total) =>
        total == 0 ? TweakState.Unknown : match == total ? TweakState.Applied : match == 0 ? TweakState.NotApplied : TweakState.Partial;

    public void Dword(string hive, string sub, string name, int value) =>
        State.Apply(new RegOp { Hive = hive, Sub = sub, Name = name, Kind = RegKind.DWord, Value = value });
}

public enum TweakState { Unknown, NotApplied, Partial, Applied }

public sealed class Tweak
{
    public required string Id { get; init; }
    public required string Group { get; init; }   // rec | opt
    public bool Default { get; init; }
    public required string TitleRu { get; init; }
    public required string TitleEn { get; init; }
    public required string DescRu { get; init; }
    public required string DescEn { get; init; }
    public required Action<TweakContext> Run { get; init; }
    public Func<TweakContext, TweakState>? Check { get; init; }
    public string Title => Loc.L(TitleRu, TitleEn);
    public string Desc => Loc.L(DescRu, DescEn);
}

public static class Tweaks
{
    static string BuiltinPowerPlan(TweakContext c)
    {
        string? guid = null;
        foreach (var src in new[] { "e9a42b02-d5df-448d-aa00-03f14749eb61", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" })
        {
            var r = Sys.Powercfg("-duplicatescheme", src);
            var g = Sys.GuidFrom(r.Output);
            if (r.Code == 0 && g != null) { guid = g; break; }
        }
        if (guid == null) throw new InvalidOperationException(Loc.L("Не удалось создать схему питания.", "Could not create a power plan."));
        Sys.Powercfg("-changename", guid, "xeoka Performance", "План питания xeoka pack");
        var sets = new (string Sub, string Setting, int Val)[]
        {
            ("54533251-82be-4824-96c1-47b60b740d00", "893dee8e-2bef-41e0-89c6-b55d0929964c", 100), // мин. состояние процессора
            ("54533251-82be-4824-96c1-47b60b740d00", "bc5038f7-23e0-4960-96da-33abaf5935ec", 100), // макс. состояние процессора
            ("54533251-82be-4824-96c1-47b60b740d00", "0cc5b647-c1df-4637-891a-dec35c318583", 100), // парковка ядер
            ("54533251-82be-4824-96c1-47b60b740d00", "be337238-0d82-4146-a960-4f3749d470c7", 2),   // режим буста
            ("2a737441-1930-4402-8d77-b2bebba308a3", "48e6b7a6-50f5-4782-a5d4-53bb8f07e226", 0),   // USB selective suspend
            ("501a4d13-42af-4429-9fd1-a8218c268e20", "ee12f906-d277-404b-b6da-e5fa1a576df5", 0),   // PCIe ASPM
            ("0012ee47-9041-4b5d-9b77-535fba8b1442", "6738e2c4-e8a5-4a42-b16a-e040e769756e", 0),   // отключение диска
            ("19cbb8fa-5279-450e-9fac-8a3d5fedd0c1", "12bbebe6-58d6-4636-95bb-3217ef867c1a", 0),   // Wi-Fi
        };
        foreach (var s in sets)
        {
            Sys.Powercfg("-setacvalueindex", guid, s.Sub, s.Setting, s.Val.ToString());
            Sys.Powercfg("-setdcvalueindex", guid, s.Sub, s.Setting, s.Val.ToString());
        }
        return guid;
    }

    static void Power(TweakContext c)
    {
        var cur = Sys.Powercfg("/getactivescheme");
        c.State.PowerPrev = Sys.GuidFrom(cur.Output);
        string? guid = null;
        var pow = c.Pack.Find("4.", "xeoka.pow");
        if (pow != null)
        {
            var r = Sys.Powercfg("/import", pow);
            guid = Sys.GuidFrom(r.Output);
            if (r.Code != 0 || guid == null) { c.Log.Warn(Loc.L("  xeoka.pow не открывается (файл повреждён). Создаю схему xeoka Performance встроенным способом", "  xeoka.pow cannot be opened (file is damaged). Creating the xeoka Performance plan the built-in way")); guid = null; }
        }
        else c.Log.Warn(Loc.L("  xeoka.pow не найден. Создаю схему xeoka Performance встроенным способом", "  xeoka.pow not found. Creating the xeoka Performance plan the built-in way"));
        guid ??= BuiltinPowerPlan(c);
        var r2 = Sys.Powercfg("/setactive", guid);
        if (r2.Code != 0) throw new InvalidOperationException("powercfg /setactive: " + r2.Output.Trim());
        c.State.PowerNew = guid;
        c.Log.Dim(Loc.L("  схема питания " + guid + " активирована", "  power plan " + guid + " activated"));
    }

    static void Mmcss(TweakContext c)
    {
        var type = "NDIS";
        var ad = NetInfo.Primary();
        if (ad != null) type = NetInfo.DriverType(ad.SubKey);
        c.Log.Dim(Loc.L("  тип драйвера сетевой карты: ", "  network driver type: ") + type);
        c.Reg("15.", type == "NetAdapterCx" ? "DISABLE-MMCSS.reg" : "XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg");
    }

    static void Network(TweakContext c)
    {
        var ad = NetInfo.Primary() ?? throw new InvalidOperationException(Loc.L("Не найден активный сетевой адаптер.", "No active network adapter was found."));
        if (!ad.Ethernet) throw new InvalidOperationException(Loc.L("Активное подключение не Ethernet (Wi-Fi пропущен для безопасности).", "The active connection is not Ethernet (Wi-Fi is skipped for safety)."));
        c.Log.Dim(Loc.L($"  адаптер: {ad.Name} ({ad.Description}), ключ {ad.SubKey}", $"  adapter: {ad.Name} ({ad.Description}), key {ad.SubKey}"));
        c.Reg("9.", "OPTIMIZE-NETWORKING.reg", ad.SubKey);
        c.Reg("9.", "DISABLE-POWERSAVING.reg", ad.SubKey);
        try
        {
            var r = Sys.PowerShell("$g = Get-NetOffloadGlobalSetting; \"$($g.ReceiveSegmentCoalescing)|$($g.PacketCoalescingFilter)\"");
            var parts = r.Output.Trim().Split('|');
            if (r.Code == 0 && parts.Length == 2) c.State.Offload = new OffloadState { Rsc = parts[0].Trim(), Pcf = parts[1].Trim() };
            var s = Sys.PowerShell("Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -PacketCoalescingFilter Disabled");
            if (s.Code != 0) c.Log.Warn("  Set-NetOffloadGlobalSetting: " + s.Output.Trim().Split('\n')[0]);
        }
        catch (Exception e) { c.Log.Warn("  Set-NetOffloadGlobalSetting: " + e.Message); }
        c.Log.Dim(Loc.L("  изменения вступят в силу после перезагрузки", "  changes take effect after a reboot"));
    }

    static void GameBar(TweakContext c)
    {
        const string cu = "HKEY_CURRENT_USER";
        c.Dword(cu, @"System\GameConfigStore", "GameDVR_Enabled", 0);
        c.Dword(cu, @"Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled", 0);
        c.Dword(cu, @"Software\Microsoft\GameBar", "AutoGameModeEnabled", 0);
        c.Dword(cu, @"Software\Microsoft\GameBar", "AllowAutoGameMode", 0);
        c.Dword(cu, @"Software\Microsoft\GameBar", "UseNexusForGameBarEnabled", 0);
    }

    static void DevicePower(TweakContext c)
    {
        var bat = c.Pack.Find("11.", "Disable-All-Device-PowerSaving.bat") ?? throw new FileNotFoundException(Loc.L("Disable-All-Device-PowerSaving.bat не найден.", "Disable-All-Device-PowerSaving.bat was not found."));
        c.Log.Dim(Loc.L("  откроется окно с отчётом: нажмите любую клавишу в нём, когда прочитаете результат", "  a report window will open: press any key in it when you have read the result"));
        var psi = new ProcessStartInfo("cmd.exe", "/c \"\"" + bat + "\"\"") { WorkingDirectory = Path.GetDirectoryName(bat)!, UseShellExecute = true };
        using var p = Process.Start(psi)!;
        p.WaitForExit();
    }

    static TweakState PowerCheck(TweakContext c)
    {
        var r = Sys.Powercfg("/getactivescheme");
        return r.Output.Contains("XEOKA", StringComparison.OrdinalIgnoreCase) ? TweakState.Applied : TweakState.NotApplied;
    }

    static TweakState MmcssCheck(TweakContext c)
    {
        var type = "NDIS";
        var ad = NetInfo.Primary();
        if (ad != null) type = NetInfo.DriverType(ad.SubKey);
        var r = c.RegMatch("15.", type == "NetAdapterCx" ? "DISABLE-MMCSS.reg" : "XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg");
        return TweakContext.ToState(r.Match, r.Total);
    }

    static TweakState NetCheck(TweakContext c)
    {
        var ad = NetInfo.Primary();
        if (ad == null || !ad.Ethernet) return TweakState.Unknown;
        var a = c.RegMatch("9.", "OPTIMIZE-NETWORKING.reg", ad.SubKey);
        var b = c.RegMatch("9.", "DISABLE-POWERSAVING.reg", ad.SubKey);
        return TweakContext.ToState(a.Match + b.Match, a.Total + b.Total);
    }

    static TweakState GameBarCheck(TweakContext c)
    {
        var ops = new (string Hive, string Sub, string Name)[]
        {
            ("HKEY_CURRENT_USER", @"System\GameConfigStore", "GameDVR_Enabled"),
            ("HKEY_CURRENT_USER", @"Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"),
            ("HKEY_CURRENT_USER", @"Software\Microsoft\GameBar", "AutoGameModeEnabled"),
            ("HKEY_CURRENT_USER", @"Software\Microsoft\GameBar", "AllowAutoGameMode"),
            ("HKEY_CURRENT_USER", @"Software\Microsoft\GameBar", "UseNexusForGameBarEnabled"),
        };
        int m = 0;
        foreach (var o in ops)
            if (RunState.Matches(new RegOp { Hive = o.Hive, Sub = o.Sub, Name = o.Name, Kind = RegKind.DWord, Value = 0 })) m++;
        return TweakContext.ToState(m, ops.Length);
    }

    static Func<TweakContext, TweakState> RegChk(string prefix, string file) => c =>
    {
        var r = c.RegMatch(prefix, file);
        return TweakContext.ToState(r.Match, r.Total);
    };

    public static readonly List<Tweak> All = new()
    {
        new Tweak { Id = "power", Group = "rec", Default = true,
            TitleRu = "План питания xeoka", TitleEn = "xeoka power plan",
            DescRu = "Включает схему питания xeoka Performance. Прежняя схема запоминается для отката.",
            DescEn = "Activates the xeoka Performance power plan. The previous plan is remembered for revert.",
            Run = Power, Check = PowerCheck },
        new Tweak { Id = "prio", Group = "rec", Default = true,
            TitleRu = "Приоритет процессов (Win32PrioritySeparation = 0x18)", TitleEn = "Process priority (Win32PrioritySeparation = 0x18)",
            DescRu = "Больше процессорного времени активному окну (игре).", DescEn = "More CPU time for the active window (the game).",
            Run = c => c.Reg("17.", "Win32PrioritySeparation-18.reg"), Check = RegChk("17.", "Win32PrioritySeparation-18.reg") },
        new Tweak { Id = "timer", Group = "rec", Default = true,
            TitleRu = "Прерывания системного таймера", TitleEn = "System timer interrupts",
            DescRu = "SerializeTimerExpiration = 1.", DescEn = "SerializeTimerExpiration = 1.",
            Run = c => c.Reg("14.", "SerializeTimerExpiration-1.reg"), Check = RegChk("14.", "SerializeTimerExpiration-1.reg") },
        new Tweak { Id = "mmcss", Group = "rec", Default = true,
            TitleRu = "MMCSS (по типу драйвера сетевой карты)", TitleEn = "MMCSS (by network driver type)",
            DescRu = "NDIS: оптимизированные параметры. NetAdapterCx: служба MMCSS отключается. Определяется автоматически.",
            DescEn = "NDIS: optimized parameters. NetAdapterCx: the MMCSS service is disabled. Detected automatically.",
            Run = Mmcss, Check = MmcssCheck },
        new Tweak { Id = "net", Group = "rec", Default = true,
            TitleRu = "Сетевой адаптер (Ethernet)", TitleEn = "Network adapter (Ethernet)",
            DescRu = "Оптимизация параметров карты и отключение энергосбережения. Путь в реестре определяется сам. Wi-Fi не затрагивается.",
            DescEn = "Tunes adapter parameters and turns off power saving. The registry path is detected automatically. Wi-Fi is not touched.",
            Run = Network, Check = NetCheck },
        new Tweak { Id = "gamebar", Group = "rec", Default = true,
            TitleRu = "Game Bar и игровой режим", TitleEn = "Game Bar and Game Mode",
            DescRu = "Отключает запись игр, Game Bar и автоматический игровой режим.",
            DescEn = "Disables game capture, Game Bar and automatic Game Mode.",
            Run = GameBar, Check = GameBarCheck },
        new Tweak { Id = "fse", Group = "rec", Default = true,
            TitleRu = "Полноэкранный режим: FSE (эксклюзивный)", TitleEn = "Fullscreen mode: FSE (exclusive)",
            DescRu = "Отключает полноэкранные оптимизации. Взаимоисключается с FSO ниже.",
            DescEn = "Disables fullscreen optimizations. Mutually exclusive with FSO below.",
            Run = c => c.Reg("16.", "FSE.reg"), Check = RegChk("16.", "FSE.reg") },
        new Tweak { Id = "devpow", Group = "rec", Default = true,
            TitleRu = "Энергосбережение всех устройств", TitleEn = "Power saving of all devices",
            DescRu = "Запрещает отключать устройства для экономии энергии и будить ПК. Откроет окно с отчётом. Не откатывается кнопкой отката.",
            DescEn = "Stops Windows from turning devices off to save power and from waking the PC. Opens a report window. Not restored by the revert button.",
            Run = DevicePower },
        new Tweak { Id = "fso", Group = "opt", Default = false,
            TitleRu = "Полноэкранный режим: FSO (оптимизации включены)", TitleEn = "Fullscreen mode: FSO (optimizations on)",
            DescRu = "Вариант вместо FSE. Включайте только один из двух.", DescEn = "An alternative to FSE. Enable only one of the two.",
            Run = c => c.Reg("16.", "FSO.reg"), Check = RegChk("16.", "FSO.reg") },
    };
}
