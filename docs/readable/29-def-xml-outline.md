# 从 XML 到游戏内容：Def 与定义系统（大纲）

状态：讨论大纲 v0.4，2026-10-28 更新定稿与草稿入口。依据工作区 RimWorld 1.7.4982 rev1280 的游戏代码整理。承接 [对象与组件章节](chapters/02-UnityWorld&UnityObject/README.md)。本组分为“XML 与 Def 结构”“Def 的加载、存储与查询”两篇；第一篇已定稿为 v1.0，按类型结构、XML、模板合并与对象数据组织，保留完整巨弓 XML、选取类型的定义样例与字段对照；第二篇仍为通用流程的整合草稿。实际 Thing 的创建、实例状态与属性计算留到后续物品模块。

## 当前文章入口

| 文章 | 内容范围 |
| --- | --- |
| XML 与 Def 结构 v1.0：[发布版](chapters/03-def-framework/01-xml-and-def-structure-release.md) · [完整解析版](chapters/03-def-framework/01-xml-and-def-structure.md) | Def 类型结构、XML 写法、模板合并、对象字段与引用、巨弓字段对照和公共方法；发布版只删除精确定位，保留全部内容 |
| [Def 的加载、存储与查询，整合草稿 v0.1](chapters/03-def-framework/02-def-loading-storage-query.md) | 内容来源、XML 处理、对象读取、来源与类型容器、引用生成与绑定、后期整理和查询 |

两篇共同存放于 [Def 框架目录](chapters/03-def-framework/README.md)。第一篇的两版均已定稿，第二篇继续共同审阅；第一篇的 [整合草稿 v0.3](chapters/03-def-framework/01-xml-and-def-structure-draft.md) 保留为底稿。下面保留逐段研究进度与原阅读计划；旧笔记中的实例创建与状态研究继续留给后续模块，当前结构篇只选择直接说明定义结构的例子。

## 逐段研究进度

已开始的讨论：[一份长剑定义与两件实际物品](30-def-and-instances.md)，先区分文件、类型、共享定义与独立实例；随后进入 [Editable 与 Def](31-editable-and-def.md)，认识定义共同具有的数据与方法，再读 [BuildableDef](32-buildabledef.md) 的属性基础值、材料与放置相关配置，以及 [ThingDef](33-thingdef.md) 如何连接具体对象类型、组件与攻击配置。接着由 [DefDatabase](34-defdatabase.md) 解释保存、查询、重名处理与编号，再进入 [ModContentPack](35-modcontentpack.md) 的内容来源、加载目录与 XML 文件选择，并由 [统一 XML 与补丁](36-xml-merge-and-patches.md) 解释节点复制、来源记录与补丁执行。随后进入 [XmlInheritance](37-xml-inheritance.md) 的模板登记、父节点选择与字段合并。后续按下面的顺序继续。

随后由 [从 XML 到对象](38-xml-to-objects.md) 解释默认读取器的类型选择、读取方法生成与缓存，以及数值、列表、嵌套配置和待连接引用；再由 [定义引用怎样连接](39-def-cross-references.md) 核对不同记录的写入方式、部分成功与普通启动中的多次解析。接着进入 [代码生成定义与 DefOf](40-generated-defs-and-defof.md)，从长剑制造配方接到生成入库、工作台取得配方，以及静态字段绑定，再由 [定义加载的收尾](41-def-final-preparation.md) 说明各类型的自身整理、材料筛选、配置检查条件与短哈希分配。

边界调整：早期笔记中的两件物品与组件样例，在本章整合时只保留“使用者引用共同定义、另有自己的状态”这一关系，以及 thingClass、comps 等配置的用途。[实际长剑的创建](42-thingmaker-and-instance-state.md) 改列为后续物品模块的预备笔记，保留已核对的源码与图示，暂不纳入本章主线。

按此边界完成的 [框架复核与整合取舍](43-def-framework-review.md) 确认主线材料已经覆盖；整合时补齐类型与对象总览、全程流程图及查询接口的收束，并按记录压缩越出本章范围的案例。

## 一、这一部分要解释什么

前两章说明引擎怎样持续运行，以及对象与组件怎样被组织、查询和更新。本部分继续解释：游戏内容从哪里来，文件中的描述怎样变成运行中的定义，以及其他系统怎样取得这些定义与配置。

本章的主线是：**内容文件与代码生成 → Def 对象 → 数据库、相互引用与加载后整理 → 可供其他系统查询和引用的定义。** 游戏中的物品、工作台与界面用于说明配置的意义；使用者内部的创建、状态变化、属性计算与显示实现，在各自模块展开。实际加载中，定义生成、入库和引用处理会相互穿插，执行顺序另按源码画图说明。

“静态定义”在这里主要用于区分共同内容配置与各个实例的变化状态。Def 本身仍然是 C# 对象，可以包含方法、引用、缓存与加载后生成的数据；不因此等于 C# 的 static，也不表示内容绝对不可修改。

本部分要让读者能够回答：

- XML 文件、Def 实例、DefDatabase 和实际游戏对象，各自是什么？
- 共同定义、嵌套配置与实际使用者之间，分别是什么关系？
- 内容包、XML 父模板、补丁、类型选择与引用解析，分别在哪一步起作用？
- 一个字段怎样进入定义，又通过什么查询或引用交给后续系统？

## 二、贯穿案例与阅读方法

本轮选择原版长剑 MeleeWeapon_LongSword 作为主例，追踪模板与补丁、定义字段、嵌套配置、关联定义及代码生成的制造配方。两件实际物品只用于说明共享定义与独立状态的区别；它们的创建步骤、耐久与品质变化，以及最终属性计算，转到物品模块。

案例按需要使用真实 XML 节选与 C# 源码，不先虚构一套能运行的 Mod。若需要教学例子，明确注明其用途，并区分原文件、处理后的 XML、已经建立的 Def 与实际物品。

文章先认识数据结构，再沿加载顺序解释定义怎样建立，最后以查询与引用说明它们怎样交给使用者。结构介绍与实际执行流程分别画图，避免把继承、引用、加载顺序混在同一种箭头中。

## 三、原逐段阅读大纲

### 1. 总览：文件、定义与实际对象

- 从主例出发，区分“一种武器的内容定义”和“游戏中实际存在的两件武器”。
- 认识 XML 节点、C# 类型、Def 实例、运行中的 Thing 实例，说明它们之间的对应关系。
- 说明定义对象怎样被多个使用者引用，以及哪些状态要保存在每个实例中。
- 将本部分放回启动与游戏运行：内容准备完成后，游戏系统才有相应的定义可以查询和使用。

配图：一份共同定义与两个实际实例的引用关系图。

### 2. Def 的结构：共同基类与代表性子类

- 从 `Verse.Editable → Verse.Def` 开始，说明每一级提供的接口与数据。
- 解释 `defName`、`label`、`description`、来源信息与扩展数据；再区分 `index`、`shortHash`、`defNameHash` 等标识的用途。
- 区分可在文件中填写的数据、加载流程补充的信息、运行中计算或缓存的结果。
- 先认识 `PostLoad`、`ResolveReferences`、`ConfigErrors` 的职责，具体调用位置在加载流程中展开。
- 以 `Def → BuildableDef → ThingDef` 为主分支，按需要提及配方、任务等其他定义类型，不逐一展开所有 Def 子类。
- 说明 `ThingDef.thingClass` 与 `comps` 等字段怎样连接后续实例及组件配置；具体执行逻辑在相关模块继续。

配图：相关类型树，并单独标出定义与运行实例的引用关系。

### 3. DefDatabase：定义怎样保存与查找

- 解释 `DefDatabase<T>` 的按类型组织方式，以及它与内容包所持有定义的关系。
- 认识列表、按名称查询表、`AllDefs`、`GetNamed` 等接口。
- 说明按名称查询、遍历与代码中的直接引用，怎样取得已经建立的定义。
- 沿 `AddAllInMods`、`Add` 与具体辅助方法，分别核对入库顺序、同一内容包内重名、不同来源重名的处理规则。
- 在调用点区分内容排序、XML 补丁修改与数据库同名处理，不提前用“后加载的一律覆盖”概括。

本节先建立保存和查询的结构；它在整体加载中的具体位置，随后续流程接回。

### 4. 内容从哪里来：内容包与文件选择

- 认识 `ModContentPack`，说明内容包、目录、程序集、XML 与资源各自的关系。
- 沿 `LoadedModManager` 认识活动内容包的建立与内容读取入口。
- 核对加载顺序、版本目录、文件来源及相应筛选条件怎样参与选择。
- 说明 `LoadableXmlAsset` 保存什么，以及后续报错如何追溯来源。
- 程序集只解释到提供可被查找的 C# 类型，纹理、音频等资源只解释到内容来源与引用入口。

### 5. XML 的整理：合并、补丁与父模板

- 沿当前普通加载路径，说明文件读取、统一 XML、补丁应用与进入节点处理的顺序。
- 认识 PatchOperation 在什么对象上操作，选取少量常见操作解释节点怎样改变。
- 展开 `XmlInheritance` 的登记、父模板查找、继承与合并规则。
- 区分 XML 的 `Name`、`ParentName`、`Abstract`，定义字段 `defName`，以及 C# 的类继承。
- 核对抽象模板、列表合并、重复节点和条件属性在各自位置的具体处理。
- 以主例对照原文件与实际用于创建定义的节点，说明为何文件里未直接写出的内容仍可能出现在结果中。

配图：XML 处理流程；遇到复杂合并或判断时，再补局部图。

### 6. 从 XML 节点建立 C# 对象

- 从当前默认入口 `DirectXmlToObjectNew.DefFromNodeNew` 进入，说明节点名称、`Class` 与实际 C# 类型的选择。
- 解释简单值、枚举、列表、嵌套对象和类型字段怎样被读取并写入对象。
- 区分 XML 的 `Class`、`ThingDef.thingClass` 与组件配置中的 `compClass`：它们分别在哪一步决定什么类型。
- 说明特殊读取方法、自定义数据结构与普通字段读取怎样衔接。
- 核对方法生成与缓存所做的工作，正文解释其用途，复杂 IL 生成细节视需要作为补充材料。
- 将定义引用的读取接到待解析记录，说明此时“创建了对象”与“关联已经完整”分别表示什么。
- 核对 `PostLoad` 等处理的实际调用位置，不将其与后续统一引用整理混为一步。

版本说明：当前 `ParseAndProcessXML` 在未指定 `legacy-xml-deserializer` 时选择新路径；旧路径由 `DirectXmlLoader`、`DirectXmlToObject` 等继续处理。正文以默认路径为主，对照旧实现时注明分支。

### 7. 加载后的整理：引用、生成与校验

- 回到 `PlayDataLoader.DoPlayLoad`，将内容包中的定义、全局数据库与后续整理连接起来。
- 区分 XML 中登记的名字引用、各 Def 的 `ResolveReferences`，以及 DefOf 静态字段的绑定。
- 解释 `DirectXmlCrossRefLoader` 怎样保存待处理引用、何时尝试解析、失败如何继续或报告。
- 认识 `DefGenerator` 的前后两组生成入口：部分定义由代码生成，需要与已有定义及后续绑定衔接。
- 按实际调用说明多轮解析与绑定的原因，再接到类型自身的整理、短哈希分配和配置检查。
- 将这些阶段放入一张实际流程图；语言注入、全局缓存与资源初始化标明位置，按主例需要选择展开程度。
- 在相应阶段解释缺失引用、类型不匹配、同名定义、字段错误等现象，不把所有报错归为同一种问题。

本节不预设“一次读取后统一解析一次”的固定模型；也不将 `ResolveReferences` 理解为所有类都执行相同处理。

### 8. 定义怎样交给使用者：框架收束

- 从数据库查询、DefOf 静态字段或其他定义中的引用，取得已经建立的定义对象。
- 以主例说明 thingClass 提供实际对象类型，comps 保存组件配置；各项配置怎样执行，由后续使用者负责。
- 用简短引用关系图区分共同定义与实际使用者，不展开 MakeThing、组件初始化与实例属性。
- 将 XML 读取、PostLoad、名称引用解析、DefOf 绑定、ResolveReferences、生成与校验放回实际加载顺序。
- 以流程图收束“内容来源 → 定义建立与入库 → 引用、生成与整理 → 查询与对外提供配置”。

本章的案例到定义可供查询和引用为止。实际物品创建、组件生命周期、耐久与品质状态及属性计算，留到物品与相关系统模块；制造任务、持续 tick 和具体绘制也按各自模块展开。

## 四、范围与后续模块的交接

| 内容 | 本部分解释到哪里 | 后续展开 |
| --- | --- | --- |
| 内容加载的执行入口 | 谁开始加载，主要阶段怎样排列 | 线程、长任务、进度显示与异常恢复的完整执行机制 |
| Thing 与组件 | thingClass、comps 的配置意义，以及定义与使用者的引用关系 | MakeThing、实际组件建立、实例状态、地图登记、生命周期与行为 |
| 属性与面板 | 属性基础值、StatDef 引用等配置怎样进入定义 | 材质与品质的参与、最终属性计算、查询缓存与界面显示 |
| 纹理、音频和其他资源 | 定义如何保存引用，内容包如何提供来源 | 解码、资源生命周期、音频播放与渲染 |
| 存档 | 运行对象引用定义的关系，必要的读取接点 | Scribe、引用恢复、存档兼容与派生状态重建 |
| Mod 与热重载 | 影响本例的目录选择、补丁、类型和引用规则 | 完整程序集加载、Harmony、热重载及兼容性专题 |
| DLC | 使用相应定义作为必要例子 | 各 DLC 的独有系统与运行模式 |

本轮以普通启动加载路径为主。源码存在的热重载等分支单独注明，不自动将普通加载过程的结论推广过去。

## 五、需要优先核对的源码入口

这里列类型与方法作为阅读导航，不将尚未展开的分支写成既定结论。正式源码节选仍保留原名，并按系列约定补充文字定位。

| 阅读内容 | 主要入口 |
| --- | --- |
| 基类与主例类型 | `Verse.Editable`、`Verse.Def`、`Verse.BuildableDef`、`Verse.ThingDef` |
| 保存与查询 | `Verse.DefDatabase<T>`、`Verse.GenDefDatabase` |
| 总加载流程 | `Verse.PlayDataLoader.DoPlayLoad`、`Verse.LoadedModManager.LoadAllActiveMods` |
| 内容包与 XML 来源 | `Verse.ModContentPack`、`Verse.LoadableXmlAsset`、`Verse.DirectXmlLoader` |
| XML 合并与补丁 | `Verse.LoadedModManager.CombineIntoUnifiedXML`、`ApplyPatches`、`ParseAndProcessXML`，以及 `Verse.PatchOperation` |
| XML 父模板 | `Verse.XmlInheritance` |
| 默认对象读取路径 | `Verse.DirectXmlToObjectNew.DefFromNodeNew` 及类型解析、字段写入相关方法 |
| 旧对象读取路径 | `Verse.DirectXmlLoader.DefFromNode`、`Verse.DirectXmlToObject` |
| 引用处理 | `Verse.DirectXmlCrossRefLoader`、各 Def 的 `ResolveReferences` |
| 定义生成与代码绑定 | `RimWorld.DefGenerator`、`RimWorld.DefOfHelper`、`Verse.ShortHashGiver` |
| 配置与使用者的接点 | `Verse.ThingDef.thingClass`、`Verse.ThingDef.comps`、`Verse.CompProperties`；实际创建留到物品模块 |

旧版 [Def 与 XML 管线资料](../mechanisms-v3/V15-defs-and-xml.md) 作为检索与对照材料，具体顺序、解析路径及行为仍回到当前源码核对。

## 六、原逐段讨论顺序

先建立主例中的“文件、类型、定义对象、使用者”关系，再读 Editable 与 Def，进入 ThingDef 所需分支和 DefDatabase。随后从内容包沿加载入口向下，展开 XML 处理、定义对象建立、引用、生成与整理，最后回到定义的查询接口及加载全程，收束框架。

遇到需要较多背景的独立系统，先说明本处的输入、输出和调用关系，再记录到对应后续模块。整合稿与发布版在完成这些讨论后另行整理。
