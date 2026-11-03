using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using XeokaPack.Core;

namespace XeokaPack;

public partial class MainWindow : Window
{
    const string TgUrl = "https://t.me/CMEPT0HOCHbIU";

    readonly Logger _log = new();
    readonly PackLocator _pack = new();
    readonly ObservableCollection<TweakVM> _rec = new(), _opt = new();
    readonly ObservableCollection<ToolVM> _tools = new();
    readonly ObservableCollection<LogItem> _logItems = new();
    readonly LayoutState _layout;
    readonly Settings _settings = Settings.Load();
    readonly Grid[] _pages;
    readonly TranslateTransform[] _pageT;

    bool _busy, _fullscreen, _closing;
    int _page;
    WindowState _prevState = WindowState.Maximized;
    double _tgFull = 330;
    TaskCompletionSource<bool>? _dlg;

    IEnumerable<TweakVM> AllTweaks => _rec.Concat(_opt);

    public MainWindow()
    {
        InitializeComponent();
        _layout = (LayoutState)Application.Current.Resources["Layout"];
        _pages = new[] { PageOpt, PageTools, PageAbout };
        _pageT = new[] { PageOptT, PageToolsT, PageAboutT };

        SoundFx.Enabled = _settings.Sound;
        UpdateSoundUi();

        foreach (var t in Tweaks.All)
        {
            var vm = new TweakVM(t) { Changed = OnTweakChanged };
            (t.Group == "rec" ? _rec : _opt).Add(vm);
        }
        foreach (var d in ToolDefs.All) _tools.Add(new ToolVM(d));
        RecList.ItemsSource = _rec;
        OptList.ItemsSource = _opt;
        ToolsList.ItemsSource = _tools;
        LogList.ItemsSource = _logItems;

        _log.Entry += (text, level) => Dispatcher.BeginInvoke(() => AddLog(text, level));

        var ver = Assembly.GetExecutingAssembly().GetName().Version;
        var vs = ver == null ? "" : $"{ver.Major}.{ver.Minor}";
        SubTitle.Text = "Оптимизация Windows одной кнопкой   |   v" + vs;
        AboutVersion.Text = "Оптимизация Windows одной кнопкой   -   версия " + vs;
        LogPathText.Text = "Журнал и откат: " + Paths.DataDir;
    }

    // ------------------------------------------------------------ запуск
    void Window_Loaded(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Maximized;
        StartBackground();
        MeasureTg();
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(520)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        SoundFx.Deep();
        AddLog("Выберите твики и нажмите «ОПТИМИЗИРОВАТЬ».", LogLevel.Dim);
        _ = RefreshPackAsync(autoDetect: true);
    }

    async Task RefreshPackAsync(bool autoDetect)
    {
        PackStatus.Text = "Ищу пак...";
        PackDot.Fill = (Brush)FindResource("WarnBrush");
        var paths = await Task.Run(() =>
        {
            if (autoDetect) _pack.AutoDetect();
            return _tools.Select(t => ToolLauncher.Resolve(_pack, t.Def)).ToList();
        });
        for (int i = 0; i < _tools.Count; i++) _tools[i].Path = paths[i];
        UpdatePackState();
    }

    void UpdatePackState()
    {
        bool ok = _pack.IsPack;
        PackDot.Fill = (Brush)FindResource(ok ? "OkBrush" : "WarnBrush");
        PackStatus.Text = ok ? "Пак найден" : "Пак не найден";
        PackPath.Text = _pack.Root;
        var vis = ok ? Visibility.Collapsed : Visibility.Visible;
        PackWarnPanelOpt.Visibility = vis;
        PackWarnPanelTools.Visibility = vis;
    }

    // ------------------------------------------------------------ фон
    static void Loop(Animatable target, DependencyProperty p, double from, double to, double seconds)
    {
        target.BeginAnimation(p, new DoubleAnimation(from, to, TimeSpan.FromSeconds(seconds))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        });
    }

    void StartBackground()
    {
        Loop(Blob1T, TranslateTransform.XProperty, -90, 190, 17); Loop(Blob1T, TranslateTransform.YProperty, -50, 90, 23);
        Loop(Blob2T, TranslateTransform.XProperty, 110, -150, 19); Loop(Blob2T, TranslateTransform.YProperty, 70, -100, 25);
        Loop(Blob3T, TranslateTransform.XProperty, -70, 170, 21); Loop(Blob3T, TranslateTransform.YProperty, 60, -90, 27);
        var w = SystemParameters.PrimaryScreenWidth + 900;
        StreakT.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-700, w, TimeSpan.FromSeconds(13)) { RepeatBehavior = RepeatBehavior.Forever });
    }

    // ------------------------------------------------------------ окно
    void MinBtn_Click(object s, RoutedEventArgs e) { SoundFx.Tap(); WindowState = WindowState.Minimized; }
    void MaxBtn_Click(object s, RoutedEventArgs e)
    {
        SoundFx.Tap();
        if (_fullscreen) { ToggleFullscreen(); return; }
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    }
    void CloseBtn_Click(object s, RoutedEventArgs e) => FadeClose();

    void FadeClose()
    {
        if (_closing) return;
        _closing = true;
        var a = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(220));
        a.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, a);
    }

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);
        MaxIcon.Data = Geometry.Parse(WindowState == WindowState.Maximized
            ? "M2.5,0.5 H9.5 V7.5 H7.5 M0.5,2.5 H7.5 V9.5 H0.5 Z"
            : "M0.5,0.5 H9.5 V9.5 H0.5 Z");
    }

    void ToggleFullscreen()
    {
        if (!_fullscreen)
        {
            _prevState = WindowState == WindowState.Minimized ? WindowState.Maximized : WindowState;
            _fullscreen = true;
            WindowState = WindowState.Normal;
            Left = 0; Top = 0;
            Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight;
            Topmost = true;
        }
        else
        {
            _fullscreen = false;
            Topmost = false;
            WindowState = _prevState;
        }
    }

    void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Overlay.Visibility == Visibility.Visible)
        {
            if (e.Key == Key.Escape) { CloseDialog(false); e.Handled = true; }
            else if (e.Key == Key.Enter) { CloseDialog(true); e.Handled = true; }
            return;
        }
        if (e.Key == Key.F11) { ToggleFullscreen(); e.Handled = true; }
        else if (e.Key == Key.Escape && _fullscreen) { ToggleFullscreen(); e.Handled = true; }
    }

    void Window_SizeChanged(object sender, SizeChangedEventArgs e) { }

    // ------------------------------------------------------------ Telegram
    void MeasureTg()
    {
        TgLine1.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        TgLine2.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        _tgFull = 22 + Math.Max(TgLine1.DesiredSize.Width, TgLine2.DesiredSize.Width) + 14 + 54;
    }

    static DoubleAnimation Ease(double to, int ms, int delayMs = 0) => new(to, TimeSpan.FromMilliseconds(ms))
    {
        BeginTime = TimeSpan.FromMilliseconds(delayMs),
        EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
    };

    void TgRoot_MouseEnter(object sender, MouseEventArgs e)
    {
        TgRoot.BeginAnimation(WidthProperty, Ease(_tgFull, 420));
        TgFill.BeginAnimation(OpacityProperty, Ease(1, 240));
        TgTexts.BeginAnimation(OpacityProperty, Ease(1, 260, 150));
    }
    void TgRoot_MouseLeave(object sender, MouseEventArgs e)
    {
        TgTexts.BeginAnimation(OpacityProperty, Ease(0, 120));
        TgRoot.BeginAnimation(WidthProperty, Ease(52, 360, 60));
        TgFill.BeginAnimation(OpacityProperty, Ease(0, 300, 80));
    }
    void TgRoot_Click(object sender, MouseButtonEventArgs e) { SoundFx.Tap(); Sys.OpenUrl(TgUrl); }
    void OpenTgBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); Sys.OpenUrl(TgUrl); }

    // ------------------------------------------------------------ навигация
    void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && int.TryParse(fe.Tag?.ToString(), out var idx)) ShowPage(idx);
    }

    void ShowPage(int idx)
    {
        if (idx == _page) return;
        SoundFx.Tick();
        NavIndT.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(idx * 54, TimeSpan.FromMilliseconds(380))
        { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.25 } });
        _pages[_page].Visibility = Visibility.Collapsed;
        _page = idx;
        var pg = _pages[idx];
        pg.Visibility = Visibility.Visible;
        pg.Opacity = 0;
        pg.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(320)));
        _pageT[idx].BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(40, 0, TimeSpan.FromMilliseconds(420))
        { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
    }

    // ------------------------------------------------------------ размеры карточек
    static double Fit(double avail, int cols, double gap) => Math.Max(220, Math.Floor(avail / cols) - gap);

    void OptScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = OptScroll.ActualWidth - 10 - 12;
        _layout.CardWidth = Fit(avail, avail >= 980 ? 2 : 1, 12);
    }
    void ToolsScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = ToolsScroll.ActualWidth - 10 - 12;
        _layout.ToolWidth = Fit(avail, avail >= 1250 ? 3 : avail >= 640 ? 2 : 1, 12);
    }
    void AboutScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = AboutScroll.ActualWidth - 10 - 12;
        _layout.AboutCardWidth = Fit(avail, avail >= 900 ? 3 : 1, 14);
    }

    // ------------------------------------------------------------ твики
    void OnTweakChanged(TweakVM vm)
    {
        SoundFx.Tap();
        if (!vm.IsOn) return;
        if (vm.Id == "fse") { foreach (var o in AllTweaks.Where(x => x.Id == "fso")) o.IsOn = false; }
        if (vm.Id == "fso") { foreach (var o in AllTweaks.Where(x => x.Id == "fse")) o.IsOn = false; }
    }

    void TweakCard_Click(object sender, MouseButtonEventArgs e)
    {
        if (_busy) return;
        if (sender is FrameworkElement fe && fe.Tag is TweakVM vm) vm.IsOn = !vm.IsOn;
    }

    void AllBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        bool any = AllTweaks.Any(v => v.IsOn);
        foreach (var v in AllTweaks) v.IsOn = false;
        if (!any) foreach (var v in AllTweaks.Where(v => v.T.Default)) v.IsOn = true;
    }

    void AddLog(string text, LogLevel level)
    {
        _logItems.Add(new LogItem { Text = text, Level = level });
        while (_logItems.Count > 500) _logItems.RemoveAt(0);
        Dispatcher.BeginInvoke(new Action(() => LogScroll.ScrollToEnd()), System.Windows.Threading.DispatcherPriority.Background);
    }

    void SetProgress(double fraction)
    {
        ProgScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(Math.Clamp(fraction, 0, 1), TimeSpan.FromMilliseconds(380))
        { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
    }

    void SetBusy(bool on)
    {
        _busy = on;
        ApplyBtn.IsEnabled = RevertBtn.IsEnabled = AllBtn.IsEnabled = !on;
        ApplyBtn.Content = on ? "ПРИМЕНЯЮ..." : "ОПТИМИЗИРОВАТЬ";
    }

    async void ApplyBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SoundFx.Tap();
        if (!_pack.IsPack)
        {
            if (await AskAsync("Папка пака не найдена",
                "Положите программу в корень пака (рядом с папками «1. База», «2. Драйверы» и т.д.) или укажите папку вручную.", "Указать папку", "Закрыть"))
                await PickFolderAsync();
            return;
        }
        var sel = AllTweaks.Where(v => v.IsOn).Select(v => v.T).ToList();
        if (sel.Count == 0) { _log.Warn("Ничего не выбрано."); return; }
        if (!await AskAsync("Применить твики?",
            $"Будет применено твиков: {sel.Count}.\n\nПеред этим создаётся точка восстановления. Изменения реестра можно откатить кнопкой «Откатить последнее».", "Применить"))
            return;

        SetBusy(true);
        _logItems.Clear();
        ProgScale.BeginAnimation(ScaleTransform.ScaleXProperty, null); ProgScale.ScaleX = 0;
        ProgTrack.Visibility = Visibility.Visible;
        SoundFx.Deep();
        (int Ok, int Fail) res;
        try
        {
            res = await Task.Run(() => Operations.Apply(sel, _log, _pack, p => Dispatcher.BeginInvoke(() => SetProgress(p))));
        }
        catch (Exception ex)
        {
            _log.Err("Критическая ошибка: " + ex.Message);
            SetBusy(false);
            return;
        }
        SetBusy(false);
        await Task.Delay(700);
        ProgTrack.Visibility = Visibility.Collapsed;
        if (res.Fail == 0) SoundFx.Chime();
        var reboot = await AskAsync(res.Fail == 0 ? "Готово" : "Готово с ошибками",
            $"Успешно: {res.Ok}, с ошибками: {res.Fail}.\n\nДля применения всех изменений нужна перезагрузка. Перезагрузить сейчас?", "Перезагрузить", "Позже");
        if (reboot)
        {
            try { Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5 /c \"XEOKA PACK\"") { CreateNoWindow = true, UseShellExecute = false }); } catch { }
        }
    }

    async void RevertBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SoundFx.Tap();
        if (!await AskAsync("Откатить изменения?", "Вернуть значения реестра, схему питания и параметры сети к состоянию до последнего применения?", "Откатить")) return;
        SetBusy(true);
        _logItems.Clear();
        try { await Task.Run(() => Operations.Revert(_log)); }
        catch (Exception ex) { _log.Err("Ошибка отката: " + ex.Message); }
        finally { SetBusy(false); }
    }

    // ------------------------------------------------------------ инструменты и пак
    async void ToolCard_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement fe || fe.Tag is not ToolVM t) return;
        SoundFx.Tap();
        if (!t.Found)
        {
            await AskAsync("Файл не найден", "«" + t.Def.File + "» не найден в паке. Укажите папку пака или положите файл на место.", "Понятно", null);
            return;
        }
        if (t.Def.Kind == ToolKind.Services)
        {
            if (!await AskAsync("Службы",
                "Будут отключены службы: DPS, Themes, Spooler (печать), WSearch (поиск), LanmanWorkstation и Netlogon (сетевые папки, домен), SessionEnv (удалённый рабочий стол), edgeupdate, GameInputSvc и другие.\n\nОтключение Themes может испортить внешний вид Windows, без Spooler не будет печати. Откат кнопкой отката не поддерживается.\n\nПродолжить?", "Продолжить"))
                return;
        }
        try { await Task.Run(() => ToolLauncher.Launch(_pack, t.Def)); }
        catch (Exception ex) { await AskAsync("Не удалось запустить", ex.Message, "Закрыть", null); }
    }

    void OpenPackBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); Sys.OpenFolder(_pack.Root); }
    void OpenLogsBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); Sys.OpenFolder(Paths.DataDir); }
    async void PickBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); await PickFolderAsync(); }

    async Task PickFolderAsync()
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = "Выберите корневую папку пака (где лежат «1. База», «2. Драйверы» и т.д.)" };
        if (dlg.ShowDialog(this) != true) return;
        if (PackLocator.IsPackRoot(dlg.FolderName))
        {
            _pack.SetRoot(dlg.FolderName);
            await RefreshPackAsync(autoDetect: false);
        }
        else await AskAsync("Это не папка пака", "В выбранной папке не найдены папки пака (1. База, 2. Драйверы ...).", "Понятно", null);
    }

    // ------------------------------------------------------------ звук
    void SoundBtn_Click(object sender, MouseButtonEventArgs e)
    {
        _settings.Sound = !_settings.Sound;
        SoundFx.Enabled = _settings.Sound;
        _settings.Save();
        UpdateSoundUi();
        SoundFx.Tap();
    }
    void UpdateSoundUi()
    {
        SoundText.Text = _settings.Sound ? "Звуки: вкл" : "Звуки: выкл";
        SoundIcon.Opacity = _settings.Sound ? 1 : 0.45;
    }

    // ------------------------------------------------------------ диалог
    Task<bool> AskAsync(string title, string text, string yes, string? no = "Отмена")
    {
        _dlg?.TrySetResult(false);
        _dlg = new TaskCompletionSource<bool>();
        DlgTitle.Text = title; DlgText.Text = text; DlgYes.Content = yes;
        DlgNo.Visibility = no == null ? Visibility.Collapsed : Visibility.Visible;
        if (no != null) DlgNo.Content = no;
        Overlay.Visibility = Visibility.Visible;
        OverlayDim.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)));
        DlgCard.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
        var sc = new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(320)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.3 } };
        DlgScale.BeginAnimation(ScaleTransform.ScaleXProperty, sc);
        DlgScale.BeginAnimation(ScaleTransform.ScaleYProperty, sc);
        return _dlg.Task;
    }

    void CloseDialog(bool result)
    {
        var d = _dlg; _dlg = null;
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(150));
        fade.Completed += (_, _) => { if (_dlg == null) Overlay.Visibility = Visibility.Collapsed; };
        OverlayDim.BeginAnimation(OpacityProperty, fade);
        DlgCard.BeginAnimation(OpacityProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(130)));
        d?.TrySetResult(result);
    }
    void DlgYes_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); CloseDialog(true); }
    void DlgNo_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); CloseDialog(false); }
}
