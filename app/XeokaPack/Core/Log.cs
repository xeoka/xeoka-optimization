using System.IO;
using System.Text;

namespace XeokaPack.Core;

public enum LogLevel { Info, Ok, Warn, Err, Dim, Head }

public static class Paths
{
    public static string DataDir { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "XEOKA-Pack");
    static Paths() { try { Directory.CreateDirectory(DataDir); } catch { } }
}

/// <summary>Журнал: событие для интерфейса + файл на диске.</summary>
public sealed class Logger
{
    public event Action<string, LogLevel>? Entry;
    readonly object _lock = new();
    readonly string _file = Path.Combine(Paths.DataDir, "log-" + DateTime.Now.ToString("yyyyMMdd") + ".txt");

    public void Write(string text, LogLevel level = LogLevel.Info)
    {
        try { lock (_lock) File.AppendAllText(_file, DateTime.Now.ToString("HH:mm:ss") + " " + text + Environment.NewLine, Encoding.UTF8); } catch { }
        Entry?.Invoke(text, level);
    }
    public void Info(string t) => Write(t, LogLevel.Info);
    public void Ok(string t) => Write(t, LogLevel.Ok);
    public void Warn(string t) => Write(t, LogLevel.Warn);
    public void Err(string t) => Write(t, LogLevel.Err);
    public void Dim(string t) => Write(t, LogLevel.Dim);
    public void Head(string t) => Write(t, LogLevel.Head);
}
