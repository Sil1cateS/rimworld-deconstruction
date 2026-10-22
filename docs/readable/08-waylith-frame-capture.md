# Waylith 阅读笔记：主线程怎样准备 RenderFrame

阅读位置：回到 EngineApplication.RunLoop，在 OnUpdate 返回之后沿可绘制路径继续。游戏流程分支停在 [Game.UpdatePlay 的入口](07-waylith-root-play.md)，本段只读主线程的准备和采集。

## 更新结束后的交接

确认没有关闭或退出请求、且本轮允许绘制后，RunLoop 执行以下核心语句。此处合并原本分布在性能统计作用域中的调用：

```csharp
FrameTiming frameTiming = new FrameTiming(Time.FrameCount, num3, (double)num2);
this.FrameRenderer.BeginMainThreadFrame(in frameTiming);
RenderFrame renderFrame = this.FrameRenderer.CaptureFrame(
    in frameTiming, this._clearValues, false);
this._renderThread.Enqueue(renderFrame);
```

FrameTiming 包含帧号、deltaTime 和累计时间。这几次调用发生在主线程：先准备，再取得渲染特性提供的数据，最后交给队列。此时形成的 RenderFrame 保存后续绘制需要的数据与引用，最终图像由后续渲染流程生成。

定位：RunLoop 的采集与入队（`Waylith.EngineApplication.cs:783`）、FrameTiming（`Waylith.Rendering.FrameTiming.cs:8`）。

## BeginMainThreadFrame：确定本轮使用的特性列表

FrameRenderer.BeginMainThreadFrame 依次执行：

1. 读取当前注册的 IRenderFeature 数组引用，保存到 _mainThreadFeatures。
2. 尝试释放已经退役、且没有仍存活的 RenderFrame 引用的特性。
3. 按数组顺序，对实现 IEarlyMainThreadRenderFeature 的特性调用 BeginMainThreadFrame。

特性的添加和移除会创建新数组，再发布新数组引用。本轮保存的是当时那一版数组；这使准备阶段与后续 CaptureFrame 可以使用相同的列表。数组里的特性对象仍是引用，不能据此推断对象的全部状态都已复制。

这里的主线程准备点位于 OnUpdate 之后。它在渲染采集之前，为需要额外准备的特性提供一个可选接口。

定位：BeginMainThreadFrame（`Waylith.Rendering.FrameRenderer.cs:253`）、添加特性时发布新数组（`Waylith.Rendering.FrameRenderer.cs:81`）、移除特性（`Waylith.Rendering.FrameRenderer.cs:105`）、可选准备接口（`Waylith.Rendering.IEarlyMainThreadRenderFeature.cs:6`）。

## CaptureFrame：逐个取得本轮数据

FrameRenderer.CaptureFrame 使用刚保存的 _mainThreadFeatures，先通过 RenderFrame.Rent 取得一个帧容器，并登记这组特性仍被存活帧使用。随后进行两轮遍历：

```csharp
// 省略性能统计作用域，保留两轮遍历的顺序。
for (int i = 0; i < mainThreadFeatures.Length; i++)
{
    renderFrame.SetFeaturePayload(i, mainThreadFeatures[i].CaptureFrame(in timing));
}
for (int j = 0; j < mainThreadFeatures.Length; j++)
{
    renderFrame.SetFeatureActive(j, mainThreadFeatures[j].IsActive);
}
```

第一轮逐个调用特性的 CaptureFrame，将返回的 payload 按索引存放；第二轮再读取各特性的 IsActive。外层采集方法会调用列表中所有特性的 CaptureFrame，具体特性可以在内部决定返回什么数据。

IRenderFeature.CaptureFrame 的返回类型是 object，允许不同特性提供不同结构的数据；是否复制、怎样保留内部资源，由各特性负责。FrameRenderer 在此负责统一组织这些结果。

若采集中抛出异常，方法会 Dispose 已取得的帧，再向外传播异常。

定位：FrameRenderer.CaptureFrame（`Waylith.Rendering.FrameRenderer.cs:206`）、IRenderFeature 接口（`Waylith.Rendering.IRenderFeature.cs:11`）。

## RenderFrame 带走了什么

| 内容 | 保存方式或作用 |
| --- | --- |
| FrameTiming | 保存本轮帧号与时间信息 |
| Features | 保存本轮使用的特性数组引用 |
| 各特性的 payload | 按索引保存 CaptureFrame 返回的对象引用 |
| 各特性的活动标记 | 保存采集后读取的 IsActive 值 |
| ClearValues | 将传入的清除值复制到容器内部数组 |
| RequestRenderContextRebuild | 保存重建请求标记；上述 RunLoop 调用传入 false |

Rent 优先从池中取回 RenderFrame，池为空才创建对象。因此，每轮取得一个容器并不意味着每轮必然新建该对象。

RenderFrame.Dispose 会释放实现 IDisposable 的 payload、清空其引用、通知 FrameRenderer 移除存活帧登记，并将容器放回池中。特性移除后的延迟释放会检查这些登记。这里先建立帧容器与特性的生命周期联系；GPU 资源何时可以释放，还需沿渲染线程和设备同步继续确认。

定位：RenderFrame.Rent（`Waylith.Rendering.RenderFrame.cs:48`）、RenderFrame.Dispose（`Waylith.Rendering.RenderFrame.cs:106`）、帧释放后的登记移除（`Waylith.Rendering.FrameRenderer.cs:238`）、退役特性释放检查（`Waylith.Rendering.FrameRenderer.cs:268`）。

## 本段边界与下一处入口

引擎通过 IRenderFeature 取得游戏提供的渲染数据。地图、世界、界面分别如何构造 payload，留到对应渲染模块；本段保留接口、调用顺序和数据归属。

当前进度到 CaptureFrame 返回。下一段从 RenderThread.Enqueue 接续，追踪 RenderFrame 怎样进入有界队列、主线程什么时候等待，以及渲染线程怎样取出这批数据。后续再沿 RecordFrame、提交、呈现与收尾逐段展开。

继续阅读：[RenderThread.Enqueue 与线程之间的帧交接](09-waylith-render-enqueue.md)。
