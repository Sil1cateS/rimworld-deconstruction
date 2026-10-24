# GameObject：把组件组织到同一个对象上（讨论稿）

状态：UnityEngine.Object 的第一个子节点，2026-10-23。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层与游戏代码整理。上接 [UnityEngine.Object](17-unityengine-object.md)，类型树与阅读安排见 [对象与组件模式](16-gameobject-component-model.md)。

管理记录与对象引用的前置说明见 [UnityWorld 概览](19-unityworld-overview.md)。

## 一、相对于父节点增加了什么

UnityEngine.Object 已经提供名称、实例编号、销毁与有效性判断等共同能力。GameObject 在这一基础上，增加了将多个组件组织到同一个对象上的接口，以及这个对象在场景、父子层级中的状态。

| 本层增加的内容 | 主要接口 | 要解决的问题 |
| --- | --- | --- |
| 默认的空间组件 | transform | 取得对象的 Transform，通过它访问位置、旋转、缩放与父子关系 |
| 添加组件 | AddComponent、带 components 参数的构造函数 | 为同一个对象组合所需功能 |
| 查询组件 | GetComponent、GetComponents、TryGetComponent，以及 InChildren 接口 | 取得已经附加的组件，让不同功能互相配合 |
| 对象活动状态 | activeSelf、activeInHierarchy、SetActive | 记录自身的活动开关，并考虑父对象链的影响 |
| 所属场景 | scene | 查询对象归属的兼容层场景 |
| 层编号 | layer | 保存一个整数编号，具体使用方式在相机与绘制模块继续追踪 |
| 对象创建和查找工具 | CreatePrimitive、CreateAssetToken、Find | 建立特定用途的对象，或按名称查询已有对象 |

名称 name 仍来自父类。位置等空间信息通过 Transform 访问，组件中的具体功能则由相应组件实现。GameObject 自己没有声明 Update，也没有把各组件的功能合并成一段自己的更新代码。

源码定位：类型与 layer（`UnityEngine.GameObject.cs:12`）、添加组件（`UnityEngine.GameObject.cs:64`）、活动状态与场景、Transform（`UnityEngine.GameObject.cs:157`）、组件查询（`UnityEngine.GameObject.cs:188`）。

## 二、组件列表究竟保存在哪里

GameObject 和附加的组件分别是 C# 对象。当前兼容层又在 UnityWorld 中为它们建立管理记录，记录彼此的所属关系。

![GameObject 实例、组件实例和 UnityWorld 管理记录的关系](figures/gameobject-composition-overview.png)

[SVG 矢量图](figures/gameobject-composition-overview.svg)；[可编辑图源](figures/gameobject-composition-overview.dot)。图中 A、B 为讲解用占位描述，箭头表示组成或记录对应关系。

GameObject 对应的 UnityGameObjectState 记录主要包含：

| 记录成员 | 保存的内容 |
| --- | --- |
| Components | 附加组件的管理记录列表，包含默认 Transform 的记录 |
| Transform | 直接指向该对象的 Transform 管理记录 |
| ActiveSelf | 对象自身的活动开关，初始为 true |
| SceneName | 所属场景的名称 |
| IsAssetToken | 是否为资源用途的对象标记 |
| 继承的 Instance、Name、InstanceId、Destroyed 等 | 实际 C# 对象及其共同管理信息 |

组件记录中的 GameObject 则指回所属对象的记录。因此，既可以从对象查组件，也可以从组件找到所属对象。这些记录类型属于 UnityWorld 内部，和 UnityEngine.Object → GameObject / Component 的公共类型树是两套结构。

读 GameObject.cs 时没有看到 Components 字段，原因就在这里：其查询、添加和启停接口会继续调用 UnityWorld，操作相应的记录。layer 则是 GameObject 自己声明的自动属性。

源码定位：共同记录（`Waylith.UnityCompat.UnityWorld.cs:1658`）、GameObject 记录（`Waylith.UnityCompat.UnityWorld.cs:1694`）、组件的所属记录（`Waylith.UnityCompat.UnityWorld.cs:1740`）。

## 三、创建一个 GameObject 时发生了什么

先看接受名称和组件类型的构造函数。以下代码保留原名和方法主体，仅省略反编译标注：

```csharp
public GameObject(string name, params Type[] components)
    : this(name, new Transform(), false)
{
    foreach (Type type in components)
    {
        this.AddComponent(type);
    }
}
```

冒号后的构造函数调用先执行：创建一个 Transform，将它、名称和 false 交给另一个构造函数。false 对应 isAssetToken，表示这里创建普通场景对象。之后才进入 foreach，逐个添加传入的组件。

被调用的私有构造函数如下：

```csharp
private GameObject(string name, Transform transform, bool isAssetToken)
{
    if (UnityRuntime.Current == null)
    {
        throw new InvalidOperationException("Unity runtime has not been initialized.");
    }
    this.IsAssetToken = isAssetToken;
    UnityRuntime.Current.World.InitializeGameObject(this, transform, name, isAssetToken);
    base.name = name;
}
```

它要求兼容运行时已经建立，然后由 InitializeGameObject 完成登记：

1. 为 GameObject 和 Transform 分别建立管理记录与编号。
2. 让 Transform 的记录指向 GameObject 的记录，并加入其 Components 列表。
3. 将两个实际实例及其记录写入 UnityWorld 的 _objects 查询表。
4. 对普通场景对象，记录当前活动场景名，并加入 _rootGameObjects 根对象列表。

最后 base.name = name 经过父类属性保存名称。到这里，对象与默认 Transform 的关系已经成立，后续添加的组件才有明确的所属对象。

不带参数的构造函数使用默认名称 "GameObject"；仅传名称的构造函数传入空的额外组件类型数组。因而“没有要求添加其他组件”时，默认 Transform 仍然存在。

源码定位：各构造函数（`UnityEngine.GameObject.cs:15`、`UnityEngine.GameObject.cs:30`、`UnityEngine.GameObject.cs:42`、`UnityEngine.GameObject.cs:52`）、建立管理记录（`Waylith.UnityCompat.UnityWorld.cs:149`）。

## 四、AddComponent 怎样把一个组件加入其中

泛型入口的源码很短，但它连接了几项不同的工作：

```csharp
public T0 AddComponent<T0>()
{
    if (UnityRuntime.Current == null)
    {
        return default(T0);
    }
    this.AddRequiredComponents(typeof(T0));
    return (T0)((object)this.Attach(UnityRuntime.Current.World.AddComponent(this, typeof(T0))));
}
```

按执行顺序读最后两行：

1. **补齐要求的组件。** AddRequiredComponents 读取目标类型及继承链上的 RequireComponent 特性，缓存其中要求的类型；同一对象上还没有相应组件时，再调用 AddComponent 添加。它会过滤空类型、抽象类型、重复类型和 Transform，后者已经由构造过程建立。
2. **创建并登记目标组件。** World.AddComponent 通常通过 Activator.CreateInstance 创建实例，建立组件管理记录，再加入 _objects 和所属对象的 Components。请求默认 Transform 时会复用已有实例。
3. **按类型接入调用位置。** Behaviour 分支的记录会加入相应运行列表并更新活动状态。随后，外层 Attach 为部分表现组件接入各自的驱动，例如网格绘制、线条或粒子；普通组件可以直接返回。
4. **返回实际组件实例。** 调用者接着设置或使用的，就是已经登记的那个对象。

这里的 Attach 是 GameObject 的一个私有方法名。通用的所属关系在 World.AddComponent 中已经建立，Attach 负责上述特定类型的额外处理。

还要注意方法的实际调用时机：在 _constructionDepth 为 0 等条件下，World.AddComponent 会处理等待激活的 Behaviour，可能在 AddComponent 返回前调用 Awake、OnEnable；Start 则另行排入等待处理的列表。因此，不能假定添加完所有组件、设好所有属性之后，脚本才开始初始化。具体判断和调用顺序在 Behaviour 分支继续阅读。

源码定位：泛型入口与依赖处理（`UnityEngine.GameObject.cs:64`、`UnityEngine.GameObject.cs:86`）、特定类型的 Attach（`UnityEngine.GameObject.cs:112`）、实例创建（`Waylith.UnityCompat.UnityWorld.cs:171`）、记录分类与登记（`Waylith.UnityCompat.UnityWorld.cs:877`、`Waylith.UnityCompat.UnityWorld.cs:911`）、激活与 Start 登记（`Waylith.UnityCompat.UnityWorld.cs:994`）。

## 五、GetComponent 怎样取得已有组件

与 AddComponent 对照着看：

```csharp
public T0 GetComponent<T0>()
{
    if (UnityRuntime.Current == null)
    {
        return default(T0);
    }
    return (T0)((object)UnityRuntime.Current.World.GetComponent(this, typeof(T0)));
}
```

World.GetComponent 遍历当前对象的 Components 记录，跳过已销毁的组件，通过 Type.IsInstanceOfType 检查实际实例是否符合请求类型，返回第一个匹配实例。查询基类时也可能匹配其派生实例。

普通 GetComponent 不要求组件处于启用状态，也不要求 GameObject 处于活动状态。因此，关闭一个对象之后，持有引用的代码仍能查询它的组件。GetComponents 返回所有匹配实例；TryGetComponent 同时返回是否找到和取得的实例。这些查询都不负责创建缺少的组件。

InChildren 系列还沿 Transform 的子对象关系继续查找，查询范围包含起始对象。当前实现中，单个查询会先检查起始对象，再用 includeInactive 筛选子对象；多个查询则对遍历到的每个对象都按 includeInactive 判断是否收集。后面读 Transform 时再结合具体层级解释这一差别。

源码定位：查询入口（`UnityEngine.GameObject.cs:188`、`UnityEngine.GameObject.cs:242`、`UnityEngine.GameObject.cs:284`）、单个与多个组件查询（`Waylith.UnityCompat.UnityWorld.cs:294`、`Waylith.UnityCompat.UnityWorld.cs:307`）、子对象查询（`Waylith.UnityCompat.UnityWorld.cs:327`、`Waylith.UnityCompat.UnityWorld.cs:341`、`Waylith.UnityCompat.UnityWorld.cs:858`）。

## 六、对象活动状态和场景归属

activeSelf 回答“对象自身的活动开关是什么”；activeInHierarchy 还检查对象是否已销毁，以及沿 Transform.Parent 找到的各级父对象是否活动、是否已销毁。

| 对象自身的 activeSelf | 父对象链 | activeInHierarchy |
| --- | --- | --- |
| true | 全部活动且未销毁，或没有父对象 | true |
| false | 任意情况 | false |
| true | 存在不活动或已销毁的父对象 | false |

上表假定当前对象未销毁。父对象被关闭时，子对象的 activeSelf 可以继续保持 true，但 activeInHierarchy 变成 false；父对象恢复后，再按整条链重新判断。

SetActive 修改自身的 ActiveSelf，并让 UnityWorld 重新检查本对象及子对象上的 Behaviour 活动状态，进而处理启用或停用方法。它不删除组件、不清空引用，也不将子对象各自的 ActiveSelf 一并改写。Behaviour 自己还有 enabled，这一层的活动开关只是后续运行条件的一部分。

scene 则通过 UnityWorld.GetSceneName 取得记录中的场景名，并包装成 Scene。这里的场景归属参与 Entry、Play 等兼容层场景的管理；不要直接把它等同于玩家存档中的一张地图。卸载场景时，UnityWorld 从属于该场景的根对象开始，继续销毁其子对象和附加组件。

源码定位：活动状态入口（`UnityEngine.GameObject.cs:157`、`UnityEngine.GameObject.cs:232`、`UnityEngine.GameObject.cs:274`）、设置与层级判断（`Waylith.UnityCompat.UnityWorld.cs:451`、`Waylith.UnityCompat.UnityWorld.cs:1318`）、更新 Behaviour 活动状态（`Waylith.UnityCompat.UnityWorld.cs:931`）、场景名与卸载（`Waylith.UnityCompat.UnityWorld.cs:635`、`Waylith.UnityCompat.UnityWorld.cs:641`）、递归销毁（`Waylith.UnityCompat.UnityWorld.cs:1144`）。

## 七、回到游戏里的相机对象

Bootstrap.BuildPlayScene 开始建立相机对象的代码如下；这里是方法开头的连续节选，名称保持原样：

```csharp
GameObject gameObject = new GameObject("Camera", new Type[]
{
    typeof(Camera),
    typeof(AudioListener)
});
Camera component = gameObject.GetComponent<Camera>();
```

执行完这几行，可以分别指出四个实际对象：名为 "Camera" 的 GameObject、默认 Transform、Camera 组件和 AudioListener 组件。最后一行取得已经附加的 Camera；component 和 gameObject 的类型、用途都不同。

随后 Bootstrap 设置相机参数与 Transform.rotation，并添加 CameraDriver、ColorCorrectionCurves。它们共同附加在同一个对象上：Transform 提供空间接口，Camera 提供观察参数，AudioListener 参与音频监听，CameraDriver 从游戏层控制相机。CameraDriver 通过 GetComponent<Camera> 取得并缓存同一对象上的相机实例。

由此已经可以解释这种组织方式怎样连接到玩家看到的画面：控制相机的脚本能够找到相机组件，并通过相机参数和对象的 Transform 改变观察状态。移动、缩放的具体计算，以及各组件实际被谁调用，等进入相应子类时继续追踪。

同一个 BuildPlayScene 还会创建名为 "GameRoot" 的对象并添加 Root_Play。它使用同一套组件组织方式，承担的却是游戏入口职责。这也说明 GameObject 可以组织具有不同用途的组件组合。

源码定位：游玩场景中的相机与 GameRoot（`RimWorldWaylith.Bootstrap.cs:785`）、CameraDriver 查询相机（`Verse.CameraDriver.cs:29`）。

本层还有两个创建工具值得留作索引：CreatePrimitive 组合 MeshFilter、MeshRenderer 与基本形状网格；CreateAssetToken 使用 isAssetToken=true 的构造路径，影响场景登记及部分表现组件的处理。具体资源与绘制行为在相应分支展开。

源码定位：基本形状对象（`UnityEngine.GameObject.cs:139`）、资源用途对象（`UnityEngine.GameObject.cs:58`）。

当前进度：GameObject 本层的组成接口、创建、添加、查询、活动状态和场景归属已建立第一轮说明。下一步回到 UnityEngine.Object 的另一个子节点 [Component](20-component.md)，先读组件怎样取得所属对象，再沿 Transform 等子节点继续。
