# Waylith 阅读笔记：UnityRuntime.Step 与生命周期分发

阅读位置：RunLoop 调用 OnUpdate，进入 Bootstrap 注册的回调，再调用 UnityRuntime.Step。本轮追踪时间、场景、Behaviour 消息与相机回调的连接，具体玩法 tick 暂留在下游。

Update、LateUpdate 的详细执行说明已补入 [Waylith 汇总稿](14-waylith-summary-draft.md)，展开了组件状态、激活与启动批次、列表复制、调用顺序和方法缓存。本文保留为此前的简要阅读笔记。

## Step 的完整主体

```csharp
public void Step(float deltaTime, float elapsedTime)
{
    this.Time.BeginFrame(deltaTime, elapsedTime);
    SceneManager.ProcessPendingLoad();
    UnityFrame unityFrame = new UnityFrame(this.Time.FrameCount, deltaTime, elapsedTime);
    this.World.Update(in unityFrame);
    this.World.LateUpdate(in unityFrame);
    Camera.DispatchPreCullForScreenCameras();
}
```

Step 在主线程的更新回调中被调用。它按顺序组织兼容层时间、待切换场景、Update、LateUpdate 与相机通知；具体对象的更新由 UnityWorld 继续分发。

定位：UnityRuntime.Step（`Waylith.UnityCompat.UnityRuntime.cs:106`）。

## 时间与场景先准备好

UnityTimeState.BeginFrame 增加兼容层 FrameCount，并记录传入的 deltaTime、elapsedTime；UnscaledDeltaTime 和 UnscaledTime 在这一层也分别取得相同输入。

随后 ProcessPendingLoad 检查是否有 LoadScene 留下的待处理场景名。若存在，就卸载旧场景、设置新场景、调用注册的构建函数，并分发相应场景事件。这个步骤位于本轮 UnityWorld.Update 之前。

初始化时的 SetInitialScene 会直接构建初始场景；运行期间的 LoadScene 先登记请求，到 Step 的这个位置才处理。两条路径的时机不同。

接着，Step 将本轮帧号与时间组成 UnityFrame，交给 UnityWorld 的阶段方法及其相关事件使用。具体 Behaviour 的 Update 消息仍通过无参方法分发，不会因此变成 Update(UnityFrame)。

定位：兼容层时间更新（`Waylith.UnityCompat.UnityTimeState.cs:55`）、ProcessPendingLoad（`UnityEngine.SceneManagement.SceneManager.cs:83`）。

## UnityWorld.Update 的顺序

这里的 World 是兼容层管理场景对象的 UnityWorld。

| 顺序 | 操作 | 作用 |
|---|---|---|
| 1 | ProcessPendingDestroy | 处理待销毁对象。 |
| 2 | FlushPendingActivation | 处理待激活 Behaviour，按条件调用 Awake、OnEnable，并安排尚未执行的 Start。 |
| 3 | FlushPendingStart | 对仍活动、未销毁、尚未开始的对象调用 Start，并记录 HasStarted。 |
| 4 | Updating 事件 | 执行订阅了更新前阶段的工作。 |
| 5 | InvokeMessagesForActiveBehaviours(Update) | 向当前活动且未销毁的已登记 Behaviour 分发 Update。 |
| 6 | PostUpdate 事件 | 执行订阅了更新后阶段的工作。 |

Start 是这里独立管理的启动阶段，不能理解为每次 Update 都重新调用。对象在运行期创建、启停和销毁时，具体进入哪一轮还要沿相应登记与状态变化路径分析。

定位：UnityWorld.Update（`Waylith.UnityCompat.UnityWorld.cs:708`）、待激活处理（`Waylith.UnityCompat.UnityWorld.cs:994`）、待启动处理（`Waylith.UnityCompat.UnityWorld.cs:1042`）。

## Update 这个名字怎样变成实际调用

创建组件状态时，UnityWorld 取得该类型的消息缓存，保存到组件状态中。Behaviour 登记后插入有序列表，并更新其活动状态。

消息缓存按类型保存。首次建立时，代码查找 Awake、Start、Update、LateUpdate 等名字对应的无参实例方法；FindMessage 从当前类型开始，找不到时再向基类查找。

找到方法后，CompileMessage 用表达式树生成 Func<object, object> 委托。之后分发消息时，从组件状态的缓存中取出对应委托，将实际对象实例交给它调用。

```text
组件实例进入兼容层
  → 按类型取得消息缓存
  → 查找同名无参方法，并生成调用委托
  → Behaviour 登记到有序列表
  → 每轮复制当前列表、筛选活动状态
  → 取得 Update 等消息对应的委托
  → 调用该实例的方法
```

因此，在这条 Behaviour 生命周期路径里，方法名约定、对象登记、消息缓存和逐轮分发共同产生了调用。它并不是普通 C# 方法仅因名字叫 Update 就自动执行，也不是每一轮重新为所有对象查找方法。

InvokeMessage 为单个消息调用提供异常日志处理；阶段事件订阅者的调用路径另有自己的行为，不能由此把所有回调都当作具有相同的异常隔离。

定位：创建组件状态（`Waylith.UnityCompat.UnityWorld.cs:877`）、登记 Behaviour（`Waylith.UnityCompat.UnityWorld.cs:911`）、活动对象分发（`Waylith.UnityCompat.UnityWorld.cs:1178`）、调用缓存委托（`Waylith.UnityCompat.UnityWorld.cs:1265`）、消息缓存与查找（`Waylith.UnityCompat.UnityWorld.cs:1468`）、编译调用委托（`Waylith.UnityCompat.UnityWorld.cs:1499`）。

## 调用顺序由什么决定

UnityWorld 先比较登记的执行顺序值，同值再比较 CreationIndex；没有为具体类型登记时，顺序值默认为 0。

Bootstrap 登记了 CameraDriver 与 WorldCameraDriver 的 -103、Root_Entry 的 -50 和 Root_Play 的 -20。这些值用于相应活动对象的排序；它们不表示这些对象一定同时存在于同一场景。

定位：顺序比较（`Waylith.UnityCompat.UnityWorld.cs:1421`）、Bootstrap 的顺序登记（`RimWorldWaylith.Bootstrap.cs:701`）。

## LateUpdate 是另一个阶段

Step 先完成整个 UnityWorld.Update 调用，再进入 UnityWorld.LateUpdate。后者依次调用 LateUpdating 事件、活动 Behaviour 的 LateUpdate、待销毁处理与 PostLateUpdate 事件。

正常阶段顺序是：

```text
Update 阶段：符合条件的对象 A、B、C 的 Update
  → 更新后处理
  → LateUpdate 阶段：届时符合条件的对象的 LateUpdate
  → 更新后期处理
```

这里按阶段分发，并非每个对象的 Update 后面立刻跟自己的 LateUpdate。两个阶段之间活动列表可以变化，因此也不应假定两次遍历必然面对完全相同的对象。

这些事件是实际的模块接入点。例如 MeshRendererDriver 在首次成功订阅后，通过 PostLateUpdate 调用其 Tick，再推进登记 Renderer 的 FrameUpdate；ParticleSystemDriver 和协程调度也使用相应事件。具体绘制提交与协程规则可以沿这些接缝另行展开。

定位：UnityWorld.LateUpdate（`Waylith.UnityCompat.UnityWorld.cs:730`）、网格渲染驱动的订阅与执行（`UnityStubs.Internal.MeshRendererDriver.cs:14`）、粒子驱动（`UnityStubs.Internal.ParticleSystemDriver.cs:14`）、协程阶段订阅（`UnityEngine.CoroutineScheduler.cs:49`）。

## 最后通知屏幕相机

DispatchPreCullForScreenCameras 遍历活动相机，对启用且没有 targetTexture 的相机，调用 Camera.onPreCull 事件，并向相机对象上的组件派发 OnPreCull 消息。

这一段提供的是相机阶段通知入口。实际订阅者做什么、怎样影响后续绘制，需要继续追踪；不能只凭 PreCull 名字，将完整可见性剔除或 GPU 绘制都归入这里。

这些调用结束后，Step 返回 Bootstrap 的更新回调，后者完成其余工作再返回 RunLoop。随后才到主循环中的 BeginMainThreadFrame、CaptureFrame 与入队位置。

定位：屏幕相机通知（`UnityEngine.Camera.cs:631`）。

## 与游戏实体和 tick 的边界

Root 继承 MonoBehaviour，Root_Entry 与 Root_Play 因而能通过这套生命周期机制接到更新。Pawn 则继承 ThingWithComps、Thing、Entity，不能把场景 Behaviour 的遍历直接等同于逐个更新殖民者。

游玩场景中的一个重要下游连接是：

```text
UnityWorld 分发 Update
  → Root_Play.Update
    → Current.Game.UpdatePlay
      → TickManager.TickManagerUpdate
        → 游戏 tick 与各子系统
```

这里先定位入口；GameRoot、Root 的职责、初始化与共享更新归入后续游戏流程研究，材料保存在游戏流程前置笔记中。

定位：Root 的继承关系（`Verse.Root.cs:14`）、Pawn 的继承关系（`Verse.Pawn.cs:16`）、Root_Play.Update（`Verse.Root_Play.cs:63`）。

## 时间接口的补充边界

- 兼容层的 FrameCount 在 UnityTimeState.BeginFrame 增加；引擎的 Waylith.Time.FrameCount 在引擎 EndFrame 增加。它们是不同状态，不能仅凭同名就认为时点和值完全相同。
- UnityTimeState 保存传入的原始 deltaTime；UnityEngine.Time.deltaTime 的 getter 还会使用 Math.Min 将读取值限制到 maximumDeltaTime。UnscaledDeltaTime 的 getter 则读取兼容层保存的值。
- 当前 UnityEngine.Time.timeScale 的 getter 固定返回 1，setter 走桩日志。游戏速度与暂停应继续追到 TickManager 的实际实现，不能套用原 Unity 引擎的时间缩放规则。

定位：兼容时间 BeginFrame（`Waylith.UnityCompat.UnityTimeState.cs:55`）、UnityEngine.Time 的读取适配（`UnityEngine.Time.cs:13`）、引擎时间 EndFrame（`Waylith.Time.cs:52`）。

游戏流程接续材料：[GameRoot、Root 与游玩更新入口](07-waylith-root-play.md)。
