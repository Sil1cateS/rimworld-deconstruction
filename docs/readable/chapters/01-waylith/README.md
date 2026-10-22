# Waylith：从启动到每一帧

本章提供两个阅读版本：

| 版本 | 阅读入口 | 内容 |
| --- | --- | --- |
| 发布版 v1.0 | [从启动到每一帧：Waylith 怎样驱动 RimWorld](release.md) | 面向一般读者，沿运行逻辑展开，使用简图和案例，不保留代码块与逐项源码定位 |
| 完整解析版 v1.0 | [完整解析](article.md) | 保留源码节选、对象与状态说明、复杂分支及详细图示，供深入阅读和核对 |

两版均于 2026-10-22 整理，依据 RimWorld 1.7.4982 rev1280 的反编译代码。

文章沿已确定的顺序展开：Waylith 总览 → 引擎创建 → 初始化 → 两条线程与三个队列 → 主线程 → 渲染线程 → 渲染数据的交换与提交。

两版开头均提供面向玩家的五点省流速览，并沿菜单鼠标输入衔接输入、更新、采集与提交。发布版使用三张简图说明整体分工、主循环分支和队列等待；完整解析版继续保留对象对照表、源码节选，以及交换链重建和 TempJob 维护的可展开补充说明。

本文采用静态源码阅读，尚未进行实际帧率与显示延迟测量。

写作约定见 [系列大纲](../../00-series-outline.md)。完整解析版的源码引用保留原名，讲解用改名须在片段前逐项说明；展开方法前，先解释涉及的类、对象与主要数据。

仓库内的文档、图片与图源使用相对于当前 Markdown 文件的链接。完整解析版采用“命名空间.类型名.cs:行号”的源码定位，例如 `RimWorldWaylith.Bootstrap.cs:749`，供本地核对；`analysis/decompiled/` 不随仓库上传。

发布版图源：

| 图 | 矢量图 | 可编辑图源 |
| --- | --- | --- |
| 从启动到画面输出 | [SVG](../../figures/waylith-release-overview.svg) | [DOT](../../figures/waylith-release-overview.dot) |
| 主线程的一轮工作 | [SVG](../../figures/waylith-release-mainloop.svg) | [DOT](../../figures/waylith-release-mainloop.dot) |
| 队列满与空时的等待 | [SVG](../../figures/waylith-release-handoff.svg) | [DOT](../../figures/waylith-release-handoff.dot) |

此前的 [模块汇总稿 v0.2](../../14-waylith-summary-draft.md)、阅读笔记和图源保留为参考资料。正文图像、SVG 与可编辑图源位于 `docs/readable/figures/`。GameRoot、Root 的详细职责留在后续游戏流程研究；渲染内部数据与 pass 实现留在地图、空间和 UI 之后的渲染模块。
