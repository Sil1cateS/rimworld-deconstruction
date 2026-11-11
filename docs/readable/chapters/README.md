# RimWorld 源码解析：章节目录

沿引擎、对象基础、定义框架与运行调度阅读，再继续进入各游戏系统。前五章已有正式版，第六章提供整合草稿，供共同阅读与修订。

| 章节 | 内容 | 阅读入口 |
| --- | --- | --- |
| 01 · Waylith | 启动、主循环、线程与渲染数据交接 | [目录与正式版](01-waylith/README.md) |
| 02 · UnityWorld 与 UnityEngine.Object | 对象登记、组件结构、启停与帧更新 | [目录与正式版](02-UnityWorld&UnityObject/README.md) |
| 03 · XML 与 Def | 定义结构，以及加载、存储与查询 | [两篇正式版](03-def-framework/README.md) |
| 04 · tick | 游戏时间、推进循环、单步分派与对象分组 | [发布版](04-tick/release.md) · [完整解析版](04-tick/article.md) |
| 05 · 线程 | 长任务、线程执行、并行工作与主线程交接 | [发布版](05-threads/release.md) · [完整解析版](05-threads/article.md) |
| 06 · 协程 | 进度保存、等待条件、帧阶段与结束清理 | [整合草稿](06-coroutines/draft.md) |

第四至第六章的衔接与写作范围见 [运行与调度整合目录](04-06-runtime-scheduling.md)。后续模块规划与逐段研究进度见 [系列大纲](../00-series-outline.md)。
