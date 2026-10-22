# Waylith 阅读笔记：RenderThread.Enqueue 与线程之间的帧交接

阅读位置：RunLoop 已在主线程取得 RenderFrame，现在调用 _renderThread.Enqueue(renderFrame)。本段追踪入队、等待与渲染线程取帧，停在 RenderThread.RenderFrame 的入口。

## Enqueue 仍在主线程执行

```csharp
public void Enqueue(RenderFrame frame)
{
    this.ThrowIfFaulted();
    this.MarkFramePending();
    try
    {
        this._frames.Add(frame);
    }
    catch
    {
        this.MarkFrameComplete();
        frame.Dispose();
        throw;
    }
    this.ThrowIfFaulted();
}
```

调用对象名为 RenderThread，但这次普通方法调用仍由 RunLoop 所在的主线程执行。真正的另一条线程在 Start 中启动，执行 RenderLoop；两条线程通过 _frames 共享帧数据。

Add 放入的是已经取得的 RenderFrame 引用。这里没有序列化或深复制，也没有在入队时生成最终图像。成功交接后，主线程继续进行入队后通知、EndFrame 和限速，渲染线程负责消费帧。

定位：Enqueue（`Waylith.Rendering.RenderThread.cs:46`）、线程启动（`Waylith.Rendering.RenderThread.cs:33`）、RunLoop 的调用及后续处理（`Waylith.EngineApplication.cs:793`）。

## 有界队列怎样限制生产速度

构造函数建立的队列是：

```csharp
this._frames = new BlockingCollection<RenderFrame>(
    Math.Max(1, renderContext.FramesInFlight));
```

容量至少为 1，由渲染上下文的 FramesInFlight 决定。队列有空位时，Add 可以放入数据；队列满时，Add 会等待。主线程等待期间，无法继续这一轮后面的代码，也无法开始下一轮输入轮询和 OnUpdate。

以容量为 2 的假设场景说明：

| 当时的位置 | 帧数据 |
| --- | --- |
| 渲染线程正在处理 | A |
| 队列中等待 | B、C，已满 |
| 主线程已经采集，正在尝试加入 | D |

主线程此时停在 Add(D)。当渲染线程之后从队列取走 B，队列腾出空位，D 才有机会加入。B 此时刚被取出，其后续记录、提交等工作可以尚未完成。

这让渲染端的处理速度反过来限制主线程生产速度，通常称为背压。相邻主循环时间采样之间，也就可能包含这段队列等待。

这条入队路径没有用新帧覆盖旧帧的逻辑。正常运行中，队列满会等待；停止或故障导致入队失败时，则进入异常处理。

容量限制的是队列里等待取出的帧数。渲染线程已经取出的帧、主线程正在尝试放入的帧，以及提交后仍保留的帧各有其他存放位置，因此不能把队列容量直接当作整个流程中所有帧数据的数量或显示延迟。

定位：队列与已提交帧数组的构造（`Waylith.Rendering.RenderThread.cs:19`）、渲染线程取帧（`Waylith.Rendering.RenderThread.cs:159`）。

## MarkFramePending 记录的是什么

MarkFramePending 在 Add 之前执行。它在锁内增加 _pendingFrames，并重置 _idle 事件：

```csharp
this._pendingFrames++;
this._idle.Reset();
```

因此，正在等待入队的帧也已经计入 pending。这个计数还涵盖队列里等待的帧和已被取出、尚未完成本次渲染线程处理的帧。

正常处理收尾调用 MarkFrameComplete：减少计数；当计数到零时，设置 _idle。Add 失败时，Enqueue 的 catch 也调用它，撤销前面增加的计数。

WaitUntilIdle 等待的正是这个事件，随后再检查渲染线程是否保存了异常。

| 状态 | 在这里表示什么 |
| --- | --- |
| 队列出现空位 | 生产者可以继续尝试加入帧 |
| 队列为空 | 当前没有等候取出的帧；渲染线程仍可能在处理已经取出的帧 |
| pending 归零、_idle 被设置 | 正常计数路径中，已登记的帧都结束了渲染线程处理或已撤销入队 |
| GPU 已完成相关工作 | 要由渲染上下文和设备同步进一步确认 |

代码将提交后的帧另存到 _submittedFrames；Stop 也在等待线程结束后，另外执行 Device.WaitIdle 再释放这些帧。这些位置说明 CPU 侧的处理收尾与 GPU 完成有各自的时机。

定位：MarkFramePending（`Waylith.Rendering.RenderThread.cs:286`）、MarkFrameComplete（`Waylith.Rendering.RenderThread.cs:297`）、WaitUntilIdle（`Waylith.Rendering.RenderThread.cs:91`）、保留已提交帧（`Waylith.Rendering.RenderThread.cs:314`）、Stop 的设备等待（`Waylith.Rendering.RenderThread.cs:64`）。

## 另一端怎样取帧

RenderLoop 的消费入口是：

```csharp
foreach (RenderFrame renderFrame in this._frames.GetConsumingEnumerable())
{
    // 调用 RenderFrame(renderFrame)，随后进行通知、释放判断与计数收尾。
}
```

队列暂时为空时，消费端会等待新数据。正常停止时，Stop 调用 CompleteAdding，不再接受新帧；已入队内容可以继续被消费，耗尽后结束遍历，再由 Join 等待线程退出。

每次取出帧后，RenderLoop 调用同一个类中的私有方法 RenderFrame(renderFrame)。该方法返回的布尔值用于决定帧容器是否已被保留：没有保留时，外层收尾释放容器；保留时，容器留给后续槽位回收。这个返回值的具体设置要在下一段结合获取、提交路径阅读。

正常收尾还会触发 NotifyRenderThreadFrameEnded，并调用 MarkFrameComplete。这里的 FrameEnded 通知位于渲染线程处理收尾处，GPU 与屏幕呈现的进度还需继续追踪。

定位：RenderLoop（`Waylith.Rendering.RenderThread.cs:159`）、下一处 RenderFrame 入口（`Waylith.Rendering.RenderThread.cs:197`）。

## 入队两侧的异常检查

ThrowIfFaulted 读取渲染线程保存的 ExceptionDispatchInfo，存在时调用 Throw 重新抛出。Enqueue 在入队前、Add 成功后各检查一次；因此，渲染线程可以在主线程提交帧的边界上报告故障。

如果 Add 本身抛出异常，catch 会撤销 pending 计数、Dispose 本次帧，再向外传播。源码中这段 catch 只包围 Add；前后的 ThrowIfFaulted 各在它之外，不能将三处异常都描述成走同一段清理。

RenderLoop 外围捕获异常后保存 _failure，并尝试调用 CompleteAdding，停止继续接收帧。主循环另有自己的 ThrowIfFaulted 检查点。

定位：异常重新抛出（`Waylith.Rendering.RenderThread.cs:80`）、渲染线程捕获异常（`Waylith.Rendering.RenderThread.cs:183`）、主循环检查点（`Waylith.EngineApplication.cs:619`）。

## 下一处入口

本段接通了主线程生产与渲染线程消费：CaptureFrame 返回 → Enqueue 等待空位并交接 → RenderLoop 取出 → RenderFrame(packet)。Enqueue 正常返回后，帧已经交给消费流程；当时渲染线程处理到哪一步，取决于实际调度。

下一段进入 RenderThread.RenderFrame，先读 TryAcquireNextFrame：渲染线程怎样取得可用的帧资源与指令缓冲，以及为什么取帧后仍可能需要等待或请求重建。继续保持 Waylith 范围，游戏内部流程书签不变。

继续阅读：[渲染线程怎样取得下一帧资源](10-waylith-frame-acquire.md)。
