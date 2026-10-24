# Component：从组件找到所属对象与其他组件（讨论稿）

状态：UnityEngine.Object 的组件分支，2026-10-24。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层与游戏代码整理。前置阅读：[UnityWorld 概览](19-unityworld-overview.md)、[UnityEngine.Object](17-unityengine-object.md)、[GameObject](18-gameobject.md)。完整类型树见 [对象与组件模式](16-gameobject-component-model.md)。

## 一、相对于父节点增加了什么

Component 直接继承 UnityEngine.Object，继续使用父类提供的名称、编号、销毁与有效性判断等接口。本层主要增加两组能力：取得组件所属的对象，以及查询该对象上的其他组件。

| 本层增加的接口 | 用途 |
| --- | --- |
| gameObject | 取得该组件所属的 GameObject |
| transform | 取得所属对象的 Transform |
| GetComponent、GetComponents | 查询同一对象上的一个或全部匹配组件 |
| TryGetComponent | 通过返回值说明是否找到，并通过 out 参数取得组件 |
| GetComponentInChildren、GetComponentsInChildren | 查询起始对象及其子对象上的组件 |
| 接受 List 参数的 GetComponents 重载 | 清空调用者提供的列表，再将查询结果填入 |

当前 Component 类没有新增字段，也没有声明 enabled、Update 等成员。所属关系保存在 UnityWorld 的管理记录中；启用状态、空间变换和具体功能由后面的子类及其管理路径逐层增加。

因此，这一层先解释“一个组件怎样找到它所处的对象及相关组件”。具体组件在每帧做什么，仍需继续查看其类型和调用入口。

源码定位：类型声明（`UnityEngine.Component.cs:8`）、所属对象与 Transform（`UnityEngine.Component.cs:12`、`UnityEngine.Component.cs:22`）、查询接口（`UnityEngine.Component.cs:31`）、列表重载（`UnityEngine.Component.cs:53`、`UnityEngine.Component.cs:67`）。

## 二、gameObject 属性：找到我属于哪个对象

先看原始属性，代码保留源码命名与主体，省略反编译标注：

```csharp
public GameObject gameObject
{
    get
    {
        return (GameObject)UnityRuntime.Current.World.GetGameObject(this);
    }
}
```

这里的 this 是当前组件实例。属性把它交给 World.GetGameObject，后者的原始方法如下：

```csharp
public object GetGameObject(object component)
{
    return this.GetComponentState(component).GameObject.Instance;
}
```

沿这条表达式逐步读：

1. GetComponentState 通过 _objects 查到当前组件的管理记录。
2. 记录中的 GameObject 指向所属对象的管理记录。
3. 该记录的 Instance 指回实际 GameObject 实例，最后返回给调用者。

这就是前面所说的“通过管理关系找到所属对象”。Component 的 getter 每次沿记录查询，本层没有自己保存一个 gameObject 字段。

还要区分同一个单词在不同代码位置的含义：BuildPlayScene 中的 gameObject 是局部变量；这里的 gameObject 是 Component 声明的属性。派生组件中的 this.gameObject 表示读取当前实例继承的这个属性，名称相同并不让两者成为同一个变量。

这些访问以组件已经登记为前提。普通添加流程由 GameObject.AddComponent 和 UnityWorld 建立所属关系。单独 new Component() 只会建立 C# 实例；若随后查询它的 gameObject，UnityWorld 找不到相应组件记录，会抛出异常。部分方法会先判断运行时是否存在，也不能由此推断所有接口在任何状态下都能安全调用。

源码定位：属性（`UnityEngine.Component.cs:12`）、取得所属对象（`Waylith.UnityCompat.UnityWorld.cs:366`）、查组件记录及失败处理（`Waylith.UnityCompat.UnityWorld.cs:1376`）、组件创建与登记（`Waylith.UnityCompat.UnityWorld.cs:171`、`Waylith.UnityCompat.UnityWorld.cs:911`）。

## 三、transform 属性：取得所属对象的 Transform

原始属性如下：

```csharp
public Transform transform
{
    get
    {
        return (Transform)UnityRuntime.Current.World.GetTransform(this);
    }
}
```

UnityWorld.GetTransform 识别传入实例的管理记录：传入 GameObject 时取其 Transform.Instance；传入组件时，取该组件所属 GameObject 的 Transform.Instance。

因此，同一 GameObject 上的 Camera、AudioListener、CameraDriver，通过各自的 transform 属性取得的是同一个 Transform 实例。它们可以沿同一套位置、旋转和父子关系协作；具体如何使用这些空间信息，由各自的功能决定。

同样，组件实例与所属 GameObject 仍各自拥有管理记录和实例编号。共用一个 Transform 接口所指向的实例，并不会将这些组件合并为同一个 C# 对象。

源码定位：transform 属性（`UnityEngine.Component.cs:22`）、按对象或组件取得 Transform（`Waylith.UnityCompat.UnityWorld.cs:372`）、各类记录（`Waylith.UnityCompat.UnityWorld.cs:1694`、`Waylith.UnityCompat.UnityWorld.cs:1740`）。

## 四、GetComponent：从所属对象上取得已有组件

Component 的泛型入口如下，T0 是这份反编译代码中的原始类型参数名：

```csharp
public T0 GetComponent<T0>()
{
    if (UnityRuntime.Current == null)
    {
        return default(T0);
    }
    return (T0)((object)UnityRuntime.Current.World.GetComponent(this.gameObject, typeof(T0)));
}
```

与 GameObject.GetComponent 对照，本层先通过 this.gameObject 取得所属对象，然后把该对象和目标类型交给 World.GetComponent。后者的原始方法为：

```csharp
public object GetComponent(object gameObject, Type componentType)
{
    foreach (UnityWorld.UnityComponentState unityComponentState in this.GetGameObjectState(gameObject).Components)
    {
        if (!unityComponentState.Destroyed && componentType.IsInstanceOfType(unityComponentState.Instance))
        {
            return unityComponentState.Instance;
        }
    }
    return null;
}
```

循环依次检查所属对象上的组件记录，跳过已销毁的记录，再判断实际实例是否符合请求类型，返回第一个匹配的 Instance。使用基类作为请求类型，也可以匹配其派生实例；查询本组件所属的类型时，当前组件自身也可能成为结果。

这段代码没有检查 enabled 或对象是否活动，所以普通 GetComponent 查询可以取得已停用但尚未销毁的组件。对于 Camera 等组件引用类型，未找到时返回 null；查询过程不会添加缺少的组件。

GetComponents 收集全部匹配项并返回数组。TryGetComponent 则复用查询结果，返回是否取得了目标类型的实例，并填写 out 参数。

接受 List 参数的重载还需留意：它们先检查列表不为空，然后 Clear，再将查询结果 AddRange 进去。因此，调用后列表原有内容会被替换；当前实现中，这种写法内部仍取得了结果数组，不能仅凭 List 参数就认为查询没有临时数组开销。

InChildren 系列沿所属对象的 Transform 子对象关系继续查询，范围包含起始对象。includeInactive 对单个与多个查询的具体筛选位置，在 [GameObject 的查询说明](18-gameobject.md) 中已有记录，等进入 Transform 时再结合层级展开。

源码定位：Component 查询入口（`UnityEngine.Component.cs:31`）、多个结果与列表重载（`UnityEngine.Component.cs:47`、`UnityEngine.Component.cs:53`、`UnityEngine.Component.cs:67`）、子对象与 TryGetComponent 入口（`UnityEngine.Component.cs:75`、`UnityEngine.Component.cs:103`）、World 的单个与多个查询（`Waylith.UnityCompat.UnityWorld.cs:294`、`Waylith.UnityCompat.UnityWorld.cs:307`）、尝试查询（`Waylith.UnityCompat.UnityWorld.cs:392`）。

## 五、相机案例：CameraDriver 怎样找到 Camera

回到 Bootstrap 已经建立的相机对象，其组成中包括默认 Transform、Camera、AudioListener，以及随后添加的 CameraDriver 等组件。

CameraDriver 的 MyCamera 属性如下，保留原始命名：

```csharp
public Camera MyCamera
{
    get
    {
        if (this.cachedCamera == null)
        {
            this.cachedCamera = base.GetComponent<Camera>();
        }
        return this.cachedCamera;
    }
}
```

第一次需要相机时，它通过继承来的 GetComponent<Camera> 查询同一对象上的相机，再保存到 cachedCamera 字段。之后只要该字段的有效性判断通过，就可以直接返回这个引用。

这里的 base 表示使用从基类继承的方法；这次调用中的当前实例仍然是 CameraDriver。它不表示沿 Transform.parent 去找父 GameObject，查询范围仍是 CameraDriver 自己所属的对象。

在 ApplyPositionToGameObject 中，CameraDriver 随后设置 MyCamera.orthographicSize 和 MyCamera.transform.position。这样就把各层接口接在一起：脚本组件通过 Component 的查询找到 Camera，通过 transform 取得所属对象的空间组件，再写入观察参数和位置，形成玩家最终看到的视野状态。移动、缩放的数值如何计算，留到相机与空间部分继续研究。

源码定位：场景中建立相机组合（`RimWorldWaylith.Bootstrap.cs:785`）、MyCamera（`Verse.CameraDriver.cs:29`）、写入相机参数与位置（`Verse.CameraDriver.cs:418`）。

## 六、从这个节点继续分支

现在再看 Component 的直接子节点，就能把共同接口与各自功能分开：

| 子节点 | 相对于 Component 首先增加的内容 |
| --- | --- |
| [Transform](21-transform.md) | 空间变换、父子关系及其查询和修改接口 |
| [MeshFilter](22-mesh-renderer-components.md) | 网格引用及其访问接口 |
| [Renderer](22-mesh-renderer-components.md) | 材质和绘制状态接口；其中 enabled 由本类自己声明 |
| [Behaviour](23-behaviour.md) | enabled、isActiveAndEnabled 两个属性，连接对应的状态与生命周期管理 |

这些类型都能继续使用 gameObject、transform 和组件查询接口，但具体运行路径还要逐类追踪。尤其是 enabled、Update 等能力，不能仅凭“是一个 Component”就全部归给这一层。

源码定位：直接子节点（`UnityEngine.Transform.cs:8`、`UnityEngine.MeshFilter.cs:6`、`UnityEngine.Renderer.cs:9`、`UnityEngine.Behaviour.cs:7`）。

当前进度：Component 共同接口及其与 UnityWorld 的连接已完成第一轮讨论。子节点阅读已有 [Transform](21-transform.md)、[MeshFilter、Renderer、MeshRenderer](22-mesh-renderer-components.md) 和 [Behaviour](23-behaviour.md)，分别追踪空间关系、网格组件协作与启停及生命周期管理。
