using System.IO;
namespace XeokaPack.Core;

/// <summary>Точка восстановления, откат, запуск набора твиков.</summary>
public static class Operations
{
    public static void CreateRestorePoint(Logger log)
    {
        log.Head(Loc.L("Создаю точку восстановления...", "Creating a restore point..."));
        try
        {
            var r = Sys.PowerShell("Enable-ComputerRestore -Drive \"$env:SystemDrive\\\" -ErrorAction SilentlyContinue; Checkpoint-Computer -Description 'Xeoka pack' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop", 180000);
            if (r.Code == 0) log.Ok(Loc.L("  точка восстановления создана", "  restore point created"));
            else log.Warn(Loc.L("  точку создать не удалось (", "  could not create a restore point (") + (r.Output.Trim().Split('\n').FirstOrDefault() ?? Loc.L("ошибка", "error")) + Loc.L("). Продолжаю, откат реестра доступен.", "). Continuing, registry revert is available."));
        }
        catch (Exception e) { log.Warn(Loc.L("  точку создать не удалось (", "  could not create a restore point (") + e.Message + Loc.L("). Продолжаю, откат реестра доступен.", "). Continuing, registry revert is available.")); }
    }

    public static (int Ok, int Fail) Apply(IReadOnlyList<Tweak> tweaks, Logger log, PackLocator pack, Action<double> progress, Action<int, int, string>? step = null)
    {
        var state = new RunState();
        var ctx = new TweakContext { Log = log, Pack = pack, State = state };
        CreateRestorePoint(log);
        int ok = 0, fail = 0, i = 0;
        progress(0);
        foreach (var t in tweaks)
        {
            step?.Invoke(i + 1, tweaks.Count, t.Title);
            log.Head("> " + t.Title);
            try { t.Run(ctx); log.Ok(Loc.L("  готово", "  done")); ok++; }
            catch (Exception e) { log.Err(Loc.L("  ошибка: ", "  error: ") + e.Message); fail++; }
            i++; progress((double)i / tweaks.Count);
        }
        try { state.Save(); } catch (Exception e) { log.Err(Loc.L("Не удалось сохранить журнал отката: ", "Could not save the revert journal: ") + e.Message); }
        log.Head(Loc.L($"Итог: успешно {ok}, с ошибками {fail}.", $"Result: {ok} succeeded, {fail} failed."));
        return (ok, fail);
    }

    public static void Revert(Logger log)
    {
        var latest = RunState.LoadLatest();
        if (latest == null) { log.Warn(Loc.L("Нет сохранённых изменений для отката.", "No saved changes to revert.")); return; }
        var (file, st) = latest.Value;
        log.Head(Loc.L("Откат изменений от ", "Reverting changes from ") + st.Time);
        int n = 0;
        for (int i = st.Ops.Count - 1; i >= 0; i--)
        {
            var o = st.Ops[i];
            try { RunState.Restore(o); n++; }
            catch (Exception e) { log.Warn(Loc.L("  не удалось восстановить ", "  could not restore ") + o.Name + ": " + e.Message); }
        }
        log.Ok(Loc.L("  восстановлено параметров реестра: ", "  registry values restored: ") + n);
        if (st.Offload != null)
        {
            var r = Sys.PowerShell($"Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing {st.Offload.Rsc} -PacketCoalescingFilter {st.Offload.Pcf}");
            if (r.Code == 0) log.Ok(Loc.L("  параметры offload восстановлены", "  offload settings restored")); else log.Warn("  offload: " + r.Output.Trim().Split('\n')[0]);
        }
        if (!string.IsNullOrEmpty(st.PowerPrev))
        {
            Sys.Powercfg("/setactive", st.PowerPrev);
            if (!string.IsNullOrEmpty(st.PowerNew)) Sys.Powercfg("/delete", st.PowerNew);
            log.Ok(Loc.L("  схема питания возвращена", "  power plan restored"));
        }
        try { File.Move(file.FullName, file.FullName + ".reverted", true); } catch { }
        log.Ok(Loc.L("Готово. Перезагрузите компьютер.", "Done. Please restart the computer."));
    }
}
