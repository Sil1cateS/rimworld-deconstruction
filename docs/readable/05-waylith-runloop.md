# Waylith 阅读笔记：RunLoop

阅读位置：EngineApplication.Run 完成应用创建和 Bootstrap.Initialize 后，调用 app.RunLoop。本轮沿正常窗口路径读完整一轮，再把影响执行过程的分支放回去。下面记录静态源码关系，实际帧率和等待时长尚未测量。

定位：RunLoop（`Waylith.EngineApplication.cs:583`）。

## 循环开始前

RunLoop 首先为当前主线程建立主线程待执行函数队列：

```csharp
this._mainThreadSyncContext = new MainThreadSynchronizationContext(Environment.CurrentManagedThreadId);
SynchronizationContext.SetSynchronizationContext(this._mainThreadSyncContext);
```

这个上下文可以接受需要回到主线程执行的回调，稍后由 Pump 处理。它与 FrameRenderer 的 RenderToMainThreadDispatcher 是两套独立机制。

无头模式在这里转入 RunHeadlessLoop。正常窗口路径随后创建 RenderThread 并调用 Start；若配置允许，再显示前一步隐藏创建的窗口、应用待处理的显示模式。

因此，进入 while 之前，渲染线程已经启动，可以等待帧队列中的数据。主线程则继续组织游戏更新和渲染采集。

定位：待执行函数队列与路径选择（`Waylith.EngineApplication.cs:585`）、渲染线程启动及窗口显示（`Waylith.EngineApplication.cs:592`）。

## while 所组织的工作

循环条件是：

```csharp
while (!this.Window.ShouldClose)
```

先按普通可更新、可绘制且没有退出请求的路径阅读。下面是职责分组，省略日志和性能统计作用域：

| 顺序 | 工作 | 主要连接 |
|---|---|---|
| 1 | 处理渲染回调、检查渲染线程错误、采样时间 | 排空 RenderToMainThreadDispatcher，检查渲染线程保存的失败，取得本轮时间。 |
| 2 | 资源维护与输入轮询 | 更新显存和纹理相关服务，调用 PrePollEvents、InputState.BeginFrame 和 Glfw.PollEvents。 |
| 3 | 判断焦点、可绘制状态和重建请求 | 决定是否继续更新、是否采集，以及是否先等待并重建绘制目标。 |
| 4 | 发布时间并执行主线程工作 | BeginFrame 更新引擎时间，Pump 取出并调用队列中的函数，再调用 OnUpdate。 |
| 5 | 更新后检查关闭状态，采集与入队 | 构造 FrameTiming，BeginMainThreadFrame、CaptureFrame，随后 Enqueue。 |
| 6 | 入队后事件、帧结束与限速 | 调用 FrameEnqueued，正常绘制路径下 EndFrame，再按目标预算等待。 |

一轮 while 并不必然完成以上所有步骤。后面的分支表给出哪些条件会截断或改变这条主路径。

## 时间从哪里来

源码中的采样是：

```csharp
float num2 = (float)this._stopwatch.Elapsed.TotalSeconds;
float num3 = num2 - num;
num = num2;
```

num2 是本次累计秒数，num 保存上一次采样，num3 是两次之差。为了讲述清楚，可以将它们分别解释为 elapsed、lastElapsed、deltaTime。

从第二次采样起，deltaTime 表示相邻两个采样点之间实际经过的时间，会包含期间的更新、采集、队列等待和限速等耗时。它不是固定步长，也不是接下来这次 OnUpdate 的单独执行耗时。

首次采样需要单独说明：num 从 0 开始，而 Stopwatch 在应用实例初始化期间就已启动。首次差值因而没有普通相邻轮次的意义；兼容层和游戏层怎样继续处理该值，要到各自代码中确认。

之后调用 EngineApplication.BeginFrame，把本轮时间发布到 Waylith.Time，并通知本机分配与作业相关运行设施开始本轮。Time.EndFrame 中的 FrameCount++ 则由后续 EndFrame 触发。

定位：采样（`Waylith.EngineApplication.cs:620`）、BeginFrame / EndFrame（`Waylith.EngineApplication.cs:911`）、Time 中的状态更新（`Waylith.Time.cs:45`）。

## 更新入口：回调现在真正被调用

BeginFrame 和待执行函数队列的 Pump 之后，来到：

```csharp
Action onUpdate = this.OnUpdate;
if (onUpdate != null)
{
    onUpdate();
}
```

这就是上一段在 Bootstrap.Initialize 中登记的游戏更新回调开始执行的位置。回调进一步进入 UnityRuntime.Step、场景生命周期分发以及相应游戏入口，完成后返回这里。

引擎组织的是一次更新机会；游戏世界推进几个 tick，还要由游戏层 TickManager 决定。在菜单、游玩、暂停等状态下，相同的引擎更新入口可以执行不同的游戏侧工作。

在当前顺序中，待执行函数队列的 Pump 位于 OnUpdate 之前；渲染回调队列的 Invoke 则更早，在本轮开头。不能把两者合并为同一个消息泵。

定位：Pump 与 OnUpdate（`Waylith.EngineApplication.cs:756`）、待执行函数队列的 Pump（`Waylith.MainThreadSynchronizationContext.cs:80`）、渲染回调处理（`Waylith.Rendering.FrameRenderer.cs:151`）。

## 更新返回之后，采集这一轮的渲染数据

没有关闭请求且允许绘制时，源码依次执行下面这些核心调用。这里合并展示原本分布于不同性能统计作用域中的语句，省略局部变量声明：

```csharp
FrameTiming frameTiming = new FrameTiming(Time.FrameCount, num3, (double)num2);
this.FrameRenderer.BeginMainThreadFrame(in frameTiming);
renderFrame = this.FrameRenderer.CaptureFrame(in frameTiming, this._clearValues, false);
this._renderThread.Enqueue(renderFrame);
```

FrameTiming 携带本轮帧号与时间。FrameRenderer 先做主线程帧准备，再采集各渲染特性提供的 payload，形成 RenderFrame，最后交给队列。

这几步都由主线程顺序执行。渲染线程随后消费数据包并记录、提交指令，可以与主线程接下来的工作重叠。Enqueue 返回本身不能证明 GPU 已完成，也不能证明屏幕已经显示这一轮内容。

RenderThread 的队列容量为 max(1, FramesInFlight)。Enqueue 中的 BlockingCollection.Add 在队列满时会等待，因此渲染端跟不上时，主线程也可能停在交接点，推迟其后续轮次。

定位：采集、入队与后续处理（`Waylith.EngineApplication.cs:783`）、RenderThread 队列与 Enqueue（`Waylith.Rendering.RenderThread.cs:19`）。

## 收尾与目标帧率

正常采集并入队后，主线程调用 FrameEnqueued 事件、结束本轮，再执行 ThrottleToTargetFrameRate。以本轮时间采样点为预算起点，限速方法计算目标预算减去已经经过的时间：

```csharp
double num = 1.0 / (double)targetFrameRate;
double num2 = this._stopwatch.Elapsed.TotalSeconds - (double)frameStartElapsed;
double num3 = num - num2;
```

若剩余时间较多，就用 Sleep 等待大部分；最后用循环等到预算结束。目标值不大于 0 时，该方法直接返回。已经超出预算时，也无法靠等待补回性能。

例如目标 60 帧时，预算约为 16.7 毫秒。这是算法试图补足的目标时间，实际调度、队列和设备开销仍会影响最终表现。

FrameProfiler.IgnoreThrottle 改变的是性能统计结束与限速的相对位置；这段代码的两个分支仍都调用限速方法，不能只凭字段名字理解成取消等待。

定位：正常绘制路径的收尾（`Waylith.EngineApplication.cs:797`）、限速方法（`Waylith.EngineApplication.cs:1521`）。

## 把分支放回去

| 条件 | 更新与绘制怎样改变 |
|---|---|
| Headless | 在窗口循环之前进入独立的 RunHeadlessLoop，保留更新入口，采用自己的循环路径。 |
| 失焦，且禁止后台运行、也不是隐藏窗口模式 | 进入 WaitEventsTimeout(0.1) 路径，跳过该轮的 BeginFrame、Pump、OnUpdate、采集和入队。 |
| 允许更新，但帧缓冲最小化或其他条件使本轮不能绘制 | 仍执行 BeginFrame、Pump 和 OnUpdate；随后等待并进行 GPU 资源维护与限速，跳过新数据包的采集和入队。 |
| 收到绘制目标大小或 Surface 重建请求 | 在相关状态允许时等待渲染线程空闲，再重建并通知；尺寸为零等情况会推迟重建并令本轮不采集。 |
| 更新期间请求退出 | 更新之后再次检查关闭与退出状态，跳过后续渲染生产。 |
| 渲染线程发生异常 | 主线程在检查点重抛保存的异常，进入异常与收尾流程。 |

因此，失焦等待、无法绘制和游戏内暂停应分别介绍。失焦路径可以跳过引擎更新；无法绘制路径仍可更新；游戏内暂停则需要追到游戏层的时间调度规则。

不能绘制时的 RetireGpuResourcesWithoutRendering 会等待渲染线程和设备空闲，再触发帧开始维护通知。它不是简单跳过绘制后立即返回，也提醒我们要根据调用位置判断事件实际在哪个线程触发。

定位：失焦判断与等待（`Waylith.EngineApplication.cs:652`）、可绘制状态与重建（`Waylith.EngineApplication.cs:694`）、更新后的关闭检查（`Waylith.EngineApplication.cs:774`）、无绘制资源维护（`Waylith.EngineApplication.cs:1513`）。

## 帧结束与退出也有自己的时机

内层 finally 会为已经执行 BeginFrame、但尚未显式 EndFrame 的路径补做结束处理；外层收尾尝试停止渲染线程并再次处理渲染回调，之后进入退出生命周期。

FrameCount 因而不能直接当成 while 迭代次数或成功显示的画面数。正常路径、无法绘制路径、失焦路径和异常路径需要按是否实际执行 BeginFrame、EndFrame 分别分析。

定位：帧结束补偿与循环收尾（`Waylith.EngineApplication.cs:821`）、RenderThread.Stop（`Waylith.Rendering.RenderThread.cs:64`）。

## 接下来的阅读入口

主循环的两个主要接缝已经定位：

- 沿 OnUpdate → UnityRuntime.Step → UnityWorld，继续解释游戏对象的 Start、Update、LateUpdate 怎样被调用，以及怎样进入游戏 tick。
- 沿 CaptureFrame → RenderFrame → RenderThread，继续解释游戏状态怎样成为可提交的绘制工作。

接下来可先深入更新通道，再回到采集与渲染通道；两条路径都以本轮已经确认的调用顺序为依据。

继续阅读：[UnityRuntime.Step 与生命周期分发](06-waylith-runtime-step.md)。

更新通道已读到 Root_Play，游戏内部流程暂存为分支。当前主线回到 OnUpdate 返回之后，继续阅读：[主线程怎样准备 RenderFrame](08-waylith-frame-capture.md)。

## 补充：Headless 的启动选择与独立循环

Headless 可以理解为“无窗口运行”。Program.Main 读取启动参数中的 Headless 开关，将结果放进 EngineApplicationOptions.Headless。这里的参数读取最终来自 Environment.GetCommandLineArgs；开关比较会去掉参数两端的 `-`、`+` 并忽略大小写，因此 `-Headless` 是源码支持的一种写法。

这个选择在应用构造阶段就产生影响：Headless 分支设置音频空输出和默认屏幕尺寸，将 Window 设为 null，提前返回；窗口、Surface、图形设备和窗口渲染环境的建立路径被跳过。Bootstrap 随后也选用无头的输入前处理，跳过有窗口分支中的纹理、输入桥接和渲染特性安装。

RunLoop 先建立主线程待执行函数队列，随即判断：

```csharp
if (this.Options.Headless)
{
    return this.RunHeadlessLoop();
}

// 只有继续窗口路径，才会执行下面的创建和启动。
if (this._renderThread == null)
{
    this._renderThread = new RenderThread(this.RenderContext, this.FrameRenderer);
}
this._renderThread.Start();
```

这里的 return 会让 Headless 直接进入另一条循环，跳过后面的 RenderThread 创建与启动。因此，在这条启动路径中没有渲染线程需要与 Headless 通信，渲染也没有被转交给另一个循环继续进行。EngineApplication 的公共成员中仍可存在 FrameRenderer 对象，但对象的存在与实际启动渲染管线是不同的事情。

RunHeadlessLoop 的主体很短，下面仅简化局部变量名和空值调用：

```csharp
private int RunHeadlessLoop()
{
    float previousSample = 0f;
    while (_shutdownRequestedReason == null)
    {
        float elapsed = (float)_stopwatch.Elapsed.TotalSeconds;
        float delta = elapsed - previousSample;
        previousSample = elapsed;
        PrePollEvents?.Invoke(this);
        InputState.BeginFrame();
        EngineApplication.BeginFrame(delta, elapsed);
        try
        {
            _mainThreadSyncContext?.Pump();
            OnUpdate?.Invoke();
        }
        finally
        {
            EngineApplication.EndFrame();
        }
    }
    ExecuteQuitLifecycle("HeadlessShutdown");
    return ExitCode;
}
```

| 工作 | 窗口路径 | Headless 路径 |
| --- | --- | --- |
| 时间、BeginFrame、Pump、OnUpdate、EndFrame | 保留，受窗口分支影响 | 保留 |
| GLFW 窗口事件、焦点与最小化判断 | 有 | 此循环没有 |
| 渲染线程 | 进入窗口循环前创建并启动 | 此启动路径不创建、不启动 |
| RenderFrame 采集入队和窗口呈现 | 由可绘制路径推进 | 此循环没有 |
| 渲染回调 DrainRenderThreadCallbacksOnMainThread | 在循环前部处理 | 此循环没有 |
| 目标帧率限速方法 | 在相应路径调用 | 此循环没有调用 |
| 循环退出条件 | 检查窗口关闭，退出请求会设置关闭状态 | 直接检查退出请求 |

Headless 保留的 Pump 从主线程待执行函数队列中取出函数并调用，将函数加入这个队列的代码不必来自渲染线程。Headless 也没有调用窗口路径中的渲染回调队列处理函数。因此，看到 Pump 仍然运行，不能据此推断还有渲染线程在与它交换数据。

Headless 因而仍能调用游戏更新回调，但它自己的循环不调用 ThrottleToTargetFrameRate 补足等待时间；回调内部是否有等待，需要看具体工作。隐藏窗口的 HideWindow 是另一个选项，最小化也只是窗口状态变化，它们都不会自动把已经运行的窗口循环切换成 RunHeadlessLoop。

源码定位：Headless 参数读取与选项传递（`RimWorldWaylith.Program.cs:28`）、开关比较规则（`RimWorldWaylith.Program.cs:105`）、参数来源（`RimWorldWaylith.ConfigDependentCommandLine.cs:37`）、构造时的无头分支（`Waylith.EngineApplication.cs:213`）、选择循环（`Waylith.EngineApplication.cs:583`）、RunHeadlessLoop（`Waylith.EngineApplication.cs:860`）。
