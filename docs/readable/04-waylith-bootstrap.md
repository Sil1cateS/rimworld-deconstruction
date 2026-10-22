# Waylith 阅读笔记：Bootstrap.Initialize

阅读位置：`EngineApplication.Run` 完成应用构造后，调用 `initialize(app)`，进入 `RimWorldWaylith.Bootstrap.Initialize`。本轮沿普通游戏启动路径，区分初始化时立即执行的配置与注册后留待运行的回调。

定位：Initialize 入口（`RimWorldWaylith.Bootstrap.cs:50`）。

## 整体作用与顺序

Bootstrap 使用前一步建立的引擎设施，接入 RimWorld 需要的兼容运行时、资源、输入、更新与绘制功能，并建立初始场景。

| 顺序 | 主要工作 | 现在执行什么，之后执行什么 |
|---|---|---|
| 1 | new UnityRuntime，ConfigureRuntime，设置内容根目录提供函数和退出处理 | 立即建立兼容运行时、配置路径与资源包入口等；提供函数和退出处理则在需要时调用。 |
| 2 | 向 app.OnUpdate 追加回调 | 现在保存回调，后续由 RunLoop 调用；回调内部才推进 UnityRuntime.Step。 |
| 3 | 配置着色器、纹理、输入和窗口位置 | 在有窗口路径中立即配置服务、建立桥接并登记相应事件处理。 |
| 4 | ConfigureFrameRenderer | 创建并安装各渲染特性及相关资源，同时登记退出与帧事件处理；后续由引擎组织采集与记录指令。 |
| 5 | RegisterExecutionOrders、RegisterResources | 登记 Behaviour 的执行顺序，以及混音器、WorldText 预制对象等运行时资源。 |
| 6 | SpawnEntryScene | 注册 Entry 与 Play 的构建函数，并立即建立初始 Entry 场景。 |

无头模式采用不同的输入和渲染配置路径；资源包烘焙模式会在正常建立 Entry 场景之前返回。下文先保留普通游戏启动主线。

## 先建立兼容运行时

```csharp
Bootstrap._unityRuntime = new UnityRuntime(app.Runtime);
Bootstrap.ConfigureRuntime(Bootstrap._unityRuntime, app.Options);
```

app.Runtime 是构造 EngineApplication 时建立的 WaylithRuntime。UnityRuntime 持有这个 Core，同时建立兼容层使用的 App、Screen、Time 和 UnityWorld，并接好对象销毁、协程启动及音频预取等连接。

这里的 UnityWorld 管理场景对象与 Behaviour 的生命周期；游戏中的星球、派系、远行队等数据另由游戏层的 World 管理。解释代码时需要分别指出这两个同名概念。

ConfigureRuntime 设置产品与版本信息、数据和持久化路径、着色器缓存目录，调用 AssetPackBoot.Open 并检查资源可用性，也将部分底层错误与警告接入游戏日志。此处是读取和解释源码，没有运行这些初始化操作或打开游戏资源包。

定位：运行时配置（`RimWorldWaylith.Bootstrap.cs:408`）、UnityRuntime 的成员与构造（`Waylith.UnityCompat.UnityRuntime.cs:31`）。

## 核心连接：追加 OnUpdate 回调

反编译代码用 `Delegate.Combine` 保留已有的 OnUpdate 委托，再追加本次注册的回调。这里发生的是保存函数，尚未调用回调内部的逐帧工作。

这个回调在普通路径中依次完成窗口尺寸同步、帧相关回调处理、界面输入分发，然后进入：

```csharp
Bootstrap._unityRuntime.Step(global::Waylith.Time.DeltaTime, global::Waylith.Time.Elapsed);
```

之后还会处理启动状态通知、画面饱和度设置、音频监听状态同步和音频后端更新等工作。完整回调也有资源包烘焙的专用分支。

因此，这一处的控制关系是：

```text
初始化期间：
  Bootstrap.Initialize → 把回调追加到 app.OnUpdate

主循环运行期间：
  EngineApplication.RunLoop → 调用 OnUpdate
    → Bootstrap 注册的回调
      → UnityRuntime.Step
```

Step 将引擎提供的时间更新到兼容层，处理待切换场景，然后调用 UnityWorld.Update、LateUpdate 和相机 PreCull 分发。具体 Behaviour 的生命周期消息调用由兼容层继续组织。

源码中的 EndOfFrame.Run 等名字需要结合实现与调用位置解释；这里先按实际代码记录它们位于 OnUpdate 回调内，不仅凭名称推断执行时点。

定位：注册的完整回调（`RimWorldWaylith.Bootstrap.cs:73`）、UnityRuntime.Step（`Waylith.UnityCompat.UnityRuntime.cs:106`）。

## 接入输入与渲染

ConfigureInput 建立 GLFW 输入桥接，按平台建立输入法桥接，并向 PrePollEvents 登记回调；这让引擎的输入轮询与兼容层的输入状态建立联系。

ConfigureFrameRenderer 则安装以下特性，下面按代码中的添加顺序列出：

| 特性 | 本轮先认识的作用 |
|---|---|
| ComputeRenderFeature | 计算工作在渲染管线中的入口。 |
| WorldRenderFeature | 世界画面的渲染入口。 |
| MapRenderFeature | 地图画面的渲染入口。 |
| CameraCaptureFeature | 相机采集相关入口。 |
| PostFxFeature | 画面合成与后处理入口。 |
| ImGuiRenderFeature | 界面数据构建与绘制入口。 |
| ScreenCaptureFeature | 截图相关入口。 |

例如地图特性的安装：

```csharp
Bootstrap._mapFeature = new MapRenderFeature(app.GraphicsDevice, app.RenderContext, app.FrameRenderer.RenderToMainThread, Bootstrap._sceneTargets);
app.FrameRenderer.AddFeature(Bootstrap._mapFeature);
```

FrameRenderer 因而获得可访问的 IRenderFeature 列表。后续采集时，各特性再根据当前状态提供相应数据；安装了特性不代表每个场景里所有特性都处于活动状态。

该配置函数还建立场景渲染目标、界面后端等对象，并登记资源清理、截图帧事件和着色器热重载相关处理。具体绘制与生命周期留到渲染部分逐项展开。

定位：ConfigureInput（`RimWorldWaylith.Bootstrap.cs:227`）、ConfigureFrameRenderer（`RimWorldWaylith.Bootstrap.cs:300`）。

## 预先登记执行顺序与部分内置资源

RegisterExecutionOrders 为 CameraDriver、WorldCameraDriver、Root_Entry 和 Root_Play 登记顺序值，UnityWorld 保存并据此排序 Behaviour。顺序值怎样参与比较、生命周期怎样分发，在兼容层部分继续阅读。

RegisterResources 登记混音器和 WorldText 预制对象等供兼容层使用的资源。这是具体的运行时资源登记步骤，不应据此将全部 Def、内容包和存档加载都视为已经结束。

定位：执行顺序登记（`RimWorldWaylith.Bootstrap.cs:701`）、内置资源登记（`RimWorldWaylith.Bootstrap.cs:710`）。

## 建立 Entry 场景

SpawnEntryScene 去掉编译器生成的委托缓存写法后，可以概括为：

```csharp
SceneManager.RegisterScene("Entry", Bootstrap.BuildEntryScene);
SceneManager.RegisterScene("Play", Bootstrap.BuildPlayScene);
SceneManager.SetInitialScene("Entry");
```

前两句保存两个场景的构建函数，最后一句设置初始场景并立即调用其构建函数。

BuildEntryScene 创建带 Camera 与 AudioListener 的对象，以及带 Root_Entry 和 LatestVersionGetter 的 GameRoot。BuildPlayScene 则建立游玩场景的相机相关组件和带 Root_Play 的 GameRoot。此时普通启动选择的是 Entry，Play 的构建函数先登记备用。

因此，在总图中提到 Root_Play 时，要说明它属于进入游玩场景之后的具体连接。启动阶段首先建立的是 Entry 场景。

SceneManager.SetInitialScene 会直接调用 BuildScene；相比之下，LoadScene 先记录 pendingSceneName，后续由 UnityRuntime.Step 中的 ProcessPendingLoad 处理。不能仅因都叫“切场景”，就把它们的执行时点混在一起。

定位：场景注册与选择（`RimWorldWaylith.Bootstrap.cs:749`）、BuildEntryScene（`RimWorldWaylith.Bootstrap.cs:769`）、BuildPlayScene（`RimWorldWaylith.Bootstrap.cs:785`）、SceneManager.SetInitialScene（`UnityEngine.SceneManagement.SceneManager.cs:58`）、SceneManager.LoadScene（`UnityEngine.SceneManagement.SceneManager.cs:77`）。

## 初始化返回时，哪些连接已经就位

| 部分 | 当前状态 |
|---|---|
| 兼容运行时 | 已创建并配置，持有场景对象、时间和屏幕等兼容状态。 |
| OnUpdate | 已追加游戏更新回调，等待主循环调用。 |
| 输入与渲染 | 普通有窗口路径下已配置桥接、特性和相关资源。 |
| 场景 | Entry 与 Play 构建函数已注册，初始 Entry 对象已建立。 |
| 主循环与渲染线程 | EngineApplication.Run 接下来才调用 RunLoop；初始化已为它准备好游戏侧连接。 |

本轮的关键区别是“立即配置和创建”与“登记后等待调用”。Bootstrap.Initialize 两种工作都做；正式文章需要沿代码逐处指出执行时机。

下一段阅读位置：Initialize 返回之后，进入 EngineApplication.RunLoop，观察它怎样按顺序使用这些连接。

继续阅读：[RunLoop](05-waylith-runloop.md)。
