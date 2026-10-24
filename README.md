# rimworld-deconstruction

从源码出发，解释 RimWorld 的引擎、对象与各个游戏系统怎样运行，再将这些过程对应到玩家熟悉的行为与画面。

目前主要阅读入口是 [《RimWorld 源码解析》系列](docs/readable/)，按系统与模块组织，使用文字、案例、必要代码和图示讲解运行逻辑。旧版技术文档与工具脚本继续保留，供深入查找和本地核对。

本仓库提供分析文章、图示、研究资料与工具脚本。游戏本体、DLC 数据、完整反编译语料及游戏资源不随仓库分发。

# 我们最新的给碳基生物读的版本已经全方位超越了老式的机读版本！

目前两章均已定稿为 v1.0，各提供两个阅读版本：

| 章节 | 主要内容 | 发布版 | 完整解析版 |
| --- | --- | --- | --- |
| 01 · Waylith：从启动到每一帧 | 引擎创建与初始化、主循环、两条线程、队列等待，以及绘制数据到 Vulkan 的交接 | [阅读发布版](docs/readable/chapters/01-waylith/release.md) | [阅读完整解析](docs/readable/chapters/01-waylith/article.md) |
| 02 · UnityWorld 与 UnityEngine.Object | 兼容层与原生 Unity 的关系、对象登记、组件组成、Transform、启停与更新，以及必要的协程支持 | [阅读发布版](docs/readable/chapters/02-UnityWorld&UnityObject/release.md) | [阅读完整解析](docs/readable/chapters/02-UnityWorld&UnityObject/article.md) |

第一次阅读可以先按章节顺序读发布版。发布版以运行逻辑和图示为主，在需要时保留代码块与表格；完整解析版保留较完整的源码节选、对象与状态说明、分支条件和源码定位。

章节范围与图源索引见 [第一章目录](docs/readable/chapters/01-waylith/README.md)、[第二章目录](docs/readable/chapters/02-UnityWorld&UnityObject/README.md)。完整的模块规划与写作约定见 [系列大纲](docs/readable/00-series-outline.md)。

## 系列范围与研究进度

当前成稿覆盖引擎运行和兼容层的对象、组件基础。后续主题包括游戏进程与 tick（游戏模拟的一步）调度、定义与存档、地图和空间、Thing 与 Pawn、AI 与工作、战斗、界面与表现，以及 DLC 独有系统；具体拆篇与顺序随模块研究继续讨论。

相机、音频和网格组件在第二章中作为协作样例，其详细功能留到对应模块。协程的完整调度也留待进程与运行部分展开。绘制数据结构与各绘制阶段的详细研究，安排在地图、空间与 UI 解析之后。

## 分析依据与源码引用

当前研究依据 RimWorld 1.7 的 `1.7.4982 rev1280`，逻辑程序集 `Assembly-CSharp` 版本为 `1.7.9787.38423`，运行时为 .NET 10，引擎为 Waylith。各篇的范围与版本以文章说明为准。

系列采用静态源码阅读，重点追踪谁调用谁、状态与数据由谁保存，以及结果如何进入下一阶段。帧率、实际耗时与显示延迟等问题，需要另外测量。涉及 UnityEngine 类型时，正文以当前兼容层实现为依据，并说明与原生 Unity 的相关区别。

源码节选沿用原有命名，讲解用例另行注明。完整解析版采用 `命名空间.类型名.cs:行号` 的文字定位，例如 `RimWorldWaylith.Bootstrap.cs:749`；这里的行号对应本地反编译文件，并非开发者的原始源码行号。仓库内文档、图片与图源使用相对链接，反编译语料不设 GitHub 文件链接。

## 资料目录

| 位置 | 内容 |
| --- | --- |
| [docs/readable/chapters/](docs/readable/chapters/) | 系列文章的发布版、完整解析版、整合底稿与章节图源 |
| [docs/readable/](docs/readable/) | 系列大纲、逐步讨论与源码阅读笔记 |
| [docs/readable/figures/](docs/readable/figures/) | 通用图像、SVG 与可编辑 DOT 图源 |
| [docs/mechanisms-v3/](docs/mechanisms-v3/) | 旧版 24 卷系统化技术资料，保留源码断言与实现索引 |
| [docs/mechanisms/](docs/mechanisms/) | 第一轮 24 卷文档，冻结归档，见 [归档说明](docs/ARCHIVE-v1.md) |
| [scripts/](scripts/) | 本地反编译、索引生成与旧版文档核对工具 |
| [analysis/index/](analysis/index/) | 类型、命名空间等检索索引 |

`RimWorld/`、`RimWorld1.6/`、`analysis/decompiled/` 与 `analysis/decompiled1.6/` 是本地输入和反编译目录，由 `.gitignore` 排除。

## 旧版技术资料与本地核对

旧版技术文档按固定结构组织，使用 `src`、`file`、`match` 记录可核对的源码片段。交付与核对记录见 [DELIVERY.md](DELIVERY.md)，实现导航及待验证问题见 [HANDOFF.md](HANDOFF.md)，旧版写作规范见 [docs/STYLE.md](docs/STYLE.md)。新系列的写作约定见上面的系列大纲。

<details>
<summary>本地反编译与旧版文档校验</summary>

本地核对需要自备合法购买的游戏副本。基本步骤如下：

1. 将所需游戏文件放到本地 `RimWorld/`，或通过脚本参数指定位置。
2. 准备 dnSpyEx 6.6 的 `dnSpy.Console.exe`，加入 `PATH`，或用 `DNSPY_CONSOLE` 环境变量指定路径。
3. 使用 [decompile.ps1](scripts/decompile.ps1) 导出程序集；Waylith 的逐类型导出与 IL 回退工具见 [dump-waylith.ps1](scripts/dump-waylith.ps1)。
4. 使用 [list-types.ps1](scripts/list-types.ps1) 生成类型索引，再按需核对旧版文档。

旧版 v3 文档的检查命令为：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\lint-docs.ps1 -Profile v3 -DocsRoot docs\mechanisms-v3
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-claims.ps1 -DocsRoot docs\mechanisms-v3
```

其他检索与诊断工具包括 [list-types-meta.ps1](scripts/list-types-meta.ps1)、[probe-type.ps1](scripts/probe-type.ps1)、[dump-types.ps1](scripts/dump-types.ps1)、[decompile-diagnose.ps1](scripts/decompile-diagnose.ps1) 与 [backtest.ps1](scripts/backtest.ps1)。路径和导出范围以各脚本参数为准。

这些检查针对旧版文档的结构与源码文本断言。`docs/readable/` 的系列文章采用自身的写作格式，结合源码节选核对、调用关系检查及共同阅读修订。历史校验结果见交付记录。

反编译文件的局部变量名与行号不能视为开发者原始源码中的命名和位置；部分类型还可能需要查 IL。既有语料中的 `Waylith.Rendering.Bc7BlockEncoder` 就保留了 IL 版本。需要实际运行才能确认的问题，另在交接资料中标注。

</details>

## 声明

### AI 使用声明

- 本项目在人工讨论与审阅、**AI 辅助**下完成，文章组织、源码分析、图示与工具脚本均有 AI 参与。
- 新系列通过源码核对与共同阅读修订；旧版技术文档另有基于 `src` / `file` / `match` 的断言检查，两者的组织与核对方式不同。
- **文本断言通过不等于语义解释必然正确**；源码核对与人工审阅仍可能遗漏分支或误判因果。
- 阅读与引用时请以源码和脚本为准；发现错误欢迎提 issue 指正。

### 游戏本体声明

- 本仓库**不包含** RimWorld 游戏本体、DLC 数据、完整反编译语料、美术、音频或其他游戏资源；本地游戏与反编译目录由 `.gitignore` 排除。
- 复现需要你**自备合法购买的游戏副本**；反编译用于互操作性与机制研究，文章仅保留解释实现所需的源码节选，不分发完整反编译产物。
- 请勿使用本项目获取、传播或再分发游戏资源。

### 使用限制

- 本项目**仅供学习与参考**，禁止基于此进行任何**利益相关行为**（包括但不限于销售、收费、付费课程、商业集成、以本项目内容牟利）。
- 文中观点仅为技术分析，不代表任何组织或厂商立场；RimWorld 的名称、商标与游戏内容归 Ludeon Studios 所有。
- 引用或转载本项目内容时，请保留本声明并注明来源。

## 版权与范围

文档是对运行行为与代码结构的**原创分析**，含说明实现所需的源码节选；仓库不分发游戏本体、完整反编译语料或资源数据。复现需要用户自备合法游戏副本。RimWorld 及相关名称归 Ludeon Studios 所有。
