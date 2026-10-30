# Def 的加载、存储与查询：定义怎样进入程序

版本：整合草稿 v0.3｜整理日期：2026-10-30

上一篇 [《XML 与 Def 结构》](01-xml-and-def-structure.md) 介绍了定义由哪些字段和配置组成。本篇继续解释：分散在文件中的内容，怎样成为游戏代码可以找到和使用的一组定义。

文章先按功能建立整体结构，再进入每一部分的调用过程。代码前介绍相关对象、变量和方法，代码后对照处理结果。文中的小型 XML 使用教学名称，帮助观察文档、对象和引用怎样变化。

本文依据 RimWorld 1.7.4982 rev1280 的普通启动路径，hotReload 为 false。源码节选保留原有命名，省略性能计时、日志及注明的支线；教学示意单独标明。

## 一、先认识本次加载要完成的四组工作

加载入口需要为后续系统准备定义对象、定义之间的引用，以及查找这些对象的入口。可以先把这项工作分成四组：

| 工作 | 这一组要解决什么 | 完成后的主要结果 |
| --- | --- | --- |
| 准备 XML | 找到各内容包的文件，将内容集中到一起，执行补丁和父模板处理 | 一份可供逐项读取的 XML 文档，以及节点的来源记录 |
| 建立与保存 Def | 按类型建立对象、填写字段，再组织成可查找的集合 | 内容包的定义列表、类型数据库的列表与名称字典 |
| 连接与补充定义 | 按名称找到目标对象，并利用已有内容生成更多定义 | 写入字段和集合的引用、新生成的定义、可直接访问的静态字段 |
| 整理并交给使用者 | 整理默认值和缓存，完成检查与短哈希准备 | 供后续代码查询、遍历和读取的定义集合 |

![定义加载的四组工作](figures/def-load-overview.png)

先记住每一组工作的任务和结果，再看它内部怎样推进。[SVG](figures/def-load-overview.svg) · [图源](figures/def-load-overview.dot)

负责组织这一过程的是 PlayDataLoader。它的 LoadAllPlayData 是加载入口，DoPlayLoad 安排具体步骤。DoPlayLoad 首先调用 LoadedModManager.LoadAllActiveMods；LoadedModManager 负责组织活动内容包，从它们取得文件，再把 XML 内容读成定义。这个调用返回以后，DoPlayLoad 继续安排入库、引用连接和收尾。

后文第二部分先完成 XML 准备，第三部分接到对象与存储，第四部分处理引用和生成，第五、六部分说明整理及使用。

源码定位：加载入口（`Verse.PlayDataLoader.cs:32`）、主流程（`Verse.PlayDataLoader.cs:94`）、内容加载（`Verse.LoadedModManager.cs:56`）。

## 二、准备 XML：从各内容包取得一份可处理的文档

这一部分接收活动内容包的信息，将它们的文件读入内存，再把内容放进统一的 XML 树。补丁和模板处理随后围绕这棵树工作，给对象读取阶段准备好节点内容。

### 2.1 准备内容包和解释文件所需的代码

这里先认识 ModContentPack：它是程序为一个活动内容包建立的管理对象，保存该包的目录、加载顺序、程序集、资源入口和定义列表。Core、DLC 与启用的 Mod 都用这类对象参与加载。

LoadedModManager 先执行三项准备工作：

| 方法 | 在这里完成什么 |
| --- | --- |
| InitializeMods | 按活动顺序建立 ModContentPack，放入 runningMods 列表 |
| LoadModContent | 加载各包的内容，其中的程序集供后面查找 C# 类型 |
| CreateModClasses | 建立程序集中的 Mod 派生对象，使相应 Mod 代码参与初始化 |

知道这三个方法的职责后，再看普通启动路径中的调用。hotReload 是 LoadAllActiveMods 的参数，在本次路径中为 false：

```csharp
LoadedModManager.InitializeMods();
LoadedModManager.LoadModContent(hotReload);
LoadedModManager.CreateModClasses();
```

这一步准备好了内容包的管理对象和代码。接下来，程序就能向每个包询问：本次应该从哪些目录读取定义文件？

### 2.2 将 XML 文件读成带来源信息的对象

每个内容包通过 InitLoadFolders 确定加载目录，按优先级保存到 foldersToLoadDescendingOrder。LoadFolders.xml 可以按版本和活动 Mod 条件选择目录；默认规则会考虑版本目录、Common 与根目录。

文件进入内存后，用 LoadableXmlAsset 保存。可以把它理解成“一份 XML 文档及其来源信息”：

| 成员 | 保存什么 |
| --- | --- |
| xmlDoc | 文件读入后的 XmlDocument，即内存中的 XML 树 |
| mod | 文件所属的 ModContentPack |
| name、fullFolderPath | 文件的来源名称和目录信息 |

负责汇总这些对象的方法是 LoadModXML。代码中的 runningMods 是活动内容包列表；modContentPack 是本轮正在读取的包；list 是本方法新建的结果列表。每个包的 LoadDefs 返回一批 LoadableXmlAsset，AddRange 将这一批追加到 list：

```csharp
List<LoadableXmlAsset> list = new List<LoadableXmlAsset>();
for (int i = 0; i < LoadedModManager.runningMods.Count; i++)
{
    ModContentPack modContentPack = LoadedModManager.runningMods[i];
    // LoadDefs 读当前包的定义文件；AddRange 把这一批读取结果加入 list。
    // 省略性能计时和异常日志。
    list.AddRange(modContentPack.LoadDefs(hotReload));
}
return list;
```

LoadDefs 内部通过 DirectXmlLoader 扫描选定目录下的 Defs/，按相对路径保留优先目录中的文件，再读取 XML。LoadModXML 返回时，list 中的每一项都能交出一份文档和它的来源，下一步便可以集中处理这些文档。

源码定位：内容包建立（`Verse.LoadedModManager.cs:183`）、目录选择（`Verse.ModContentPack.cs:302`）、文档收集（`Verse.LoadedModManager.cs:318`）、文件扫描（`Verse.DirectXmlLoader.cs:17`）、来源对象（`Verse.LoadableXmlAsset.cs:53`）。

### 2.3 CombineIntoUnifiedXML 为什么收集顶层节点

各个文件都以 Defs 作为根元素，下面放一份份定义或模板。为了让补丁能够在一个范围内查找内容，也让后续代码集中遍历定义，CombineIntoUnifiedXML 会创建一个新的 Defs 根元素，把各文件中的完整定义块放到它下面。

这里的“顶层节点”，指文件根元素 Defs 的直接子节点。一块 StatDef 连同自己的 defName、label、category 等字段，整体成为待导入的一项。按这个层级收集，统一文档里仍然保留一份份完整的内容描述。

先看输入和结果。下面用两个示意文件说明，名称和字段内容为教学用途：文件 A 描述一个属性分类，文件 B 描述一个归属该分类的属性。StatCategoryDef 表示属性分类，StatDef 的 category 字段引用这个分类。

**文件 A：**

```xml
<Defs>
  <StatCategoryDef>
    <defName>ExampleCategory</defName>
    <label>示例分类</label>
  </StatCategoryDef>
</Defs>
```

**文件 B：**

```xml
<Defs>
  <StatDef>
    <defName>ExampleStat</defName>
    <label>示例属性</label>
    <category>ExampleCategory</category>
  </StatDef>
</Defs>
```

组合完成后，新文档中的相关内容是：

```xml
<Defs>
  <StatCategoryDef>
    <defName>ExampleCategory</defName>
    <label>示例分类</label>
  </StatCategoryDef>
  <StatDef>
    <defName>ExampleStat</defName>
    <label>示例属性</label>
    <category>ExampleCategory</category>
  </StatDef>
</Defs>
```

新文档使用新建的 Defs 根元素容纳两个定义块，各自的字段仍保存在原来的层级。后面的补丁可以用 XPath 在这棵树中选择目标：XPath 是按路径和条件寻找 XML 节点的表达式，例如 `/Defs/StatDef[defName="ExampleStat"]` 会选择 Defs 下、defName 为 ExampleStat 的 StatDef 节点。补丁因此可以围绕同一根元素查找来自各个文件的内容。

**再看代码怎样得到这个结果。** 调用者将 LoadModXML 返回的文档列表传给参数 xmls，同时传入一个新建的 assetlookup 字典，让方法填写节点来源。片段中会用到：

| 名称或成员 | 在这段代码中指什么 |
| --- | --- |
| xmls | 所有待组合的 LoadableXmlAsset |
| loadableXmlAsset | 当前正在处理的一份来源对象 |
| xmlDocument | 本方法创建并最终返回的新文档 |
| DocumentElement、ChildNodes | 分别取得文档根元素，以及这个根元素的直接子节点 |
| obj、xmlNode、xmlNode2 | obj 暂存当前子节点，转成 XmlNode 后由 xmlNode 接收；xmlNode2 保存复制到新文档的节点 |
| assetlookup | 以复制后的节点为键，记下它来自哪份 LoadableXmlAsset |

代码中，CreateElement 创建元素，AppendChild 把节点加到指定父节点下面，ImportNode(xmlNode, true) 则在目标文档中复制节点及其后代。以下节选有效文档的处理路径：

```csharp
public static XmlDocument CombineIntoUnifiedXML(
    List<LoadableXmlAsset> xmls,
    Dictionary<XmlNode, LoadableXmlAsset> assetlookup)
{
    XmlDocument xmlDocument = new XmlDocument();
    xmlDocument.AppendChild(xmlDocument.CreateElement("Defs"));

    foreach (LoadableXmlAsset loadableXmlAsset in xmls)
    {
        // 此处节选有效文档的路径，省略检查和日志。
        foreach (object obj in loadableXmlAsset.xmlDoc.DocumentElement.ChildNodes)
        {
            XmlNode xmlNode = (XmlNode)obj;
            XmlNode xmlNode2 = xmlDocument.ImportNode(xmlNode, true);
            assetlookup[xmlNode2] = loadableXmlAsset;
            xmlDocument.DocumentElement.AppendChild(xmlNode2);
        }
    }
    return xmlDocument;
}
```

方法开头先建立新的 Defs 根元素。进入循环后，每次拿到一个完整定义块，将副本放到 xmlNode2，记下来源，再把副本挂到新根元素下面。最后返回的 xmlDocument，就是上面展示的组合结果。

每复制一项，assetlookup 同时登记一次来源。以这两个示意文件为例，它保存的是“新文档中的分类节点 → 文件 A 的来源对象”“新文档中的属性节点 → 文件 B 的来源对象”。后面建立 Def 时，可以沿这张表找到所属内容包。

![两个文件如何组成统一文档，并留下来源记录](figures/xml-unified-example.png)

组合得到两项可继续处理的数据：统一的 XML 文档，以及随文档传下去的来源字典。[SVG](figures/xml-unified-example.svg) · [图源](figures/xml-unified-example.dot)

源码定位：文档组合（`Verse.LoadedModManager.cs:408`）、示意中的类型与字段（`RimWorld.StatCategoryDef.cs:7`、`RimWorld.StatDef.cs:312`）。

### 2.4 在统一文档上执行补丁，再准备父模板

统一文档准备好以后，ApplyPatches 让各包的补丁依次修改它。补丁对象称为 PatchOperation；它的 Apply 方法接收当前 XmlDocument。Add、Replace、Remove 等具体操作用 XPath 选择节点，再加入、替换或删除内容。后面的操作接着处理前面留下的结果。

补丁结束后，ParseAndProcessXML 开始准备父模板，再逐项建立定义。为了让一个节点能找到它的命名父模板，程序先登记所有顶层元素，再统一调用 XmlInheritance.Resolve。

下面这段中，xmlDoc 是传进来的统一文档，assetlookup 是刚才填写的来源字典。childNodes 取得根元素的子节点，局部变量 list 将它们收集成便于遍历的列表。TryGetValue 尝试找出当前节点的来源；TryRegister 登记节点及其来源包；Resolve 根据这些记录准备模板合并结果：

```csharp
XmlNodeList childNodes = xmlDoc.DocumentElement.ChildNodes;
List<XmlNode> list = new List<XmlNode>();
foreach (object obj in childNodes)
{
    list.Add(obj as XmlNode);
}

for (int i = 0; i < list.Count; i++)
{
    if (list[i].NodeType == XmlNodeType.Element)
    {
        LoadableXmlAsset loadableXmlAsset = null;
        assetlookup.TryGetValue(list[i], out loadableXmlAsset);
        XmlInheritance.TryRegister(
            list[i],
            (loadableXmlAsset != null) ? loadableXmlAsset.mod : null);
    }
}
XmlInheritance.Resolve();
```

至此，对象读取阶段可以同时取得当前节点、父模板补齐的内容和来源信息。具体合并规则可接回上一篇的 [XML 模板说明](01-xml-and-def-structure.md#四xml-模板怎样补全内容)。

源码定位：补丁执行（`Verse.LoadedModManager.cs:390`）、模板登记与逐项读取（`Verse.LoadedModManager.cs:437`）。

## 三、建立与保存 Def：把节点变成可以查找的对象

这一部分将准备好的 XML 读成 C# 对象，填入定义字段，再保存到内容包列表和类型数据库中。完成后，程序可以按定义类型和 defName 找到相应对象，后面的引用连接便有了查找目标。

### 3.1 先确定 C# 类型，再取得会读取它的方法

ParseAndProcessXML 遍历顶层节点，检查内容包条件后，将节点交给 DirectXmlToObjectNew.DefFromNodeNew。这个方法跳过注释和抽象模板项，对需要建立定义的节点选择类型并调用读取方法。

阅读代码前，先看其中名称的含义：

| 名称 | 保存什么，或完成什么工作 |
| --- | --- |
| node | 传入的原始顶层 XML 节点 |
| resolvedNodeFor | XmlInheritance.GetResolvedNodeFor 找到的模板合并结果 |
| text | 准备用来查找 C# 类型的名称，先取元素名，Class 属性可以进一步指定 |
| xmlAttribute2 | 当前读取到的 Class 属性 |
| typeInAnyAssembly | GenTypes.GetTypeInAnyAssembly 按名称找到的 C# Type |
| defParserForType | GetDefParserForType 取得的读取委托，即可以调用的读取方法引用 |
| def | 读取方法返回的定义对象 |

ParseValueAndReturnDefDelegate 是这类读取方法的委托类型，调用后返回 Def。前两个参数对应签名里的 unused、unused2，本入口传入 0；后两个参数提供节点和实际 C# 类型。读取成功以后，ResolveDefNameHash 根据 defName 填写定义的名称哈希。

沿类型有效、读取成功的路径，相关代码是：

```csharp
XmlNode resolvedNodeFor = XmlInheritance.GetResolvedNodeFor(node);
string text = node.Name;
XmlAttribute xmlAttribute2 = resolvedNodeFor.Attributes["Class"];
if (xmlAttribute2 != null)
{
    text = xmlAttribute2.Value;
}
Type typeInAnyAssembly = GenTypes.GetTypeInAnyAssembly(text, null);

// 省略类型校验与日志，继续成功读取的路径。
Def def = null;
DirectXmlToObjectNew.ParseValueAndReturnDefDelegate defParserForType =
    DirectXmlToObjectNew.GetDefParserForType(typeInAnyAssembly);
def = defParserForType(0, 0, node, typeInAnyAssembly);
def.ResolveDefNameHash();
```

以示意文件 B 为例，元素名 StatDef 帮助程序找到 StatDef 类型，随后取得会建立和填写这类对象的读取方法。GetDefParserForType 会缓存读取委托，后面的同类节点可以继续复用。

### 3.2 遍历字段，得到对象与待连接记录

现在进入读取方法内部。普通复杂对象路径先建立对象，让字段初值和构造函数提供起始数据，再逐个读取 XML 子节点。字段查找会沿 C# 类型结构寻找成员，随后按字段类型选择处理方式。

![普通复杂对象的字段读取循环](../../figures/xml-object-field-loop.png)

图中每走完一轮，就已经处理了当前子节点，并继续下一个字段。[SVG](../../figures/xml-object-field-loop.svg) · [图源](../../figures/xml-object-field-loop.dot)

读取 defName、label 时，文本可以直接写入字符串字段；数值、枚举、Type、列表和嵌套对象则各有对应的读取方法。提供 LoadDataFromXmlCustom 的类型，会把节点交给自己的方法解释。

读到示意中的 category 时，字段类型是 StatCategoryDef。读取器把当前接收对象、category 的字段信息和目标名称 ExampleCategory 交给 DirectXmlCrossRefLoader，保存到待连接记录中。后面按名称找到目标时，就能沿这份记录写回正确位置。

因此，这两段示意 XML 的关键读取结果，可以表示为：

```text
定义对象
  StatCategoryDef：defName = "ExampleCategory"，label = "示例分类"
  StatDef：defName = "ExampleStat"，label = "示例属性"

另存的待连接记录
  接收对象：上面的 StatDef 对象
  需要填写的字段：category
  目标类型：StatCategoryDef
  目标名称："ExampleCategory"
```

待连接记录集中保存在 DirectXmlCrossRefLoader 管理的列表中，供后面几轮解析使用。普通字段循环结束后，读取方法还会调用适用的 PostLoad，让相应类型处理刚读到的数据。DefFromNodeNew 最后填写名称哈希，把定义对象交回 ParseAndProcessXML。

源码定位：默认入口（`Verse.DirectXmlToObjectNew.cs:16`）、读取委托与签名（`Verse.DirectXmlToObjectNew.cs:119`、`Verse.DirectXmlToObjectNew.cs:1596`）、字段循环（`Verse.DirectXmlToObjectNew.cs:1029`）、字段查找（`Verse.XmlToObjectUtils.cs:15`）、引用登记（`Verse.DirectXmlCrossRefLoader.cs:29`）。

### 3.3 将定义登记到来源内容包

对象建立后，程序先给它补上来源信息，并加入来源包的定义列表。这样可以保存“哪些定义来自这个内容包”，也为下一步批量收集提供入口。

ParseAndProcessXML 用顶层节点在 assetlookup 中取得 LoadableXmlAsset，源码将这次查找的结果命名为 loadableXmlAsset2。它的 mod 成员给出内容包，代码用 modContentPack2 接收；def 则是刚建立的定义。随后调用：

`modContentPack2.AddDef(def, loadableXmlAsset2.name)`

AddDef 的参数 source 在这里接收来源文件名，this 表示当前内容包对象。它把来源和文件名写入 Def，再将对象引用追加到本包的 defs 列表。完整实现如下：

```csharp
public void AddDef(Def def, string source = "Unknown")
{
    def.modContentPack = this;
    def.fileName = source;
    this.defs.Add(def);
}
```

如果顶层节点由补丁新建、没有对应来源记录，程序将建立的定义放入 LoadedModManager.patchedDefs，留给下一步一并收集。

这一轮顶层节点读取结束后，LoadAllActiveMods 完成补丁的后续处理，清理本轮补丁和模板缓存，然后返回 DoPlayLoad。各包现在已经持有所属定义。

### 3.4 按类型收集，建立名称查询入口

接下来的目标，是让查询者可以带着“定义类型 + defName”找到对象。`DefDatabase<T>` 为每个 T 保存自己的静态列表和查询字典，AddAllInMods 负责从各内容包收集能作为 T 使用的定义。

返回 DoPlayLoad、完成语言元数据初始化后，程序开始这批收集。片段中的几个调用可以这样读：

- typeof(Def).AllSubclasses() 取得 Def 子类的 Type，defType 是本轮处理的类型。
- `DefDatabase<>` 表示等待填入类型参数的泛型类。GenGeneric.InvokeStaticMethodOnGenericType 把 defType 填进去，再调用指定名字的静态方法。
- Parallel.ForEach 并行处理这批类型，等各项完成后，主流程继续向下。

例如，defType 为 StatDef 时，这次调用就对应到 `DefDatabase<StatDef>.AddAllInMods()`。源码中的循环为：

```csharp
Parallel.ForEach<Type>(typeof(Def).AllSubclasses(), delegate(Type defType)
{
    GenGeneric.InvokeStaticMethodOnGenericType(
        typeof(DefDatabase<>), defType, "AddAllInMods");
});
```

AddAllInMods 按内容包优先级和活动顺序收集对象。同包重复名称会被记录并跳过；收集辅助方法遇到跨来源的已有同名项时，先从当前库移除旧项，再加入当前项。Add 随后将引用写入 defsList、defsByName，并将当前位置写入 index。

| 容器 | 内容与用途 |
| --- | --- |
| defsList | 按列表保存定义引用，供遍历、计数和编号 |
| defsByName | 用 defName 取得定义引用 |
| defsByShortHash | 后面用分配好的 shortHash 建立另一种查询入口 |

示意中的两个对象在相关容器里形成这样的关系：

```text
该内容包的 defs 列表
  → 分类对象
  → 属性对象

相关类型库中的名称字典
  DefDatabase<StatCategoryDef>："ExampleCategory" → 分类对象
  DefDatabase<StatDef>："ExampleStat" → 属性对象
```

![来源列表和类型库中的定义引用](figures/def-storage-views.png)

内容包列表保存来源关系，类型库提供查询入口；这些容器中的引用可以指向同一份对象。[SVG](figures/def-storage-views.svg) · [图源](figures/def-storage-views.dot)

本部分完成后，程序已经有定义对象和名称字典。前面留下的 category 目标名称，现在可以进入相应数据库查找。

源码定位：来源登记（`Verse.LoadedModManager.cs:437`、`Verse.ModContentPack.cs:610`）、入库调用（`Verse.PlayDataLoader.cs:94`）、类型收集（`Verse.DefDatabase.cs:43`、`Verse.GenDefDatabase.cs:63`）、泛型静态调用（`Verse.GenGeneric.cs:29`）、保存与替换（`Verse.DefDatabase.cs:90`、`Verse.DefDatabase.cs:319`）。

## 四、连接与补充定义：让已读取的配置取得可用关联

本部分要把待连接名称写成对象引用，并用已有定义生成更多内容。常用定义还会被放进公共静态字段，供其他代码直接访问。完成这些工作后，各类型就能沿已取得的引用继续整理自己的数据。

### 4.1 先看这一组工作的安排

这里有三组主要参与者：DirectXmlCrossRefLoader 管理待连接记录；DefGenerator 调用具体生成器建立新定义；DefOfHelper 把查询到的定义写入带 DefOf 标记的类中的公共静态字段。

| 调用 | 在流程中承担什么工作 |
| --- | --- |
| ResolveAllWantedCrossReferences | 处理待连接记录，按类型与名称寻找目标，并完成对应写入 |
| RebindAllDefOfs | 给公共静态定义字段赋值；true 采用早期尝试模式，false 采用最终绑定模式 |
| GenerateImpliedDefs_PreResolve | 在各类型自身整理之前，根据已有内容生成一批定义 |
| Clear | 清理本轮待连接记录，结束这批名称处理 |

解析调用中的 FailMode 控制相应缺失问题的报告方式：前两轮使用 Silent，最后一轮使用 LogErrors。下面先看 DoPlayLoad 的外层安排，再进入各项工作：

```csharp
DirectXmlCrossRefLoader.ResolveAllWantedCrossReferences(FailMode.Silent);
DefOfHelper.RebindAllDefOfs(true);

// 省略此处的语言与其他早期准备。
DefGenerator.GenerateImpliedDefs_PreResolve(false);

try
{
    DirectXmlCrossRefLoader.ResolveAllWantedCrossReferences(FailMode.LogErrors);
}
finally
{
    DirectXmlCrossRefLoader.Clear();
}
DefOfHelper.RebindAllDefOfs(false);
```

外层先连接一轮引用、填入早期静态字段，再调用生成器；生成器返回后，外层继续连接引用，清理记录并做最终静态绑定。PreResolve 生成器内部还穿插一轮解析，完整顺序见图：

![生成、引用连接与静态绑定的安排](figures/def-binding-stages.png)

三轮解析之间，数据库会增加新定义，后面的解析可以继续寻找刚出现的目标。[SVG](figures/def-binding-stages.svg) · [图源](figures/def-binding-stages.dot)

### 4.2 将待连接名称写成对象引用

DirectXmlCrossRefLoader 将待处理记录保存在 wantedRefs 列表中。每条记录的 TryResolve 执行该记录的查找与处理；需要后置写入的部分由 Apply 完成。ResolveAllWantedCrossReferences 先并行处理这些记录，再调用完成项的 Apply，最后移出已完成项。

对示意中的普通字段记录，程序从记录中取得字段类型 StatCategoryDef 和目标名称 ExampleCategory，通过 GenDefDatabase 进入相应类型库查询。找到分类对象后，把它写入接收对象的 category 字段。结果便是：

```text
StatDef 对象（defName = "ExampleStat"）
  category → StatCategoryDef 对象（defName = "ExampleCategory"）
```

列表记录也会将找到的定义加入目标列表，并保留仍待查找的名称；字典记录先准备键值，再完成相应写入。这里需要记住的结果，是后续代码可以沿字段和集合直接访问目标定义。

### 4.3 新生成的定义继续加入同一套数据库

PreResolve 生成器先补入一批定义，执行内部的一轮引用解析，再继续生成其余部分。这样，后续生成代码既能使用已有定义，也能使用前面刚连接好的引用。

具体生成器建立对象后，将它交给 AddImpliedDef。参数 def 接收这个对象，T 是本次采用的定义类型，hotReload 在当前路径中为 false。方法会记录 generated 标记，填写名称哈希和可用的来源信息，调用 PostLoad，再加入类型数据库：

```csharp
public static void AddImpliedDef<T>(T def, bool hotReload = false) where T : Def, new()
{
    def.generated = true;
    def.ResolveDefNameHash();
    ModContentPack modContentPack = def.modContentPack;
    if (modContentPack != null)
    {
        modContentPack.AddDef(def, "ImpliedDefs");
    }
    def.PostLoad();
    if (hotReload && DefDatabase<T>.GetNamed(def.defName, false) != null)
    {
        return;
    }
    DefDatabase<T>.Add(def);
}
```

generated 标明这份定义由代码生成；PostLoad 让该类型处理建立后的数据；`DefDatabase<T>.Add` 则把它加入接下来可以查询的集合。新条目由此成为后续生成和引用解析的输入。

### 4.4 给 DefOf 静态字段写入查询结果

带 DefOf 标记的类可以提供公共静态字段，用来保存常用定义。DefOfHelper 遍历这些字段，根据字段类型和名称查询；DefAlias 可以为字段指定另一个 defName。

读下面两行之前，先看局部变量：fieldInfo 描述正在处理的静态字段，fieldType 是该字段的类型，text 保存查询名称，flag 控制普通缺失日志。GetDef 查询目标，SetValue 将结果写入该静态字段；静态字段无需指定接收实例，因此这里的第一个参数为 null：

```csharp
Def def = GenDefDatabase.GetDef(fieldType, text, flag);
fieldInfo.SetValue(null, def);
```

成功赋值后，使用者读取该字段，就能取得已经保存的定义引用。

经过生成器内部与返回后的解析，主流程再执行最终绑定。本部分将 XML 中的名称、生成器补充的内容和代码中的静态入口连接起来，接着把这些对象交给各类型自己的整理方法。

源码定位：外层安排（`Verse.PlayDataLoader.cs:94`）、记录处理（`Verse.DirectXmlCrossRefLoader.cs:247`）、字段查找与写入（`Verse.DirectXmlCrossRefLoader.cs:333`、`Verse.DirectXmlCrossRefLoader.cs:388`）、生成顺序（`RimWorld.DefGenerator.cs:11`）、生成定义入库（`RimWorld.DefGenerator.cs:72`）、静态绑定（`RimWorld.DefOfHelper.cs:27`）。

## 五、整理与收尾：为后续使用准备好数据

已经建立并连接的定义，还需要按各自规则整理默认值、配置集合和缓存。本部分先完成这批类型处理，再执行后置生成、配置检查和短哈希分配，最后让加载入口返回。

### 5.1 调用各类型的 ResolveReferences

ResetStaticDataPre 集中组织一批系统准备，包含分类节点、研究项目坐标和若干缓存的整理。随后，DoPlayLoad 调用各类型库的 ResolveAllReferences，让库内的定义执行自己的 ResolveReferences。

这里会看到 ThingCategoryDef、RecipeDef、ThingDef：它们分别描述内容分类、配方和实体配置。主流程先处理前两类，随后处理其他类型，最后处理 ThingDef。

ResolveAllReferences 的两个参数也先说明：onlyExactlyMyType 决定是否只处理运行时类型恰好等于 T 的对象；parallel 决定本次调用内部是否并行。加载流程传入的第一个参数为 true，让对象交给其实际类型对应的库来处理。GenGeneric 的调用方式与前面的入库循环相同：

```csharp
PlayDataLoader.ResetStaticDataPre();

DefDatabase<ThingCategoryDef>.ResolveAllReferences(true, true);
DefDatabase<RecipeDef>.ResolveAllReferences(true, true);
foreach (Type type in typeof(Def).AllSubclasses())
{
    if (!(type == typeof(ThingDef)) &&
        !(type == typeof(ThingCategoryDef)) &&
        !(type == typeof(RecipeDef)))
    {
        GenGeneric.InvokeStaticMethodOnGenericType(
            typeof(DefDatabase<>), type, "ResolveAllReferences",
            new object[] { true, false });
    }
}
DefDatabase<ThingDef>.ResolveAllReferences(true, false);
```

具体库先写入一轮 index，再遍历符合类型条件的定义，调用各对象的 ResolveReferences，完成后再次编号。定义可以在这里根据已连接的对象整理分类集合、补默认值或建立缓存。Def 基类也会继续调用各个 modExtensions 的整理方法。

这一批调用返回时，相应类型已经完成本次处理，主流程继续进行后置准备。

### 5.2 后置生成、检查和键位准备

接下来的调用各有明确任务：

| 调用或条件 | 在这里做什么 |
| --- | --- |
| GenerateImpliedDefs_PostResolve | 在类型整理后补充定义，当前实现生成键位相关内容 |
| ResetStaticDataPost | 组织建筑配置、统计属性等后置整理，并清理显示名称缓存 |
| Prefs.DevMode | 读取开发者模式开关，决定是否执行本处整批配置检查 |
| ErrorCheckAllDefs | 遍历定义的 ConfigErrors 返回值，将问题写入日志 |
| KeyPrefs.Init | 初始化键位设置 |
| GiveAllShortHashes | 给后面的短哈希查询准备编号与字典 |

知道各项作用后，再看它们的顺序：

```csharp
DefGenerator.GenerateImpliedDefs_PostResolve(false);
PlayDataLoader.ResetStaticDataPost();

if (Prefs.DevMode)
{
    Parallel.ForEach<Type>(typeof(Def).AllSubclasses(), delegate(Type defType)
    {
        GenGeneric.InvokeStaticMethodOnGenericType(
            typeof(DefDatabase<>), defType, "ErrorCheckAllDefs");
    });
}
KeyPrefs.Init();
ShortHashGiver.GiveAllShortHashes();
```

这批后置工作完成后，定义集合和键位设置得到相应准备。下一步展开其中最后一项：短哈希怎样变成查询入口。

### 5.3 分配 shortHash，填写查询字典

shortHash 是保存在 Def 中的 ushort 数值，可以作为按小整数查找定义的键。GiveAllShortHashes 按框架选定的类型组取得定义，按 defName 排序，再逐个分配数值。它从名称的稳定哈希取得候选，遇到零或本组已占用的值，就继续寻找可用值。

整组分配完成后，程序调用对应数据库的 InitializeShortHashDictionary。defsList 是已有定义列表，defsByShortHash 是短哈希查询字典；EnsureCapacity 先按列表长度预留容量，循环再逐项取出定义的 shortHash，填写“数值 → 定义引用”：

```csharp
public static void InitializeShortHashDictionary()
{
    DefDatabase<T>.defsByShortHash.EnsureCapacity(DefDatabase<T>.defsList.Count);
    for (int i = 0; i < DefDatabase<T>.defsList.Count; i++)
    {
        DefDatabase<T>.defsByShortHash[DefDatabase<T>.defsList[i].shortHash] =
            DefDatabase<T>.defsList[i];
    }
}
```

完成以后，按名称查找使用 defsByName，按短哈希查找使用 defsByShortHash，遍历则使用 defsList。这些入口都围绕已经保存的对象工作。

### 5.4 返回加载入口

DoPlayLoad 还会把后续语言、资源等函数交给 LongEventHandler.ExecuteWhenFinished，由它按当前长任务状态安排执行。

随后，DoPlayLoad 返回 LoadAllPlayData。外层把 PlayDataLoader 保存加载状态的布尔字段 loadedInt 设为 true，并完成正常返回。至此，这次调用已经走过文件准备、对象建立、引用连接以及整理收尾；后续系统可以使用相应查询入口取得定义。

源码定位：类型整理与收尾顺序（`Verse.PlayDataLoader.cs:94`）、前后系统准备（`Verse.PlayDataLoader.cs:663`、`Verse.PlayDataLoader.cs:722`）、逐项整理与编号（`Verse.DefDatabase.cs:143`、`Verse.DefDatabase.cs:210`）、配置检查（`Verse.DefDatabase.cs:223`）、短哈希分配（`Verse.ShortHashGiver.cs:14`、`Verse.ShortHashGiver.cs:48`）、字典建立（`Verse.DefDatabase.cs:302`）、加载标记（`Verse.PlayDataLoader.cs:32`）。

## 六、使用定义：从名称或已有引用找到对象

最后看使用者怎样拿到前面准备的数据。这一部分接收的通常是定义类型、defName、shortHash，或者已经保存定义的字段；查询结果交回定义对象，供调用者继续读取配置和执行自己的功能。

### 6.1 从 defName 取得定义

最直接的入口是 `DefDatabase<T>.GetNamed`。T 指定定义类型，参数 defName 提供名称。方法内部用 defsByName.TryGetValue 查字典，找到时把对象放进局部变量 t，再返回给调用者：

```csharp
T t;
if (DefDatabase<T>.defsByName.TryGetValue(defName, out t))
{
    return t;
}
```

沿用前面的教学定义，查询调用可以写成下面这样；这是调用示意：

```csharp
DefDatabase<StatDef>.GetNamed("ExampleStat");
```

这次调用返回前面建立并入库的 StatDef 对象。它保存 defName 和 label；引用连接完成后，调用者还可以沿 category 字段取得 ExampleCategory 对应的分类对象。两个 XML 文件描述的内容，就通过这些对象和引用交到了使用者手中。

### 6.2 其他位置已经保存了什么，就从哪里访问

| 使用者已经具备的信息 | 常用入口 | 得到什么 |
| --- | --- | --- |
| 定义类型和 defName | `DefDatabase<T>.GetNamed` | 名称字典中的定义引用 |
| 运行时取得的 Type 和 defName | GenDefDatabase.GetDef | 相应类型库中的定义引用 |
| 需要逐个查看某类定义 | AllDefs、AllDefsListForReading | 供遍历的定义列表 |
| 相应分组中的 shortHash | GetByShortHash | 短哈希字典中的定义引用 |
| 已绑定的 DefOf 字段，或其他对象中的 Def 字段 | 直接读取该字段 | 已经保存的定义引用 |

后续游戏系统取得这些定义，再执行任务、计算数值或组织画面。定义加载这一组工作，为它们准备好了可查找的对象、相互关联的配置，以及整理后的数据。

源码定位：名称查询（`Verse.DefDatabase.cs:251`）、按 Type 查询（`Verse.GenDefDatabase.cs:13`）、遍历入口（`Verse.DefDatabase.cs:14`、`Verse.DefDatabase.cs:24`）、短哈希查询（`Verse.DefDatabase.cs:291`）。

目录与各版状态见 [本组目录](README.md)。更细的目录选择、补丁组合、读取器分支和引用记录，保留在 [研究笔记索引](../../29-def-xml-outline.md#逐段研究进度)中，按需要查阅。
