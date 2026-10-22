# Waylith 模块概览图（讨论稿）

![Waylith 模块概览](figures/waylith-overview.png)

图源：[Graphviz DOT](figures/waylith-overview.dot)；放大查看：[SVG](figures/waylith-overview.svg)、[PNG](figures/waylith-overview.png)。

帧级主线的后续细化：[帧的时序、结束与等待](13-waylith-frame-timeline.md)，将主线程、渲染线程、GPU 与平台呈现按同步关系对齐。

## 怎样读这张图

1. **从启动区进入**：Program.Main 准备配置，EngineApplication.Run 创建应用、调用 Bootstrap.Initialize，然后进入 RunLoop。
2. **主线程先更新游戏**：主循环通过已注册的 OnUpdate 回调进入兼容运行时，由 UnityWorld 分发 Update、LateUpdate 等生命周期消息。游玩场景中的 Root_Play 和 Game 是游戏逻辑的重要入口。
3. **主线程随后采集绘制数据**：FrameRenderer 调用各渲染特性的准备与采集入口；地图、世界、界面等特性提供各自的数据，最终组装为 RenderFrame。
4. **通过队列交给渲染线程**：主线程把 RenderFrame 放入有界队列。渲染线程取出数据、获取绘制资源、记录指令，随后提交并发起呈现请求。
5. **观察线程边界**：游戏更新和渲染数据采集都在主线程，指令记录与提交在渲染线程，GPU 再执行已提交的工作。队列两端可以并行推进，也会因队列容量与资源同步产生等待。

实线表示调用或执行；蓝色虚线表示数据；紫色点线表示启动时的注册。图中的 ①②③ 只标主线程的更新、采集和入队顺序。两种独立回调的处理归在主循环节点中。

## 图中的范围与简化

- Waylith 篇沿引擎调用顺序说明采集、线程交接、Vulkan 指令记录、提交与呈现。具体绘制数据结构和各模块怎样绘制，放入独立的 [渲染模块](15-rendering-module-notes.md)，在地图、空间和 UI 解析完成之后研究。
- 此图介绍模块之间的主干协作；具体方法的返回、资源释放、异常、窗口重建与无头模式，读到相应代码时再展开。
- FrameRenderer 在两个线程上承担不同工作：主线程准备并采集数据，渲染线程根据已采集数据调用各 pass 记录指令。因此图中出现两次 FrameRenderer。
- RenderFrame 是由各渲染模块提供本轮数据后组成的数据包；图形指令提交、GPU 完成与最终画面显示分别属于后续阶段。
- 游戏层节点汇总模拟和绘制准备的多个入口；它与渲染特性之间的蓝线表示数据来源，不是一个名为“生成所有绘制数据”的单一函数。
- 界面特性会在 CaptureFrame 中执行 buildUi。因此，部分主线程绘制准备发生在采集过程中，不能把所有可见内容都归入前面的游戏 Update。
- 两套回调队列相互独立。已确认主循环中的处理入口；本轮检索尚未找到 RenderToMainThreadDispatcher 的实际入队调用点，图中不预设其生产端，也不把它画成每帧必经的渲染回路。

## 对应源码

| 图中连接 | 源码入口 |
|---|---|
| 应用创建、初始化与进入循环 | EngineApplication.Run（`Waylith.EngineApplication.cs:499`） |
| 循环中的更新、采集与入队 | RunLoop（`Waylith.EngineApplication.cs:583`） |
| 注册游戏更新回调 | Bootstrap.Initialize（`RimWorldWaylith.Bootstrap.cs:73`） |
| 兼容运行时与生命周期 | UnityRuntime.Step（`Waylith.UnityCompat.UnityRuntime.cs:106`）、UnityWorld.Update（`Waylith.UnityCompat.UnityWorld.cs:708`） |
| 安装渲染特性 | ConfigureFrameRenderer（`RimWorldWaylith.Bootstrap.cs:300`） |
| 采集特性 payload | FrameRenderer.CaptureFrame（`Waylith.Rendering.FrameRenderer.cs:206`） |
| 地图与界面数据来源的例子 | MapRenderFeature（`RimWorldWaylith.Rendering.MapRenderFeature.cs:57`）、ImGuiRenderFeature（`RimWorldWaylith.Imgui.ImGuiRenderFeature.cs:44`） |
| 有界队列与渲染线程 | RenderThread（`Waylith.Rendering.RenderThread.cs:19`）、RenderLoop（`Waylith.Rendering.RenderThread.cs:159`） |
| 指令记录与提交 | FrameRenderer.RecordFrame（`Waylith.Rendering.FrameRenderer.cs:316`）、GraphicsDevice.SubmitGraphicsAndPresent（`Waylith.Graphics.GraphicsDevice.cs:533`） |
| 独立的回调处理机制 | 待执行函数队列的 Pump（`Waylith.MainThreadSynchronizationContext.cs:80`）、渲染回调 Invoke（`Waylith.Rendering.RenderToMainThreadDispatcher.cs:21`） |

更详细的调用梳理见 [第一轮讨论材料](01-waylith-discussion.md)。

## 下一步：从图左上角读起

Program.Main 准备配置与初始化委托后，调用：

```csharp
int num = EngineApplication.Run(engineApplicationOptions, action);
```

这里的 action 指向 Bootstrap.Initialize。EngineApplication.Run 的关键顺序如下，省略日志和外围异常处理：

```csharp
app = new EngineApplication(options);
if (initialize != null)
{
    initialize(app);
}
num = app.RunLoop();
```

第一步创建引擎应用；第二步把这个应用交给游戏的初始化函数，让它配置后续要使用的连接；第三步进入循环，持续调用已经接好的更新与绘制入口。传入 initialize，并不表示它会在每一轮循环中重新执行。

读下一段时，可以分别追问：应用构造函数建立了哪些基础设施，Bootstrap 接入了哪些游戏功能，以及 RunLoop 开始之后怎样使用它们。

定位：Program.Main 的调用（`RimWorldWaylith.Program.cs:60`）、Run 中的创建、初始化和循环（`Waylith.EngineApplication.cs:529`）。

继续阅读：[创建 EngineApplication](03-waylith-construction.md)。
