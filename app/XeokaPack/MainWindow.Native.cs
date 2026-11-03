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

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        if (PresentationSource.FromVisual(this) is HwndSource src) src.AddHook(WndProc);
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
        return IntPtr.Zero;
    }
}
