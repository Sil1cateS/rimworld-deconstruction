# RimWorld 源码解析：章节目录

沿引擎、对象基础、定义框架与运行调度阅读，再继续进入各游戏系统。第一至第七章均已定稿。

| 章节 | 内容 | 阅读入口 |
| --- | --- | --- |
| 01 · Waylith | 启动、主循环、线程与渲染数据交接 | [目录与正式版](01-waylith/README.md) |
| 02 · UnityWorld 与 UnityEngine.Object | 对象登记、组件结构、启停与帧更新 | [目录与正式版](02-UnityWorld&UnityObject/README.md) |
| 03 · XML 与 Def | 定义结构，以及加载、存储与查询 | [两篇正式版](03-def-framework/README.md) |
| 04 · tick | 游戏时间、推进循环、单步分派与对象分组 | [发布版](04-tick/release.md) · [完整解析版](04-tick/article.md) |
| 05 · 线程 | 长任务、线程执行、并行工作与主线程交接 | [发布版](05-threads/release.md) · [完整解析版](05-threads/article.md) |
| 06 · 协程 | 进度保存、等待条件、帧阶段与结束清理 | [发布版](06-coroutines/release.md) · [完整解析版](06-coroutines/article.md) |
| 07 · 世界生成 | 从世界设置和逐层生成读到确认落点与首张地图 | [发布版](07-world-generation/release.md) · [完整解析版](07-world-generation/article.md) · [子章目录](07-world-generation/README.md) |
| 07a · 气候与地形规则 | 群系评分、湖泊与河流、道路、地标与特征 | [发布版](07-world-generation/01-climate-terrain-rules-release.md) · [完整解析版](07-world-generation/01-climate-terrain-rules.md) |
| 07b · 世界数据的存储与查询 | 地块与世界对象、选址查询、地形页读数与存读档 | [发布版](07-world-generation/02-world-data-storage-query-release.md) · [完整解析版](07-world-generation/02-world-data-storage-query.md) |

第四至第六章的衔接与写作范围见 [运行与调度整合目录](04-06-runtime-scheduling.md)。已定稿章节与后续模块的关系见 [系列结构图](../00-series-outline.md#系列结构图)。
