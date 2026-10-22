# Waylith 阅读笔记：创建 EngineApplication

阅读位置：总图的启动区，`EngineApplication.Run` 中的 `new EngineApplication(options)`。本轮只读应用创建阶段，记录源码与讨论要点，尚未写成正式文章。

## 这一段要回答的问题

在调用 Bootstrap.Initialize 之前，引擎已经准备好了什么？哪些对象只是建立了容器，哪些设施已经连接到底层系统，又有哪些工作要等进入主循环以后才开始？

定位：EngineApplication 构造函数（`Waylith.EngineApplication.cs:208`）。

## 进入构造函数正文前的初始化

类中分散着以下三处初始化。这里将它们放在一起展示，便于认识应用持有的对象，不表示它们在原文件中相邻：

```csharp
public WaylithRuntime Runtime { get; } = new WaylithRuntime();
public FrameRenderer FrameRenderer { get; } = new FrameRenderer();
private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
```

- WaylithRuntime 建立引擎级的应用状态，记录当前主线程等信息。Bootstrap 之后会在它之上创建 UnityRuntime，接入兼容层。
- FrameRenderer 的对象此时已经存在，内部渲染特性数组初始为空。地图、世界、界面等特性随后由 Bootstrap 安装。
- Stopwatch 已开始计时。后面读帧时间时，需要记住计时器的启动点和主循环取样点分别在哪里。

定位：Runtime 初始化（`Waylith.EngineApplication.cs:86`）、FrameRenderer 初始化（`Waylith.EngineApplication.cs:179`）、计时器初始化（`Waylith.EngineApplication.cs:1625`）、WaylithRuntime 构造（`Waylith.Runtime.WaylithRuntime.cs:30`）、初始特性数组（`Waylith.Rendering.FrameRenderer.cs:467`）。

## 正文首先记录应用与配置，再选择运行方式

```csharp
EngineApplication.Instance = this;
this.Options = options;
```

接下来的 Headless 分支会初始化可选的空输出音频后端，设置尺寸信息，将 Window 设为空，然后提前返回。因此后面的窗口与图形设施属于常规有窗口路径。

本轮顺着常规窗口路径阅读，无头模式作为一个独立分支保留。这里也能看到，游戏更新所需的运行框架与真实窗口、图形输出可以采用不同的启动路径。

定位：运行方式分支（`Waylith.EngineApplication.cs:210`）。

## 常规窗口路径的主干

| 顺序 | 源码中的主要工作 | 这一阶段建立的连接 |
|---|---|---|
| 1 | VulkanStartup.Prepare、平台分支、GLFW 初始化与检查 | 准备底层图形库与窗口系统；处理平台配置及失败情况。 |
| 2 | 设置窗口提示，构造 CreateInfo，Glfw.CreateWindow | 建立本机窗口对象，并记录初始尺寸和位置。 |
| 3 | GraphicsDevice.CreateInstance，初始化可选音频后端 | 建立 Vulkan 实例；为后续音频输出准备后端。 |
| 4 | CreateSurface、GraphicsDevice.Create、new WindowRenderContext | 将窗口与图形呈现关联，选择图形设备与队列，建立窗口绘制上下文。 |
| 5 | ConfigureGpuServices，登记显示与窗口事件，创建 GlfwInputSource | 将纹理、网格、计算等服务接到图形设备，建立显示状态变化与输入处理的连接。 |

这些步骤之间穿插了日志、显示器信息和平台细节。第一次讲主干时可以按上表组织，再在对应位置补充值得解释的分支。

定位：平台准备（`Waylith.EngineApplication.cs:229`）、创建窗口（`Waylith.EngineApplication.cs:326`）、图形与音频设施（`Waylith.EngineApplication.cs:338`）、显示与输入连接（`Waylith.EngineApplication.cs:384`）。

## 窗口、Surface、Device 与 RenderContext 分别是什么

这些对象共同参与将图形工作送到窗口，但分别承担不同职责：

| 对象 | 在这里的作用 |
|---|---|
| Window | 本机窗口，提供尺寸、位置和窗口事件等信息。 |
| Vulkan Instance | 应用使用 Vulkan 的实例级入口，后续设备创建从这里继续。 |
| Surface | 图形呈现与这个本机窗口之间的关联对象；CreateSurface 内部调用 Glfw.CreateWindowSurface。 |
| GraphicsDevice | 引擎对图形设备的封装；Create 中选择设备与队列族、创建逻辑设备，并保存后续提交所需的信息。 |
| WindowRenderContext | 面向这个窗口的绘制与提交上下文，连接设备、Surface、呈现模式及相关绘制资源。构造时调用 Rebuild。 |

源码在创建窗口之后，先建立 Instance；随后初始化可选音频后端，再建立 Surface、GraphicsDevice 和 WindowRenderContext。首次解释图形对象关系时可以抽出这条依赖：

```text
本机窗口 + Vulkan Instance
  → 为窗口创建 Surface
  → 选择并创建 GraphicsDevice
  → 建立 WindowRenderContext
```

这是对象依赖摘要；音频等穿插步骤仍按上表的实际位置说明。

定位：CreateSurface（`Waylith.EngineApplication.cs:1575`）、GraphicsDevice.Create（`Waylith.Graphics.GraphicsDevice.cs:328`）、WindowRenderContext 构造（`Waylith.Graphics.WindowRenderContext.cs:74`）。

## 第一个能直接对应到画面的细节：窗口先隐藏创建

构造函数中设置：

```csharp
Glfw.WindowHint(GlfwWindowHint.Visible, 0);
```

之后才调用 Glfw.CreateWindow。到 RunLoop 开始时，满足配置条件才显示窗口：

```csharp
if (!this.Options.HideWindow)
{
    this.Window.Visible = true;
    this._windowShown = true;
    this.ApplyPendingDisplayMode();
}
```

因此，“窗口对象已经创建”与“窗口已经出现在屏幕上”在代码中是两个时点。中间还会完成后续引擎构造和 Bootstrap.Initialize。这个顺序能够解释启动过程中的可见性安排；它本身不能证明某次实际启动等待或黑屏的具体原因。

定位：隐藏创建（`Waylith.EngineApplication.cs:309`）、开始循环前显示（`Waylith.EngineApplication.cs:600`）。

## 第二个重要细节：登记一个动作，不代表立刻执行它

ConfigureGpuServices 中有这些相邻的连接：

```csharp
this._meshUploadHandler = new Action<Mesh>(this.GraphicsDevice.MeshUploads.Enqueue);
this._meshReleaseHandler = new Action<Mesh>(this.GraphicsDevice.MeshUploads.Release);
Mesh.UploadRequested += this._meshUploadHandler;
Mesh.ReleaseRequested += this._meshReleaseHandler;
this.FrameRenderer.RenderThreadFrameStarting += this.GraphicsDevice.MeshUploads.BeginRenderFrame;
```

这段代码把网格上传、释放请求和渲染帧开始事件接到相应处理函数。当前发生的是建立连接；具体工作会在相应请求或事件触发时执行。

它与 Run 方法接收 initialize 委托的方式可以一起解释：有时函数在当前步骤调用，有时只是先把将来要调用的函数保存或注册下来。阅读初始化代码时，需要区分这两种情况。

定位：ConfigureGpuServices（`Waylith.EngineApplication.cs:441`）。

## 这一步完成后的状态

以常规窗口路径成功完成为前提：

| 部分 | 当前状态 |
|---|---|
| 引擎应用、引擎级运行时与计时器 | 已创建。 |
| 本机窗口 | 已创建，按构造时设置仍隐藏。 |
| 图形设备与窗口绘制上下文 | 已建立，相关 GPU 服务已配置。 |
| 音频后端 | 若配置了后端，已初始化并设为当前后端。 |
| 输入及窗口事件连接 | 已建立引擎层的输入来源和相关事件处理。 |
| FrameRenderer | 已创建，并接入引擎级服务事件；渲染特性列表仍待 Bootstrap 配置。 |
| RenderThread | 常规路径在 RunLoop 中创建并启动，还没有进入这一阶段。 |
| 游戏接入 | 接下来调用 Bootstrap.Initialize，注册游戏更新并安装渲染特性。 |

定位：渲染线程创建与启动（`Waylith.EngineApplication.cs:592`）、Bootstrap 游戏接入（`RimWorldWaylith.Bootstrap.cs:53`）。

构造函数还有异常清理路径：在主要窗口与图形初始化的 try 块中失败，会尝试 Dispose，再重新抛出原异常。这里不将“开始创建”当作“一定完成”。

下一段阅读位置：`initialize(app)`，进入 Bootstrap.Initialize，观察它怎样使用刚建立的引擎设施接入 RimWorld。

继续阅读：[Bootstrap.Initialize](04-waylith-bootstrap.md)。
