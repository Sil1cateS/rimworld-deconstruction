# 游戏运行与调度：帧、tick、长任务、线程与协程（大纲）

状态：讨论大纲 v0.11，2026-11-06 已接通加载结束后的主线程工作与整体线程交接。依据工作区 RimWorld 1.7.4982 rev1280 的代码与兼容层整理。当前按三篇组织，后续结合逐段阅读调整内容与拆篇。

这一组围绕游戏怎样安排执行展开：每帧调用哪些工作、模拟时间怎样推进、耗时操作交给谁、等待以后由谁继续执行。“游戏运行流程”从 Root 和 Game 接下去，线程协作与协程分别在实际调用位置展开。

承接 [Waylith 章节](chapters/01-waylith/README.md)、[对象与组件章节](chapters/02-UnityWorld&UnityObject/README.md) 和 [Def 框架章节](chapters/03-def-framework/README.md)。此前停在 Game.UpdatePlay 的阅读进度见 [游戏入口笔记](07-waylith-root-play.md)，协程的初步材料见 [MonoBehaviour 与 CoroutineScheduler](28-monobehaviour.md)。

## 逐段研究进度

已读 [从场景入口到 Game.UpdatePlay](45-game-update-entry.md)：先认识 Root、Current 和 Game 的关系，回接共享更新与等待判断，再展开一次游玩帧的分派，以暂停和两张已加载地图对照执行结果。

接着进入 [TickManager 的时间与循环](46-tickmanager-time-scheduling.md)：认识计数、速度、时间余额与计时器，追踪 Time.deltaTime 的来源，读完 TickManagerUpdate 的循环与退出处理，并用具体数值对照正负余额、数量上限和耗时限制。

随后阅读 [从 DoSingleTick 到 TickList](47-single-tick-and-ticklists.md)：按顺序接通地图前置、计数推进、三种对象列表、世界与全局系统、地图后置及末尾工作；再展开登记、分组、当前 tick 选组与 Thing.DoTick 的交接，以五个 Rare 对象对照轮换。

接着回到 [速度控制与实际推进](48-time-controls-and-simulation-speed.md)：沿按钮、按键、控制检查、暂停切换和强制正常速度截止时间，解释选择怎样参与推进；结合固定帧间隔案例与 FPS/TPS 显示公式，接到实际完成量。第一篇的主线素材已接通。

长任务部分从 [自动存档的排队与同步执行](49-long-event-queue-and-synchronous-save.md) 开始：认识 LongEventHandler 与 QueuedLongEvent，沿入队、选中当前任务、窗口绘制标记、暂停与等待判断，读到主线程调用任务主体和清理。

随后进入 [异步长任务与后续函数](50-asynchronous-long-events.md)：从启动加载追到线程建立、主体执行、状态文字、结束检查与主线程收尾，再展开 ExecuteWhenFinished 的登记条件、列表遍历及可选场景操作。

接着阅读 [迭代器长任务](51-iterator-long-events.md)：由 IEnumerable 登记接到 IEnumerator，展开 MoveNext 返回后的时间检查与进度保留，并用分段耗时案例和世界绘制层登记位置对照。三条长任务执行路径已接通。

并行工作从 [XML 文件读取](52-parallel-xml-reading.md) 开始：从补丁加载追到共享待处理集合、固定下标结果数组、两个读取线程与调用方共同取文件，再通过 Join 接回后续加载。

随后阅读 [线程池批次与完成等待](53-threadpool-batches-and-completion.md)：从交叉引用解析进入 GenThreading.ParallelForEach，展开列表切分、线程池工作项、按批累计完成量和通知后的重新检查，再接回 Apply 与成功记录移除。

接着回到 [加载结束后的主线程交接](54-loading-main-thread-handoff.md)：从实际登记的函数追到 IsAlive 检查、后续函数列表的执行与下一项界面初始化，再接回引擎帧顺序。整体图已串起主线程、长任务线程、读取线程及线程池工作项，长任务与两个并行案例的主线素材已接通。下一步进入协程记录与调度。

## 一、这一组要建立的整体结构

| 拟定文章 | 主要问题 | 承接与交接 |
| --- | --- | --- |
| 第一篇：主线程更新与游戏时间 | 一帧怎样进入游戏，一帧执行多少个 tick，一个 tick 怎样分派工作 | 从 UnityRuntime.Step 接到 Root、Game、TickManager，停在各系统的调用入口 |
| 第二篇：长任务与线程协作 | 耗时任务怎样排队、执行、等待、完成；并行工作怎样交回结果 | 接回定义加载中的 LongEventHandler、文件读取线程和并行处理，再追踪后续执行 |
| 第三篇：协程的分段执行 | IEnumerator 的进度由谁保存，yield 后何时恢复，停止后怎样处理记录 | 接回 UnityWorld 的帧阶段，展开 CoroutineScheduler 的记录与判断 |

先建立一张运行总图，以游戏进程为外框，标出主线程、渲染线程，以及案例实际使用的后台和工作线程；再在主线程中标出帧阶段、游玩更新、tick 循环、长任务检查与协程推进位置。线程之间另用时序图表示工作交接和等待，图中的调用顺序与并行关系分别说明。

## 二、第一篇：主线程更新与游戏时间

这一篇先把帧级调用接到模拟推进，让读者能判断眼前发生的是哪一类更新，以及它由什么时间和条件驱动。

### 1. 接入游戏运行入口

- 简要回接 UnityRuntime.Step、UnityWorld 与 GameRoot，认识 Root、Root_Entry、Root_Play 的职责与当前游戏引用。
- 沿 Root_Play.Update 阅读 base.Update、长任务等待判断，以及进入 Current.Game.UpdatePlay 的条件。
- Entry 到 Play 的切换先说明调度接点；新建世界、地图生成和存档读取的内部过程在各自模块展开。

### 2. 组织一次帧级更新

- 展开 Root.Update 的时间、长任务、界面与声音等共享工作，再看 Game.UpdatePlay 的调用顺序。
- 说明 TickManagerUpdate、WorldUpdate、MapUpdate、GameComponentUpdate 等入口各自位于哪里，执行结果怎样返回这一帧。
- 在总图上标出进入 tick 循环前后的帧级工作，接到暂停时仍可运行的内容。

### 3. 从时间间隔决定模拟步数

- 先介绍 TickManager 的时间计数、速度状态、待推进时间、当帧 tick 数与计时器。
- 追踪 Time.deltaTime 的来源，说明 realTimeToTickThrough 怎样累加，CurTimePerTick 与 TickRateMultiplier 怎样参与判断。
- 展开 TickManagerUpdate 的循环：何时执行一个 tick，何时继续，何时退出，以及剩余待推进时间怎样处理。

### 4. 分派一次 tick 的工作

- 读取 DoSingleTick 的主要顺序：地图前置处理、时间计数、各 TickList、世界与全局管理器、地图后置处理等。
- 介绍 TickList 保存的分组、待登记和待移除对象，再解释 Normal、Rare、Long 的调用间隔与对象分配方式。
- 接到 Thing.DoTick 等入口，后续实体、Pawn、工作与战斗行为留给对应模块。

### 5. 处理暂停、倍速与耗时限制

- 按实际判断解释玩家暂停、强制暂停、强制正常速度与其他速度分支。
- 对照每帧 tick 数量限制、执行耗时限制和时间积余处理，说明目标推进速度怎样受到当前工作量影响。
- 将 FPS、每帧 tick 数和每秒实际 tick 数放到同一条时间线上理解；实际性能数值另行测量。

案例候选：暂停后观察界面和相机；切换正常速度与加速；一次帧间隔变长以后，跟踪随后一帧的 tick 循环。先用具体时间数据展示计算，再回到游戏现象。

拟用图：主线程调用总图、帧与 tick 的时间对照图、TickManagerUpdate 判断流程图，以及 TickList 分组示意。

## 三、第二篇：长任务与线程协作

这一篇沿任务的生命周期解释调度：谁提交、谁保存、谁执行、谁等待，以及完成后由谁继续后面的工作。

### 1. 保存长任务与后续工作

- 介绍 LongEventHandler、QueuedLongEvent、eventQueue、currentEvent 与待执行函数列表。
- 从 QueueLongEvent 的调用者出发，说明任务内容、显示文字、执行方式和完成函数怎样进入记录。
- 追踪 Root.Update 调用 LongEventsUpdate 时，任务怎样从排队状态变成当前任务。

### 2. 选择长任务的执行路径

- 分别阅读同步函数、后台线程函数和迭代器长任务的推进路径。
- 说明加载窗口何时取得显示机会，执行中的任务怎样更新文字，ShouldWaitForEvent 与 ForcePause 在哪里影响游戏运行。
- 对照主线程、长任务线程及按帧继续执行的位置，标出实际等待点。

### 3. 处理完成、后续函数与场景交接

- 读取任务完成、异常、场景加载及状态清理的顺序。
- 展开 ExecuteWhenFinished：函数保存到哪里，什么条件下立即执行，什么条件下留待后续执行。
- 接回上一章的数据加载和 Root_Play 的启动，让“加载阶段结束以后继续做什么”形成完整交接。

### 4. 拆分并行工作并等待结果

- 用已读过的定义加载作为入口，选择 DirectXmlLoader 和 GenThreading 的代表性调用。
- 介绍批次、工作线程、完成计数与等待对象，解释数据怎样分给多个执行者，再由调用方确认完成。
- 对照直接建立 Thread、使用线程池和 Parallel 调用的路径；每种机制先追一个完整案例，再按需要扩展。

### 5. 接回主线程及其他线程

- 从具体调用者追踪后续函数保存与主线程执行的位置；启动加载案例已经接到 LongEventHandler 的待执行函数列表，再放回含有 Waylith 队列 Pump 的完整帧顺序。
- 渲染线程作为已有协作对象接回，标出后续的绘制数据交接位置；资源准备内部的设备操作留到相应模块展开。
- 依照查到的执行路径讨论哪些工作并行、哪些环节需要串行或等待，为以后各系统的性能分析提供依据。

案例候选：定义文件从多个读取者交回；一批引用解析等待所有批次结束；加载任务完成后安排界面或场景相关工作。各案例按源码确认数据归属与线程，再画时序图。

拟用图：长任务状态图、同步与后台执行时序图、并行批次与完成等待图、返回主线程的交接图。

## 四、第三篇：协程的分段执行

这一篇从一段 IEnumerator 开始，跟踪它怎样保存进度、交出等待条件，以及在后续阶段获得继续执行的机会。

### 1. 保存执行进度与等待状态

- 简要解释 IEnumerator、MoveNext、Current 与 yield，并用一个短示意连接到执行过程。
- 介绍 Coroutine、CoroutineHandle 与 CoroutineScheduler 的关系，重点说明 Owner、迭代器栈、等待种类、恢复时间和完成标记。
- 把这些字段接到 Start、Step、Advance 的各自职责。

### 2. 登记并推进协程

- 从 MonoBehaviour.StartCoroutine 进入，说明记录何时加入列表、首次 Advance 在哪里发生。
- 阅读 Advance 如何推进栈顶迭代器，结束一层后如何继续外层，以及什么时候返回调度器。
- 对照 Step 的等待检查、Advance 的实际执行与完成记录的移除。

### 3. 按等待条件恢复执行

- 逐项解释 null、等待秒数、等待帧末、WaitForFixedUpdate、子迭代器、Coroutine 和 AsyncOperation 的处理。
- 追踪时间字段的来源，检查等待秒数与暂停、倍速之间的关系。
- 按实际帧阶段标出 yield 后最早可能恢复的位置，包括同一帧内是否有再次推进机会。

### 4. 接入帧阶段并结束记录

- 展开 EnsureSubscribed 怎样接入 Updating、PostUpdate、PostLateUpdate，以及主机驱动的帧末处理。
- 核对 WaitForFixedUpdate 在当前兼容层对应的推进位置。
- 继续看停止、自然结束、异常、Owner 状态、组件销毁与场景变化分别触发什么处理，并核对迭代器的清理行为。

案例候选：沿已有的“A → yield null → B → 等待秒数 → C”示意，逐帧记录实际执行位置；再加一个等待子协程和停止协程的例子。教学代码与游戏中的实际调用另行标注。

拟用图：协程记录结构图、迭代器栈变化图、等待状态转换图，以及跨帧执行时序图。

## 五、这一组的写作方式与范围

- 每部分先说明任务、输入与结果；重要类先介绍持有的数据，再读方法；源码片段之前解释相关变量与参数，案例放在通用过程之后。
- 标题按处理步骤命名。帧、tick、线程执行、任务排队与协程等待，都接到各自实际调用点和时间字段。
- 引擎的主循环与渲染队列复用前章结论，本组重点接到游戏运行。地图、实体与各玩法系统先标出调用入口，具体行为随后展开。
- 线程参与情况按实际案例列出；帧率、吞吐量、耗时与瓶颈判断，需要与测量结果配合。

## 六、起读位置与源码入口

建议从第一篇开始，先重建 Root_Play.Update → Game.UpdatePlay → TickManagerUpdate 这一条主线。LongEventHandler 在总图中先保留位置，第二篇再展开；协程按第三篇接回已经明确的帧阶段。

下表列出本次已确认存在的主要入口，内部规则随后按讨论进度细读：

| 入口 | 用途 |
| --- | --- |
| UnityRuntime.Step（`Waylith.UnityCompat.UnityRuntime.cs:106`） | 承接兼容层的一帧 |
| Root.Update、Root_Play.Update（`Verse.Root.cs:113`、`Verse.Root_Play.cs:63`） | 共享工作、长任务检查与游玩入口 |
| Game.UpdatePlay（`Verse.Game.cs:661`） | 游戏的帧级分派 |
| TickManagerUpdate、DoSingleTick（`Verse.TickManager.cs:375`、`Verse.TickManager.cs:414`） | 决定步数与执行模拟步 |
| TickList.Tick（`Verse.TickList.cs:75`） | 分组登记与对象更新 |
| LongEventsUpdate、QueueLongEvent（`Verse.LongEventHandler.cs:193`、`Verse.LongEventHandler.cs:61`） | 长任务的登记与推进 |
| ExecuteWhenFinished（`Verse.LongEventHandler.cs:224`） | 安排后续函数 |
| GenThreading.ParallelForEach（`Verse.GenThreading.cs:87`） | 并行批次与等待 |
| DirectXmlLoader.XmlAssetsInModFolder（`Verse.DirectXmlLoader.cs:17`） | 文件读取的线程协作案例 |
| CoroutineScheduler.Start、Step、Advance（`UnityEngine.CoroutineScheduler.cs:15`、`UnityEngine.CoroutineScheduler.cs:134`、`UnityEngine.CoroutineScheduler.cs:188`） | 协程登记、等待检查与推进 |

本文件保存研究范围、拆篇安排与阅读进度；逐段讨论后再组织整合正文。系列入口见 [系列大纲](00-series-outline.md)。
