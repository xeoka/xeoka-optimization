using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// Генератор лицензий и шифратор пака xeoka tech.
// Держи private.pem только у себя, никогда не выкладывай и не коммить в репозиторий.
//
// Лицензия:
//   xeoka-license-gen --key private.pem --hw XXXX-XXXX-XXXX-XXXX-XXXX [--note "имя покупателя"] [--days 0] [--out license.lic]
// Шифрование пака (делает сборка, вручную не нужно):
//   xeoka-license-gen pack --key private.pem --dir папка_с_паком --out pack.xkp
//
// Ключ шифрования пака выводится из private.pem, отдельного секрета заводить не нужно.
// В каждую лицензию кладётся этот ключ, зашифрованный под ID компьютера покупателя:
// без действующей лицензии для этого ПК пак (pack.xkp) расшифровать нельзя.

string mode = args.Length > 0 && args[0] == "pack" ? "pack" : "license";
string? keyPath = null, hw = null, note = null, outPath = null, dir = null;
int days = 0;
for (int i = mode == "pack" ? 1 : 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--key": keyPath = args[++i]; break;
        case "--hw": hw = args[++i]; break;
        case "--note": note = args[++i]; break;
        case "--days": days = int.Parse(args[++i]); break;
        case "--out": outPath = args[++i]; break;
        case "--dir": dir = args[++i]; break;
    }
}

if (keyPath == null || (mode == "license" && hw == null) || (mode == "pack" && (dir == null || outPath == null)))
{
    Console.WriteLine("Использование:");
    Console.WriteLine("  xeoka-license-gen --key private.pem --hw XXXX-XXXX-XXXX-XXXX-XXXX [--note \"имя\"] [--days 0] [--out license.lic]");
    Console.WriteLine("  xeoka-license-gen pack --key private.pem --dir <папка пака> --out pack.xkp");
    return 1;
}

using var rsa = RSA.Create();
rsa.ImportFromPem(File.ReadAllText(keyPath));
// Ключ пака: HMAC-SHA256 от закрытого ключа. Тот же закрытый ключ всегда даёт тот же ключ пака.
var packKey = HMACSHA256.HashData(rsa.ExportPkcs8PrivateKey(), Encoding.UTF8.GetBytes("xeoka-pack-key-v1"));

if (mode == "pack")
{
    using var zip = new MemoryStream();
    using (var za = new ZipArchive(zip, ZipArchiveMode.Create, true, Encoding.UTF8))
    {
        var root = Path.GetFullPath(dir!);
        foreach (var f in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            var rel = Path.GetRelativePath(root, f).Replace('\\', '/');
            za.CreateEntryFromFile(f, rel, CompressionLevel.Optimal);
        }
    }
    var plain = zip.ToArray();
    var magic = Encoding.ASCII.GetBytes("XKP1");
    var nonce = RandomNumberGenerator.GetBytes(12);
    var tag = new byte[16];
    var ct = new byte[plain.Length];
    using (var g = new AesGcm(packKey, 16)) g.Encrypt(nonce, plain, ct, tag, magic);
    using var fs = File.Create(outPath!);
    fs.Write(magic); fs.Write(nonce); fs.Write(tag); fs.Write(ct);
    Console.WriteLine($"Пак зашифрован: {outPath} ({fs.Length / 1048576} МБ)");
    return 0;
}

hw = hw!.Trim().ToUpperInvariant();
// Ключ пака, зашифрованный под этот компьютер: nonce(12) + tag(16) + шифртекст
var wrapKey = SHA256.HashData(Encoding.UTF8.GetBytes("xeoka-wrap|" + hw));
var wn = RandomNumberGenerator.GetBytes(12);
var wt = new byte[16];
var wc = new byte[packKey.Length];
using (var g = new AesGcm(wrapKey, 16)) g.Encrypt(wn, packKey, wc, wt);
var pk = Convert.ToBase64String(wn.Concat(wt).Concat(wc).ToArray());

var id = Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant();
var payload = JsonSerializer.SerializeToUtf8Bytes(new
{
    id,
    hw,
    note,
    exp = days > 0 ? DateTime.UtcNow.AddDays(days).ToString("o") : null,
    pk
});
var sig = rsa.SignData(payload, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
var code = Convert.ToBase64String(payload) + "." + Convert.ToBase64String(sig);

Console.WriteLine();
Console.WriteLine($"ID ключа: {id}  (для отзыва)   ID компьютера: {hw}   Срок: {(days > 0 ? days + " дн." : "бессрочно")}");
Console.WriteLine();
Console.WriteLine("Код активации (отправь покупателю):");
Console.WriteLine();
Console.WriteLine(code);
Console.WriteLine();
if (outPath != null)
{
    File.WriteAllText(outPath, code);
    Console.WriteLine("Сохранено в " + outPath);
}
return 0;
