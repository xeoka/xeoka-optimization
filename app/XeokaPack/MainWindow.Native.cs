using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace XeokaPack;

/// <summary>Окно без рамки при разворачивании не должно залезать под панель задач.</summary>
public partial class MainWindow
{
    const int WM_GETMINMAXINFO = 0x0024;
    const uint MONITOR_DEFAULTTONEAREST = 2;

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct MINMAXINFO { public POINT ptReserved, ptMaxSize, ptMaxPosition, ptMinTrackSize, ptMaxTrackSize; }
    [StructLayout(LayoutKind.Sequential)]
    struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public int dwFlags; }

    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO mi);

    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT r);

    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    const int DWMWCP_ROUND = 2;

    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    const int GWL_STYLE = -16;
    const int WS_MAXIMIZEBOX = 0x00010000;

    /// <summary>
    /// Снимает системный флаг "кнопка максимизации" у окна. У нас своя кнопка разворачивания
    /// (WindowState мы переключаем в коде — она продолжает работать как раньше), а этот флаг
    /// у Windows 11 отвечает за автоматическую всплывающую подсказку Snap Layout (мелкие
    /// квадраты-раскладки) при наведении на область, которую Windows считает "кнопкой максимизации" —
    /// она вылезала поверх нашей кастомной кнопки и выглядела как лишние "квадратики" в шапке.
    /// </summary>
    void DisableSnapLayoutFlyout()
    {
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            var style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, style & ~WS_MAXIMIZEBOX);
        }
        catch { }
    }

    /// <summary>Лёгкое скругление углов окна штатными средствами Windows 11 (на Windows 10 просто ничего не делает).</summary>
    void ApplyRoundedCorners()
    {
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            int pref = DWMWCP_ROUND;
            DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int));
        }
        catch { }
    }

    /// <summary>При разворачивании окно без рамки выступает за экран на толщину рамки: сдвигаем содержимое внутрь, чтобы кнопки не обрезались.</summary>
    void UpdateMaxMargin()
    {
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            if (WindowState != WindowState.Maximized || _fullscreen) { Shell.Margin = new Thickness(0); return; }
            var mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
            if (mon == IntPtr.Zero || !GetMonitorInfo(mon, ref mi) || !GetWindowRect(hwnd, out var r)) return;
            var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(this);
            Shell.Margin = new Thickness(
                Math.Max(0, mi.rcWork.left - r.left) / dpi.DpiScaleX,
                Math.Max(0, mi.rcWork.top - r.top) / dpi.DpiScaleY,
                Math.Max(0, r.right - mi.rcWork.right) / dpi.DpiScaleX,
                Math.Max(0, r.bottom - mi.rcWork.bottom) / dpi.DpiScaleY);
        }
        catch { }
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        if (PresentationSource.FromVisual(this) is HwndSource src) src.AddHook(WndProc);
        ApplyRoundedCorners();
        DisableSnapLayoutFlyout();
    }

    IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_GETMINMAXINFO)
        {
            try
            {
                var mmi = Marshal.PtrToStructure<MINMAXINFO>(lParam);
                var mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                if (mon != IntPtr.Zero)
                {
                    var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
                    if (GetMonitorInfo(mon, ref mi))
                    {
                        mmi.ptMaxPosition.x = mi.rcWork.left - mi.rcMonitor.left;
                        mmi.ptMaxPosition.y = mi.rcWork.top - mi.rcMonitor.top;
                        mmi.ptMaxSize.x = mi.rcWork.right - mi.rcWork.left;
                        mmi.ptMaxSize.y = mi.rcWork.bottom - mi.rcWork.top;
                        Marshal.StructureToPtr(mmi, lParam, true);
                    }
                }
            }
            catch { }
            handled = true;
        }
        else if (msg == 0x0046 /* WM_WINDOWPOSCHANGED */) Dispatcher.BeginInvoke(UpdateMaxMargin, System.Windows.Threading.DispatcherPriority.Render);
        else if (msg == 0x0231 /* WM_ENTERSIZEMOVE */) PauseBackground();
        else if (msg == 0x0232 /* WM_EXITSIZEMOVE */) ResumeBackground();
        return IntPtr.Zero;
    }
}
