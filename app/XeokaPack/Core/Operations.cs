using System.IO;
namespace XeokaPack.Core;

/// <summary>Точка восстановления, откат, запуск набора твиков.</summary>
public static class Operations
{
    public static void CreateRestorePoint(Logger log)
    {
        log.Head("Создаю точку восстановления...");
        try
        {
            var r = Sys.PowerShell("Enable-ComputerRestore -Drive \"$env:SystemDrive\\\" -ErrorAction SilentlyContinue; Checkpoint-Computer -Description 'XEOKA Pack' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop", 180000);
            if (r.Code == 0) log.Ok("  точка восстановления создана");
            else log.Warn("  точку создать не удалось (" + (r.Output.Trim().Split('\n').FirstOrDefault() ?? "ошибка") + "). Продолжаю, откат реестра доступен.");
        }
        catch (Exception e) { log.Warn("  точку создать не удалось (" + e.Message + "). Продолжаю, откат реестра доступен."); }
    }

    public static (int Ok, int Fail) Apply(IReadOnlyList<Tweak> tweaks, Logger log, PackLocator pack, Action<double> progress)
    {
        var state = new RunState();
        var ctx = new TweakContext { Log = log, Pack = pack, State = state };
        CreateRestorePoint(log);
        int ok = 0, fail = 0, i = 0;
        progress(0);
        foreach (var t in tweaks)
        {
            log.Head("> " + t.Title);
            try { t.Run(ctx); log.Ok("  готово"); ok++; }
            catch (Exception e) { log.Err("  ошибка: " + e.Message); fail++; }
            i++; progress((double)i / tweaks.Count);
        }
        try { state.Save(); } catch (Exception e) { log.Err("Не удалось сохранить журнал отката: " + e.Message); }
        log.Head($"Итог: успешно {ok}, с ошибками {fail}.");
        return (ok, fail);
    }

    public static void Revert(Logger log)
    {
        var latest = RunState.LoadLatest();
        if (latest == null) { log.Warn("Нет сохранённых изменений для отката."); return; }
        var (file, st) = latest.Value;
        log.Head("Откат изменений от " + st.Time);
        int n = 0;
        for (int i = st.Ops.Count - 1; i >= 0; i--)
        {
            var o = st.Ops[i];
            try { RunState.Restore(o); n++; }
            catch (Exception e) { log.Warn("  не удалось восстановить " + o.Name + ": " + e.Message); }
        }
        log.Ok("  восстановлено параметров реестра: " + n);
        if (st.Offload != null)
        {
            var r = Sys.PowerShell($"Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing {st.Offload.Rsc} -PacketCoalescingFilter {st.Offload.Pcf}");
            if (r.Code == 0) log.Ok("  параметры offload восстановлены"); else log.Warn("  offload: " + r.Output.Trim().Split('\n')[0]);
        }
        if (!string.IsNullOrEmpty(st.PowerPrev))
        {
            Sys.Powercfg("/setactive", st.PowerPrev);
            if (!string.IsNullOrEmpty(st.PowerNew)) Sys.Powercfg("/delete", st.PowerNew);
            log.Ok("  схема питания возвращена");
        }
        try { File.Move(file.FullName, file.FullName + ".reverted", true); } catch { }
        log.Ok("Готово. Перезагрузите компьютер.");
    }
}
