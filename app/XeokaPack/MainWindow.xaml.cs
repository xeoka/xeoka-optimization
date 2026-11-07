using System.IO;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
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
        Loc.Set(_settings.Lang);
        InitializeComponent();
        _layout = (LayoutState)Application.Current.Resources["Layout"];
        _pages = new[] { PageOpt, PageTools, PageAbout, PageSettings };
        _pageT = new[] { PageOptT, PageToolsT, PageAboutT, PageSettingsT };

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
        _ver = vs;
        SumList.ItemsSource = _summary;
        BuildThemeList();
        RefreshTexts();
        Loc.Changed += () => Dispatcher.BeginInvoke(RefreshTexts);
    }

    string _ver = "";
    readonly ObservableCollection<SumItem> _summary = new();
    readonly ObservableCollection<ThemeVM> _themes = new();

    void RefreshTexts()
    {
        SubTitle.Text = Loc.L("Оптимизация Windows одной кнопкой   |   v", "Windows optimization in one click   |   v") + _ver;
        AboutVersion.Text = Loc.L("Оптимизация Windows одной кнопкой   -   версия ", "Windows optimization in one click   -   version ") + _ver;
        LogPathText.Text = Loc.L("Журнал и откат: ", "Log and revert data: ") + Paths.DataDir;
        ToolsRiskText.Text = Loc.L(ThemeManager.Current.RiskRu, ThemeManager.Current.RiskEn) + Loc.T("tools_risk");
        foreach (var v in AllTweaks) v.Refresh();
        foreach (var t in _tools) t.Refresh();
        foreach (var t in _themes) t.Refresh();
        if (_pack != null) UpdatePackState();
        UpdateSoundUi();
        SetBusy(_busy);
        LangRu.Opacity = _settings.Lang == "ru" ? 1 : 0.55;
        LangEn.Opacity = _settings.Lang == "en" ? 1 : 0.55;
        LangAuto.Opacity = _settings.Lang == "auto" ? 1 : 0.55;
        _ = RefreshSummaryAsync();
    }

    // ------------------------------------------------------------ состояние и сводка
    async Task RefreshStatesAsync()
    {
        var tweaks = AllTweaks.ToList();
        var res = await Task.Run(() =>
        {
            var ctx = new TweakContext { Log = new Logger(), Pack = _pack, State = new RunState() };
            return tweaks.Select(v =>
            {
                try { return v.T.Check == null ? TweakState.Unknown : v.T.Check(ctx); }
                catch { return TweakState.Unknown; }
            }).ToList();
        });
        for (int i = 0; i < tweaks.Count; i++) tweaks[i].State = res[i];
    }

    async Task RefreshSummaryAsync()
    {
        var items = await Task.Run(() => { try { return SysInfo.Collect(_pack); } catch { return new List<SumItem>(); } });
        _summary.Clear();
        foreach (var i in items) _summary.Add(i);
    }

    // ------------------------------------------------------------ настройки
    void BuildThemeList()
    {
        foreach (var t in ThemeManager.All) _themes.Add(new ThemeVM(t, () => _settings.Theme));
        ThemeList.ItemsSource = _themes;
    }

    void Lang_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement fe) return;
        SoundFx.Tap();
        _settings.Lang = fe.Tag?.ToString() ?? "auto";
        _settings.Save();
        Loc.Set(_settings.Lang);
    }

    void Theme_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement fe) return;
        SoundFx.Tick();
        _settings.Theme = fe.Tag?.ToString() ?? "violet";
        _settings.Save();
        ThemeManager.Apply(_settings.Theme, this);
        ToolsRiskText.Text = Loc.L(ThemeManager.Current.RiskRu, ThemeManager.Current.RiskEn) + Loc.T("tools_risk");
        foreach (var t in _themes) t.Refresh();
        foreach (var t in _tools) t.Refresh();
        foreach (var v in AllTweaks) v.Refresh();
    }

    void SetSoundBtn_Click(object sender, RoutedEventArgs e) => SoundBtn_Click(sender, null!);

    async void SupportBtn_Click(object sender, RoutedEventArgs e)
    {
        SoundFx.Tap();
        SupportBtn.IsEnabled = false;
        try
        {
            var sum = _summary.ToList();
            var tw = AllTweaks.Select(v => (v.T.Title, v.State.ToString())).ToList();
            var path = await Task.Run(() => Support.Build(_pack, sum, tw, _settings));
            SoundFx.Chime();
            try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + path + "\"") { UseShellExecute = true }); } catch { }
            await AskAsync(Loc.L("Архив готов", "Archive ready"),
                Loc.L("Файл сохранён на рабочем столе:\n" + path + "\n\nОтправьте его автору в Telegram.", "Saved to your desktop:\n" + path + "\n\nSend it to the author on Telegram."),
                Loc.L("Понятно", "OK"), null);
        }
        catch (Exception ex) { await AskAsync(Loc.L("Не удалось собрать архив", "Could not create the archive"), ex.Message, Loc.L("Закрыть", "Close"), null); }
        SupportBtn.IsEnabled = true;
    }

    // ------------------------------------------------------------ анимация применения
    void FxStart()
    {
        ApplyFx.Visibility = Visibility.Visible;
        FxArc.Visibility = Visibility.Visible;
        FxCheck.Opacity = 0;
        FxTitle.Text = Loc.L("Применяю оптимизации", "Applying optimizations");
        FxStep.Text = "";
        ApplyFx.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(280)));
        FxRot.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.1)) { RepeatBehavior = RepeatBehavior.Forever });
    }

    async Task FxFinish(bool ok)
    {
        FxRot.BeginAnimation(RotateTransform.AngleProperty, null);
        FxArc.Visibility = Visibility.Collapsed;
        FxTitle.Text = ok ? Loc.L("Готово", "Done") : Loc.L("Готово с ошибками", "Done with errors");
        FxStep.Text = "";
        FxCheck.Stroke = (Brush)FindResource(ok ? "OkBrush" : "WarnBrush");
        FxCheck.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(260)));
        var sp = new DoubleAnimation(0.4, 1, TimeSpan.FromMilliseconds(520)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 } };
        FxCheckScale.BeginAnimation(ScaleTransform.ScaleXProperty, sp);
        FxCheckScale.BeginAnimation(ScaleTransform.ScaleYProperty, sp);
        await Task.Delay(1300);
        var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(320));
        ApplyFx.BeginAnimation(OpacityProperty, fade);
        await Task.Delay(340);
        ApplyFx.Visibility = Visibility.Collapsed;
    }

    // ------------------------------------------------------------ запуск
    void Window_Loaded(object sender, RoutedEventArgs e)
    {
        // Разворачиваем на весь экран поверх панели задач (а не просто Maximized, который оставляет
        // панель задач снизу видимой). Esc при необходимости вернёт обычное развёрнутое окно с панелью задач.
        _fullscreen = true;
        Left = 0; Top = 0;
        Width = SystemParameters.PrimaryScreenWidth; Height = SystemParameters.PrimaryScreenHeight;
        WindowState = WindowState.Normal;
        Topmost = true;
        MaxIcon.Data = Geometry.Parse("M2.5,0.5 H9.5 V7.5 H7.5 M0.5,2.5 H7.5 V9.5 H0.5 Z"); // окно и так во весь экран — показываем иконку "восстановить"
        Activated += (_, _) => { if (_fullscreen) Topmost = true; };
        Deactivated += (_, _) => { if (_fullscreen) Topmost = false; };
        StartBackground();
        MeasureTg();
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(520)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        AddLog(Loc.L("Выберите твики и нажмите «ОПТИМИЗИРОВАТЬ».", "Pick tweaks and press OPTIMIZE."), LogLevel.Dim);
        ThemeManager.Apply(_settings.Theme, this);
        RefreshTexts();
        if (!CheckLicense()) return;
        _ = RefreshPackAsync(autoDetect: true);
    }

    // ------------------------------------------------------------ лицензия
    bool CheckLicense()
    {
        var lic = License.Check();
        if (lic.Valid) { ActivationOverlay.Visibility = Visibility.Collapsed; StopActVideo(); return true; }
        ActHwidText.Text = License.HardwareId();
        ActError.Visibility = Visibility.Collapsed;
        ActivationOverlay.Visibility = Visibility.Visible;
        StartActVideo();
        return false;
    }

    void StartActVideo()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "activation.mp4");
            if (!File.Exists(path))
            {
                ActVolumePanel.Visibility = Visibility.Collapsed;
                try { File.AppendAllText(Path.Combine(Paths.DataDir, "error.txt"), "\n" + DateTime.Now + "  activation video not found: " + path + "\n"); } catch { }
                return;
            }
            ActVideo.Volume = ActVolumeSlider.Value;
            ActVideo.Source = new Uri(path, UriKind.Absolute);
            ActVideo.Position = TimeSpan.Zero;
            ActVideo.Play();
            ActVolumePanel.Visibility = Visibility.Visible;
        }
        catch { ActVolumePanel.Visibility = Visibility.Collapsed; }
    }

    void StopActVideo()
    {
        try { ActVideo.Stop(); ActVideo.Source = null; } catch { }
    }

    void ActVideo_MediaEnded(object sender, RoutedEventArgs e)
    {
        try { ActVideo.Position = TimeSpan.Zero; ActVideo.Play(); } catch { }
    }

    void ActVolumeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        try { ActVideo.Volume = e.NewValue; } catch { }
    }

    void ActCopyHwid_Click(object sender, RoutedEventArgs e)
    {
        SoundFx.Tap();
        try { Clipboard.SetText(ActHwidText.Text); } catch { }
    }

    void ActBuy_Click(object sender, RoutedEventArgs e)
    {
        SoundFx.Tap();
        Sys.OpenUrl(TgUrl);
    }

    void ActActivate_Click(object sender, RoutedEventArgs e)
    {
        SoundFx.Tick();
        if (License.Activate(ActCodeBox.Text, out var error))
        {
            SoundFx.Chime();
            ActivationOverlay.Visibility = Visibility.Collapsed;
            StopActVideo();
            _ = RefreshPackAsync(autoDetect: true);
        }
        else
        {
            ActError.Text = error;
            ActError.Visibility = Visibility.Visible;
        }
    }

    async Task RefreshPackAsync(bool autoDetect)
    {
        PackStatus.Text = Loc.L("Ищу пак...", "Looking for the pack...");
        PackDot.Fill = (Brush)FindResource("WarnBrush");
        var paths = await Task.Run(() =>
        {
            if (autoDetect) _pack.AutoDetect();
            return _tools.Select(t => ToolLauncher.Resolve(_pack, t.Def)).ToList();
        });
        for (int i = 0; i < _tools.Count; i++) _tools[i].Path = paths[i];
        UpdatePackState();
        _ = RefreshStatesAsync();
    }

    string? _unblockedRoot;

    void UpdatePackState()
    {
        bool ok = _pack.IsPack;
        PackDot.Fill = (Brush)FindResource(ok ? "OkBrush" : "WarnBrush");
        PackStatus.Text = ok ? Loc.L("Пак найден", "Pack found") : Loc.L("Пак не найден", "Pack not found");
        PackPath.Text = _pack.Root;
        if (ok && _unblockedRoot != _pack.Root) { _unblockedRoot = _pack.Root; var root = _pack.Root; _ = Task.Run(() => ToolLauncher.UnblockTree(root)); }
        var vis = ok ? Visibility.Collapsed : Visibility.Visible;
        PackWarnPanelOpt.Visibility = vis;
        PackWarnPanelTools.Visibility = vis;
    }

    // ------------------------------------------------------------ фон
    readonly List<ClockController> _bgClocks = new();

    void Loop(Animatable target, DependencyProperty p, double from, double to, double seconds)
    {
        var anim = new DoubleAnimation(from, to, TimeSpan.FromSeconds(seconds))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        var clock = anim.CreateClock();
        target.ApplyAnimationClock(p, clock);
        _bgClocks.Add(clock.Controller!);
    }

    void StartBackground()
    {
        Loop(Blob1T, TranslateTransform.XProperty, -90, 190, 17); Loop(Blob1T, TranslateTransform.YProperty, -50, 90, 23);
        Loop(Blob2T, TranslateTransform.XProperty, 110, -150, 19); Loop(Blob2T, TranslateTransform.YProperty, 70, -100, 25);
        Loop(Blob3T, TranslateTransform.XProperty, -70, 170, 21); Loop(Blob3T, TranslateTransform.YProperty, 60, -90, 27);
        var w = SystemParameters.PrimaryScreenWidth + 900;
        var streak = new DoubleAnimation(-700, w, TimeSpan.FromSeconds(13)) { RepeatBehavior = RepeatBehavior.Forever };
        var sc = streak.CreateClock();
        StreakT.ApplyAnimationClock(TranslateTransform.XProperty, sc);
        _bgClocks.Add(sc.Controller!);
    }

    /// <summary>Пока окно двигают или меняют его размер, на время останавливаем фоновую анимацию — иначе перетаскивание дёргается.</summary>
    internal void PauseBackground() { foreach (var c in _bgClocks) c.Pause(); }
    internal void ResumeBackground() { foreach (var c in _bgClocks) c.Resume(); }

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
        Dispatcher.BeginInvoke(() => ThemeManager.Apply(_settings.Theme, this), System.Windows.Threading.DispatcherPriority.Loaded);
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

    // Пересчёт ширины карточек ждёт, пока размер окна перестанет меняться (90 мс), а не делает это
    // на каждый кадр — иначе при перетаскивании/растягивании окна карточки заметно дёргаются.
    readonly DispatcherTimer _layoutDebounce = new() { Interval = TimeSpan.FromMilliseconds(90) };
    Action? _pendingLayout;

    void DebounceLayout(Action apply)
    {
        _pendingLayout = apply;
        _layoutDebounce.Stop();
        _layoutDebounce.Tick -= LayoutDebounce_Tick;
        _layoutDebounce.Tick += LayoutDebounce_Tick;
        _layoutDebounce.Start();
    }

    void LayoutDebounce_Tick(object? sender, EventArgs e)
    {
        _layoutDebounce.Stop();
        _pendingLayout?.Invoke();
        _pendingLayout = null;
    }

    void OptScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = OptScroll.ActualWidth - 10 - 12 - 18;
        DebounceLayout(() =>
        {
            _layout.CardWidth = Fit(avail, avail >= 980 ? 2 : 1, 12);
            _layout.SumWidth = Fit(avail - 20, avail >= 1100 ? 4 : avail >= 760 ? 3 : 2, 12);
        });
    }
    void ToolsScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = ToolsScroll.ActualWidth - 10 - 12 - 18;
        DebounceLayout(() => _layout.ToolWidth = Fit(avail, avail >= 1250 ? 3 : avail >= 640 ? 2 : 1, 12));
    }
    void AboutScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double avail = AboutScroll.ActualWidth - 10 - 12 - 18;
        DebounceLayout(() => _layout.AboutCardWidth = Fit(avail, avail >= 900 ? 3 : 1, 14));
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
        SoundFx.Tick();
        bool any = AllTweaks.Any(v => v.IsOn);
        foreach (var v in AllTweaks) v.SetSilently(false);
        if (!any) foreach (var v in AllTweaks.Where(v => v.T.Default)) v.SetSilently(true);
        if (AllTweaks.Any(v => v.Id == "fse" && v.IsOn)) foreach (var o in AllTweaks.Where(x => x.Id == "fso")) o.SetSilently(false);
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
        ApplyBtn.Content = on ? Loc.L("ПРИМЕНЯЮ...", "APPLYING...") : Loc.L("ОПТИМИЗИРОВАТЬ", "OPTIMIZE");
    }

    async void ApplyBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SoundFx.Tap();
        if (!_pack.IsPack)
        {
            if (await AskAsync(Loc.L("Папка пака не найдена", "Pack folder not found"),
                Loc.L("Положите программу в папку, распакованную из архива пака целиком, или укажите эту папку вручную.", "Put the program inside the folder extracted from the pack archive, or pick that folder manually."), Loc.L("Указать папку", "Pick folder"), Loc.L("Закрыть", "Close")))
                await PickFolderAsync();
            return;
        }
        var sel = AllTweaks.Where(v => v.IsOn).Select(v => v.T).ToList();
        if (sel.Count == 0) { _log.Warn(Loc.L("Ничего не выбрано.", "Nothing selected.")); return; }
        if (!await AskAsync(Loc.L("Применить твики?", "Apply tweaks?"),
            Loc.L($"Будет применено твиков: {sel.Count}.\n\nПеред этим создаётся точка восстановления. Изменения реестра можно откатить кнопкой «Откатить последнее».", $"Tweaks to apply: {sel.Count}.\n\nA restore point is created first. Registry changes can be undone with the Revert button."), Loc.L("Применить", "Apply")))
            return;

        SetBusy(true);
        _logItems.Clear();
        ProgScale.BeginAnimation(ScaleTransform.ScaleXProperty, null); ProgScale.ScaleX = 0;
        ProgTrack.Visibility = Visibility.Visible;
        SoundFx.Deep();
        FxStart();
        (int Ok, int Fail) res;
        try
        {
            res = await Task.Run(() => Operations.Apply(sel, _log, _pack, p => Dispatcher.BeginInvoke(() => SetProgress(p)),
                (n, total, title) => Dispatcher.BeginInvoke(() => FxStep.Text = $"{n} / {total}   {title}")));
        }
        catch (Exception ex)
        {
            _log.Err(Loc.L("Критическая ошибка: ", "Critical error: ") + ex.Message);
            SetBusy(false);
            ApplyFx.Visibility = Visibility.Collapsed;
            return;
        }
        SetBusy(false);
        await FxFinish(res.Fail == 0);
        _ = RefreshStatesAsync();
        await Task.Delay(100);
        ProgTrack.Visibility = Visibility.Collapsed;
        if (res.Fail == 0) SoundFx.Chime();
        var reboot = await AskAsync(res.Fail == 0 ? Loc.L("Готово", "Done") : Loc.L("Готово с ошибками", "Done with errors"),
            Loc.L($"Успешно: {res.Ok}, с ошибками: {res.Fail}.\n\nДля применения всех изменений нужна перезагрузка. Перезагрузить сейчас?", $"Succeeded: {res.Ok}, failed: {res.Fail}.\n\nA restart is needed for all changes to take effect. Restart now?"), Loc.L("Перезагрузить", "Restart"), Loc.L("Позже", "Later"));
        if (reboot)
        {
            try { Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5 /c \"xeoka optimization\"") { CreateNoWindow = true, UseShellExecute = false }); } catch { }
        }
    }

    async void RevertBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SoundFx.Tap();
        if (!await AskAsync(Loc.L("Откатить изменения?", "Revert changes?"), Loc.L("Вернуть значения реестра, схему питания и параметры сети к состоянию до последнего применения?", "Restore registry values, the power plan and network settings to how they were before the last run?"), Loc.L("Откатить", "Revert"))) return;
        SetBusy(true);
        _logItems.Clear();
        try { await Task.Run(() => Operations.Revert(_log)); _ = RefreshStatesAsync(); }
        catch (Exception ex) { _log.Err(Loc.L("Ошибка отката: ", "Revert error: ") + ex.Message); }
        finally { SetBusy(false); }
    }

    // ------------------------------------------------------------ инструменты и пак
    async void ToolCard_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement fe || fe.Tag is not ToolVM t) return;
        SoundFx.Tap();
        if (!t.Found)
        {
            await AskAsync(Loc.L("Файл не найден", "File not found"), Loc.L("«" + t.Def.File + "» не найден в паке. Укажите папку пака или положите файл на место.", "\"" + t.Def.File + "\" was not found in the pack. Pick the pack folder or put the file back."), Loc.L("Понятно", "OK"), null);
            return;
        }
        if (t.Def.Kind == ToolKind.Services)
        {
            if (!await AskAsync(Loc.L("Службы", "Services"),
                Loc.L("Будут отключены службы: DPS, Themes, Spooler (печать), WSearch (поиск), LanmanWorkstation и Netlogon (сетевые папки, домен), SessionEnv (удалённый рабочий стол), edgeupdate, GameInputSvc и другие.\n\nОтключение Themes может испортить внешний вид Windows, без Spooler не будет печати. Откат кнопкой отката не поддерживается.\n\nПродолжить?", "These services will be disabled: DPS, Themes, Spooler (printing), WSearch (search), LanmanWorkstation and Netlogon (network folders, domain), SessionEnv (remote desktop), edgeupdate, GameInputSvc and others.\n\nDisabling Themes can break the look of Windows, and without Spooler there is no printing. The revert button cannot undo this.\n\nContinue?"), Loc.L("Продолжить", "Continue")))
                return;
        }
        if (t.Def.Kind == ToolKind.ActivateWindows)
        {
            if (!await AskAsync(Loc.L("Стороннее ПО", "Third-party software"),
                Loc.L("Скачивается и запускается сторонний скрипт активации Windows с get.activated.win (Microsoft Activation Scripts). Это не наш код — мы не можем за него отвечать. Запускается со скрытым окном PowerShell.\n\nПродолжить?", "This downloads and runs a third-party Windows activation script from get.activated.win (Microsoft Activation Scripts). It's not our code — we can't be responsible for it. It runs in a hidden PowerShell window.\n\nContinue?"), Loc.L("Продолжить", "Continue")))
                return;
        }
        try { await Task.Run(() => ToolLauncher.Launch(_pack, t.Def)); }
        catch (Exception ex) { await AskAsync(Loc.L("Не удалось запустить", "Could not launch"), ex.Message, Loc.L("Закрыть", "Close"), null); }
    }

    void OpenPackBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); Sys.OpenFolder(_pack.Root); }
    void OpenLogsBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); Sys.OpenFolder(Paths.DataDir); }
    async void PickBtn_Click(object sender, RoutedEventArgs e) { SoundFx.Tap(); await PickFolderAsync(); }

    async Task PickFolderAsync()
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = Loc.L("Выберите папку, распакованную из архива пака", "Pick the folder extracted from the pack archive") };
        if (dlg.ShowDialog(this) != true) return;
        if (PackLocator.IsPackRoot(dlg.FolderName))
        {
            _pack.SetRoot(dlg.FolderName);
            await RefreshPackAsync(autoDetect: false);
        }
        else await AskAsync(Loc.L("Это не папка пака", "This is not the pack folder"), Loc.L("В выбранной папке не найден пак.", "No pack was found in the selected folder."), Loc.L("Понятно", "OK"), null);
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
        SoundText.Text = _settings.Sound ? Loc.L("Звуки: вкл", "Sounds: on") : Loc.L("Звуки: выкл", "Sounds: off");
        SoundIcon.Opacity = _settings.Sound ? 1 : 0.45;
        SetSoundBtn.Content = _settings.Sound ? Loc.T("tog_on") : Loc.T("tog_off");
    }

    // ------------------------------------------------------------ диалог
    Task<bool> AskAsync(string title, string text, string yes, string? no = "")
    {
        _dlg?.TrySetResult(false);
        _dlg = new TaskCompletionSource<bool>();
        DlgTitle.Text = title; DlgText.Text = text; DlgYes.Content = yes;
        DlgNo.Visibility = no == null ? Visibility.Collapsed : Visibility.Visible;
        if (no != null) DlgNo.Content = no == "" ? Loc.L("Отмена", "Cancel") : no;
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
