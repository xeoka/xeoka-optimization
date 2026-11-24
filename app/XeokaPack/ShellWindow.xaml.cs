using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Web.WebView2.Core;
using XeokaPack.Core;

namespace XeokaPack;

/// <summary>Окно-оболочка: рисует интерфейс из встроенного HTML (WebView2), а всю логику держит в Core.</summary>
public partial class ShellWindow : Window
{
    const string Host = "xeoka.app";
    const string TgUrl = "https://t.me/CMEPT0HOCHbIU";

    readonly PackLocator _pack = new();
    readonly Settings _settings = Settings.Load();
    readonly Logger _log = new();
    bool _busy;

    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    public ShellWindow()
    {
        Loc.Set("ru");
        SoundFx.Enabled = _settings.Sound;
        InitializeComponent();
        _log.Entry += (text, level) => Push(new JsonObject { ["ev"] = "log", ["text"] = text, ["level"] = level.ToString().ToLowerInvariant() });
        StateChanged += (_, _) => Push(new JsonObject { ["ev"] = "win", ["max"] = WindowState == WindowState.Maximized });
        Loaded += async (_, _) => await StartAsync();
    }

    // ------------------------------------------------------------ запуск WebView2
    static string WebDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XEOKA-Pack", "web");

    static void ExtractWeb()
    {
        var asm = Assembly.GetExecutingAssembly();
        var dir = WebDir;
        Directory.CreateDirectory(dir);
        foreach (var name in asm.GetManifestResourceNames())
        {
            const string prefix = "web/";
            if (!name.StartsWith(prefix, StringComparison.Ordinal)) continue;
            var rel = name.Substring(prefix.Length).Replace('\\', '/');
            var target = Path.Combine(dir, rel.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using var s = asm.GetManifestResourceStream(name)!;
            using var f = File.Create(target);
            s.CopyTo(f);
        }
    }

    async Task StartAsync()
    {
        try
        {
            ExtractWeb();
            var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XEOKA-Pack", "webview");
            Directory.CreateDirectory(data);
            var env = await CoreWebView2Environment.CreateAsync(null, data);
            await Web.EnsureCoreWebView2Async(env);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Не удалось запустить интерфейс: нужен Microsoft Edge WebView2 Runtime (в Windows 11 он есть по умолчанию).\n\nУстановить: https://go.microsoft.com/fwlink/p/?LinkId=2124703\n\n" + ex.Message,
                "xeoka tech", MessageBoxButton.OK, MessageBoxImage.Error);
            Application.Current.Shutdown();
            return;
        }

        var c = Web.CoreWebView2;
        c.Settings.AreDevToolsEnabled = false;
        c.Settings.AreDefaultContextMenusEnabled = false;
        c.Settings.IsStatusBarEnabled = false;
        c.Settings.IsZoomControlEnabled = false;
        c.Settings.IsPinchZoomEnabled = false;
        c.Settings.IsSwipeNavigationEnabled = false;
        c.Settings.AreBrowserAcceleratorKeysEnabled = false;
        c.Settings.AreDefaultScriptDialogsEnabled = false;
        c.SetVirtualHostNameToFolderMapping(Host, WebDir, CoreWebView2HostResourceAccessKind.Deny);
        c.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://" + Host + "/", StringComparison.OrdinalIgnoreCase)) e.Cancel = true; };
        c.NewWindowRequested += (_, e) => e.Handled = true;
        c.WebMessageReceived += OnMessage;
        c.Navigate("https://" + Host + "/index.html");
    }

    // ------------------------------------------------------------ обмен сообщениями
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    void Push(JsonObject o)
    {
        try
        {
            var txt = o.ToJsonString();
            Dispatcher.BeginInvoke(() => { try { Web.CoreWebView2?.PostWebMessageAsJson(txt); } catch { } });
        }
        catch { }
    }

    void Reply(int id, object? data = null, string? error = null)
    {
        var o = new JsonObject { ["id"] = id, ["ok"] = error == null };
        if (error != null) o["error"] = error;
        else if (data != null) o["data"] = JsonSerializer.SerializeToNode(data, Json);
        Push(o);
    }

    async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        JsonNode? msg;
        try { msg = JsonNode.Parse(e.WebMessageAsJson); } catch { return; }
        if (msg == null) return;
        int id = msg["id"]?.GetValue<int>() ?? 0;
        string cmd = msg["cmd"]?.GetValue<string>() ?? "";
        try
        {
            var data = await Handle(cmd, msg);
            if (id != 0) Reply(id, data);
        }
        catch (Exception ex)
        {
            _log.Err(ex.Message);
            if (id != 0) Reply(id, error: ex.Message);
        }
    }

    bool Licensed => License.Check().Valid;

    static string S(JsonNode m, string k) => m[k]?.GetValue<string>() ?? "";

    async Task<object?> Handle(string cmd, JsonNode m)
    {
        switch (cmd)
        {
            case "init":
            {
                var lic = License.Check();
                _ = Task.Run(() => { _pack.AutoDetect(); Push(PackEvent()); });
                return new
                {
                    version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "",
                    licensed = lic.Valid,
                    licNote = lic.Note,
                    licExpires = lic.Expires?.ToString("dd.MM.yyyy"),
                    hwid = License.HardwareId(),
                    tg = TgUrl,
                    pack = new { found = _pack.IsPack, root = _pack.Root },
                    settings = new { theme = _settings.UiTheme, anim = _settings.Anim, sound = _settings.Sound },
                    tweaks = Tweaks.All.Select(t => new { id = t.Id, g = GroupOf(t.Id), i = IconOf(t.Id), n = t.Title, d = t.Desc, r = RiskOf(t.Id), on = t.Default, hasCheck = t.Check != null }),
                    tools = ToolDefs.All.Select((t, i) => new { idx = i, g = ToolGroup(t), t = t.Title, d = t.Desc, r = ToolRisk(t), confirm = ToolConfirm(t) }),
                };
            }
            case "specs":
            {
                var (cards, line) = await Task.Run(() => Specs.Collect(_pack));
                return new { cards, line };
            }
            case "states":
                return await Task.Run(StatesNow);
            case "activate":
            {
                if (License.Activate(S(m, "key"), out var err)) { SoundFx.Chime(); return new { ok = true }; }
                return new { ok = false, error = err };
            }
            case "apply":
                return await ApplyAsync(m);
            case "revert":
                return await RevertAsync();
            case "tool":
                return await ToolAsync(m["idx"]?.GetValue<int>() ?? -1);
            case "openTg":
                Sys.OpenUrl(TgUrl); return null;
            case "openFolder":
                if (S(m, "what") == "logs") Sys.OpenFolder(Paths.DataDir); else Sys.OpenFolder(_pack.Root);
                return null;
            case "pickPack":
            {
                var dlg = new Microsoft.Win32.OpenFolderDialog { Title = "Выберите папку, распакованную из архива пака" };
                if (dlg.ShowDialog(this) != true) return new { picked = false };
                if (!PackLocator.IsPackRoot(dlg.FolderName)) return new { picked = true, ok = false };
                _pack.SetRoot(dlg.FolderName);
                _ = Task.Run(() => ToolLauncher.UnblockTree(_pack.Root));
                Push(PackEvent());
                return new { picked = true, ok = true, root = _pack.Root };
            }
            case "support":
            {
                var sum = await Task.Run(() => SysInfo.Collect(_pack));
                var st = await Task.Run(StatesNow);
                var rows = Tweaks.All.Select(t => (t.Title, st.FirstOrDefault(x => x.id == t.Id)?.st ?? "Unknown")).ToList();
                var path = await Task.Run(() => Support.Build(_pack, sum, rows, _settings));
                try { Process.Start("explorer.exe", "/select,\"" + path + "\""); } catch { }
                return new { path };
            }
            case "set":
            {
                var k = S(m, "k");
                if (k == "theme") _settings.UiTheme = S(m, "v");
                else if (k == "anim") _settings.Anim = m["v"]?.GetValue<bool>() ?? true;
                else if (k == "sound") { _settings.Sound = m["v"]?.GetValue<bool>() ?? true; SoundFx.Enabled = _settings.Sound; }
                _settings.Save();
                return null;
            }
            case "sfx":
            {
                var n = S(m, "name");
                if (n == "chime") SoundFx.Chime(); else if (n == "deep") SoundFx.Deep(); else SoundFx.Tap();
                return null;
            }
            case "reboot":
                try { Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 5 /c \"xeoka tech\"") { CreateNoWindow = true, UseShellExecute = false }); } catch { }
                return null;
            case "win":
                WindowOp(S(m, "op"));
                return null;
        }
        return null;
    }

    JsonObject PackEvent() => new() { ["ev"] = "pack", ["found"] = _pack.IsPack, ["root"] = _pack.Root };

    // ------------------------------------------------------------ окно
    void WindowOp(string op)
    {
        var h = new WindowInteropHelper(this).Handle;
        switch (op)
        {
            case "min": WindowState = WindowState.Minimized; break;
            case "max": WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; break;
            case "close": Close(); break;
            case "drag": NcDrag(h, 2); break;
            case "l": NcDrag(h, 10); break;
            case "r": NcDrag(h, 11); break;
            case "t": NcDrag(h, 12); break;
            case "tl": NcDrag(h, 13); break;
            case "tr": NcDrag(h, 14); break;
            case "b": NcDrag(h, 15); break;
            case "bl": NcDrag(h, 16); break;
            case "br": NcDrag(h, 17); break;
        }
    }

    static void NcDrag(IntPtr h, int hit)
    {
        ReleaseCapture();
        SendMessage(h, 0x00A1, (IntPtr)hit, IntPtr.Zero);
    }

    // ------------------------------------------------------------ твики
    static string GroupOf(string id) => id switch
    {
        "power" or "devpow" => "power",
        "prio" or "timer" or "mmcss" => "cpu",
        "net" => "net",
        _ => "game",
    };
    static string IconOf(string id) => id switch
    {
        "power" => "power", "devpow" => "plug", "prio" => "cpu", "timer" => "timer", "mmcss" => "layers",
        "net" => "net", _ => "gamepad",
    };
    static string RiskOf(string id) => id == "devpow" ? "warn" : "ok";

    record StateRow(string id, string st);

    List<StateRow> StatesNow()
    {
        var ctx = new TweakContext { Log = new Logger(), Pack = _pack, State = new RunState() };
        return Tweaks.All.Select(t =>
        {
            TweakState s;
            try { s = t.Check == null ? TweakState.Unknown : t.Check(ctx); } catch { s = TweakState.Unknown; }
            return new StateRow(t.Id, s.ToString());
        }).ToList();
    }

    async Task<object?> ApplyAsync(JsonNode m)
    {
        if (_busy) throw new InvalidOperationException("Уже выполняется операция.");
        if (!Licensed) throw new InvalidOperationException("Нужен ключ активации.");
        if (!_pack.IsPack) throw new InvalidOperationException("nopack");
        var ids = (m["ids"] as JsonArray)?.Select(x => x?.GetValue<string>() ?? "").ToHashSet() ?? new HashSet<string>();
        var sel = Tweaks.All.Where(t => ids.Contains(t.Id)).ToList();
        if (sel.Count == 0) throw new InvalidOperationException("Ничего не выбрано.");
        _busy = true;
        SoundFx.Deep();
        try
        {
            var res = await Task.Run(() => Operations.Apply(sel, _log, _pack,
                p => Push(new JsonObject { ["ev"] = "progress", ["p"] = p }),
                (n, total, title) => Push(new JsonObject { ["ev"] = "step", ["n"] = n, ["total"] = total, ["title"] = title })));
            if (res.Fail == 0) SoundFx.Chime();
            return new { ok = res.Ok, fail = res.Fail };
        }
        finally { _busy = false; }
    }

    async Task<object?> RevertAsync()
    {
        if (_busy) throw new InvalidOperationException("Уже выполняется операция.");
        if (!Licensed) throw new InvalidOperationException("Нужен ключ активации.");
        _busy = true;
        try { await Task.Run(() => Operations.Revert(_log)); return new { ok = 1, fail = 0 }; }
        finally { _busy = false; }
    }

    // ------------------------------------------------------------ инструменты
    static string ToolGroup(ToolDef t)
    {
        if (t.Kind == ToolKind.BiosConfig || t.TitleRu.StartsWith("BIOS", StringComparison.Ordinal)) return "bios";
        if (t.Kind == ToolKind.Nvidia || System.Text.RegularExpressions.Regex.IsMatch(t.TitleRu, "DDU|NVCleanstall|CRU|драйвера сети|NVIDIA")) return "drv";
        return "sys";
    }
    static string ToolRisk(ToolDef t) =>
        t.Kind == ToolKind.Services ? "bad" : t.Risk ? "warn" : t.Kind is ToolKind.ActivateWindows or ToolKind.RemoveEdge ? "warn" : "ok";

    static string? ToolConfirm(ToolDef t) => t.Kind switch
    {
        ToolKind.Services => "Будут отключены службы: DPS, Themes, Spooler (печать), WSearch (поиск), LanmanWorkstation и Netlogon (сетевые папки, домен), SessionEnv (удалённый рабочий стол), edgeupdate, GameInputSvc и другие.\n\nОтключение Themes может испортить внешний вид Windows, без Spooler не будет печати. Откат кнопкой отката не поддерживается.",
        ToolKind.ActivateWindows => "Скачивается и запускается сторонний скрипт активации Windows с get.activated.win (Microsoft Activation Scripts). Это не наш код — мы не можем за него отвечать. Запускается со скрытым окном PowerShell.",
        ToolKind.RemoveEdge => "Edge будет полностью удалён: его же скрытый деинсталлятор, плюс зачистка ярлыков, остаточных ключей реестра и папки приложения. Автообновление отключится. Также будут стёрты профили Edge всех пользователей на этом ПК — история, кэш, сохранённые пароли и закладки, это необратимо. Пока не поставите другой браузер, часть ссылок и PDF может открываться не сразу. WebView2 (нужен другим программам, в том числе этой) не трогаем.",
        _ => null,
    };

    async Task<object?> ToolAsync(int idx)
    {
        if (!Licensed) throw new InvalidOperationException("Нужен ключ активации.");
        if (idx < 0 || idx >= ToolDefs.All.Count) throw new InvalidOperationException("Нет такого инструмента.");
        var def = ToolDefs.All[idx];
        if (ToolLauncher.Resolve(_pack, def) == null) return new { found = false, file = def.File };
        SoundFx.Tap();
        await Task.Run(() => ToolLauncher.Launch(_pack, def));
        return new { found = true };
    }
}
