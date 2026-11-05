using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace XeokaPack.Core;

public sealed record LicenseInfo(bool Valid, string? Note, DateTime? Expires, string Reason);

/// <summary>
/// Лицензия привязана к железу (ID процессора + серийник материнской платы), подписана RSA.
/// Публичный ключ лежит прямо в коде — им можно только ПРОВЕРИТЬ подпись, подделать лицензию им нельзя.
/// Подписывает лицензии только инструмент tools/LicenseGen, у которого есть закрытый ключ (он не в этом репозитории).
/// </summary>
public static class License
{
    const string PublicKeyPem = "-----BEGIN PUBLIC KEY-----\nMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA7KXOHZTWizen4oGX6piB\nJeDtfgOeFsQKIS0Z3XLL+DdGJIQg/ER7WOyGOCY7Wh7Utnk3vmb08JynmAsITUUz\nwyp6Cfia6c0fS4k3csrFgAeDtI9/h7+B4wV3/5hDL2KDc6Y40wk0IIg75I+CbegM\nnp3flcLcWuqFyC0GnpSj9wzAKRNK8cu30zAZmn9f13/Xt3Wr9lwmu/ptWCLuFINW\nI0B4WsXHVJUZBxEYCXgc69aIXlwDa0YBeydBwMid2VZD1kdqhBNmvjT4qvDgiJxt\nWTdAxwjdAdoHe6IYWJgDryK5aKKvDWtRrSYNgWFxQRKAUZexv0EcJOTN1Qiq4Ilv\nmyJQCRC46jDaXfkfqNxi+apKraxgcejG2ywAwAq8ROQXsp+DjbVgDlNCzhaReDHR\nHR/vK9EKRA9McYJ5q9k49g49KuZRBOwncRHcIRItm2Ibi+ONwCd31Q7wB4rfBmhh\n65c8627wYyh0mlw7FFqnHxqDk8JyGmZdnG7XTaMojaB7AgMBAAE=\n-----END PUBLIC KEY-----";

    public static string FilePath => Path.Combine(Paths.DataDir, "license.lic");

    // ---------------------------------------------------------- hardware id
    static string? _hw;

    /// <summary>ID этого компьютера: SHA-256 от ID процессора и серийника материнской платы, в виде XXXX-XXXX-XXXX-XXXX.</summary>
    public static string HardwareId()
    {
        if (_hw != null) return _hw;
        string cpu = "", board = "";
        try
        {
            var r = Sys.PowerShell(
                "$c=(Get-CimInstance Win32_Processor).ProcessorId -join ';';" +
                "$b=(Get-CimInstance Win32_BaseBoard).SerialNumber -join ';';" +
                "Write-Output ($c+'|'+$b)");
            var parts = r.Output.Trim().Split('|');
            cpu = parts.Length > 0 ? parts[0].Trim() : "";
            board = parts.Length > 1 ? parts[1].Trim() : "";
        }
        catch { }
        var raw = "XEOKA-HWID-v1|" + cpu + "|" + board;
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        var hex = Convert.ToHexString(hash)[..20];
        _hw = string.Join("-", Enumerable.Range(0, 5).Select(i => hex.Substring(i * 4, 4)));
        return _hw;
    }

    // ---------------------------------------------------------- проверка
    sealed record Payload(string Hw, string? Note, string? Exp);
    static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public static LicenseInfo Check()
    {
        string? code = null;
        try { if (File.Exists(FilePath)) code = File.ReadAllText(FilePath).Trim(); }
        catch { return new(false, null, null, "io"); }
        if (string.IsNullOrWhiteSpace(code)) return new(false, null, null, "missing");
        return Verify(code);
    }

    public static LicenseInfo Verify(string code)
    {
        try
        {
            var parts = code.Trim().Split('.');
            if (parts.Length != 2) return new(false, null, null, "format");
            var payloadBytes = Convert.FromBase64String(Pad(parts[0]));
            var sig = Convert.FromBase64String(Pad(parts[1]));

            using var rsa = RSA.Create();
            rsa.ImportFromPem(PublicKeyPem);
            if (!rsa.VerifyData(payloadBytes, sig, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
                return new(false, null, null, "signature");

            var p = JsonSerializer.Deserialize<Payload>(payloadBytes, JsonOpts) ?? throw new Exception();
            if (!string.Equals(p.Hw, HardwareId(), StringComparison.OrdinalIgnoreCase))
                return new(false, p.Note, null, "hardware");

            DateTime? exp = string.IsNullOrEmpty(p.Exp) ? null : DateTime.Parse(p.Exp, null, System.Globalization.DateTimeStyles.RoundtripKind);
            if (exp != null && exp < DateTime.UtcNow) return new(false, p.Note, exp, "expired");

            return new(true, p.Note, exp, "ok");
        }
        catch { return new(false, null, null, "parse"); }
    }

    public static bool Activate(string code, out string error)
    {
        error = "";
        var res = Verify(code.Trim());
        if (!res.Valid)
        {
            error = res.Reason switch
            {
                "hardware" => Loc.L("Этот код выдан для другого компьютера.", "This code was issued for a different computer."),
                "expired" => Loc.L("Срок действия кода истёк.", "This code has expired."),
                "signature" => Loc.L("Код повреждён или недействителен.", "The code is corrupted or invalid."),
                _ => Loc.L("Неверный код активации.", "Invalid activation code."),
            };
            return false;
        }
        try
        {
            Directory.CreateDirectory(Paths.DataDir);
            File.WriteAllText(FilePath, code.Trim());
            return true;
        }
        catch (Exception ex) { error = ex.Message; return false; }
    }

    static string Pad(string b64)
    {
        b64 = b64.Replace('-', '+').Replace('_', '/');
        return b64.PadRight(b64.Length + (4 - b64.Length % 4) % 4, '=');
    }
}
