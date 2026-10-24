// Read-only ECMA-335/IL inventory. No game assembly is loaded for execution.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

public static class AssemblySnapshot
{
    static bool Redirected(string name) { return name.StartsWith("UnityEngine", StringComparison.Ordinal) || (name.StartsWith("Unity.",StringComparison.Ordinal) && name != "Unity.Newtonsoft.Json") || name == "Assembly-CSharp-firstpass"; }
    static string DeclaringName(ITypeDefOrRef type)
    {
        var spec=type as TypeSpec;
        var inst=spec == null ? null : spec.TypeSig as GenericInstSig;
        return inst == null ? type.FullName : inst.GenericType.FullName;
    }
    public static string AuditReferences(string gamePath, string stubPath, string output)
    {
        using(var game=ModuleDefMD.Load(gamePath))
        using(var stubs=ModuleDefMD.Load(stubPath))
        using(var w=new StreamWriter(output,false,new UTF8Encoding(false)))
        {
            w.WriteLine("kind\tname\told_assembly\tmatch\tstub_definition");
            var types=stubs.GetTypes().ToDictionary(t=>t.FullName);
            var comparer=new SigComparer(SigComparerOptions.DontCompareTypeScope);
            int found=0,missing=0;
            foreach(var t in game.GetTypeRefs())
            {
                string asm=t.DefinitionAssembly == null ? "" : t.DefinitionAssembly.Name.String;
                if(!Redirected(asm)) continue;
                bool match=types.ContainsKey(t.FullName);
                w.WriteLine("type\t"+Cell(t.FullName)+"\t"+asm+"\t"+(match?"type":"unmatched")+"\t"+(match?Cell(t.FullName):""));
            }
            foreach(var m in game.GetMemberRefs())
            {
                string asm=m.DeclaringType == null || m.DeclaringType.DefinitionAssembly == null ? "" : m.DeclaringType.DefinitionAssembly.Name.String;
                if(!Redirected(asm)) continue;
                TypeDef t;
                string result="unmatched",definition="";
                if(types.TryGetValue(DeclaringName(m.DeclaringType),out t))
                {
                    var seen=new HashSet<string>();
                    int depth=0;
                    while(t != null && seen.Add(t.FullName))
                    {
                        if(m.IsMethodRef)
                        {
                            var hit=t.Methods.FirstOrDefault(d=>d.Name==m.Name && comparer.Equals(d.MethodSig,m.MethodSig));
                            if(hit != null) {result=depth==0?"signature":"inherited-signature";definition=hit.FullName;break;}
                        }
                        else if(m.IsFieldRef)
                        {
                            var hit=t.Fields.FirstOrDefault(d=>d.Name==m.Name && comparer.Equals(d.FieldSig,m.FieldSig));
                            if(hit != null) {result=depth==0?"signature":"inherited-signature";definition=hit.FullName;break;}
                        }
                        TypeDef next=null;
                        if(t.BaseType != null) types.TryGetValue(DeclaringName(t.BaseType),out next);
                        t=next;depth++;
                    }
                }
                if(result=="unmatched") missing++;else found++;
                w.WriteLine("member\t"+Cell(m.FullName)+"\t"+asm+"\t"+result+"\t"+Cell(definition));
            }
            return "Members matched="+found+" unmatched="+missing+"; signatures only; no behavior or runtime-loader proof.";
        }
    }
    static string Cell(object value) { return (value == null ? "" : value.ToString()).Replace("\\", "\\\\").Replace("\t", "\\t").Replace("\r", "\\r").Replace("\n", "\\n"); }
    static string Hash(string text) { using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-", ""); }
    static string Index(Instruction i, Dictionary<Instruction, int> indices) { return i == null ? "END" : indices[i].ToString(CultureInfo.InvariantCulture); }
    static string Operand(object value, Dictionary<Instruction, int> indices)
    {
        if (value == null) return "";
        if (value is Instruction) return "target:" + Index((Instruction)value, indices);
        if (value is IList<Instruction>) return "targets:" + string.Join(",", ((IList<Instruction>)value).Select(i => Index(i, indices)));
        if (value is string) return "str:" + Cell(value);
        if (value is Local) return "local:" + ((Local)value).Index;
        if (value is Parameter) return "arg:" + ((Parameter)value).Index;
        if (value is float) return ((float)value).ToString("R", CultureInfo.InvariantCulture);
        if (value is double) return ((double)value).ToString("R", CultureInfo.InvariantCulture);
        if (value is IFullName) return ((IFullName)value).FullName;
        return Convert.ToString(value, CultureInfo.InvariantCulture);
    }
    static string Body(MethodDef method)
    {
        if (!method.HasBody) return "<no-body>";
        var body = method.Body;
        body.SimplifyMacros(method.Parameters);
        var indices = new Dictionary<Instruction, int>();
        for (int i=0; i<body.Instructions.Count; i++) indices[body.Instructions[i]]=i;
        var b = new StringBuilder();
        b.Append("init:").Append(body.InitLocals).Append('\n');
        foreach (var local in body.Variables) b.Append("local:").Append(local.Type.FullName).Append('\n');
        foreach (var instruction in body.Instructions) b.Append(instruction.OpCode.Name).Append(' ').Append(Operand(instruction.Operand, indices)).Append('\n');
        foreach (var h in body.ExceptionHandlers) b.Append("eh:").Append(h.HandlerType).Append('|').Append(Index(h.TryStart, indices)).Append('|').Append(Index(h.TryEnd, indices)).Append('|').Append(Index(h.HandlerStart, indices)).Append('|').Append(Index(h.HandlerEnd, indices)).Append('|').Append(Index(h.FilterStart, indices)).Append('|').Append(h.CatchType == null ? "" : h.CatchType.FullName).Append('\n');
        return b.ToString();
    }
    public static string Export(string assemblyPath, string prefix)
    {
        using (var module = ModuleDefMD.Load(assemblyPath))
        using (var tw = new StreamWriter(prefix+".types.tsv", false, new UTF8Encoding(false)))
        using (var mw = new StreamWriter(prefix+".methods.tsv", false, new UTF8Encoding(false)))
        using (var fw = new StreamWriter(prefix+".fields.tsv", false, new UTF8Encoding(false)))
        using (var rw = new StreamWriter(prefix+".refs.tsv", false, new UTF8Encoding(false)))
        using (var trw = new StreamWriter(prefix+".typerefs.tsv", false, new UTF8Encoding(false)))
        using (var mrw = new StreamWriter(prefix+".memberrefs.tsv", false, new UTF8Encoding(false)))
        {
            tw.WriteLine("type\ttop_type\tattributes\tbase\tinterfaces\tmethods\tfields\ttoken");
            mw.WriteLine("method\ttype\tattributes\timpl_attributes\til_hash\tinstructions\ttoken\thas_interpolation\tcalled_members");
            fw.WriteLine("field\ttype\tattributes\tconstant\ttoken");
            rw.WriteLine("assembly\tversion\tpublic_key_token");
            trw.WriteLine("type\tassembly");
            mrw.WriteLine("member\tassembly");
            int types=0, methods=0, fields=0;
            foreach(var t in module.GetTypes())
            {
                if (t.Name == "<Module>") continue;
                types++;
                var top=t; while(top.DeclaringType!=null) top=top.DeclaringType;
                tw.WriteLine(string.Join("\t", Cell(t.FullName),Cell(top.FullName),Cell(t.Attributes),Cell(t.BaseType == null ? "" : t.BaseType.FullName),Cell(string.Join(";", t.Interfaces.Select(i=>i.Interface.FullName))),t.Methods.Count,t.Fields.Count,t.MDToken.ToString()));
                foreach(var m in t.Methods)
                {
                    methods++;
                    var calls = m.HasBody ? m.Body.Instructions.Where(i => i.Operand is IMethod).Select(i => ((IMethod)i.Operand).FullName).Distinct().OrderBy(s => s).ToArray() : new string[0];
                    mw.WriteLine(string.Join("\t",Cell(m.FullName),Cell(t.FullName),Cell(m.Attributes),Cell(m.ImplAttributes),Hash(Body(m)),m.HasBody?m.Body.Instructions.Count:0,m.MDToken.ToString(),calls.Any(s=>s.Contains("DefaultInterpolatedStringHandler")),Cell(string.Join(" | ", calls))));
                }
                foreach(var f in t.Fields)
                {
                    fields++;
                    fw.WriteLine(string.Join("\t",Cell(f.FullName),Cell(t.FullName),Cell(f.Attributes),Cell(f.HasConstant ? f.Constant.Value : null),f.MDToken.ToString()));
                }
            }
            foreach(var a in module.GetAssemblyRefs()) rw.WriteLine(string.Join("\t",Cell(a.Name),a.Version,Cell(a.PublicKeyOrToken)));
            foreach(var t in module.GetTypeRefs()) trw.WriteLine(Cell(t.FullName)+"\t"+Cell(t.DefinitionAssembly == null ? "" : t.DefinitionAssembly.Name));
            foreach(var m in module.GetMemberRefs()) mrw.WriteLine(Cell(m.FullName)+"\t"+Cell(m.DeclaringType == null || m.DeclaringType.DefinitionAssembly == null ? "" : m.DeclaringType.DefinitionAssembly.Name));
            return module.Assembly.FullName + " | runtime=" + module.RuntimeVersion + " | machine="+module.Machine+" | types="+types+" | methods="+methods+" | fields="+fields;
        }
    }
}
