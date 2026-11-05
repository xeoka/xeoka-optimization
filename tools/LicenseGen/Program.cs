using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// Генератор лицензий XEOKA OPTIMIZATION.
// Держи private.pem только у себя, никогда не выкладывай и не коммить в репозиторий.
//
// Использование:
//   xeoka-license-gen --key private.pem --hw XXXX-XXXX-XXXX-XXXX-XXXX [--note "имя покупателя"] [--days 0] [--out license.lic]
//
// hw — это "ID этого компьютера", его покупатель видит на экране активации и присылает тебе.
// --days 0 (по умолчанию) = бессрочная лицензия. --days 365 = на год.

string? keyPath = null, hw = null, note = null, outPath = null;
int days = 0;

for (int i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--key": keyPath = args[++i]; break;
        case "--hw": hw = args[++i]; break;
        case "--note": note = args[++i]; break;
        case "--days": days = int.Parse(args[++i]); break;
        case "--out": outPath = args[++i]; break;
    }
}

if (keyPath == null || hw == null)
{
    Console.WriteLine("Использование: xeoka-license-gen --key private.pem --hw XXXX-XXXX-XXXX-XXXX-XXXX [--note \"имя\"] [--days 0] [--out license.lic]");
    return 1;
}

hw = hw.Trim().ToUpperInvariant();
var payload = JsonSerializer.SerializeToUtf8Bytes(new
{
    hw,
    note,
    exp = days > 0 ? DateTime.UtcNow.AddDays(days).ToString("o") : null
});

using var rsa = RSA.Create();
rsa.ImportFromPem(File.ReadAllText(keyPath));
var sig = rsa.SignData(payload, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);

var code = Convert.ToBase64String(payload) + "." + Convert.ToBase64String(sig);

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
