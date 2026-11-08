# 第四章 · tick：游戏时间与模拟调度

本章于 2026-11-08 定稿，依据 RimWorld 1.7.4982 rev1280 的代码整理。

| 版本 | 内容 |
| --- | --- |
| [发布版 v1.0](release.md) | 从游玩现象出发，完整讲解帧入口、速度判断、推进循环、单步分派、对象登记和轮换，配有关键代码与帧率案例 |
| [完整解析版 v1.0](article.md) | 提供字段声明、更多源码节选、实现细节及反编译位置，便于逐段核对 |

共同审读的 [整合草稿 v0.1](draft.md) 保留作底稿。

主线：UnityRuntime.Step → Root_Play 与 Game.UpdatePlay → 时间与速度状态 → TickManagerUpdate → DoSingleTick → TickList → 对象更新入口。

本章保留推进循环、速度与暂停、对象分组、帧频案例和计数公式；地图、物品及玩法系统内部的具体工作在后续模块展开。

图片、SVG 与可编辑 DOT 复用 [系列通用图目录](../../figures/)。源码采用 `命名空间.类型名.cs:行号` 的文字定位，文档与图片均使用相对链接。

上一章：[XML 与 Def](../03-def-framework/README.md)。下一章：[线程](../05-threads/README.md)。[本组整合目录](../04-06-runtime-scheduling.md) · [系列大纲](../../00-series-outline.md)。
