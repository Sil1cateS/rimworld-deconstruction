# 第六章 · 协程：进度、等待与结束

本章于 2026-11-14 定稿，依据 RimWorld 1.7.4982 rev1280 的兼容层实现。

| 版本 | 内容 |
| --- | --- |
| [发布版 v1.0](release.md) | 从开发者索引查找启动、帧阶段与等待指令，结合原版案例和代码示例读到停止与清理。 |
| [完整解析版 v1.0](article.md) | 展开 `CoroutineHandle` 字段、`Step` 的检查循环、生命周期调用及源码定位。 |

配图的 PNG、SVG 和可编辑 DOT 存在 [系列通用图目录](../../figures/)。共同审读的 [整合草稿](draft.md) 可供对照。

上一章：[线程](../05-threads/README.md)。[本组整合目录](../04-06-runtime-scheduling.md) · [系列大纲](../../00-series-outline.md)。
