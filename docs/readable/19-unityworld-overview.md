# UnityWorld：先认识对象的管理者（讨论稿）

状态：对象类型树的前置概览，2026-10-23。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层代码整理。阅读顺序为本篇 → [UnityEngine.Object](17-unityengine-object.md) → [GameObject](18-gameobject.md) → [Component](20-component.md) 及其子节点；总目录见 [对象与组件模式](16-gameobject-component-model.md)。

## 一、为什么先认识 UnityWorld

前面沿类型树阅读时，许多方法都会调用 UnityRuntime.Current.World。若还不知道 World 是什么，就很难解释组件保存在哪里、创建方法返回后对象为何还在，以及谁会在下一帧调用组件的方法。

UnityWorld 是 Waylith.UnityCompat 命名空间中的一个管理类，负责登记 GameObject 和组件，记录它们的所属关系与运行状态，并安排相应的初始化、更新、停用和销毁处理。这里的 World 指这部分兼容层管理功能；玩家存档中的世界、地图等概念在游戏层另有实现。

它与 UnityEngine.Object 的分工可以先这样认识：

| 类型 | 本轮首先关心的职责 |
| --- | --- |
| UnityWorld | 管理登记进来的对象、组件及其关系，安排相应方法的调用 |
| UnityEngine.Object | 提供对象类型共有的名称、编号、销毁和有效性判断等接口 |
| GameObject | 提供组织、查询组件以及控制对象活动状态的接口 |
| Component 及其子类 | 提供组件的共同接口，再逐层增加空间、相机、声音或脚本等具体功能 |

**UnityWorld 与这些对象建立的是管理和引用关系。** UnityEngine.Object → GameObject / Component 才是后面要研究的类型继承关系。UnityWorld 本身没有继承 UnityEngine.Object，也不是可附加到 GameObject 上的组件。

源码定位：UnityWorld 类型声明（`Waylith.UnityCompat.UnityWorld.cs:20`）。

## 二、谁建立 UnityWorld，谁持续使用它

UnityRuntime 在自己的属性初始化中建立 UnityWorld，原始声明如下：

```csharp
public UnityWorld World { get; } = new UnityWorld();
```

因此，UnityRuntime.Current.World 的含义是：先取得当前兼容运行时实例，再通过它的 World 属性取得这套对象管理实例。

运行时建立后，UnityRuntime.Step 在每帧调用这个 World 的 Update 和 LateUpdate。创建对象、查询组件、改变活动状态等代码，也会经由相应接口调用同一个 World。这就把创建方法里建立的对象接到了后续帧的管理流程上。

源码定位：World 属性（`Waylith.UnityCompat.UnityRuntime.cs:42`）、运行时构造（`Waylith.UnityCompat.UnityRuntime.cs:55`）、每帧调用（`Waylith.UnityCompat.UnityRuntime.cs:106`）。

## 三、实际对象与管理记录

先定义这里所说的“管理记录”：它是 UnityWorld 为实际对象另外建立的一个 C# 对象，保存编号、状态、所属关系等信息。记录中的 Instance 指回实际对象；两者是不同实例。

UnityWorld 中几组主要记录和列表如下：

| 源码成员 | 保存什么 | 主要用途 |
| --- | --- | --- |
| _objects | 实际对象 → 相应管理记录的查询表 | 根据传入的对象取得其记录 |
| _rootGameObjects | 没有父对象的根 GameObject 记录 | 管理对象层级的起点，参与场景和销毁处理 |
| _behaviours | Behaviour 分支的组件记录 | 按相应条件与顺序安排约定方法的调用 |
| _pendingActivation | 等待激活处理的 Behaviour 记录 | 处理 Awake、OnEnable 等调用 |
| _pendingStart | 等待 Start 处理的 Behaviour 记录 | 在相应处理位置调用 Start |
| _pendingDestroy | 等待销毁处理的对象记录 | 在相应处理位置执行销毁 |

最后三项在这里统称“待处理列表”，具体类型与处理条件在后面的生命周期部分展开。UnityWorld 还管理资源登记、实例化函数等内容，本篇先建立与对象和组件有关的认识。

_objects 的原始声明为：

```csharp
private readonly ConcurrentDictionary<object, UnityWorld.UnityObjectState> _objects = new ConcurrentDictionary<object, UnityWorld.UnityObjectState>(ReferenceEqualityComparer.Instance);
```

其键是实际对象，值是 UnityObjectState 及其派生记录；ReferenceEqualityComparer.Instance 指定按对象引用身份区分键。记录中又有下面这个原始属性：

```csharp
public object Instance { get; }
```

这个结构同时解释了两件事：代码能够通过实例查到对应记录，而管理记录也能取得实际实例并调用其方法。

源码定位：查询表与主要列表（`Waylith.UnityCompat.UnityWorld.cs:1577`、`Waylith.UnityCompat.UnityWorld.cs:1592`、`Waylith.UnityCompat.UnityWorld.cs:1595`、`Waylith.UnityCompat.UnityWorld.cs:1618`、`Waylith.UnityCompat.UnityWorld.cs:1624`、`Waylith.UnityCompat.UnityWorld.cs:1630`）、Instance 属性（`Waylith.UnityCompat.UnityWorld.cs:1680`）。

## 四、创建方法返回后，对象为什么仍然存在

以已经读过的相机对象为例，创建过程把 GameObject 和组件登记进 UnityWorld。下面画的是登记后的引用关系，箭头表示对象引用，省略了其他字段与引用路径。

![UnityRuntime、UnityWorld、管理记录与实际对象之间的引用](figures/unityworld-object-references.png)

[SVG 矢量图](figures/unityworld-object-references.svg)；[可编辑图源](figures/unityworld-object-references.dot)。

BuildPlayScene 中的 gameObject、component 是局部变量，分别保存 GameObject 和 Camera 的引用。方法返回后，这次调用的局部变量结束使用；图中的 UnityWorld、查询表和记录仍然存在，也仍然持有这些实际对象的引用。

因此，局部变量的名字与使用范围，和被引用对象的存活时间，是两个需要分开理解的问题。改变局部变量名，不会修改对象的 name，也不会改变它在 UnityWorld 中的登记。

这也不是将对象复制进另一份“世界数据”：记录的 Instance 指向原来的实际对象，查询组件取得的仍是那个实例。后续代码可以通过记录或查询再次取得它。

引擎销毁是另一个过程：UnityWorld 处理停用、销毁方法及所属关系，移除相应登记，并通过 ObjectDestroyed 通知兼容对象更新销毁标记。完成这些处理后，C# 内存也不一定立刻释放；垃圾回收器还要根据是否存在存活引用路径决定能否回收。

这一说明针对经 UnityWorld 登记的 GameObject 与组件。其他资源类型还涉及 AssetRegistry 等管理方式，读 UnityEngine.Object 和资源分支时分别说明。

源码定位：登记对象与 Transform（`Waylith.UnityCompat.UnityWorld.cs:149`）、登记组件（`Waylith.UnityCompat.UnityWorld.cs:911`）、组件与 GameObject 的销毁处理（`Waylith.UnityCompat.UnityWorld.cs:1112`、`Waylith.UnityCompat.UnityWorld.cs:1144`）、销毁标记处理的连接（`Waylith.UnityCompat.UnityRuntime.cs:55`）。

## 五、怎样让这些对象参与后续运行

管理记录让 UnityWorld 能找到对象，但“被登记”还不足以说明对象每帧会做什么。还要看组件的类型、状态，以及相应调用入口。

| 阶段 | UnityWorld 在本轮讨论中涉及的工作 |
| --- | --- |
| 建立对象 | 登记 GameObject、默认 Transform，以及后续附加的组件 |
| 查询和修改 | 根据实际对象查记录，取得组件、调整所属关系或活动状态 |
| 每帧 Update | 处理等待销毁、激活和 Start 的记录，再进入相应更新调用 |
| 每帧 LateUpdate | 安排相应后续更新，处理等待销毁的记录，并调用该阶段登记的函数 |
| 销毁或场景卸载 | 处理对象、组件及子对象的关系，移除登记并发出销毁通知 |

例如，Behaviour 分支通过相应列表和约定方法查找获得调用机会；网格绘制等组件还会接入专门的驱动。因此，后面每读一个组件类型，都要继续问“谁在什么条件下调用它”。

这里先保留运行顺序的轮廓。Update、LateUpdate 的已有流程分析见 [UnityRuntime.Step 笔记](06-waylith-runtime-step.md)，具体生命周期判断留到相关类型展开。

源码定位：Update 与 LateUpdate（`Waylith.UnityCompat.UnityWorld.cs:708`、`Waylith.UnityCompat.UnityWorld.cs:730`）、组件登记与 Behaviour 分支（`Waylith.UnityCompat.UnityWorld.cs:911`）、活动 Behaviour 的方法调用（`Waylith.UnityCompat.UnityWorld.cs:1178`）。

有了这层管理关系，再读 [UnityEngine.Object](17-unityengine-object.md) 时，名称、编号、销毁等接口中的 World 调用就有了明确去向。之后继续沿类型树逐级说明每层增加了什么。
