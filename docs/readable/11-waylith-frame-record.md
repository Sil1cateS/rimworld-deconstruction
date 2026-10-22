# Waylith 阅读笔记：FrameRenderer.RecordFrame 怎样组织指令记录

阅读位置：渲染线程已取得 AcquiredFrame，回收旧槽位数据包，准备调用 FrameRenderer.RecordFrame。本段追踪记录前通知、payload 与 pass 的对应关系、三段记录顺序，停在 TrySubmitFrame 的入口。

## 进入 RecordFrame 之前

RenderThread 在成功获取资源后，先发出 RenderThreadFrameStarting 通知，再取出 FrameResources 和 CommandBuffer。如果主 render pass 或尺寸变化，就发出渲染目标重建通知。随后 Reset 指令缓冲、Begin 记录，并构造 FrameContext。

帧开始通知连接了 MeshUploads.BeginRenderFrame、GpuTextureService.BeginRenderFrame 和 ComputeBufferResourceManager.OnRenderFrameStarting 等维护入口。这里先确认调用位置，各服务的资源管理细节留到对应部分。

FrameContext 保存渲染上下文、已取得的图像资源和指令缓冲，并提供 RenderPass、Framebuffer、Extent 等属性。它与主线程采集的 RenderFrame 一起传入 RecordFrame：前者提供记录环境，后者提供本次各特性的数据。

定位：RenderThread 的准备顺序（`Waylith.Rendering.RenderThread.cs:225`）、维护入口的注册（`Waylith.EngineApplication.cs:450`）、FrameContext 的构造（`Waylith.Rendering.FrameContext.cs:161`）。

## 记录开头还有两项准备

RecordFrame 首先用 Interlocked.Exchange 取走 _nextFrameEvents 并置空，然后调用取出的委托。这里对应 AddNextFrameCallback 登记的一次性回调；它在本次渲染线程记录入口执行。一个实际调用方是 ShaderHotReloader，请求重载时登记 ReloadOnRenderThread。

因此，此处的“下一帧回调”应定位到下一次取到该回调的 RecordFrame 调用。没有进入记录阶段的引擎更新，不会仅凭帧号推进就执行这里的回调。

随后方法读取 frame.Features。如果数组引用不同于 _lastRecordedFeatures，就补齐相应特性的 OnRenderTargetRebuilt 通知。_rebuiltFeatures 集合用于跟踪已经通知过的特性，避免在这条补齐路径中反复通知同一个对象。

定位：RecordFrame 开头（`Waylith.Rendering.FrameRenderer.cs:316`）、AddNextFrameCallback（`Waylith.Rendering.FrameRenderer.cs:138`）、热重载调用方（`Waylith.Rendering.ShaderHotReloader.cs:150`）、补齐重建通知（`Waylith.Rendering.FrameRenderer.cs:192`）。

## feature、payload 与 pass 怎样对应

主线程通过 IRenderFeature.CaptureFrame 取得 payload。渲染线程则读取同一特性提供的 Passes，按阶段调用 IRenderPass.Record：

```csharp
void Record(in FrameContext ctx, object featurePayload);
```

RecordFrame 通过索引取出该特性的 payload，将它传给这个特性中符合当前阶段条件的各个 pass。一个特性可以有多个 pass，这些调用接收同一份 featurePayload 引用；具体类型转换和使用方式由 pass 实现。

本段循环检查的是 frame.GetFeatureActive(index)，也就是主线程采集后保存的活动标记。特性数组同样来自该 RenderFrame；但 Passes 是记录时从特性对象上读取的，不能将整个特性对象与所有资源都描述为已深复制的快照。

定位：IRenderFeature（`Waylith.Rendering.IRenderFeature.cs:10`）、IRenderPass.Record（`Waylith.Rendering.IRenderPass.cs:24`）、活动标记、payload 与 pass 的读取（`Waylith.Rendering.FrameRenderer.cs:329`）。

## 三段记录顺序

RecordFrame 对特性数组做三轮遍历。每一轮都保持特性数组顺序，再保持该特性 Passes 的列表顺序，按以下条件筛选：

| 阶段 | 筛选条件 | 外层提供的记录环境 |
| --- | --- | --- |
| 主 render pass 之前 | pass.PreBackbuffer | 有 Attachment 时派生 FrameContext，否则使用原上下文 |
| 主 render pass 内 | !pass.PreBackbuffer 且不是 IPostBackbufferPass | 外层 BeginRenderPass 后，使用主 FrameContext 调用 Record |
| 主 render pass 之后 | pass 实现 IPostBackbufferPass | 外层 EndRenderPass 后，使用主 FrameContext 调用 Record |

主线可以写成：

```text
所有活动特性中符合条件的前置 pass
  → BeginRenderPass（主目标、绘制范围、帧内保存的 ClearValues）
  → 所有活动特性中符合条件的普通 pass
  → EndRenderPass
  → 所有活动特性中符合条件的后置 pass
```

这里先按阶段分组，再按列表顺序调用。举例说，若特性 A、B 各有一个前置和一个普通 pass，记录顺序会是 A 前置、B 前置，再到主 render pass 内的 A 普通、B 普通。

本方法没有按 PassId 排序；PassId 在其他模块中的路由或筛选用途，需要沿相应代码阅读。

定位：前置遍历（`Waylith.Rendering.FrameRenderer.cs:329`）、主 render pass 开始（`Waylith.Rendering.FrameRenderer.cs:352`）、普通 pass 遍历（`Waylith.Rendering.FrameRenderer.cs:365`）、结束与后置遍历（`Waylith.Rendering.FrameRenderer.cs:387`）。

## 两种 pass 与 Attachment

IRenderPass 是 Waylith 的 C# 接口，Record 方法可以组织绘制、计算或复制等指令。主目标的 BeginRenderPass / EndRenderPass 则在指令缓冲中划出一段 Vulkan render pass 记录范围。多个 Waylith 普通 pass 可以在这同一段范围内记录。

前置 pass 有 Attachment 时，FrameRenderer 只调用 Attachment.MakeFrameContext 派生上下文，再调用 pass.Record。它不会在这条通用分支中自动替每个前置 pass 开始或结束 Vulkan render pass；需要的记录范围由具体实现组织。

MakeFrameContext 保留原渲染上下文、Resources 和 CommandBuffer，覆盖 RenderPass、Framebuffer、Extent、采样数与格式等属性。其中 Attachment 的 Framebuffer 按 SubmissionFrameIndex 选择。具体 pass 可以据此向中间目标记录工作。

定位：Attachment 分支（`Waylith.Rendering.FrameRenderer.cs:339`）、MakeFrameContext（`Waylith.Rendering.PassAttachment.cs:58`）、FrameContext 的覆盖构造（`Waylith.Rendering.FrameContext.cs:176`）。

## 把阶段对应到游戏画面

仅用已注册的实现说明调度位置，暂不深入地图网格与界面的内部绘制规则：

| 实现 | 阶段与工作 |
| --- | --- |
| ComputeRenderPass | PreBackbuffer 为 true，前置阶段处理采集的计算分派 |
| MapMainPass | PreBackbuffer 为 true，内部使用 SceneColorTargets 等目标记录地图场景 |
| CompositePass | PreBackbuffer 为 false，通过 PostFxFeature 提供，在主 render pass 内读取场景颜色纹理并记录合成绘制 |
| ImGuiRenderFeature | 普通 pass，在主 render pass 内将采集的 ImGuiDrawSnapshot 交给 host.Render |
| ScreenCaptureFeature | 实现 IPostBackbufferPass，在主 render pass 之后记录从主颜色图像到截图目标的复制 |

Bootstrap 将 PostFxFeature 注册在 ImGuiRenderFeature 之前。结合阶段规则，在相应特性活动、payload 有效且资源就绪的路径上，可以得到这一局部顺序：

```text
地图内容记录到场景目标
  → 合成场景颜色到窗口主目标
  → 记录界面
  → 有截图请求时，记录主颜色图像的截图复制
```

这个顺序解释了场景、界面和截图工作在帧内怎样衔接。截图阶段这里只记录 GPU 图像复制，CPU 读取或文件保存还需沿截图模块继续追踪。世界、相机采集等其他已注册特性也各有工作；上图只截取相关连接。

定位：特性注册顺序（`RimWorldWaylith.Bootstrap.cs:300`）、计算 pass（`Waylith.Rendering.Compute.ComputeRenderPass.cs:39`）、地图 pass 的阶段与入口（`RimWorldWaylith.Rendering.MapRenderFeature.cs:235`）、地图场景目标记录（`RimWorldWaylith.Rendering.MapRenderFeature.cs:347`）、合成 pass（`Waylith.Rendering.PostFx.CompositePass.cs:37`）、界面 pass（`RimWorldWaylith.Imgui.ImGuiRenderFeature.cs:81`）、截图复制（`RimWorldWaylith.Rendering.ScreenCaptureFeature.cs:146`）。

## Record 最终记录了什么

以 CompositePass 为例，它取得本提交槽位对应的场景颜色纹理，将纹理设为输入，设置饱和度参数，再调用 PostEffectPass.RecordInline。后者绑定图形管线、设置视口和裁剪范围、绑定输入与参数，最后调用：

```csharp
commandBuffer.Draw(3, 1, 0, 0);
```

这一层已经可以追到具体指令记录调用。FrameRenderer 负责阶段组织、上下文和 payload 分发，具体 pass 负责把这些内容转成指令；管线与 shader 怎样决定每个像素，留到相应渲染模块。

定位：合成输入与参数（`Waylith.Rendering.PostFx.CompositePass.cs:46`）、RecordInline 的指令调用（`Waylith.Rendering.PostFx.PostEffectPass.cs:122`）。

## 当前停点

RecordFrame 正常返回后，调用方结束 CommandBuffer 的记录，再调用 TrySubmitFrame。GPU 执行与窗口呈现的交接位于这之后。

下一段进入 WindowRenderContext.TrySubmitFrame，继续阅读等待与发出的 semaphore、图形队列提交和 PresentFrame，接通这一帧从记录到提交、呈现的路径。

定位：记录结束与提交入口（`Waylith.Rendering.RenderThread.cs:243`）。

继续阅读：[TrySubmitFrame、图形提交与呈现](12-waylith-frame-submit.md)。
