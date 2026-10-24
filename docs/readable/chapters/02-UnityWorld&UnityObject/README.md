# UnityWorld 与 UnityEngine.Object：对象与组件的组织方式

本章提供两个阅读版本：

| 版本 | 阅读入口 | 内容 |
| --- | --- | --- |
| 发布版 v1.0 | [从每一帧到对象与组件](release.md) | 沿运行逻辑解释对象管理、组件组成、空间关系与启停更新，保留必要的代码块、表格和案例 |
| 完整解析版 v1.0 | [完整解析](article.md) | 保留较完整的源码节选、管理记录、阶段顺序、边界说明与源码定位，供深入阅读和核对 |

两版均于 2026-10-24 定稿，依据 RimWorld 1.7.4982 rev1280 的兼容层与游戏代码。

两版开篇先说明与原生 Unity 的关系，以及对象模型和常用接口的保留怎样帮助旧 Mod 迁移，同时区分接口存在、行为一致与实际运行兼容。

本章按以下主线展开：

UnityRuntime.Step → UnityWorld 的管理记录与帧阶段 → UnityEngine.Object → GameObject 与 Component → Transform → 其他组件的协作样例 → Behaviour → MonoBehaviour 的必要功能。

正文重点解释对象怎样被登记、查询、组合、启停与更新。Camera、AudioSource、AudioListener、MeshFilter、Renderer、MeshRenderer 作为相应父类后的功能样例，具体相机、音频和渲染实现分别留给后续模块。协程保留必要接口、管理记录与帧阶段连接，CoroutineScheduler 的详细调度留给进程与运行模块。

本章目录中的 UnityObject 对应源码类型 UnityEngine.Object；正文使用源码原名。两版的代码节选沿用原有命名，讲解用例单独注明。文档和图片使用相对链接；完整解析版的源码采用“命名空间.类型名.cs:行号”的文字定位，行号对应当前本地反编译源码，源码不随仓库上传。

图像、SVG 与可编辑 DOT 图源位于本章 [figures](figures/) 和系列通用图目录。发布版使用更新顺序图、类型树和相机组件组合图；完整解析版还保留管理引用、空间换算与激活流程等图示。

此前的 [整合草稿 v0.1](draft.md) 与逐类阅读笔记保留为参考材料，笔记索引见完整解析版末尾。本章采用静态源码阅读，调用顺序与边界说明以此版本的实现为依据。

上一章：[Waylith 完整解析](../01-waylith/article.md)、[简洁发布版](../01-waylith/release.md)。系列入口：[系列大纲](../../00-series-outline.md)。
