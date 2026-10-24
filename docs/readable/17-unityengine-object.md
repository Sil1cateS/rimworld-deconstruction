# UnityEngine.Object：对象树的共同起点（讨论稿）

状态：类型树的第一层，2026-10-23。依据工作区 RimWorld 1.7.4982 rev1280 的代码整理，作为 [对象与组件讨论](16-gameobject-component-model.md) 中类型树的起点。

前置阅读：[UnityWorld：先认识对象的管理者](19-unityworld-overview.md)，先说明对象、管理记录和所持引用之间的关系。

下一节点：[GameObject：把组件组织到同一个对象上](18-gameobject.md)。

## 一、父节点与本层职责

UnityEngine.Object 的父类是 System.Object，也就是 C# 中 object 所对应的类型。System.Object 提供 GetType、Equals、GetHashCode、ToString 等基础接口；UnityEngine.Object 在这一基础上，增加兼容层所需的名称、实例编号、销毁状态与一组对象操作入口。

后面的 GameObject、Component，以及 Material、Mesh、Texture 等资源类型，都从这个节点继续派生。因而这一层首先解释它们共享的能力，再到子节点说明各自增加了什么。

| 相对于 System.Object 增加的内容 | 相关成员 | 主要用途 |
| --- | --- | --- |
| 名称 | name、_fallbackName、OnNameChanged | 取得与修改对象名，并为派生类提供名称变化的处理位置 |
| 实例编号 | GetInstanceID、fallbackInstanceId、nextFallbackInstanceId | 取得当前运行中的对象编号 |
| 销毁标记 | _destroyed、MarkDestroyed | 保存对象已经完成销毁处理的状态 |
| 自定义比较与有效性判断 | ==、!=、隐式 bool 转换 | 让条件判断能考虑销毁标记 |
| 对象操作工具 | Destroy、DestroyImmediate、Instantiate、FindObjectsOfType、FindObjectsByType、DontDestroyOnLoad | 提供共同调用入口，具体工作继续交给相应管理代码 |
| 构造时的资源登记 | Object 构造函数 | 为 GameObject、Component 分支之外的对象登记资源弱引用 |
| 兼容接口与常量 | hideFlags、kInstanceID_None、objectIsNullMessage、cloneDestroyedMessage | 保留相关接口和常量；是否有实际行为需继续查看实现 |

本层还没有 gameObject、transform、组件列表、场景活动状态或 Update。它们由后续分支或管理代码提供。

源码定位：类型声明（`UnityEngine.Object.cs:9`）、名称（`UnityEngine.Object.cs:145`）、实例编号（`UnityEngine.Object.cs:165`）、比较与有效性判断（`UnityEngine.Object.cs:253`）、其余字段与常量（`UnityEngine.Object.cs:288`）。

## 二、本层自己保存的数据

先看与名称、编号和销毁直接相关的字段。以下保留原有声明与名称，省略它们之间的反编译标注：

```csharp
private static int nextFallbackInstanceId;
private string _fallbackName = string.Empty;
private bool _destroyed;
private readonly int fallbackInstanceId = Interlocked.Decrement(ref Object.nextFallbackInstanceId);
```

_fallbackName 是对象自身保存的名称，_destroyed 是本层的销毁标记。每个实例还会取得一个 fallbackInstanceId；初始化时通过 Interlocked.Decrement 从本类的静态计数器取得递减编号。

这和 UnityWorld 中的管理记录是两处数据。对象已经登记到 UnityWorld 时，name、GetInstanceID 会优先使用相应记录；没有可用记录时，再使用对象自身的后备值。

### 2.1 name：对象名怎样读写

读取 name 时，代码先尝试从 UnityWorld 取得名称；没有取得时，使用 _fallbackName。

写入时，先把新名称保存到 _fallbackName，再尝试更新 UnityWorld 中的记录，最后调用 OnNameChanged。这个 protected virtual 方法在本类中的主体为空，派生类可以覆写它，处理名称变化带来的后续工作。

因此，名称既可以供调用方读取，也预留了让派生类响应修改的位置。它没有在这里承担创建组件、启用对象或执行逐帧更新的职责。

源码定位：名称属性与变化通知（`UnityEngine.Object.cs:145`、`UnityEngine.Object.cs:283`）、UnityWorld 中的名称读写（`Waylith.UnityCompat.UnityWorld.cs:400`）。

### 2.2 GetInstanceID：优先使用哪一个编号

方法主体如下，保留源码命名：

```csharp
public int GetInstanceID()
{
    if (UnityRuntime.Current == null)
    {
        return this.fallbackInstanceId;
    }
    int instanceId = UnityRuntime.Current.World.GetInstanceId(this);
    if (instanceId != 0)
    {
        return instanceId;
    }
    return this.fallbackInstanceId;
}
```

有兼容运行时且能取得登记编号时，返回 UnityWorld 的编号；没有运行时或没有对应记录时，返回本实例的后备编号。这里的编号用于运行中的对象识别，不是对象名称，也不是 C# 引用的内存地址。

源码定位：GetInstanceID（`UnityEngine.Object.cs:165`）、后备编号字段（`UnityEngine.Object.cs:297`）、UnityWorld 中的编号查询（`Waylith.UnityCompat.UnityWorld.cs:421`）。

## 三、构造函数先做什么

UnityEngine.Object 的构造函数很短：

```csharp
public Object()
{
    if (!(this is Component) && !(this is GameObject))
    {
        AssetRegistry.Register(this);
    }
}
```

这里按实例所属的类型分支判断：GameObject、Component 及其派生实例，走后面的对象与组件登记过程；其他 Object 实例则在这里加入 AssetRegistry。

AssetRegistry 保存的是弱引用。它可以记录仍能取得的资源实例，后续收集时也会检查对象是否仍有效；这份登记本身不会用强引用一直保住对象。

因此，本类构造函数还没有把对象登记成场景中的 GameObject 或组件，也没有启动 Start、Update 等调用。沿树继续阅读时，还要查看子类构造、AddComponent 和 UnityWorld 分别补上哪些步骤。

源码定位：Object 构造函数（`UnityEngine.Object.cs:22`）、资源弱引用登记与收集（`UnityStubs.Internal.AssetRegistry.cs:13`）。

## 四、销毁状态与 C# 引用

### 4.1 Destroy 把请求交给谁

Destroy 与 DestroyImmediate 是本层提供的静态工具方法。它们接收一个 Object，再根据运行时和登记情况选择处理路径。

| 目标情况 | 当前实现的处理 |
| --- | --- |
| 目标已经被相应空值判断判为无效 | 直接返回 |
| 没有兼容运行时，或目标没有 UnityWorld 登记编号 | 若目标实现 IDisposable，先调用 Dispose，再设置对象自身的 _destroyed |
| 目标具有 UnityWorld 登记编号 | 转交 UnityWorld.DestroyObject；普通 Destroy 传入 false，DestroyImmediate 传入 true |

下游仍会检查具体目标能否销毁。对于允许销毁的普通场景对象，Destroy 会先登记请求，由相应处理位置完成销毁；DestroyImmediate 则请求立即处理。Transform、资源用途对象等分支的限制，后面结合具体类型继续阅读。

UnityWorld 完成对象销毁时，会移除相关记录并调用 ObjectDestroyed 中登记的函数。UnityRuntime 在初始化时把 Object.MarkDestroyed 接到这个位置，于是实际实例的 _destroyed 标记也被设置。

这个流程管理的是对象在兼容层中的状态与清理。C# 引用变量仍可能指向该实例，托管内存何时回收则由 GC 另外处理。

源码定位：销毁入口（`UnityEngine.Object.cs:47`、`UnityEngine.Object.cs:77`）、销毁标记（`UnityEngine.Object.cs:33`）、连接销毁通知（`Waylith.UnityCompat.UnityRuntime.cs:59`）、下游目标检查（`Waylith.UnityCompat.UnityWorld.cs:666`）、完成销毁与通知（`Waylith.UnityCompat.UnityWorld.cs:1112`）。

### 4.2 为什么已经销毁，却仍可能持有引用

本层重载了 ==、!=，并提供隐式 bool 转换。它们使 UnityEngine.Object 的有效性判断包含销毁状态。

以一个**已经设置销毁标记、但 C# 引用仍然非空**的实例为例，表中变量的静态类型为 UnityEngine.Object：

| 判断方式 | 此例中的结果 | 检查的内容 |
| --- | --- | --- |
| obj == null | true | 调用本层重载，将已销毁实例视为无效 |
| ReferenceEquals(obj, null) | false | C# 引用仍指向该实例 |
| obj is null | false | 引用本身并非 null |
| if (obj) | 不进入分支 | 隐式 bool 转换同时检查引用与销毁标记 |

表中的 obj 是讲解用变量名，不是某个源码调用点的摘录。普通 Destroy 仅仅登记请求时，不保证标记已经设置；应当区分请求发出与实际销毁完成。

这类判断还与表达式的静态类型有关。先转换成 System.Object 再做 == 比较，不会选择 UnityEngine.Object 的这组重载。本类也没有覆写 Equals、GetHashCode，不能把 == 的特殊行为直接套用到所有比较方式上。

源码阅读说明：本地 C# 反编译文本将运算符内部的一些直接引用比较也显示成了 ==。本节已回查 UnityStubs.dll 中 op_Equality、op_Inequality、op_Implicit 的 IL：直接引用比较使用分支指令，随后按条件读取 _destroyed；不能把反编译显示的同名运算符理解为递归调用。这里用行为表解释，不直接照抄那段有歧义的文本。

源码定位：比较运算符与隐式转换（`UnityEngine.Object.cs:253`、`UnityEngine.Object.cs:267`）；对应 op_Equality 的方法标记为 `0x06000ED6`。

## 五、共同工具入口，以及实现边界

这些静态方法由 Object 提供，但具体效果依赖它们继续调用的管理代码。它们不会让所有派生对象自动取得同一种运行方式。

| 入口 | 当前实现继续做什么 |
| --- | --- |
| Instantiate | 交给 UnityWorld 的实例化入口；带父对象、位置和旋转的重载还会尝试取得结果的 Transform 并应用相应设置 |
| FindObjectsOfType / FindObjectsByType | 将请求类型与活动筛选条件交给 UnityWorld；实际查找范围和顺序需要按该实现阅读 |
| DontDestroyOnLoad | 交给 UnityWorld，取得相应 GameObject，并递归修改该层级的场景归属 |
| Destroy / DestroyImmediate | 按上一节的分支处理，具体生命周期方法由下游继续调用 |

这里先记录两个已经确认的边界：

- **Instantiate 依赖登记的创建函数。** UnityWorld 会查找原对象对应的创建函数，找到后调用；没有找到时，当前实现直接返回原对象。因此不能仅凭方法名就认定任意对象都能被完整复制。资源模板怎样登记创建函数，后续研究实例化时展开。
- **hideFlags 目前只有占位设置接口。** setter 调用 StubWarner.LogStub，没有在本类中保存相应标志或实现完整效果。

FindObjects 的具体类型范围、活动筛选与排序，以及 DontDestroyOnLoad 在父子层级和场景卸载中的实际效果，留到对应分支细读。本层常量中的错误消息文本，也不能代替对方法实际分支的检查。

源码定位：实例化入口与变换重载（`UnityEngine.Object.cs:180`）、创建函数的选择（`Waylith.UnityCompat.UnityWorld.cs:213`）、按类型查找（`UnityEngine.Object.cs:12`、`UnityEngine.Object.cs:123`）、跨场景保留入口（`UnityEngine.Object.cs:113`、`Waylith.UnityCompat.UnityWorld.cs:602`）、hideFlags（`UnityEngine.Object.cs:274`）。

## 六、沿子节点继续：各自增加什么

理解根节点后，后续分支可以从“已经继承这些共同能力”开始，不必反复解释名称和销毁入口。

| 子节点 | 相对于 UnityEngine.Object 首先增加的内容 |
| --- | --- |
| GameObject | 组件附加与查询、默认 Transform、场景和活动状态接口、层编号等 |
| Component | 所属 GameObject、所属 Transform，以及组件之间的查询接口 |
| Mesh、Material、Texture 等资源分支 | 各自的网格、材质、纹理数据及相应功能；按需连接资源与渲染模块 |
| ScriptableObject | 另一种资源对象派生入口，具体创建接口在资源分支研究 |

到这一层，还没有“每个对象每帧执行 Update”的统一规则。后面进入 Behaviour 分支，并结合 UnityWorld 的登记、约定方法查找和状态检查，才继续解释哪些实际实例会取得这些调用。

下一节点先读 [GameObject](18-gameobject.md)，明确它新增的对象组成与管理关系；再进入同级的 [Component 分支](20-component.md)。
