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

    /// <summary>Применяет .reg из пака (или встроенную копию). netSub подменяет номер ключа сетевой карты.</summary>
    public void Reg(string prefix, string file, string? netSub = null)
    {
        List<RegOp> ops;
        var p = Pack.Find(prefix, file);
        if (p != null) ops = RegFile.ParseFile(p);
        else if (Embedded.Reg.TryGetValue(file, out var txt)) { Log.Dim("  файл " + file + " не найден, использую встроенную копию"); ops = RegFile.Parse(txt); }
        else throw new FileNotFoundException("Файл " + file + " не найден в паке.");
        int done = 0;
        foreach (var op in ops)
        {
            if (op.Kind == RegKind.Unsupported) { Log.Warn("  пропущено (тип значения не поддерживается): " + op.Name); continue; }
            if (netSub != null) op.Sub = NetKey.Replace(op.Sub, "$1\\" + netSub);
            try { State.Apply(op); done++; }
            catch (Exception e) { Log.Warn("  ошибка записи " + op.Name + ": " + e.Message); }
        }
        Log.Dim($"  записано параметров: {done} из {ops.Count}");
    }

    public void Dword(string hive, string sub, string name, int value) =>
        State.Apply(new RegOp { Hive = hive, Sub = sub, Name = name, Kind = RegKind.DWord, Value = value });
}

public sealed class Tweak
{
    public required string Id { get; init; }
    public required string Group { get; init; }   // rec | opt
    public bool Default { get; init; }
    public required string Title { get; init; }
    public required string Desc { get; init; }
    public required Action<TweakContext> Run { get; init; }
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
        if (guid == null) throw new InvalidOperationException("Не удалось создать схему питания.");
        Sys.Powercfg("-changename", guid, "XEOKA Performance", "План питания XEOKA PACK");
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
            if (r.Code != 0 || guid == null) { c.Log.Warn("  xeoka.pow не открывается (файл повреждён). Создаю схему XEOKA Performance встроенным способом"); guid = null; }
        }
        else c.Log.Warn("  xeoka.pow не найден. Создаю схему XEOKA Performance встроенным способом");
        guid ??= BuiltinPowerPlan(c);
        var r2 = Sys.Powercfg("/setactive", guid);
        if (r2.Code != 0) throw new InvalidOperationException("powercfg /setactive: " + r2.Output.Trim());
        c.State.PowerNew = guid;
        c.Log.Dim("  схема питания " + guid + " активирована");
    }

    static void Mmcss(TweakContext c)
    {
        var type = "NDIS";
        var ad = NetInfo.Primary();
        if (ad != null) type = NetInfo.DriverType(ad.SubKey);
        c.Log.Dim("  тип драйвера сетевой карты: " + type);
        c.Reg("15.", type == "NetAdapterCx" ? "DISABLE-MMCSS.reg" : "XEOKA-OPTIMIZED-MMCSS-SETTINGS.reg");
    }

    static void Network(TweakContext c)
    {
        var ad = NetInfo.Primary() ?? throw new InvalidOperationException("Не найден активный сетевой адаптер.");
        if (!ad.Ethernet) throw new InvalidOperationException("Активное подключение не Ethernet (Wi-Fi пропущен для безопасности).");
        c.Log.Dim($"  адаптер: {ad.Name} ({ad.Description}), ключ {ad.SubKey}");
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
        c.Log.Dim("  изменения вступят в силу после перезагрузки");
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
        var bat = c.Pack.Find("11.", "Disable-All-Device-PowerSaving.bat") ?? throw new FileNotFoundException("Disable-All-Device-PowerSaving.bat не найден.");
        c.Log.Dim("  откроется окно с отчётом: нажмите любую клавишу в нём, когда прочитаете результат");
        var psi = new ProcessStartInfo("cmd.exe", "/c \"\"" + bat + "\"\"") { WorkingDirectory = Path.GetDirectoryName(bat)!, UseShellExecute = true };
        using var p = Process.Start(psi)!;
        p.WaitForExit();
    }

    public static readonly List<Tweak> All = new()
    {
        new Tweak { Id = "power", Group = "rec", Default = true, Title = "План питания XEOKA",
            Desc = "Включает схему питания XEOKA Performance. Прежняя схема запоминается для отката.", Run = Power },
        new Tweak { Id = "prio", Group = "rec", Default = true, Title = "Приоритет процессов (Win32PrioritySeparation = 0x18)",
            Desc = "Больше процессорного времени активному окну (игре).", Run = c => c.Reg("17.", "Win32PrioritySeparation-18.reg") },
        new Tweak { Id = "timer", Group = "rec", Default = true, Title = "Прерывания системного таймера",
            Desc = "SerializeTimerExpiration = 1.", Run = c => c.Reg("14.", "SerializeTimerExpiration-1.reg") },
        new Tweak { Id = "mmcss", Group = "rec", Default = true, Title = "MMCSS (по типу драйвера сетевой карты)",
            Desc = "NDIS: оптимизированные параметры. NetAdapterCx: служба MMCSS отключается. Определяется автоматически.", Run = Mmcss },
        new Tweak { Id = "net", Group = "rec", Default = true, Title = "Сетевой адаптер (Ethernet)",
            Desc = "Оптимизация параметров карты и отключение энергосбережения. Путь в реестре определяется сам. Wi-Fi не затрагивается.", Run = Network },
        new Tweak { Id = "gamebar", Group = "rec", Default = true, Title = "Game Bar и игровой режим",
            Desc = "Отключает запись игр, Game Bar и автоматический игровой режим.", Run = GameBar },
        new Tweak { Id = "fse", Group = "rec", Default = true, Title = "Полноэкранный режим: FSE (эксклюзивный)",
            Desc = "Отключает полноэкранные оптимизации. Взаимоисключается с FSO ниже.", Run = c => c.Reg("16.", "FSE.reg") },
        new Tweak { Id = "devpow", Group = "rec", Default = true, Title = "Энергосбережение всех устройств",
            Desc = "Запрещает отключать устройства для экономии энергии и будить ПК. Откроет окно с отчётом. Не откатывается кнопкой отката.", Run = DevicePower },
        new Tweak { Id = "fso", Group = "opt", Default = false, Title = "Полноэкранный режим: FSO (оптимизации включены)",
            Desc = "Вариант вместо FSE. Включайте только один из двух.", Run = c => c.Reg("16.", "FSO.reg") },
    };
}
