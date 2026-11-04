using System.Windows.Data;
using System.Windows.Markup;
using XeokaPack.Core;

namespace XeokaPack;

/// <summary>{local:T ключ} — строка интерфейса на выбранном языке (обновляется на лету).</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TExtension : MarkupExtension
{
    public string Key { get; set; } = "";
    public TExtension() { }
    public TExtension(string key) { Key = key; }
    public override object ProvideValue(IServiceProvider serviceProvider)
    {
        var b = new Binding("[" + Key + "]") { Source = Loc.I, Mode = BindingMode.OneWay };
        return b.ProvideValue(serviceProvider);
    }
}
