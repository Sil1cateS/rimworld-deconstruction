# Def 的加载、存储与查询：定义怎样进入程序

版本：整合草稿 v0.1｜整理日期：2026-10-27

上一篇 [《XML 与 Def 结构》](01-xml-and-def-structure.md) 说明了文件、类型、定义对象与内部配置的关系。本篇继续沿普通启动，解释谁读取这些数据、对象保存在哪里、名称引用怎样连接，以及其他代码如何取得定义。

本文依据 RimWorld 1.7.4982 rev1280 的默认读取路径整理，暂不使用具体游戏内容案例。热重载、完整线程调度、语言注入与资源生命周期只标明必要位置；实际 Thing 创建、实例状态及属性计算留给后续模块。

先记住两点：**定义建立、入库、引用连接和后期整理是不同步骤；查询能力也不是到最后才一次性出现。** 已经入库的定义可以在加载中被查询，但它的某些关联与缓存仍可能尚未准备好。

## 一、谁组织加载，谁保存数据

### 1.1 几个主要参与者

| 类型或系统 | 本处的职责 |
| --- | --- |
| PlayDataLoader | 组织游戏内容准备，连接入库、生成、引用解析及后期整理 |
| LoadedModManager | 建立活动内容包，组织文件读取、统一 XML、补丁与定义读取 |
| ModContentPack | 保存一个活动内容包的目录、程序集、资源入口及定义列表 |
| LoadableXmlAsset | 保存一份已尝试读取的 XML 文档及来源信息 |
| XmlInheritance | 登记模板关系，准备可供读取的合并结果 |
| DirectXmlToObjectNew | 默认读取器，建立 Def 及内部配置对象 |
| DefDatabase&lt;T&gt; | 按类型保存与查询已经建立的定义 |
| DirectXmlCrossRefLoader | 保存名称引用记录，按显式调用尝试连接目标 |
| DefGenerator、DefOfHelper | 分别组织代码生成定义、绑定公共静态字段 |

ModMetaData 是内容包的元数据；ModContentPack 是本次加载中组织内容的对象；程序集提供的 Mod 派生对象则可以实现相应代码功能。三者不能仅因都与 Mod 有关就视为同一个对象。

### 1.2 普通启动的主线

LoadAllPlayData 进入 DoPlayLoad，后者调用 LoadedModManager.LoadAllActiveMods(false)。从文件读取到定义可供使用，主要关系如下：

![普通启动中的定义加载主线](figures/def-load-overview.png)

图按执行阶段概括，引用解析与生成内部的穿插在后文单独展开。语言、资源与全局初始化的若干调用未逐项画出；框架在中间阶段就可能查询已经入库的定义。[SVG](figures/def-load-overview.svg) · [图源](figures/def-load-overview.dot)

这里没有一个“先把一切读完，再同时完成所有引用”的统一步骤。文件会先变成 XML，XML 再变成对象；对象入库以后，引用解析、代码生成和静态绑定还会穿插推进。

源码定位：外层与总流程（`Verse.PlayDataLoader.cs:32`、`Verse.PlayDataLoader.cs:94`）、内容加载（`Verse.LoadedModManager.cs:56`）。

## 二、内容包怎样找到本次使用的文件

### 2.1 按活动内容包建立 ModContentPack

InitializeMods 遍历 ModsConfig.ActiveModsInLoadOrder，为可用目录建立 ModContentPack，写入相应加载序号。它使用这里已经给出的活动顺序，不在构造内容包时重新计算依赖关系。

Core、DLC 与其他 Mod 都使用这套内容包结构。构造时保存包信息，建立程序集和资源等处理对象，确定加载目录，并将有关资源包交给底层查找。这个构造过程尚未把所有 XML 直接变成 Def。

普通路径接着调用 LoadModContent、CreateModClasses、LoadModXML。程序集加载使后续类型查找能够发现代码提供的 C# 类型；资源读取还有通过 ExecuteWhenFinished 等安排的工作，不能仅按登记顺序认定全部完成时间。

### 2.2 一个内容包可以采用多个加载目录

InitLoadFolders 将本次采用的目录放入 foldersToLoadDescendingOrder，优先查找的目录在前面。

采用 LoadFolders.xml 时，主要按下面的顺序选择一组列表：

1. 尝试 CurrentVersionString 对应的非空列表。
2. 若未采用，筛选可解析且不高于当前版本的键，再按字符串降序选择候选。
3. 若仍未采用，尝试 default 列表。
4. 没有采用配置列表时，进入默认目录规则。

第二步的排序使用字符串键，不能改写成“按数字版本严格选最大值”。配置列表被采用以后，从末尾向前处理目录，并判断 IfModActive、IfModActiveAll、IfModNotActive 等条件；多个条件同时存在时需要同时满足。

采用配置分支后，不会自动补上 Common 与根目录，也不会仅因条件最终没有留下目录，就再次改走默认规则。

默认目录分支则先选相应版本目录，再加入存在的 Common，最后加入根目录。版本目录优先精确匹配；常规正版本候选中，优先不高于当前版本的最高版本，若候选都较新，也可能选到较新的版本。选中目录不表示已经验证其中内容与当前版本兼容。

### 2.3 文件选择与定义重名处理发生在不同层次

LoadModXML 按活动内容包顺序枚举各包的 LoadDefs，得到 LoadableXmlAsset 总列表。LoadDefs 的名称容易造成误会：这个入口返回的是 XML 来源对象，尚不是 Def 实例。

扫描时，读取器按目录优先级寻找 Defs/ 下的 XML，以相对于加载目录的路径作为去重键。字典 TryAdd 保留先遇到的同路径文件，后面的同路径项不再单独读取；这里不会合并它们的节点或字段。

| 层次 | 比较什么 | 主要结果 |
| --- | --- | --- |
| 同包多个加载目录的文件选择 | 相对文件路径 | 保留优先目录中的文件 |
| XML 补丁与模板处理 | 节点、属性、模板名与字段结构 | 修改或整理将被读取的 XML |
| 定义入库 | 对象的 defName | 按具体入口跳过、替换或改名 |

不同内容包各自扫描，不会因为相对路径相同就在这一步互相排除。文件入口也没有显式按文件名排序，不能据此建立“文件名字母越靠后，定义一定越晚生效”的规则。

文件读取有局部并行实现，返回前会等待这批读取完成。LoadableXmlAsset 保存来源包、文件名、目录和 XmlDocument；读取失败时可以留下 xmlDoc=null 的来源对象。一个来源对象存在，不保证文档有效。

源码定位：内容包建立（`Verse.LoadedModManager.cs:183`、`Verse.ModContentPack.cs:181`）、目录选择（`Verse.ModContentPack.cs:302`）、XML 收集（`Verse.LoadedModManager.cs:318`）、文件扫描（`Verse.DirectXmlLoader.cs:17`）、来源对象（`Verse.LoadableXmlAsset.cs:53`）。

## 三、先整理 XML，再建立定义对象

### 3.1 CombineIntoUnifiedXML 复制各文档的子节点

这个方法创建新的 Defs 根节点，按来源列表顺序，将每份文档根元素下的子节点深度导入统一文档。

同时，assetlookup 记录“导入后的顶层节点 → 原 LoadableXmlAsset”。它不以 defName 为键，也没有给每一个内部字段分别记录来源。

这一步没有合并同名定义的字段，没有解析 ParentName，也没有创建 Def。具有同一 defName 的节点仍可能先后进入统一文档，等待后面的处理。

### 3.2 PatchOperation 修改的是同一份文档

补丁从 Patches/ 读取，Operation 节点被建立为具体 PatchOperation 对象。此处使用 DirectXmlToObject 读取补丁对象；默认 Def 读取器采用新路径，不代表所有 XML 入口都已经统一成新实现。

带路径的操作使用 XPath 在 XML 树中选择目标节点。value 保存准备加入或替换的 XML 内容，仍不是已经建立的 Def。

ApplyPatches 按 runningMods 及其 Patches 的遍历顺序，让操作修改同一个 XmlDocument。后面的操作看到前面已经修改过的结果。

| 操作或组合 | 主要行为 |
| --- | --- |
| Add | 将 value 的子节点加入匹配目标内部 |
| Replace | 用 value 的子节点替换匹配目标本身 |
| Remove | 从父节点移除匹配目标 |
| Test | 返回 XPath 是否找到节点，不修改内容 |
| Conditional | 按匹配情况选择子操作，缺少分支时另有返回规则 |
| Sequence | 按顺序调用子操作，某项返回 false 时停止其余子操作 |

最外层 ApplyPatches 没有检查 Apply 的 bool 返回值；顶层操作正常返回 false 后，它仍继续后面的顶层操作。抛异常则在这一层记录错误并继续，也没有撤销先前修改的代码。

Sequence 内部会检查返回值，但停止剩余子项同样不等于回滚。PatchOperation.success 还能将正常返回结果保留、设为 true、设为 false 或取反；这不会跳过操作本身，也不消除它抛出的异常。

ErrorCheckPatches 在执行前收集配置问题；ParseAndProcessXML 之后的 ClearCachedPatches 会调用 Complete，再清除补丁对象缓存。名称中的 Clear 不表示恢复被补丁修改的 XML。

### 3.3 模板合并在补丁之后

ParseAndProcessXML 先登记顶层元素的模板关系，再调用 XmlInheritance.Resolve，然后继续建立定义。具体合并规则见上一篇的 [XML 模板关系](01-xml-and-def-structure.md#七xml-模板关系怎样补全节点)。

因此，补丁匹配的是模板合并之前的当前树。某字段最后会由父模板补入，不表示补丁执行时它已经存在于子节点下。

模板结果另存，原始节点仍用于来源查询。内置补丁向根部添加或替换顶层节点时，不会自动给新节点补 assetlookup 记录；修改原顶层节点内部的内容，则通常仍可通过原顶层对象找到来源。

这些区别决定后面的 Def 会由哪个内容包登记，或进入没有对应内容包来源的 patchedDefs。

源码定位：统一文档（`Verse.LoadedModManager.cs:408`）、补丁应用与检查（`Verse.LoadedModManager.cs:390`、`Verse.LoadedModManager.cs:348`）、操作公共入口（`Verse.PatchOperation.cs:12`）、顺序组合（`Verse.PatchOperationSequence.cs:11`）、模板与对象读取（`Verse.LoadedModManager.cs:437`）、补丁完成处理（`Verse.LoadedModManager.cs:594`）。

## 四、默认读取器怎样建立 Def 与内部配置

### 4.1 根节点选择类型，再取得读取方法

没有指定 legacy-xml-deserializer 时，ParseAndProcessXML 调用 DirectXmlToObjectNew.DefFromNodeNew；旧分支继续使用 DirectXmlLoader.DefFromNode。

默认入口跳过非元素节点，以及原始节点上 Abstract="True" 的项。随后用原节点元素名提供默认类型名，若模板解析结果存在 Class 属性则采用它，再通过类型查找与 GenTypes.IsDef 检查。

只有类型存在并属于 Def 分支，才继续取得读取委托。委托是可以调用的方法引用；这里分别有建立 Def、写字段与添加列表项的读取方法。

GetDefParserForType 的实现如下：

```csharp
public static DirectXmlToObjectNew.ParseValueAndReturnDefDelegate GetDefParserForType(Type type)
{
    if (DirectXmlToObjectNew.TypeCanBeDeserializedWithSharedBody(type))
    {
        type = typeof(Def);
    }
    DirectXmlToObjectNew.ParseValueAndReturnDefDelegate parseValueAndReturnDefDelegate;
    if (DirectXmlToObjectNew.parseDefMethods.TryGetValue(type, out parseValueAndReturnDefDelegate))
    {
        return parseValueAndReturnDefDelegate;
    }
    parseValueAndReturnDefDelegate = DirectXmlToObjectNew.CreateDefParserForType(type);
    DirectXmlToObjectNew.parseDefMethods[type] = parseValueAndReturnDefDelegate;
    return parseValueAndReturnDefDelegate;
}
```

第一次遇到相应类型时，读取器用 DynamicMethod 与 ILGenerator 生成读取方法，再缓存委托。后续可以复用它，不必为每个对象重新组织同一套步骤。

满足条件的类型可以共用方法体。缓存键改为 Def 不表示对象被改建成普通 Def；实际调用仍传入真实类型，生成的方法按它建立对象并寻找字段。自定义读取、PostLoad 等因素会影响是否采用共享分支。

这里还保留 FieldInfo.SetValue 等反射调用，即运行时通过类型、字段信息访问对象。因此，“生成读取方法”不等于“彻底消除反射”。生成方法和执行方法也要分开：Emit 正在写指令，委托被调用时才真正建立并填写当前对象。

### 4.2 普通复杂对象按字段递归读取

![普通复杂对象的字段读取循环](../../figures/xml-object-field-loop.png)

图示主要路径，省略值类型装箱、部分空节点及异常分支。自定义读取有独立路径。[SVG](../../figures/xml-object-field-loop.svg) · [图源](../../figures/xml-object-field-loop.dot)

普通引用类型先通过相应无参构造建立对象，字段初值与构造逻辑提供未被 XML 覆盖的起始数据。然后遍历子节点，通过 XmlToObjectUtils.DoFieldSearch 查找字段，包括继承来的成员。

| 数据类型或情况 | 主要处理 |
| --- | --- |
| 字符串、数值与枚举等 | 按对应规则解析并写入字段 |
| Type | 将名称解析为 System.Type |
| 普通嵌套对象 | 递归建立并读取 |
| 普通列表 | 取得条目类型，检查 XML 形状，再逐项读取 |
| Def 字段或 Def 列表项 | 通常登记名称引用，等待后面连接 |
| 提供 LoadDataFromXmlCustom 的类型 | 进入自定义读取，按该方法解释节点 |

字段查找还考虑 LoadAlias、大小写与忽略缺失节点的处理。普通未知字段会记录错误并跳过；大小写不一致时，也可能记录错误但继续使用找到的字段。Class 帮助选择读取类型，但类型适用性与赋值错误仍可能在后续步骤暴露。

普通复杂对象的字段循环结束后，若找到 PostLoad，生成的方法会调用它。自定义读取、空节点等分支有各自规则，不能把这次调用推广到所有对象。

**PostLoad 执行过，不意味着已经入库或引用完整。** 其中还可以通过 ExecuteWhenFinished 安排另一些函数，它们可能立即执行，也可能在长任务流程之后执行。

### 4.3 顶层与条目条件分别处理

顶层定义的 MayRequire、MayRequireAnyOf 可以让本次对象建立被跳过。普通非 Def 列表项也有条件检查；Def 引用条目则可能把条件登记下来，在后续查找失败时参与日志判断。

因此，不能因为 XML 使用同一属性名，就断言所有位置都会以同一种方式过滤对象。

源码定位：默认入口（`Verse.DirectXmlToObjectNew.cs:16`）、委托缓存与生成（`Verse.DirectXmlToObjectNew.cs:119`、`Verse.DirectXmlToObjectNew.cs:196`）、复杂对象路径（`Verse.DirectXmlToObjectNew.cs:1029`）、对象建立与共享条件（`Verse.DirectXmlToObjectNew.cs:1325`、`Verse.DirectXmlToObjectNew.cs:1378`）、字段查找（`Verse.XmlToObjectUtils.cs:15`）、条件处理（`Verse.DirectXmlToObjectNew.cs:1351`）、主调用点（`Verse.LoadedModManager.cs:437`）。

## 五、定义保存在哪里

### 5.1 先按来源登记，再按类型收集

默认读取返回 Def 后，ParseAndProcessXML 查询原顶层节点的来源。有对应内容包时，调用 ModContentPack.AddDef；没有时，加入 LoadedModManager 的 patchedDefs。

AddDef 的实现很短：

```csharp
public void AddDef(Def def, string source = "Unknown")
{
    def.modContentPack = this;
    def.fileName = source;
    this.defs.Add(def);
}
```

XML 调用点传入来源文档的 name，因此 fileName 保存的是来源名称，不是开发者的 C# 文件路径，也不等于完整文件路径。

LoadAllActiveMods 返回后，DoPlayLoad 对 Def 的各个子类调用相应 DefDatabase 的 AddAllInMods。类型枚举也包含抽象子类；各库通过 OfType<T> 选取能作为 T 使用的对象，因此同一对象可以进入多个兼容类型的库。

内容包从“属于哪个来源”组织定义，数据库从“属于哪种类型”组织定义。对象本身可以同时被两边引用。

### 5.2 DefDatabase 的三种存储视图

类型声明是：

```csharp
public static class DefDatabase<T> where T : Def
```

这是静态泛型类，不需要创建一个数据库实例再传入类型。不同的 T 分别具有自己的静态容器。

| 容器 | 结构 | 用途 |
| --- | --- | --- |
| defsList | List&lt;T&gt; | 遍历、计数与按位置编号 |
| defsByName | Dictionary&lt;string, T&gt; | 以 defName 查询 |
| defsByShortHash | Dictionary&lt;ushort, T&gt; | 以后续分配的 shortHash 查询 |

![来源与类型容器共同保存定义引用](figures/def-storage-views.png)

图中所有可见存储箭头都指向同一个定义对象，不表示数据处理顺序。短哈希字典在后面阶段才填写。[SVG](figures/def-storage-views.svg) · [图源](figures/def-storage-views.dot)

### 5.3 入库顺序与重名处理

AddAllInMods 先按 OverwritePriority，再按活动列表中的位置处理内容包。Core 的优先级为 0，其他包为 1；各包完成后再处理 patchedDefs 中相应类型的项。

| 重名发生的位置 | 当前处理 |
| --- | --- |
| 同包为当前 T 筛出的候选再次出现同名 | 记录错误，跳过后来这一项 |
| AddAllInMods 的辅助函数遇到目标库已有同名 | 从该库移除旧项，再添加当前项 |
| 直接调用 Add，名称已被当前库使用 | 记录错误，给传入对象追加随机数字并重查，直到名称可用 |

这三项是不同调用位置的判断，不是可以任选的设置。替换当前库的条目，也不会自动删除原内容包中的对象，或把所有已经保存的旧引用都指向新对象。

Add 真正保存对象的核心是：

```csharp
DefDatabase<T>.defsList.Add(def);
DefDatabase<T>.defsByName.Add(def.defName, def);
```

随后写入列表末项的 index；定义过多时记录错误，但这里没有因这条日志撤销添加。Add 本身不分配 shortHash，也不自动同步短哈希字典。

### 5.4 index 会随编号改变

SetIndices 先遍历列表写完 index，再逐个调用 PostSetIndices。移除旧项和批量整理等入口会触发相应编号。

一个定义可能出现在多个兼容类型的库里，但对象只有一个 index 字段。因此，某处实际使用的 index 需要结合类型库与阶段顺序理解，不能当成跨所有容器、永不变化的定义身份。

源码定位：来源分配（`Verse.LoadedModManager.cs:437`）、内容包登记（`Verse.ModContentPack.cs:610`）、数据库收集、添加与移除（`Verse.DefDatabase.cs:43`、`Verse.DefDatabase.cs:90`、`Verse.DefDatabase.cs:118`）、类型筛选（`Verse.GenDefDatabase.cs:63`）、编号（`Verse.DefDatabase.cs:210`）、内容包优先级（`Verse.ModContentPack.cs:95`）。

## 六、名称引用、代码生成与 DefOf 怎样穿插推进

### 6.1 名称引用先保存记录，再显式解析

XML 读取遇到需要另一份 Def 的字段时，通常先登记 DirectXmlCrossRefLoader 记录。记录保存需要写入的对象或集合、目标名称、类型和条件；它没有要求目标必须在读取这一行时已经存在。

主要容器是 wantedRefs，以及按目标集合查找对应记录的 wantedListDictRefs。不同记录的工作方式不同：

| 记录 | 主要行为 |
| --- | --- |
| WantedRefForObject | 查到目标后在 TryResolve 中直接写字段 |
| WantedRefForList&lt;T&gt; | 找到一项就追加到目标列表，并从待查名称中移除成功项 |
| WantedRefForDictionary&lt;K, V&gt; | TryResolve 准备键值数据，Apply 再处理和写入字典 |

一次 ResolveAllWantedCrossReferences 先并行调用各项 TryResolve，将返回 true 的记录加入已完成集合；等待本轮结束后逐个 Apply，再移出已完成记录。对象与列表没有额外 Apply 写入，它们已经在 TryResolve 修改目标。

列表可以部分成功。晚找到的项会追加在已有内容之后，因此多轮解析不保证始终维持最初 XML 的条目顺序。false 也不表示目标完全没有被修改。

字典还有独立边界：它会改用 LogErrors，正常走到末尾可返回 true，而不要求每个引用都找到；Apply 中非 Def 数据还会交给旧 DirectXmlToObject 路径读取。不能把对象、列表、字典都概括成同一种重试机制。

FailMode.Silent 主要控制相应缺失日志。条件允许缺失时，通常仍会尝试查询；找到目标仍可写入，找不到的记录也不一定被条件直接删除。声音替代与字典等分支还有自己的日志处理，Silent 不表示绝对没有日志。

### 6.2 为什么普通启动会多次尝试

![普通启动中的生成、引用解析与静态绑定](figures/def-binding-stages.png)

图只展开引用与生成附近的主线；相关语言处理和其他初始化合并标示，具体生成器内部工作未逐项展开。[SVG](figures/def-binding-stages.svg) · [图源](figures/def-binding-stages.dot)

| 顺序 | 主要调用 |
| --- | --- |
| 入库后 | 首轮 ResolveAllWantedCrossReferences，使用 Silent |
| 随后 | 早期 RebindAllDefOfs(true)，以及相关早期处理 |
| PreResolve 生成内部 | 先加入一批生成定义，再调用一轮 Silent 解析，之后继续生成 |
| 生成器返回后 | 使用 LogErrors 再解析一轮，并在 finally 中 Clear |
| 之后 | 最终 RebindAllDefOfs(false)，再进入类型自身整理等阶段 |

阶段之间数据库增加了内容，先前找不到的目标便可能在后面出现。一部分生成逻辑也会先使用已有引用，所以不能简单挪成“所有生成结束以后才第一次连接”。

Clear 只清空登记容器，不撤销已经写入的引用。仍未找到的记录则被丢弃，不再由原记录继续重试。LoadingInProgress 也只是检查 wantedRefs 是否非空，不是在报告后台线程状态或验证所有引用成功。

这套设施按加载阶段使用。成功记录从 wantedRefs 移除后，目标集合对应的旧记录仍可留在 wantedListDictRefs，直到 Clear；不能将它当作随时登记后都会自动恢复解析的常驻服务。

### 6.3 代码生成直接建立并登记 Def

DefGenerator 组织 PreResolve、PostResolve 两组生成。具体生成器建立对象，再交给 AddImpliedDef；它不需要先把结果写成 XML 再读回来。

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

这个方法接收已经建立的对象，不是在内部调用 new T()。普通路径依次设置生成标记、名称哈希、可用的来源登记，调用 PostLoad，再加入当前 T 的数据库。ImpliedDefs 是来源名称，不表示必须存在同名 XML 文件。

本篇以 hotReload=false 为范围。这里直接加入当前 T 的库，也没有自动将生成对象补入所有兼容父类型的库。

PostResolve 生成在类型自身整理之后执行，随后还会经历后置系统准备与短哈希等阶段。主流程没有在每次新增定义后自动重跑整套全库引用整理或最终 DefOf 绑定，需要按实际调用保证依赖。

### 6.4 DefOf 保存已有定义的静态引用

DefOf 是类上的标记特性；带标记的类中，公共静态字段可由 DefOfHelper 绑定。识别依据是标记，不是类名是否以 DefOf 结尾。

BindDefsFor 遍历字段，检查它属于 Def 类型；默认用字段名作为查询名称，DefAlias 可以改用指定 defName。普通非声音字段最后执行：

```csharp
Def def = GenDefDatabase.GetDef(fieldType, text, flag);
fieldInfo.SetValue(null, def);
```

fieldType 是字段类型，text 是名称，flag 控制普通缺失时的错误日志。SetValue 的目标为 null，因为这里写入静态字段。完成以后，普通字段访问直接读取保存的引用，不会每次重新查 XML。

早期与最终绑定都会查询并赋值。早期主要关闭普通缺失错误，最终通常报告缺失；MayRequire 等属性在这里也主要改变普通缺失日志，不直接跳过查找和字段赋值。找不到普通目标时可以写入 null，声音字段则有专用路径。

EnsureInitializedInCtor 的当前实现主要检查时机并记录警告，没有在其中调用整套绑定。因此，静态构造函数执行过，不等于所有静态定义字段已被填好；普通对象构造期间提前读取字段，也不会因后面绑定完成就自动重新赋值。

源码定位：引用登记与解析（`Verse.DirectXmlCrossRefLoader.cs:29`、`Verse.DirectXmlCrossRefLoader.cs:247`）、清理与状态（`Verse.DirectXmlCrossRefLoader.cs:232`、`Verse.DirectXmlCrossRefLoader.cs:20`）、两组生成与登记（`RimWorld.DefGenerator.cs:11`、`RimWorld.DefGenerator.cs:59`、`RimWorld.DefGenerator.cs:72`）、DefOf 标记（`RimWorld.DefOf.cs:7`）、绑定与时机检查（`RimWorld.DefOfHelper.cs:12`、`RimWorld.DefOfHelper.cs:27`、`RimWorld.DefOfHelper.cs:88`）。

## 七、类型自身整理、配置检查与短哈希

### 7.1 ResolveReferences 由具体类型决定做什么

名称引用解析结束、最终 DefOf 绑定完成以后，DoPlayLoad 先执行 ResetStaticDataPre，再按类型调用数据库的 ResolveAllReferences。

该方法前后各执行一次 SetIndices，中间遍历符合条件的定义并调用其 ResolveReferences。onlyExactlyMyType 为 true 时，只处理运行时类型恰好等于 T 的对象；前后编号仍遍历整个列表。

普通加载先处理 ThingCategoryDef，再处理 RecipeDef；随后遍历排除 ThingCategoryDef、RecipeDef、ThingDef 后的其他 Def 子类，最后处理 ThingDef。前两组的 parallel=true，表示在各自调用内部并行，不表示这些组同时开始。该批工作结束后才继续后续阶段。

具体类型的 ResolveReferences 可以补默认值、整理内部配置、建立集合或缓存。它与前面按登记名称填引用的解析器职责不同；也不能根据名称就认为每个 Def 都执行相同处理。

Def 本层的实现清楚展示了这种继续调用：

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

单个定义在数据库的整理调用中抛异常，会被捕获并记录，再继续其他对象；已经作出的修改不会因此自动撤销。

主流程随后还登记着色器、安排预热，执行 PostResolve 生成与 ResetStaticDataPost。两个 ResetStaticData 入口组织多个系统的准备，不能仅按名字将它们统一理解为清空静态字段。

### 7.2 ConfigErrors 是检查入口，不是入库许可

本处整批 ErrorCheckAllDefs 受 Prefs.DevMode 控制。执行时，数据库跳过 ignoreConfigErrors=true 的对象，遍历其他对象的 ConfigErrors 结果并记录日志；检查抛异常也会在这里记录。

因此，关闭开发者模式只会跳过本处的整批检查，不会关闭 XML 读取、引用解析或其他阶段的错误。报告一条配置问题，也不表示该对象被自动移出数据库，或加载事务被回滚。

ConfigErrors 可以由类型覆写，检查内容各不相同；部分实现还带有整理动作。不能把“没有看到这批错误”解释为所有定义都已验证有效。

### 7.3 shortHash 在后面的独立阶段分配

经过配置检查分支与键位设置初始化后，GiveAllShortHashes 按所选定义类型组处理：取得定义，按 defName 排序，逐个分配，再调用对应数据库的 InitializeShortHashDictionary。

分组会跳过抽象类型，并排除在 Def 以下已有非抽象祖先的类型；不能因某个 DefDatabase 存在，就推断它在这里另有独立一组短哈希。

单项分配从名称的 StableStringHash 取得候选 ushort，遇到 0 或本组已占用值就继续加一寻找。已经持有非零 shortHash 的对象会记录错误并跳过分配。

![短哈希候选值与冲突处理](../../figures/def-short-hash-allocation.png)

图省略寻找次数过多时的日志提示；该提示没有让循环自动扩容或退出。[SVG](../../figures/def-short-hash-allocation.svg) · [图源](../../figures/def-short-hash-allocation.dot)

分配完成后，数据库用已有数值填写查询字典：

```csharp
public static void InitializeShortHashDictionary()
{
    DefDatabase<T>.defsByShortHash.EnsureCapacity(DefDatabase<T>.defsList.Count);
    for (int i = 0; i < DefDatabase<T>.defsList.Count; i++)
    {
        DefDatabase<T>.defsByShortHash[DefDatabase<T>.defsList[i].shortHash] = DefDatabase<T>.defsList[i];
    }
}
```

这里不负责产生 shortHash，也没有先清空字典。正常加载依赖相应阶段顺序，单独调用 Add 不等于所有查询结构立即同步就绪。

shortHash 只在相应分组中参与查询，最终值受其他占用情况影响。它不是跨所有内容组合永不变化的全局身份，也不是运行中实例的独立编号。

源码定位：批量整理与编号（`Verse.DefDatabase.cs:143`、`Verse.DefDatabase.cs:210`）、扩展整理（`Verse.Def.cs:38`）、主流程与前后准备（`Verse.PlayDataLoader.cs:94`、`Verse.PlayDataLoader.cs:663`、`Verse.PlayDataLoader.cs:722`）、配置检查（`Verse.DefDatabase.cs:223`）、分组与分配（`Verse.GenDefDatabase.cs:57`、`Verse.ShortHashGiver.cs:14`、`Verse.ShortHashGiver.cs:48`）、字典填写（`Verse.DefDatabase.cs:302`）。分组筛选的既有 IL 核对位置保留在 [数据库研究笔记](../../34-defdatabase.md)。

## 八、其他代码怎样取得已经建立的定义

### 8.1 显式名称查询

DefDatabase<T>.GetNamed 在 defsByName 中查找。默认找不到时记录错误并返回 default(T)；T 继承 Def，所以这里返回的是 null。传 errorOnFail=false 时不记录该普通缺失错误。

GetNamedSilentFail 只是这个调用的包装：

```csharp
public static T GetNamedSilentFail(string defName)
{
    return DefDatabase<T>.GetNamed(defName, false);
}
```

名称查询用的是 defName，不根据 label 或 description 猜测目标。这次操作返回已经入库的对象引用，不会重新读取对应文件。

若运行时拿到的是 Type，而不是在代码中直接写明泛型参数，可以用 GenDefDatabase.GetDef。它查找并缓存相应泛型库的查询委托，再传入名称与日志选项。缓存的是调用方法，不是另一份定义列表。

### 8.2 遍历与短哈希查询

| 入口 | 返回或查询什么 |
| --- | --- |
| AllDefs | 以 IEnumerable&lt;T&gt; 返回 defsList |
| AllDefsListForReading | 直接返回原 List&lt;T&gt; |
| DefCount | 返回列表 Count |
| GetByShortHash | 查询 defsByShortHash，找不到时返回 null |

前两个入口都没有复制列表。ForReading 表达使用意图，但类型本身不禁止修改；直接改列表也不会自动维护名称字典或短哈希字典。

GetByShortHash 则需要对应字典已经填写。拥有一个 Def 对象或名称查询成功，不足以证明短哈希入口此时也已准备完成。

### 8.3 读取静态字段或已有引用

另外两种常见方式不需要在使用位置再次写名称查询：读取已经绑定的 DefOf 静态字段，或沿其他对象已经保存的 Def 字段、列表项访问目标。

它们的结果仍然是对象引用。访问者可以读取目标的字段或方法，但哪些后期准备已经完成，需要结合调用阶段判断。DefOf 提供方便的静态入口，不会让所有依赖自动提前就绪。

### 8.4 Clear 与 ClearCachedData 的对象不同

| 操作 | 当前库或对象的变化 |
| --- | --- |
| DefDatabase.Clear | 清空本库的列表、名称字典与短哈希字典 |
| DefDatabase.ClearCachedData | 遍历定义，调用各自的 ClearCachedData |
| Def.ClearCachedData | 本层清除 cachedLabelCap，派生类型还可继续处理 |

清空容器不等于销毁所有定义。其他代码已经持有的对象引用不会因此自动消失，也不会自动变成后来重新建立的定义。

源码定位：名称与短哈希查询（`Verse.DefDatabase.cs:251`、`Verse.DefDatabase.cs:285`、`Verse.DefDatabase.cs:291`）、遍历入口（`Verse.DefDatabase.cs:14`、`Verse.DefDatabase.cs:24`）、按运行时类型查询（`Verse.GenDefDatabase.cs:13`）、清理（`Verse.DefDatabase.cs:126`、`Verse.DefDatabase.cs:134`、`Verse.Def.cs:64`）。

## 九、怎样判断加载进度与错误的含义

| 已到达的阶段 | 可以确认什么 | 不能由此直接确认什么 |
| --- | --- | --- |
| 文件读取结束 | 已取得本轮来源对象与可用文档 | 每份文档有效、每个节点都将建立定义 |
| DefFromNodeNew 返回对象 | 已有定义及相应读取结果 | 已入库、所有引用已连接 |
| Add 入库完成 | 列表与名称字典已登记当前项 | 短哈希、静态绑定与后期缓存全部就绪 |
| 某轮引用解析结束 | 本轮已按各记录类型尝试处理 | 剩余项全部成功，或没有部分写入 |
| ResolveReferences 返回 | 相关类型完成本次调用 | 所有定义都执行相同处理或通过全部检查 |
| DoPlayLoad 返回 | 外层可以设置 loadedInt=true | 所有安排的后续函数和资源工作都已经完成 |

失败也要放回具体入口：无效根节点、找不到类型、未知字段、缺失定义、模板错误、补丁 false 返回与抛异常，都有不同处理。有的跳过单项，有的保留待连接记录，有的退回原节点继续；Log.Error 本身不能统一解释为整个加载立即终止。

LoadAllPlayData 还有外层异常与恢复分支，受相应配置及状态控制。那是加载流程的另一层职责，本篇不把局部日志与异常恢复混为一步。

源码定位：默认读取失败处理（`Verse.DirectXmlToObjectNew.cs:16`）、模板结果回退（`Verse.XmlInheritance.cs:115`）、外层加载与标记（`Verse.PlayDataLoader.cs:32`）、后续函数登记（`Verse.LongEventHandler.cs:224`）。

## 十、定义框架到哪里结束

这一组过程把内容来源变成程序中的定义对象，再通过来源容器、类型数据库、名称记录与静态字段建立可查询、可访问的关系。类型自身的方法继续整理默认值、关联与缓存，使后续系统能够按各自入口使用配置。

定义框架负责这些共同的数据准备与访问机制。具体系统怎样创建运行对象、推进任务、计算数值或形成画面，继续沿使用者的代码研究；无需在这里为每一种内容重复展开其运行过程。

两篇合起来，先回答了“定义由什么组成”，再回答“定义怎样进入程序并被找到”。范围与后续修订入口见 [本组目录](README.md)。
