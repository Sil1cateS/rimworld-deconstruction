# Behaviour：组件的启用状态怎样接入生命周期（讨论稿）

状态：Component 的 Behaviour 分支，2026-10-24。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层与游戏代码整理。前置阅读：[Component](20-component.md)、[UnityWorld 概览](19-unityworld-overview.md)；与 [Renderer 分支](22-mesh-renderer-components.md) 对照阅读，完整类型树见 [对象与组件模式](16-gameobject-component-model.md)。

## 一、本层完整增加了哪些成员

Behaviour 直接继承 Component，继续使用 gameObject、transform 和组件查询接口。本类显式增加的成员只有两个属性，没有新增字段或普通方法：

| 属性 | 本层职责 | 继续调用的 UnityWorld 方法 |
| --- | --- | --- |
| enabled | 读取或设置组件自身的启用开关 | IsBehaviourEnabled、SetBehaviourEnabled |
| isActiveAndEnabled | 读取启用开关与管理记录中的活动标记的组合结果 | IsBehaviourActiveAndEnabled |

先说明这三个 World 方法的分工：IsBehaviourEnabled 返回相应记录的 Enabled；SetBehaviourEnabled 修改该标记并安排启停处理；IsBehaviourActiveAndEnabled 返回记录中的 Enabled && IsActiveInHierarchy。它们通过 GetBehaviourState 根据实际组件查找 UnityBehaviourState 记录。

enabled 的完整原始实现如下，保留命名和方法主体，省略反编译标注：

```csharp
public bool enabled
{
    get
    {
        UnityRuntime unityRuntime = UnityRuntime.Current;
        return unityRuntime == null || unityRuntime.World.IsBehaviourEnabled(this);
    }
    set
    {
        if (UnityRuntime.Current == null)
        {
            return;
        }
        UnityRuntime.Current.World.SetBehaviourEnabled(this, value);
    }
}
```

isActiveAndEnabled 的完整原始实现为：

```csharp
public bool isActiveAndEnabled
{
    get
    {
        UnityRuntime unityRuntime = UnityRuntime.Current;
        return unityRuntime != null && unityRuntime.World.IsBehaviourActiveAndEnabled(this);
    }
}
```

后面的讨论以运行时已经建立、组件已经登记为前提。原始代码还保留了运行时不存在时的分支：enabled 读取返回 true，赋值直接返回；isActiveAndEnabled 读取返回 false。这些分支不能代替正常的对象登记。

源码定位：Behaviour 全部新增属性（`UnityEngine.Behaviour.cs:12`、`UnityEngine.Behaviour.cs:31`）、三个 World 入口（`Waylith.UnityCompat.UnityWorld.cs:469`、`Waylith.UnityCompat.UnityWorld.cs:475`、`Waylith.UnityCompat.UnityWorld.cs:493`）、查找 Behaviour 记录（`Waylith.UnityCompat.UnityWorld.cs:1391`）。

## 二、开关和活动状态保存在什么地方

UnityWorld.CreateComponentState 会识别组件是否属于 Behaviour 继承分支，并为它建立 UnityBehaviourState。RegisterComponent 将这种记录插入 _behaviours 列表，随后重新判断活动条件。

| 管理记录成员 | 含义 |
| --- | --- |
| Enabled | 组件自身的启用开关，默认 true |
| IsActiveInHierarchy | 当前管理流程已写入的 Behaviour 活动标记 |
| HasAwoken | 是否已经经过首次 Awake 阶段的处理 |
| HasStarted | 是否已经经过首次 Start 阶段的处理 |
| GuiDepth | 与 GUI 调用排列有关的数据，进入 UI 部分时再展开 |
| 继承的 GameObject、Instance、Messages 等 | 所属对象、实际组件，以及已找到的约定方法 |

HasAwoken、HasStarted 是管理阶段的标记；实际类型可以没有对应方法，管理代码仍会完成该阶段的记录。

这里还要区分两个含义接近的值：GameObject.activeInHierarchy 根据对象自身及父对象链的活动开关判断；Behaviour 记录中的 IsActiveInHierarchy 则在启停处理过程中更新。isActiveAndEnabled 的 World 实现如下：

```csharp
public bool IsBehaviourActiveAndEnabled(object behaviour)
{
    UnityWorld.UnityBehaviourState behaviourState = this.GetBehaviourState(behaviour);
    return behaviourState.Enabled && behaviourState.IsActiveInHierarchy;
}
```

在对象未销毁、相应启停处理已完成的通常状态下，可以这样理解：

| Behaviour.enabled | GameObject.activeSelf | 父对象链是否全部活动 | isActiveAndEnabled |
| --- | --- | --- | --- |
| true | true | 是，或没有父对象 | true |
| false | true | 是，或没有父对象 | false |
| true | false | 任意 | false |
| true | true | 否 | false |

但 getter 本身没有重新遍历父对象链。等待激活的记录，或正在执行启停方法的中间时刻，需要按管理标记实际写入的顺序判断；不能将这个属性一概替换成 enabled && gameObject.activeInHierarchy。

同名的 Renderer.enabled 由 Renderer 自己声明为自动属性，MeshRenderer 的驱动会读取它；Behaviour.enabled 则进入这里的 World 启停处理。两个类型分别从 Component 派生，各有自己的实现。

源码定位：记录分类与登记（`Waylith.UnityCompat.UnityWorld.cs:877`、`Waylith.UnityCompat.UnityWorld.cs:911`）、Behaviour 状态记录（`Waylith.UnityCompat.UnityWorld.cs:1761`）、GameObject 层级活动判断（`Waylith.UnityCompat.UnityWorld.cs:1318`）、活动组合结果（`Waylith.UnityCompat.UnityWorld.cs:493`）、Renderer 的同名属性（`UnityEngine.Renderer.cs:65`）。

## 三、设置 enabled 为什么可能立即调用组件方法

在进入 setter 调用的方法之前，先认识它使用的两个辅助方法：

| UnityWorld 内部方法 | 职责 |
| --- | --- |
| RefreshBehaviourActivity | 检查启用、层级活动和销毁状态，处理停用或登记等待激活的记录 |
| FlushPendingActivation | 处理等待激活的记录，安排 Awake、OnEnable 等阶段 |

_constructionDepth 是 UnityWorld 在实例化工厂执行期间维护的构造嵌套计数；为 0 时，这里允许立即处理等待激活的记录。它并不表示每一个普通 C# 构造函数是否正在执行。

SetBehaviourEnabled 的原始实现如下：

```csharp
public void SetBehaviourEnabled(object behaviour, bool enabled)
{
    using (this._gate.EnterScope())
    {
        UnityWorld.UnityBehaviourState behaviourState = this.GetBehaviourState(behaviour);
        if (behaviourState.Enabled != enabled)
        {
            behaviourState.Enabled = enabled;
            this.RefreshBehaviourActivity(behaviourState);
            if (this._constructionDepth == 0)
            {
                this.FlushPendingActivation();
            }
        }
    }
}
```

当数值确实改变时，它先写入 Enabled，然后重新判断活动状态，必要时在这次属性赋值返回之前就处理激活。因此，enabled = true 可能连接到当前调用中的 OnEnable，不能统一理解为“下一帧才处理”。若对象层级尚未活动，单独启用组件仍不足以激活它。

设置 enabled = false 会改变这个组件的状态。所属 GameObject 自己的活动开关、同对象上其他 Behaviour 的 Enabled 不会因此被一并改写。组件实例及其登记也继续存在，后续仍可通过组件查询取得。

源码定位：设置开关（`Waylith.UnityCompat.UnityWorld.cs:475`）、实例化期间的构造深度（`Waylith.UnityCompat.UnityWorld.cs:213`）。

## 四、活动条件怎样转成停用与激活处理

下面的 RefreshBehaviourActivity 使用已经读过的 IsGameObjectActiveInHierarchy 检查对象层级。InvokeMessage 是 World 执行已找到的约定方法的入口；目标方法不存在时直接返回，查找与调用过程在后文继续说明。

_pendingActivation 保存等待激活的 Behaviour 记录，配套的 _pendingActivationSet 用于避免同一轮重复加入。

```csharp
private void RefreshBehaviourActivity(UnityWorld.UnityBehaviourState behaviour)
{
    if (!behaviour.Enabled || !this.IsGameObjectActiveInHierarchy(behaviour.GameObject) || behaviour.Destroyed)
    {
        if (behaviour.IsActiveInHierarchy)
        {
            behaviour.IsActiveInHierarchy = false;
            this.InvokeMessage(behaviour, UnityWorld.UnityMessageType.OnDisable);
        }
        return;
    }
    if (this._pendingActivationSet.Add(behaviour))
    {
        this._pendingActivation.Add(behaviour);
    }
}
```

这段判断有两条主要路径：

- 条件不满足：若原来处于活动状态，先将活动标记清为 false，再尝试调用 OnDisable；原来就不活动则直接返回。
- 条件满足：将记录加入等待激活的列表，后续处理时再次检查相关条件。

GameObject.SetActive 和 Transform 换父对象等操作，也会经由层级状态检查接到相应 Behaviour 的处理。因此，同一个组件既会受自身 enabled 影响，也会受所属对象和父对象的活动状态影响。

等待列表的后续处理分为三个相关入口：

| UnityWorld 内部方法 | 如何继续处理 |
| --- | --- |
| FlushPendingActivation | 按当前批次排序；先一轮尝试首次 Awake，再一轮尝试 OnEnable。激活后写入 IsActiveInHierarchy，并为尚未经过 Start 阶段的记录安排等待处理 |
| FlushPendingActivationInline | 在激活过程中又添加 Behaviour 等嵌套情况中，针对单条记录检查并处理相应阶段 |
| FlushPendingStart | 在相应调用位置，尝试为尚未经过 Start 阶段、未销毁且活动的记录调用 Start，并写入 HasStarted |

“先 Awake、后 OnEnable”这里描述的是当前批次的两轮处理，不能扩展成整个场景内所有对象都一次性完成同一阶段。各阶段还会重新检查状态；Awake、OnEnable 等方法中的代码也可能改变对象状态，需按实际执行顺序阅读。

![Behaviour 从活动条件检查，到激活、首次 Start 和每帧调用的管理连接](figures/behaviour-activation-overview.png)

[SVG 矢量图](figures/behaviour-activation-overview.svg)；[可编辑图源](figures/behaviour-activation-overview.dot)。图中是主要管理连接，各处理阶段仍会再次检查状态。

当前实现中，Awake 的尝试调用也处于 Enabled、对象层级活动等条件检查之内。例如，在不活动的对象上添加组件，不能据此假定添加返回前就已经经过 Awake。本文按本地兼容层实现说明这些时序。

首次阶段的标记在普通停用时不会被清除。因此，再次激活通常会重新尝试 OnEnable，而不会仅因开关切换就重新走首次 Awake、Start。

源码定位：活动检查（`Waylith.UnityCompat.UnityWorld.cs:944`）、激活处理的两种入口（`Waylith.UnityCompat.UnityWorld.cs:962`、`Waylith.UnityCompat.UnityWorld.cs:994`）、首次 Start 处理（`Waylith.UnityCompat.UnityWorld.cs:1042`）、GameObject 活动修改（`Waylith.UnityCompat.UnityWorld.cs:451`）、换父对象后的层级检查（`Waylith.UnityCompat.UnityWorld.cs:566`）。

## 五、Awake、OnEnable、Update 等方法是怎样找到的

Behaviour 的类声明并没有新增这些虚方法。UnityWorld 会检查实际组件类型，按约定名称查找它们，再保存可以调用对应实例的函数。

先将相关方法的职责放在一起：

| UnityWorld 内部方法 | 职责 |
| --- | --- |
| GetMessages(Type type) | 按实际类型取得或建立方法缓存，涉及 Awake、OnEnable、Start、Update、LateUpdate、OnDisable、OnApplicationQuit、OnDestroy、OnGUI |
| FindMessage(Type type, string name) | 从实际类型开始向基类查找指定名称的无参数实例方法 |
| CompileMessage(MethodInfo method) | 将找到的方法转换成可以接收实际实例并执行调用的函数 |
| InvokeMessage | 从组件记录的 Messages 中选出对应函数，再传入 Instance 执行；没有对应函数则返回 |

FindMessage 的原始实现如下：

```csharp
private static Func<object, object> FindMessage(Type type, string name)
{
    Type type2 = type;
    while (type2 != null)
    {
        MethodInfo method = type2.GetMethod(name, BindingFlags.DeclaredOnly | BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, Type.EmptyTypes, null);
        if (method != null)
        {
            return UnityWorld.CompileMessage(method);
        }
        type2 = type2.BaseType;
    }
    return null;
}
```

它允许查找 public 和非 public 的实例方法，参数列表要求为空；当前层未找到时，才继续看基类。找到一个对应方法后即返回，因此它不会自动将继承链上所有同名方法逐个调用。

查找结果按类型缓存，后续阶段使用保存的函数，避免每帧从头进行同样的方法查找。InvokeMessage 还会处理异常记录；若方法返回 IEnumerator，则通过登记的 MessageCoroutineStarter 连接协程调度。协程的启动与推进在 MonoBehaviour 分支继续研究。

源码定位：类型方法缓存（`Waylith.UnityCompat.UnityWorld.cs:1468`）、名称查找（`Waylith.UnityCompat.UnityWorld.cs:1482`）、建立执行函数（`Waylith.UnityCompat.UnityWorld.cs:1499`）、执行方法（`Waylith.UnityCompat.UnityWorld.cs:1265`）。

## 六、每帧怎样选择要调用的 Behaviour

World.Update 开始时依次处理等待销毁、等待激活和等待 Start 的记录，然后执行该阶段登记的函数，并安排活动 Behaviour 的 Update。World.LateUpdate 则在相应位置安排 LateUpdate。已有完整帧顺序可对照 [UnityRuntime.Step 笔记](06-waylith-runtime-step.md)。

承担列表遍历的是 InvokeMessagesForActiveBehaviours。它先用 CopyBehaviours 将 _behaviours 复制到临时列表；这个辅助方法负责清空目标列表、准备容量并复制元素。之后按遍历到的记录当时的标记决定是否调用：

```csharp
private void InvokeMessagesForActiveBehaviours(UnityWorld.UnityMessageType messageType)
{
    using (this._gate.EnterScope())
    {
        UnityWorld.CopyBehaviours(this._behaviours, this._behaviourDispatchScratch);
    }
    foreach (UnityWorld.UnityBehaviourState unityBehaviourState in this._behaviourDispatchScratch)
    {
        if (unityBehaviourState.IsActiveInHierarchy && !unityBehaviourState.Destroyed)
        {
            this.InvokeMessage(unityBehaviourState, messageType);
        }
    }
    this._behaviourDispatchScratch.Clear();
}
```

_behaviours 的排列优先考虑登记的类型执行顺序，同值时比较 CreationIndex。当前循环使用临时列表固定本轮遍历对象，再检查活动与销毁标记，最后尝试执行对应方法。

这里的直接筛选条件没有 HasStarted。虽然 World.Update 的开头先处理 Start，若组件在帧内其他位置才建立并激活，仍需结合建立时点与后续列表读取判断调用顺序，不能从上述常规帧顺序推出所有情况下都先 Start、后首次 Update 或 LateUpdate。

这也说明 enabled 所控制的范围：例如停用 CameraDriver，会通过上述状态管理影响 World 对其约定方法的调用；它仍然是可以取得的 C# 实例，其他代码显式调用其普通方法还要按相应调用点分析。

源码定位：帧阶段（`Waylith.UnityCompat.UnityWorld.cs:708`、`Waylith.UnityCompat.UnityWorld.cs:730`）、活动列表遍历（`Waylith.UnityCompat.UnityWorld.cs:1178`）、复制辅助方法（`Waylith.UnityCompat.UnityWorld.cs:1460`）、执行顺序比较（`Waylith.UnityCompat.UnityWorld.cs:1432`）。

## 七、实际案例：启停音频监听组件

AudioListener 沿 AudioListener → AudioBehaviour → Behaviour 继承这两个状态接口。AudioBehaviour 当前类体为空，具体监听功能由 AudioListener 继续增加。

它声明了一个保存活动监听组件的静态列表 ActiveListeners。下面是用于本案例的两个方法节选，名称与主体保持原样：

```csharp
public void OnEnable()
{
    if (!AudioListener.ActiveListeners.Contains(this))
    {
        AudioListener.ActiveListeners.Add(this);
    }
}

public void OnDisable()
{
    AudioListener.ActiveListeners.Remove(this);
}
```

当 World 的启停处理尝试调用这些方法时，实际效果就是将监听组件加入或移出这个列表。AudioListener.Current 从列表末尾选择当前监听器，SyncToBackend 再使用选中的实例更新后端位置与方向。停用组件会影响这条选择路径，不能直接据此推断整个游戏音频都会停止；完整音频行为在对应模块展开。

这里的 OnEnable、OnDisable 是 AudioListener 自己声明的方法。Behaviour 提供状态访问，UnityWorld 根据实际类型找到方法，并在相应状态变化时安排调用。这三部分共同形成具体行为。

源码定位：AudioBehaviour 空类（`UnityEngine.AudioBehaviour.cs:6`）、监听器选择与启停方法（`UnityEngine.AudioListener.cs:36`、`UnityEngine.AudioListener.cs:50`、`UnityEngine.AudioListener.cs:59`）、向后端更新监听状态（`UnityEngine.AudioListener.cs:65`）。

## 八、接下来沿哪些子节点继续

| Behaviour 的直接子节点 | 相对于本层首先增加的内容 |
| --- | --- |
| [Camera](24-camera.md) | 相机参数、坐标转换、阶段函数与显式绘制入口 |
| [AudioBehaviour](25-audiobehaviour.md) | 当前没有新增成员，建立音频组件的中间分支；继续到 [AudioSource](26-audiosource.md)、[AudioListener](27-audiolistener.md) |
| [MonoBehaviour](28-monobehaviour.md) | 协程的启动与停止接口等，供 Root、CameraDriver 等脚本类型继续派生 |

当前进度：Behaviour 本层的全部新增属性、管理状态和相关方法调用连接已建立第一轮说明。本轮所选的 [Camera](24-camera.md)、[AudioBehaviour](25-audiobehaviour.md) 与 [MonoBehaviour](28-monobehaviour.md) 三条分支已有对应讨论，具体游戏逻辑继续随相应脚本展开。
