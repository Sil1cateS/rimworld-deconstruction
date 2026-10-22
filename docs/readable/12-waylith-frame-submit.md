# Waylith 阅读笔记：TrySubmitFrame、图形提交与呈现

阅读位置：FrameRenderer.RecordFrame 已返回，RenderThread 结束主指令缓冲的记录，调用 _renderContext.TrySubmitFrame。本段沿正常窗口路径连接同步对象、图形队列、PresentFrame 和本次 CPU 处理的收尾。

游戏流程分支继续停在 Game.UpdatePlay 入口。程序调用关系以本地源码为依据，GPU 同步与呈现接口的语义另核对 Vulkan 官方文档。

## 无参数调用补上窗口路径的同步对象

RenderContext 的无参数 TrySubmitFrame 将三个空 Span 转交给虚方法：额外等待的 semaphore、对应等待阶段，以及额外发出的 semaphore。本次普通主路径没有额外项；WindowRenderContext 的实现会在各数组的首项补上自己的同步要求。

| 内容 | 本路径填入的值 | 作用 |
| --- | --- | --- |
| 等待的 semaphore | 当前提交槽位的 ImageReadySemaphore | 接上前面获取交换链图像的通知 |
| 对应等待阶段 | ColorAttachmentOutputBit | 指定这项等待所约束的管线阶段 |
| 发出的 semaphore | GetImageRenderingFinishedSemaphore() | 供后面的呈现操作等待 |
| 指令缓冲 | 当前提交槽位的 CommandBuffer | 上一段已经结束记录的主指令缓冲 |
| fence | 当前提交槽位的 Fence | 供 CPU 后续复用槽位时等待提交完成 |

等待阶段是提交参数的一部分，不能将这项 semaphore 等待概括为 CPU 在此逐条等待所有绘制指令执行。

定位：无参数重载（`Waylith.Graphics.RenderContext.cs:214`）、窗口提交参数组装（`Waylith.Graphics.WindowRenderContext.cs:448`）。

## 三种同步连接

这条路径上的同步关系可以分别读成：

```text
图像获取操作
  → 发出 ImageReadySemaphore
  → 图形提交在指定阶段等待

本次图形提交
  → 发出本张交换链图像对应的 rendering-finished semaphore
  → 呈现操作等待

本次图形提交
  → 触发提交槽位的 fence
  → CPU 后续复用该槽位时等待
```

窗口使用的 rendering-finished semaphore 按交换链图像建立数组，再按 FrameIndex 选取；ImageReadySemaphore、CommandBuffer 和 fence 则来自提交槽位。

这种分别索引的方式接上了前一段的两套编号。Vulkan 官方指南说明，提交 fence 的完成关系不涵盖呈现操作对 semaphore 的使用；将呈现等待的 semaphore 按交换链图像管理，并结合图像重新获取的同步关系，可以安排其复用。本地代码的结构与这一方案相符。这是结合源码与接口语义作出的解释，源码本身没有在此写出设计理由。参见 [交换链 semaphore 复用指南](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html)。

定位：获取图像时指定 semaphore（`Waylith.Graphics.WindowRenderContext.cs:503`）、按图像建立数组（`Waylith.Graphics.WindowRenderContext.cs:584`）、按 FrameIndex 取值（`Waylith.Graphics.WindowRenderContext.cs:599`）。

## SubmitGraphicsAndPresent 的 CPU 调用顺序

WindowRenderContext 将上述内容传给 GraphicsDevice.SubmitGraphicsAndPresent。该方法先执行 BeforeSubmit 钩子，再在 _graphicsQueueSyncRoot 锁内依次执行：

```csharp
this.GraphicsQueue.Submit(
    waitSemaphores, waitStages, commandBuffers, signalSemaphores, fence);
vkResult = present();
```

BeforeSubmit 在纹理服务配置中绑定到 SubmitPendingTextureCommands。这是提交前的另一个资源服务接点，纹理命令本身留给资源管理部分展开。

锁约束的是 CPU 侧这组队列调用的访问顺序。图形指令交给 GraphicsQueue，present 委托进入 WindowRenderContext.PresentFrame；窗口构造时将其呈现队列设为 GraphicsDevice.PresentQueue。

图形提交附带的 fence 用于在所提交指令缓冲完成执行时发出信号，供后续 CPU 等待。参见 [vkQueueSubmit 官方说明](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueueSubmit.html)。

定位：SubmitGraphicsAndPresent（`Waylith.Graphics.GraphicsDevice.cs:533`）、纹理服务钩子（`Waylith.Rendering.GpuTextureService.cs:150`）、呈现队列的选择（`Waylith.Graphics.WindowRenderContext.cs:74`）。

## PresentFrame 提出了什么请求

PresentFrame 取得当前图像对应的 rendering-finished semaphore，构造 VkPresentInfoKHR。它描述：等待哪一个 semaphore、使用哪一个 swapchain，以及呈现其中哪一个 FrameIndex。随后调用：

```csharp
vkResult = this.queue.PresentKHR(vkPresentInfoKHR);
```

至此，已经生成的图像通过呈现请求交给平台呈现路径。Vulkan 说明，这个调用可以阻塞；其排队的操作包含 semaphore 等待和向呈现引擎提出请求，而实际图像处理及显示时序由呈现引擎和平台决定。因此，仅从这里返回，无法判定用户在屏幕上看到该帧的精确时点。参见 [vkQueuePresentKHR 官方说明](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueuePresentKHR.html)。

定位：PresentFrame（`Waylith.Graphics.WindowRenderContext.cs:415`）。

## 呈现结果与保留数据包

SubmitGraphicsAndPresent 返回的是 present 委托的结果。WindowRenderContext 再将其映射为 FrameResult：

| 呈现返回值 | FrameResult 与外层动作 |
| --- | --- |
| Success | 返回 Success |
| ErrorOutOfDateKHR 或 SuboptimalKHR | 返回 NeedsResize，RenderThread 登记重建请求 |
| ErrorSurfaceLostKHR | 返回 SurfaceLost，RenderThread 登记表面重建请求 |
| 其他未处理结果或异常 | 沿异常路径传播 |

PresentFrame 会将部分 Vulkan 结果异常转成状态，便于按上述路径处理。图形提交在 present 调用之前已经执行，因此呈现报告重建时，本次图形工作仍可能在设备上执行。

外层 RenderThread.RenderFrame 处理重建标志后，仍将 packet 放进对应的 _submittedFrames 槽位，然后返回 true。这个布尔值向 RenderLoop 表达数据包已经被保留；呈现结果由 FrameResult 另行表达。

定位：呈现结果映射（`Waylith.Graphics.WindowRenderContext.cs:469`）、异常转状态（`Waylith.Graphics.WindowRenderContext.cs:434`）、重建标志与数据包保留（`Waylith.Rendering.RenderThread.cs:246`）。

## 本次 CPU 处理结束之后

RenderLoop 的正常收尾会调用 NotifyRenderThreadFrameEnded，再根据返回的保留标志决定是否释放数据包，最后调用 MarkFrameComplete。提交保留路径上的数据包留在槽位中，等待后续槽位复用或停机清理。

这就把之前的生命周期接起来了：

```text
主线程采集 RenderFrame
  → 入队并交给渲染线程
  → 获取资源、记录、提交图形工作并提出呈现请求
  → 保留数据包，结束本次渲染线程 CPU 处理
  → 后续复用提交槽位时等待旧提交 fence
  → 回收旧数据包
```

主线程则在 Enqueue 返回后，按自己的路径发出 FrameEnqueued、执行引擎 EndFrame 和限速。两条线程的这些收尾可以在时间上交错。引擎 EndFrame、渲染线程 FrameEnded、提交 fence 完成和屏幕显示各有对应的状态与时点。

定位：RenderLoop 收尾（`Waylith.Rendering.RenderThread.cs:159`）、保留与槽位回收（`Waylith.Rendering.RenderThread.cs:314`）、主线程入队后的收尾（`Waylith.EngineApplication.cs:793`）。

## 当前停点

正常窗口路径已经从更新、采集、线程交接接到指令记录、图形提交、呈现请求和数据包回收。后续可将两条线程的收尾、GPU 完成与下一帧开始按时序对齐，并汇总队列、fence、图像获取、呈现和主线程限速这些不同的等待位置。

继续阅读：[帧的时序、结束与等待](13-waylith-frame-timeline.md)。
