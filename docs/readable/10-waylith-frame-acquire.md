# Waylith 阅读笔记：渲染线程怎样取得下一帧资源

阅读位置：RenderLoop 从队列取出 RenderFrame，调用 RenderThread.RenderFrame(packet)。本段追踪 TryAcquireNextFrame、旧帧回收与失败分支，停在成功获取之后的指令记录准备处。

游戏流程分支仍保留在 Game.UpdatePlay 入口；此处继续沿 Waylith 的帧级行为阅读。程序调用关系以本地源码为依据，Vulkan 等待与图像获取接口的语义另外核对官方文档。

## 从帧数据包到渲染资源

RenderThread.RenderFrame 的前半段按以下顺序执行：

```text
检查 packet 是否直接请求重建
  → TryAcquireNextFrame
  → 读取 SubmissionFrameIndex
  → 释放该提交槽位保留的旧 RenderFrame
  → 检查获取结果
  → 成功时取出 FrameResources 和 CommandBuffer
```

packet 是主线程提供的渲染数据包。取得它之后，渲染线程还需要找到本次使用的目标图像、相关资源和指令缓冲，才能进入记录阶段。

定位：RenderThread.RenderFrame（`Waylith.Rendering.RenderThread.cs:197`）。

## 两套编号各自选择什么

TryAcquireNextFrame 的实现位于基类 RenderContext；窗口路径通过其 GetNextFrameIndex 虚方法进入 WindowRenderContext。这里有两套不同的编号：

| 编号或数据 | 选择方式与用途 |
| --- | --- |
| SyncObjectsIndex | 在 AllSyncObjects 数组中循环选择提交槽位 |
| SubmissionFrameIndex | 通过接口返回上述 SyncObjectsIndex，供渲染线程登记和回收提交后的帧数据包 |
| FrameIndex | 获取交换链图像时返回的图像编号，用来选择 FrameResources |
| SyncObjects.CommandBuffer、Fence 等 | 按提交槽位保存的指令缓冲与同步对象 |
| FrameResources | 按交换链图像保存的颜色图像、视图、Framebuffer，以及按配置建立的深度或多重采样附件等资源 |

CreateSyncObjects 按 FramesInFlight 建立提交槽位；窗口的 FrameResources 数组按交换链实际的 ImageCount 建立。这两套数量与编号分别使用。例如，两个提交槽位与三张交换链图像可以组合工作，当前提交槽位编号无需与取得的图像编号相等。

定位：提交编号的接口实现（`Waylith.Graphics.RenderContext.cs:163`）、提交槽位创建（`Waylith.Graphics.RenderContext.cs:605`）、交换链图像资源创建（`Waylith.Graphics.WindowRenderContext.cs:374`）、附件与 Framebuffer 初始化（`Waylith.Graphics.RenderContext.cs:443`）。

## 先等待提交槽位，再获取图像

RenderContext.TryAcquireNextFrame 首先推进槽位编号：

```csharp
this.SyncObjectsIndex = (this.SyncObjectsIndex + 1) % this.AllSyncObjects.Length;
VkFence fence = this.SyncObjects.Fence;
```

随后调用 WaitForFences，等待选中槽位的 fence。窗口提交代码会把该 fence 传入图形队列提交；正常复用路径中，这一步用于等待该槽位上一次图形提交的执行完成，再继续使用它的指令缓冲等设施。

fence 初始创建为已触发状态，因此第一次使用某槽位时不需要等待一份尚不存在的旧提交。根据 Vulkan 接口语义，等待条件已满足时 WaitForFences 可以立即返回，否则等待条件满足或超时。本代码传入的等待参数采用无限超时形式。参见 [vkWaitForFences 官方说明](https://docs.vulkan.org/refpages/latest/refpages/source/vkWaitForFences.html)。

接着，GetNextFrameIndex 在窗口路径调用：

```csharp
base.Device.AcquireNextImageKHR(
    this.swapchain,
    (IntPtr)(-1),
    base.SyncObjects.ImageReadySemaphore,
    default(VkFence),
    out imageIndex);
```

这个调用取得下一张用于呈现的交换链图像编号，并设置图像获取的信号通知。没有图像可供获取时，它也可能等待；本代码同样传入无限超时形式。参见 [vkAcquireNextImageKHR 官方说明](https://docs.vulkan.org/refpages/latest/refpages/source/vkAcquireNextImageKHR.html)。

因此，本方法名中的 Try 表示结果会以状态返回，不能由此推断它是一次不等待的尝试。

获取操作返回图像编号后，后续图形提交仍使用 ImageReadySemaphore 建立等待关系。CPU 能够继续记录指令，与 GPU 何时获准访问该图像，需要分别理解；具体等待阶段留到提交部分阅读。

定位：TryAcquireNextFrame（`Waylith.Graphics.RenderContext.cs:245`）、窗口获取图像（`Waylith.Graphics.WindowRenderContext.cs:503`）、槽位 fence 的初始状态（`Waylith.Graphics.RenderContext.cs:627`）、提交时传入同步对象（`Waylith.Graphics.WindowRenderContext.cs:448`）、实际图形队列提交（`Waylith.Graphics.GraphicsDevice.cs:533`）。

## 成功时得到的 AcquiredFrame

只有 GetNextFrameIndex 返回 Success 时，TryAcquireNextFrame 才重置该槽位的 fence，返回成功状态及以下组合：

```csharp
new AcquiredFrame(
    this.FrameResources[this.FrameIndex],
    this.SyncObjects.CommandBuffer)
```

可以将它读成：把本次取得的图像资源，与本次选中的提交槽位的指令缓冲配成一组。AcquiredFrame 是保存这两个引用的结构体，RenderThread 在成功分支将它们解构出来供后续记录使用。

RenderFrame 保存主线程采集的渲染内容；AcquiredFrame 提供本次记录所用的目标资源和指令缓冲。两者在后续 RecordFrame 中相遇。

定位：成功分支（`Waylith.Graphics.RenderContext.cs:253`）、AcquiredFrame 的构造与解构（`Waylith.Graphics.AcquiredFrame.cs:15`）、渲染线程解构资源（`Waylith.Rendering.RenderThread.cs:225`）。

## 为什么此时才释放旧 RenderFrame

TryAcquireNextFrame 正常返回之后，RenderThread 读取 SubmissionFrameIndex，调用 DisposeSubmittedFrame。该方法找到这个槽位之前保留的 RenderFrame，释放后清空槽位引用。

这一步接上了上一段的生命周期：

```text
旧数据包被记录并进入提交路径
  → 保存在 _submittedFrames[对应槽位]
  → 之后再次选中这个槽位
  → 等待该槽位旧提交的 fence
  → 回收这个槽位保留的旧数据包
```

所以，RenderLoop 完成本次 CPU 处理、减少 pending 时，数据包仍可能保留；槽位后续复用时才回收它。这里确认的是对应图形提交的完成关系，屏幕是否已经显示该图像还涉及呈现流程。

源码将旧数据包回收放在获取结果判断之前。即使本次图像获取返回重建等状态，正常返回路径也已经先完成了该槽位的 fence 等待。

定位：获取后回收旧包（`Waylith.Rendering.RenderThread.cs:206`）、旧包释放（`Waylith.Rendering.RenderThread.cs:321`）、提交路径保留本次数据包（`Waylith.Rendering.RenderThread.cs:258`）。

## 获取结果怎样改变本次处理

| 获取结果 | 本地代码的处理 |
| --- | --- |
| Success | 重置 fence，返回 AcquiredFrame，进入记录准备 |
| ErrorOutOfDateKHR 或 SuboptimalKHR | 映射为 NeedsResize；渲染线程登记重建请求并返回 false |
| ErrorSurfaceLostKHR | 映射为 SurfaceLost；登记表面重建请求并返回 false |
| NotReady 或 Timeout 对应的容错分支 | 映射为 NotReady，首次记录警告；本次返回 false |

窗口获取函数会捕获部分 Vulkan 结果异常并转成返回状态，其他异常继续向外传播。本表描述该版本代码的处理策略，例如它将 SuboptimalKHR 也归入重建路径。

RenderFrame 返回 false 时，外层 RenderLoop 会在收尾中释放本次数据包。因此，已经采集、入队和取出的数据包，也可能在这一阶段结束处理，未进入本次指令记录。

另有一个更早的分支：如果 packet.RequestRenderContextRebuild 已设置，RenderFrame 在调用 TryAcquireNextFrame 之前就登记重建请求并返回 false。

定位：结果映射（`Waylith.Graphics.RenderContext.cs:264`）、窗口异常转状态（`Waylith.Graphics.WindowRenderContext.cs:503`）、渲染线程的结果分支（`Waylith.Rendering.RenderThread.cs:199`）、外层释放判断（`Waylith.Rendering.RenderThread.cs:171`）。

## 重建请求回到主线程

RequestResize 和 RequestSurfaceRecreate 分别通过 Interlocked.Exchange 设置标志。RunLoop 在后续可绘制路径读取并清除这些标志，等待渲染线程空闲后，调用 Rebuild 或 RecreateSurfaceAndRebuild，并通知渲染特性和渲染线程。

销毁交换链相关旧资源之前，WindowRenderContext 还会调用 Device.WaitIdle。如果表面尺寸为零，主循环则重新登记请求并推迟重建。本段先接通控制路径；实际大小、表面和交换链的重建细节可在窗口管理部分展开。

定位：请求标志（`Waylith.Rendering.RenderThread.cs:263`）、主线程处理请求（`Waylith.EngineApplication.cs:726`）、销毁前的设备等待（`Waylith.Graphics.WindowRenderContext.cs:272`）。

## 当前停点

正常路径已取得 AcquiredFrame，旧槽位数据包也已回收。接下来是帧开始维护通知、渲染目标变化通知、CommandBuffer.Reset / Begin，再建立 FrameContext 并调用 FrameRenderer.RecordFrame。

下一段沿这一小段准备进入 RecordFrame，解释各个渲染特性提供的 payload 怎样交给渲染 pass，成为记录进指令缓冲的工作。

继续阅读：[FrameRenderer.RecordFrame 怎样组织指令记录](11-waylith-frame-record.md)。
