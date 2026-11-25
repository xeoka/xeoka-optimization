using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace XeokaPack.Core;

/// <summary>Расшифровка pack.xkp (AES-256-GCM, внутри zip) во временную папку на время работы программы.</summary>
public static class PackVault
{
    static string TmpBase => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XEOKA-Pack", "pk");

    /// <summary>Удаляет остатки прошлых запусков (если программа закрылась аварийно).</summary>
    public static void CleanStale()
    {
        try
        {
            if (!Directory.Exists(TmpBase)) return;
            foreach (var d in Directory.EnumerateDirectories(TmpBase))
                try { Directory.Delete(d, true); } catch { }
        }
        catch { }
    }

    public static void Cleanup(string? dir)
    {
        if (string.IsNullOrEmpty(dir)) return;
        try { Directory.Delete(dir, true); } catch { }
    }

    public static string Extract(string vaultFile, byte[] key)
    {
        var data = File.ReadAllBytes(vaultFile);
        var magic = Encoding.ASCII.GetBytes("XKP1");
        if (data.Length < 33 || !data.AsSpan(0, 4).SequenceEqual(magic)) throw new InvalidDataException("not a vault");
        var plain = new byte[data.Length - 32];
        using (var g = new AesGcm(key, 16))
            g.Decrypt(data.AsSpan(4, 12), data.AsSpan(32), data.AsSpan(16, 16), plain, magic);
        var dir = Path.Combine(TmpBase, Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(dir);
        using var ms = new MemoryStream(plain);
        using var za = new ZipArchive(ms, ZipArchiveMode.Read, false, Encoding.UTF8);
        za.ExtractToDirectory(dir);
        return dir;
    }
}
