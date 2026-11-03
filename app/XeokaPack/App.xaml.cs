using System.IO;
using System.Threading;
using System.Windows;
using XeokaPack.Core;

namespace XeokaPack;

public partial class App : Application
{
    Mutex? _mutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        _mutex = new Mutex(true, "XEOKA-PACK-single-instance", out var created);
        if (!created) { Shutdown(); return; }

        DispatcherUnhandledException += (_, a) => { Report(a.Exception); a.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, a) => Report(a.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, a) => a.SetObserved();

        base.OnStartup(e);
        try { new MainWindow().Show(); }
        catch (Exception ex) { Report(ex); Shutdown(); }
    }

    static void Report(Exception? ex)
    {
        var text = ex?.ToString() ?? "неизвестная ошибка";
        try { File.WriteAllText(Path.Combine(Paths.DataDir, "error.txt"), DateTime.Now + Environment.NewLine + text); } catch { }
        try { MessageBox.Show(text, "XEOKA PACK: ошибка", MessageBoxButton.OK, MessageBoxImage.Error); } catch { }
    }
}
