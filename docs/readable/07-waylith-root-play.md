# 游戏流程前置笔记：GameRoot、Root 与游玩更新入口

阅读位置：UnityRuntime.Step → UnityWorld.Update → 活动 Behaviour 的 Update → Root_Entry / Root_Play。本笔记保存从 Waylith 汇总稿移出的游戏层说明，再沿 Root_Play 的共享更新、提前返回、游玩专用更新三段阅读，停在 Game.UpdatePlay 的入口。

进度书签：本笔记保留为游戏流程模块的前置材料。Game.UpdatePlay 内部尚未展开；当前 Waylith 主线已返回 RunLoop 的帧采集部分，见 [主线程怎样准备 RenderFrame](08-waylith-frame-capture.md)。

## GameRoot 和 Root 承担什么工作

先看 Entry 构建函数中的两句实际代码：

```csharp
GameObject gameObject = new GameObject("GameRoot");
gameObject.AddComponent<Root_Entry>();
```

第一句建立一个 `GameObject`，并把它命名为 `GameRoot`。GameObject 是兼容层管理的场景对象，可以承载多个组件；这个对象用来承载游戏运行入口，本身没有需要画在地图上的外观。

第二句创建一个 `Root_Entry` 组件并附加到这个对象上。文中所说的“挂载”，就是这样的组件附加操作。兼容层会管理组件的激活、启动和更新，因此这个组件之后可以接到 Start、Update 等调用。`AddComponent` 本身并没有立即执行其整套逐帧更新。

Play 场景采用相同做法，但附加的是 `Root_Play`。两者都继承游戏侧的抽象基类 `Verse.Root`，Root 再继承 `MonoBehaviour`，从而接入兼容层的生命周期。共同的 Root 负责初始化界面与声音入口，以及长事件、共享服务和界面等公共更新；派生类继续处理各自阶段的工作：Root_Entry 管理菜单阶段的音乐等更新，Root_Play 则把游玩更新继续交给 `Current.Game.UpdatePlay` 等入口。

GameRoot 这个名字也用于查找。场景变化时，游戏会用 `GameObject.Find("GameRoot")` 找到对象，再取得其 Root_Entry 或 Root_Play 组件，保存为当前运行入口。这样，场景里创建的组件就与游戏侧访问当前 Root 的代码连接起来了。

源码定位：创建 GameRoot 并附加组件（`RimWorldWaylith.Bootstrap.cs:779`）、GameObject.AddComponent（`UnityEngine.GameObject.cs:64`）、Root 基类（`Verse.Root.cs:14`）、Root_Entry.Update（`Verse.Root_Entry.cs:34`）、当前 Root 的查找与保存（`Verse.Current.cs:127`）。

## 初始 Entry 怎样继续建立游戏运行状态

普通启动的第一次 Step 中，待启动的 Root_Entry 会先接到 Start，再参与 Update。它的 Start 先调用 Root.Start：识别当前场景并保存当前 Root，执行一次性的公共初始化；尚未载入游戏数据时，还会安排加载游戏数据和随后初始化界面、声音入口的长事件。Root_Entry.Start 随后建立菜单音乐管理器，并检查自动读档请求。

因此，初始场景的建立、组件的 Start、游戏数据加载和界面初始化，是沿启动流程逐步发生的工作。Awake、OnEnable 也可能已经在初始化期间添加组件、处理激活时调用，不能把它们全部固定到第一次 Step 内。

Root_Entry.Update 从 Root.Update 的公共更新开始，其中会推进长事件；若需要等待长事件，派生类会提前返回。条件允许时，它才继续菜单音乐、已有世界与 Entry 游戏数据等更新。Step 之后仍会返回 Bootstrap 登记的更新函数和主循环；在可绘制路径中，主线程可以继续采集当时的界面状态。

源码定位：Root_Entry.Start 与 Update（`Verse.Root_Entry.cs:12`）、Root.Start 的初始化与长事件（`Verse.Root.cs:27`）、Root.Update（`Verse.Root.cs:113`）、添加组件时的激活处理（`Waylith.UnityCompat.UnityWorld.cs:171`）。

## Root_Play.Update 的主干

下面保留调用顺序，省略包围游玩专用更新的 try/catch：

```csharp
public override void Update()
{
    base.Update();
    if (LongEventHandler.ShouldWaitForEvent || this.destroyed)
    {
        return;
    }

    ShipCountdown.ShipCountdownUpdate();
    if (ModsConfig.IdeologyActive)
    {
        ArchonexusCountdown.ArchonexusCountdownUpdate();
    }
    TargetHighlighter.TargetHighlighterUpdate();
    Current.Game.UpdatePlay();
    this.musicManagerPlay.MusicUpdate();
    PerformanceBenchmarkUtility.CheckBenchmark();
}
```

Root_Play 在这里组织游玩场景的一次帧级更新。实际工作分散到基类 Root、静态管理器和 Current.Game，逐个 Pawn 的模拟还在下游。

定位：Root_Play.Update（`Verse.Root_Play.cs:63`）。

## base.Update 先推进共享工作

base.Update 调用 Root.Update。它首先执行分辨率更新、RealTime.Update 和帧耗时统计，然后调用 LongEventHandler.LongEventsUpdate。

长事件更新之后分成两条路径：如果返回的标志表示请求了场景切换，Root 将自身的 destroyed 字段设为 true；否则，在 ShouldWaitForEvent 为 false 时，继续执行共享工作。

| 位置 | 这一段承担的工作 |
| --- | --- |
| 分支之前 | 分辨率、时间、帧统计、长事件推进 |
| 允许继续时 | 随机状态栈与鼠标位置栈检查、Steam 更新、头像及战斗目标等缓存和静态管理器更新 |
| 随后 | uiRoot.UIRootUpdate、满足条件时首次应用设置、soundRoot.Update |

因此，Root_Play 的提前返回检查发生在 base.Update 之后。但这也不表示所有共享工作都会无条件执行：Root.Update 内部已经有自己的分支。

UIRootUpdate 在游玩场景中继续进入世界界面、地图界面、警报、教学等更新。UI 的 OnGUI 入口另行处理绘制与输入，不能把这里的 UI 更新等同于整个界面绘制过程。

定位：Root.Update（`Verse.Root.cs:113`）、RealTime.Update（`Verse.RealTime.cs:31`）、UIRoot_Play.UIRootUpdate（`RimWorld.UIRoot_Play.cs:58`）、UIRoot_Play.UIRootOnGUI（`RimWorld.UIRoot_Play.cs:21`）。

## 等待长事件与旧 Root 停止更新

ShouldWaitForEvent 的含义需要按 getter 阅读。它要求同时满足：

1. 有正在执行或排队的长事件；
2. 当前事件存在且不使用标准窗口，或者 UIRoot、WindowStack 中至少一个尚不存在。

有长事件并不自动满足等待条件。这里也没有读取游戏的暂停或倍速状态。

destroyed 则是 Root 的一个字段。在本轮追踪的路径中，同步长事件执行 SceneManager.LoadScene 后，将 sceneChanged 输出标志设为 true，Root.Update 据此设置 destroyed。兼容层的 LoadScene 此时只登记待加载场景，真正的场景处理位于后续 Step 的 ProcessPendingLoad。

这就接上了上一段的场景生命周期：

```text
当前 Root 更新长事件
  → 长事件请求 LoadScene
  → Root 标记 destroyed
  → Root_Play 跳过剩余游玩更新
  → 后续 Step 处理待切换场景
```

因此，检查这个字段时，应理解为当前 Root 已被标记为不再继续工作，不能据此断言底层对象已经完成销毁。

return 只结束这次 Root_Play.Update。外层 UnityWorld、Step 和引擎循环仍可继续执行。Root.OnGUI 也有独立入口：在 Root 尚未被标记 destroyed、但需要等待长事件时，它保留长事件与遮罩显示路径，跳过常规 UIRootOnGUI。

定位：ShouldWaitForEvent（`Verse.LongEventHandler.cs:17`）、同步长事件的场景请求（`Verse.LongEventHandler.cs:350`）、兼容层 LoadScene（`UnityEngine.SceneManagement.SceneManager.cs:77`）、待加载处理（`UnityEngine.SceneManagement.SceneManager.cs:83`）、Root.OnGUI（`Verse.Root.cs:155`）。

## 通过检查之后，按顺序协调游玩工作

| 调用 | 可以在这一层确认的职责 |
| --- | --- |
| ShipCountdownUpdate | 推进飞船起飞结局的过渡倒计时 |
| ArchonexusCountdownUpdate | 在 Ideology 启用时，推进 Archonexus 结局倒计时 |
| TargetHighlighterUpdate | 处理登记的目标箭头与圆圈绘制请求 |
| Current.Game.UpdatePlay | 进入当前游戏对象的更新，包括下游 tick 调度 |
| musicManagerPlay.MusicUpdate | 调用游玩场景音乐管理器的更新入口 |
| CheckBenchmark | 调用性能基准检查入口 |

这里已经出现一个具体的 DLC 接入位置：IdeologyActive 控制 ArchonexusCountdown 的调用。其他 DLC 怎样接入，需要分别追踪各自实现。

## 从倒计时读到结局画面

ShipCountdown.InitiateCountdown(Building) 将 timeLeft 设为 7.2f，播放起飞声音，并以相同持续参数启动白色渐变。ShipCountdownUpdate 在 timeLeft 大于零时减去 Time.deltaTime，耗尽后调用 CountdownEnded。

这几行将结局过渡拆成可追踪的工作：启动时登记声音和渐变，每次帧级更新减少剩余时间，结束时进入后续结局处理。这里的倒计时属于起飞结局过渡；飞船反应堆启动期间的长期进度需要另行追踪。

ArchonexusCountdownUpdate 同样减去 Time.deltaTime，结束时调用 EndGame。这两段推进逻辑使用帧时间；在 Root_Play 中，它们都位于 Game.UpdatePlay 之前。

Time.deltaTime 的值来自上一段读到的兼容层接口，getter 还受 maximumDeltaTime 限制。因此这里能确认的是代码按该接口报告的时间累积，不能将其直接等同于任何运行条件下都严格相同的墙钟秒数。

定位：飞船倒计时初始化（`RimWorld.ShipCountdown.cs:25`）、飞船倒计时推进（`RimWorld.ShipCountdown.cs:44`）、Archonexus 倒计时推进（`RimWorld.ArchonexusCountdown.cs:64`）、Time.deltaTime（`UnityEngine.Time.cs:13`）。

## 从目标请求读到箭头和圆圈

TargetHighlighter.Highlight 根据目标和参数，将箭头位置或圆圈的位置、半径登记进列表。TargetHighlighterUpdate 逐项处理这些列表：

```text
arrowPositions
  → 在 DrawingMap 时逐个调用 DrawArrowPointingAt
  → 清空列表

circleOverlays
  → 在 DrawingMap 时逐个调用 DrawCircleOutline
  → 清空列表
```

两个 Clear 都位于 DrawingMap 判断之外。因此，即使当次没有绘制地图，这批请求也会被清空。若要在后续更新继续显示，调用方需要再次登记。

这个例子展示了游戏侧怎样提出可视内容：先记录目标数据，再统一发出绘制调用。此处发出调用之后，仍需经过后续帧收集与渲染流程，最终才能成为屏幕上的图像。具体哪个界面在什么时点登记目标，可在目标与 UI 模块中继续追踪。

定位：Highlight 登记目标（`RimWorld.TargetHighlighter.cs:15`）、TargetHighlighterUpdate（`RimWorld.TargetHighlighter.cs:82`）。

## 异常边界与下一处入口

源方法将通过检查后的整组游玩更新包在同一个 try/catch 中。如果其中一次调用抛出异常并传播到这里，本次剩余调用会被跳过，然后记录错误。Root.Update 自己也有一个 try/catch；不能将此理解为每项更新都有独立的异常隔离。

后续恢复游戏流程阅读时，从 Game.UpdatePlay 接续。它调用 TickManagerUpdate，也会继续更新信件、世界、地图、GameComponent 和其他管理器。届时需要进一步区分每帧入口与游戏 tick，才能解释暂停、倍速和同一帧内可能发生的模拟推进。

定位：Root_Play 的异常范围（`Verse.Root_Play.cs:70`）、Game.UpdatePlay（`Verse.Game.cs:661`）。
