using System.IO;
using System.Net.Http;

namespace XeokaPack.Core;

/// <summary>
/// Список отозванных ключей: revoked.txt в репозитории (по одному ID ключа или ID компьютера в строке, после # комментарий).
/// Подтягивается при запуске; если сети нет, берётся копия с прошлого раза.
/// </summary>
public static class Revocation
{
    const string Url = "https://raw.githubusercontent.com/xeoka/xeoka-optimization/main/revoked.txt";
    static HashSet<string> _set = new();
    static string Cache => Path.Combine(Paths.DataDir, "revoked.cache");

    public static bool IsRevoked(string? id, string? hw)
    {
        var s = _set;
        return (!string.IsNullOrEmpty(id) && s.Contains(id.Trim().ToUpperInvariant()))
            || (!string.IsNullOrEmpty(hw) && s.Contains(hw.Trim().ToUpperInvariant()));
    }

    static HashSet<string> Parse(string text)
    {
        var h = new HashSet<string>();
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Split('#')[0].Trim().ToUpperInvariant();
            if (line.Length > 0) h.Add(line);
        }
        return h;
    }

    /// <summary>Обновляет список (до 4 секунд ожидания). Без сети используется последняя сохранённая копия.</summary>
    public static async Task RefreshAsync()
    {
        try { if (File.Exists(Cache)) _set = Parse(File.ReadAllText(Cache)); } catch { }
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("xeoka-tech");
            var text = await http.GetStringAsync(Url + "?t=" + DateTime.UtcNow.Ticks);
            _set = Parse(text);
            try { File.WriteAllText(Cache, text); } catch { }
        }
        catch { }
    }
}
