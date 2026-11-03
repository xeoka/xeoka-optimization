using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace XeokaPack.Core;

public enum RegKind { DWord, String, Delete, Unsupported }

public sealed class RegOp
{
    public string Hive = "";
    public string Sub = "";
    public string Name = "";
    public RegKind Kind;
    public object? Value;
}

/// <summary>Разбор текстовых .reg (DWORD, строки, удаление значения).</summary>
public static class RegFile
{
    static readonly Regex KeyRx = new(@"^\[(-?)(HKEY_[A-Z_]+)\\?(.*)\]$", RegexOptions.Compiled);
    static readonly Regex DefRx = new(@"^@\s*=\s*(.+)$", RegexOptions.Compiled);
    static readonly Regex NamedRx = new(@"^""((?:[^""\\]|\\.)*)""\s*=\s*(.+)$", RegexOptions.Compiled);
    static readonly Regex DwordRx = new(@"^dword:([0-9a-fA-F]{1,8})$", RegexOptions.Compiled);
    static readonly Regex StrRx = new(@"^""((?:[^""\\]|\\.)*)""$", RegexOptions.Compiled);
    static readonly Regex Unesc = new(@"\\(.)", RegexOptions.Compiled);
    static readonly Regex Zw = new("[​-‍﻿]", RegexOptions.Compiled);

    public static List<RegOp> ParseFile(string path)
    {
        using var sr = new StreamReader(path, Encoding.UTF8, true);
        return Parse(sr.ReadToEnd());
    }

    public static List<RegOp> Parse(string text)
    {
        var ops = new List<RegOp>();
        string? hive = null, sub = null;
        foreach (var raw in text.Split('\n'))
        {
            var l = raw.Trim();
            if (l.Length == 0 || l.StartsWith(';') || l.StartsWith("Windows Registry Editor")) continue;
            var km = KeyRx.Match(l);
            if (km.Success)
            {
                if (km.Groups[1].Value == "-") { hive = null; continue; }
                hive = km.Groups[2].Value; sub = km.Groups[3].Value; continue;
            }
            if (hive == null) continue;
            string name, rest;
            var dm = DefRx.Match(l);
            var nm = NamedRx.Match(l);
            if (dm.Success) { name = ""; rest = dm.Groups[1].Value; }
            else if (nm.Success) { name = Zw.Replace(Unesc.Replace(nm.Groups[1].Value, "$1"), ""); rest = nm.Groups[2].Value; }
            else continue;
            rest = rest.Trim();
            var op = new RegOp { Hive = hive, Sub = sub ?? "", Name = name };
            var w = DwordRx.Match(rest);
            var s = StrRx.Match(rest);
            if (w.Success) { op.Kind = RegKind.DWord; op.Value = unchecked((int)Convert.ToUInt32(w.Groups[1].Value, 16)); }
            else if (s.Success) { op.Kind = RegKind.String; op.Value = Unesc.Replace(s.Groups[1].Value, "$1"); }
            else if (rest == "-") op.Kind = RegKind.Delete;
            else op.Kind = RegKind.Unsupported;
            ops.Add(op);
        }
        return ops;
    }
}
