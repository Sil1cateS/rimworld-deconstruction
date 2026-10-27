# Editable 与 Def：定义共同具有的数据与方法（讨论稿）

状态：Def 公共基类的逐层阅读，2026-10-24。依据工作区 RimWorld 1.7.4982 rev1280 的游戏代码整理。上接 [一份长剑定义与两件实际物品](30-def-and-instances.md)，范围见 [本部分大纲](29-def-xml-outline.md)。本轮先读 Editable 与 Def，具体加载顺序和各定义子类随后继续。

## 一、先找到这两个类的位置

上一轮的长剑定义是 ThingDef 实例，它沿 `System.Object → Editable → Def → BuildableDef → ThingDef` 继承共同能力。

Editable 先提供加载后处理、引用整理与配置检查的方法；Def 在此基础上增加定义名称、显示文本、来源信息、编号、缓存与扩展数据。后面的子类再增加物品、地形、配方等具体内容所需的数据和逻辑。

这条类型树与前一章的 UnityEngine.Object 分支分别存在。一个 Def 继承了哪些方法，要沿这里的父类继续查找。

## 二、Editable：只有三个虚方法的共同基础

Editable 本身没有声明字段，也不是抽象类。它提供的三个方法如下：

| 方法 | 提供的处理位置 | 本类实现 |
| --- | --- | --- |
| ResolveReferences | 供具体类型整理引用与相关数据 | 空方法 |
| PostLoad | 供具体类型完成读取后的处理 | 空方法 |
| ConfigErrors | 向调用者提供配置错误的字符串序列 | 返回空序列 |

其中 `IEnumerable<string>` 表示调用者可以逐项遍历结果，`Enumerable.Empty<string>()` 表示没有返回项。去掉反编译注释后，本类完整声明为：

```csharp
public class Editable
{
    public virtual void ResolveReferences()
    {
    }

    public virtual void PostLoad()
    {
    }

    public virtual IEnumerable<string> ConfigErrors()
    {
        return Enumerable.Empty<string>();
    }
}
```

virtual 允许后代覆写实现。具体类型没有额外处理时，可以沿用这里的默认行为；需要执行父类逻辑时，覆写方法自行调用 base。

这些方法声明本身不会安排运行时机。加载代码、数据库或其他调用者执行到相应位置，才会调用它们。加载器怎样找到 PostLoad、引用整理何时开始，后面沿具体流程展开。

源码定位：完整类型（`Verse.Editable.cs:8`）、三个方法（`Verse.Editable.cs:11`、`Verse.Editable.cs:16`、`Verse.Editable.cs:21`）。

## 三、Def：在共同处理入口之上增加定义身份与内容

Def 的声明是 `public class Def : Editable, IEquatable<Def>`。它继续使用 Editable 的方法体系，并实现针对 Def 的类型化相等比较。

先按数据的用途认识本层字段。下面按当前普通加载与使用方式分类；具体是谁填写、在哪里修改，仍需结合各自调用点。

| 数据组 | 成员 | 本层需要理解的作用 |
| --- | --- | --- |
| 定义名称 | defName | 程序识别和查找定义时使用的名字，初值为 UnnamedDef |
| 显示内容 | label、description | 面向玩家的名称与描述；翻译数据还可能在后续阶段改变显示内容 |
| 描述链接 | descriptionHyperlinks | 保存说明中关联的定义链接，链接对象通过 def 指向目标定义 |
| 扩展数据 | modExtensions | 保存附加的 DefModExtension 对象，供相应功能读取 |
| 配置检查开关 | ignoreConfigErrors、ignoreIllegalLabelCharacterConfigError | 分别参与整体配置检查入口和 label 的特定字符检查 |
| 数据库位置 | index | 定义在相应数据库列表中的序号，初值为 ushort.MaxValue |
| 名称哈希 | defNameHash | 根据 defName 计算，供本类 GetHashCode 和类型化比较使用 |
| 短哈希 | shortHash | 由专门流程分配的 ushort 值，配合数据库中的短哈希查询使用 |
| 来源信息 | modContentPack、fileName | 记录所属内容包和来源名称 |
| 生成标记 | generated | 记录是否经过相应代码生成入口；AddImpliedDef 会将它设为 true |
| 显示缓存 | cachedLabelCap | 保存处理过的名称，供 LabelCap 重用 |
| 调试值 | debugRandomId | 字段初始化时取得的随机 ushort 值；本类不将它作为按名查询的键 |

本类还声明了 DefaultDefName 常量，以及检查定义名称和显示名称字符的两个静态正则表达式。它们提供默认值和检查规则，不是每份定义各自持有的内容对象。

### 3.1 哪些信息通常来自文件，哪些由程序补充

长剑 XML 中的 defName、label、description 等描述，最终进入定义对象的相应字段。label、description 所带的翻译相关特性只是声明了处理信息，具体翻译仍需其他代码执行。

另外一些字段由加载或整理流程补充。例如，ModContentPack.AddDef 将当前内容包写入 def.modContentPack，把传入的来源名称写入 def.fileName，再保存这份定义。因此，fileName 在这里是来源记录，不应直接理解为开发者 C# 源文件的路径。

index 在定义入库和重新排列序号时写入；shortHash 由 ShortHashGiver 分配；generated 在相应生成入口设置。它们与 XML 中作为名字出现的 defName 分别承担不同职责。

这些来源、编号、缓存等字段在 Def 声明中还标有 Unsaved(false)。读取器如何处理字段特性，留到 XML 转对象时解释；不能仅凭“这是 public 字段”就推断任意同名 XML 标签都按普通配置字段处理。

源码定位：本层字段与检查规则（`Verse.Def.cs:119`、`Verse.Def.cs:125`、`Verse.Def.cs:131`、`Verse.Def.cs:135`、`Verse.Def.cs:141`、`Verse.Def.cs:149`、`Verse.Def.cs:153`、`Verse.Def.cs:157`、`Verse.Def.cs:161`、`Verse.Def.cs:165`、`Verse.Def.cs:169`、`Verse.Def.cs:173`、`Verse.Def.cs:177`、`Verse.Def.cs:181`、`Verse.Def.cs:184`、`Verse.Def.cs:187`、`Verse.Def.cs:190`）；来源写入（`Verse.ModContentPack.cs:610`）、序号处理（`Verse.DefDatabase.cs:90`、`Verse.DefDatabase.cs:210`）、短哈希分配（`Verse.ShortHashGiver.cs:48`）、生成标记（`RimWorld.DefGenerator.cs:72`）。

## 四、显示名称、缓存与信息条目

### 4.1 LabelCap：按需要处理名称，再保存结果

LabelCap 是一个返回 TaggedString 的虚属性。它读取 label，使用 CapitalizeFirst 取得首字母大写形式，并将结果保存在 cachedLabelCap；NullOrEmpty 用来判断相应内容是否为空。完整 getter 如下：

```csharp
public virtual TaggedString LabelCap
{
    get
    {
        if (this.label.NullOrEmpty())
        {
            return null;
        }
        if (this.cachedLabelCap.NullOrEmpty())
        {
            this.cachedLabelCap = this.label.CapitalizeFirst();
        }
        return this.cachedLabelCap;
    }
}
```

第一次读取且缓存为空时，属性进行处理并保存；后续读取可以直接使用已有结果。对本例原始英文 label 而言，这使调用方可以取得 longsword 的首字母大写形式；完整显示文本还可能包含材质、品质等其他内容。

Def.ClearCachedData 的本层实现将 cachedLabelCap 设为 null，让下一次读取重新建立缓存。它也是虚方法，后代可以继续清理自己的缓存。修改 label 的字段值，并不会单凭赋值动作自动清除此字段之外的缓存。

### 4.2 SpecialDisplayStats：本层提供来源条目

SpecialDisplayStats 接收 StatRequest，返回可以逐项遍历的 StatDrawEntry 信息条目。Def 这一层在 modContentPack 存在且不是 Core 时，建立内容来源条目，并按官方扩展或其他 Mod 选择相应说明，显示内容包名称。

本例原版长剑来自 Core，这一层不会因此返回该来源条目。后代还可以覆写并增加其他条目，所以不能据此推断整张物品信息页没有内容。具体数值怎样成为面板条目，在属性与 UI 模块继续。

源码定位：名称与缓存（`Verse.Def.cs:13`、`Verse.Def.cs:64`）、信息条目入口（`Verse.Def.cs:30`）。后者的实际迭代逻辑已补查，定位说明见本篇末尾。

## 五、扩展数据怎样跟随定义参与处理

DefModExtension 是另一种普通 C# 对象的基类，本层提供 ConfigErrors 和 ResolveReferences(Def parentDef) 两个虚方法，默认分别返回空序列、执行空方法。modExtensions 列表保存这些扩展对象，具体子类可以增加功能需要的配置。

`Def.GetModExtension<T>` 按类型取得第一个匹配扩展。T 受 DefModExtension 基类约束，因此找不到时，default(T) 在这里表示空引用。完整方法如下：

```csharp
public T GetModExtension<T>() where T : DefModExtension
{
    if (this.modExtensions == null)
    {
        return default(T);
    }
    for (int i = 0; i < this.modExtensions.Count; i++)
    {
        if (this.modExtensions[i] is T)
        {
            return this.modExtensions[i] as T;
        }
    }
    return default(T);
}
```

is T 也允许匹配相应派生类型。`HasModExtension<T>` 再使用这个查询结果判断是否存在扩展。查询只取得已有对象，不会在缺失时补建。

这些扩展对象保存附加数据与相应处理方法。某个游戏功能如何读取并使用它们，需要继续查调用位置；它们本身不因此获得每帧 Update。

Def 还覆写了 ResolveReferences。在以下代码中，base.ResolveReferences 调用 Editable 的实现，modExtensions 则是刚才认识的扩展列表：

```csharp
public override void ResolveReferences()
{
    base.ResolveReferences();
    if (this.modExtensions != null)
    {
        for (int i = 0; i < this.modExtensions.Count; i++)
        {
            this.modExtensions[i].ResolveReferences(this);
        }
    }
}
```

因此，Def 本层的引用整理会继续进入各个扩展，并将当前定义作为 parentDef 交给它们。这个 parentDef 表示扩展所属的定义，与 XML 的父模板或 C# 的父类是不同关系。

源码定位：扩展基类（`Verse.DefModExtension.cs:8`、`Verse.DefModExtension.cs:11`、`Verse.DefModExtension.cs:17`）、查询接口（`Verse.Def.cs:88`、`Verse.Def.cs:105`）、本层引用整理（`Verse.Def.cs:38`）。

## 六、配置检查提供什么，谁会执行这些方法

Def.ConfigErrors 覆写 Editable 的默认方法，主要逐项提供配置错误字符串。本层包含以下检查与处理：

- defName 是否仍为默认名称 UnnamedDef，是否为字符串 null，以及是否符合名称字符规则。
- 各个 modExtensions 返回的配置错误。
- 非 null 的 description 是否为空字符串，以及首尾是否出现空白字符。
- descriptionHyperlinks 中目标为空和目标重复的问题。
- 未开启对应忽略选项时，label 是否包含正则规则禁止的方括号或花括号字符。

其中，空目标的描述链接会先从列表移除并记录警告。因而，这个方法不只是返回字符串，也可能整理该列表和输出警告；它没有在此提供一套自动修复所有配置错误的过程。

ignoreConfigErrors 的整体跳过判断放在 `DefDatabase<T>.ErrorCheckAllDefs` 中：该方法遍历定义，检查开关，再遍历 ConfigErrors 返回的字符串并记录错误。ignoreIllegalLabelCharacterConfigError 则参与 Def 自己的特定字符检查。

可以先将几个调用关系放在一起：

| 方法 | 已核对的调用关系 |
| --- | --- |
| PostLoad | XML 读取路径查找并接入该方法；代码生成定义的 AddImpliedDef 也直接调用它 |
| ResolveReferences | `DefDatabase<T>.ResolveAllReferences` 中对符合条件的定义调用，再进入实际类型的覆写 |
| ConfigErrors | `DefDatabase<T>.ErrorCheckAllDefs` 遍历其结果并记录错误 |
| PostSetIndices | `DefDatabase<T>.SetIndices` 先写入各定义的 index，再遍历调用 |
| ClearCachedData | 定义数据库的清缓存入口会逐个调用；其他处理路径也可以显式调用 |

Def 没有自己覆写 PostLoad，因此本层沿用 Editable 的空实现；它新增的 PostSetIndices 在本层也为空。空方法仍然给后代提供了可以覆写的处理位置。

这里的方法在 C# 声明中明确使用了 virtual、override。ConfigErrors 等方法返回迭代器时，实际检查随调用者的遍历继续执行；上述调用并没有把它们交给 CoroutineScheduler，也不需要因此等待下一帧。

源码定位：配置检查入口（`Verse.Def.cs:51`）、序号后处理（`Verse.Def.cs:59`）、调用方（`Verse.DefDatabase.cs:134`、`Verse.DefDatabase.cs:143`、`Verse.DefDatabase.cs:210`、`Verse.DefDatabase.cs:223`）、读取路径查找 PostLoad（`Verse.XmlToObjectUtils.cs:218`）、代码生成入口（`RimWorld.DefGenerator.cs:72`）。本层检查的实际迭代逻辑已补查，定位说明见本篇末尾。

## 七、名字、编号、哈希与相等判断分别看

defName 是名字，index 是相应数据库中的列表序号，shortHash 是专门分配的短值。Def 还提供了几项与名称有关的方法：

| 方法 | 本层实现 |
| --- | --- |
| ToString | 返回 defName，因而日志等位置可以显示定义名字 |
| ResolveDefNameHash | 调用 defName.GetHashCode，将结果保存到 defNameHash |
| GetHashCode | 返回已经保存的 defNameHash |
| Equals(Def other) | 检查非空、名称哈希相同，以及实际 C# 类型相同 |

Equals(Def other) 的完整实现是：

```csharp
public bool Equals(Def other)
{
    return other != null && other.defNameHash == this.defNameHash && other.GetType() == base.GetType();
}
```

这段代码比较的是保存的哈希值和实际类型，并没有在这里逐字比较 defName。哈希相同也不能由此推导为名字必然相同。

本层实现了 `IEquatable<Def>` 的比较方法，但没有在此覆写 Equals(object)，也没有重载 ==。因此，调用哪一种比较仍需看表达式的静态类型与实际调用入口；ReferenceEquals 则始终是在检查是否同一实例。上一轮“两件物品引用同一份定义”的判断，使用的正是这种引用身份比较。

这些方法也解释了为何变更定义名字时，不能只修改一个字符串就假定所有关系都已更新：本层还有保存的名称哈希，数据库还有按名查询结构。具体重命名、重名处理与重新登记流程，后面读 DefDatabase 时继续。

源码定位：字符串与哈希接口（`Verse.Def.cs:70`、`Verse.Def.cs:76`、`Verse.Def.cs:82`）、类型化比较（`Verse.Def.cs:111`）、短值分配（`Verse.ShortHashGiver.cs:48`）。

## 八、回到长剑定义，下一层还要增加什么

长剑定义已经从 Def 取得了名称、描述、来源、编号、扩展与共同处理方法。但 Def 本层还没有声明 thingClass、武器攻击工具或物品组件配置；这些具体内容需要继续沿 BuildableDef、ThingDef 查找。

因此，读一份长剑 XML 时，可以沿两个方向核对：一个字段在哪一级类型中声明，又由哪个读取或使用位置赋值、查询并产生结果。接下来阅读 [BuildableDef](32-buildabledef.md)，再回到 ThingDef 的实际内容结构。

### 本轮对迭代方法的补充核对

当前反编译的 Def.cs 对 ConfigErrors、SpecialDisplayStats 只展示了创建迭代器的入口。本篇关于具体检查、链接整理和来源条目的说明，另外按本地 Assembly-CSharp.dll 中的实际迭代方法核对：

| 方法 | 元数据与 IL 定位 |
| --- | --- |
| `Verse.Def+<ConfigErrors>d__23.MoveNext` | Token 0x0600ECB0；IL_0066 起检查名称，IL_0129 起处理扩展，IL_01D6 起检查描述，IL_0285 起处理链接，IL_03E0 起检查显示名称字符 |
| `Verse.Def+<SpecialDisplayStats>d__19.MoveNext` | Token 0x0600ECB9；IL_0021 起检查来源，随后建立信息条目 |

这里说明核对依据，不将编译器生成的状态字段当作 Def 的公共接口。具体迭代器实现与协程的详细区别，留在执行与调度部分继续。
