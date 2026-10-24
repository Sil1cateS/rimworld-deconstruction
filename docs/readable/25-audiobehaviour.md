# AudioBehaviour：音频组件的中间类型（讨论稿）

状态：Behaviour 的 AudioBehaviour 子节点，2026-10-24。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层代码整理。上接 [Behaviour](23-behaviour.md)，同级的相机分支见 [Camera](24-camera.md)，完整类型树见 [对象与组件模式](16-gameobject-component-model.md)。

## 一、本层没有新增成员

AudioBehaviour 的声明很短。去掉文件开头的 using 和反编译注释后，完整内容如下：

```csharp
namespace UnityEngine
{
    public class AudioBehaviour : Behaviour
    {
    }
}
```

这里没有显式声明字段、属性或方法，也没有覆写父类的方法。因此，沿着类型树从 Behaviour 走到 AudioBehaviour 时，并没有新增加一套声音播放功能。

源码定位：完整类声明（`UnityEngine.AudioBehaviour.cs:6`）。

## 二、空类仍然建立了一个共同类型

这一分支的继承关系是：

```text
UnityEngine.Object
└─ Component
   └─ Behaviour
      └─ AudioBehaviour
         ├─ AudioSource
         └─ AudioListener
```

AudioSource 和 AudioListener 都可以作为 AudioBehaviour 类型使用，也都继承了更上层已经提供的能力：

| 能力来自哪一层 | 音频组件已经能够使用什么 |
| --- | --- |
| [UnityEngine.Object](17-unityengine-object.md) | name、GetInstanceID，以及共同的销毁和有效性判断接口 |
| [Component](20-component.md) | gameObject、transform，以及查找同一对象上其他组件的接口 |
| [Behaviour](23-behaviour.md) | enabled、isActiveAndEnabled，连接组件启停与对象活动状态 |
| AudioBehaviour | 没有新增成员；为两个音频子类保留共同的类型位置 |

因此，AudioBehaviour 类型的变量可以引用一个 AudioSource 实例，也可以引用一个 AudioListener 实例。通过这个变量能够直接访问哪些成员，仍由 AudioBehaviour 及其父类提供的接口决定；例如可以使用 enabled，但不能直接调用只有 AudioSource 才声明的 Play。

这也说明了空类的实际作用：兼容层保留了 UnityEngine.AudioBehaviour 这个类型及其继承关系，其他代码仍然可以用它声明变量、参数或进行类型判断。它没有在本层实现统一的音频操作。

源码定位：两个直接子类的声明（`UnityEngine.AudioSource.cs:13`、`UnityEngine.AudioListener.cs:9`）。

## 三、它怎样接入 UnityWorld

UnityWorld.CreateComponentState 判断组件是否属于 Behaviour 分支时，检查的是组件实际类型能否作为 UnityEngine.Behaviour 使用。AudioSource 和 AudioListener 通过继承链满足这个条件，因此会建立 UnityBehaviourState 管理记录。随后 RegisterComponent 将记录加入 Behaviour 的管理顺序，并刷新活动状态。

这条路径没有为 AudioBehaviour 设置音频专用的管理记录类型，AudioBehaviour 自己也没有声明 Update、OnEnable 或 OnDisable。UnityWorld 仍根据组件的实际类型及其父类查找约定方法，再按已有的启停和每帧流程调用找到的方法。

前面读过的 AudioListener.OnEnable、AudioListener.OnDisable 就是子类自己声明的方法；它们将当前监听组件加入或移出列表。AudioSource 则自己声明了 Update，在已有播放对象且使用空间声音时更新声源的空间状态。这些行为分别来自具体子类。

源码定位：建立管理记录与登记组件（`Waylith.UnityCompat.UnityWorld.cs:877`、`Waylith.UnityCompat.UnityWorld.cs:911`）、查找约定方法（`Waylith.UnityCompat.UnityWorld.cs:1468`、`Waylith.UnityCompat.UnityWorld.cs:1482`）、子类的启停与更新方法（`UnityEngine.AudioListener.cs:50`、`UnityEngine.AudioListener.cs:59`、`UnityEngine.AudioSource.cs:630`）。

## 四、两个子节点分别增加什么

从这里继续向下，声音的具体功能才开始出现：

| 子节点 | 首先增加的职责 | 后续要接回的运行过程 |
| --- | --- | --- |
| [AudioSource](26-audiosource.md) | 引用音频片段，提供 Play、Pause、Stop 等播放入口，以及音量、循环、空间声音等设置 | 谁创建声源、谁要求播放、参数怎样传给音频后端，以及空间状态怎样持续更新 |
| [AudioListener](27-audiolistener.md) | 管理活动监听器，提供总音量接口，并向后端传递选中监听器的位置与朝向 | 谁创建监听器、当前使用哪一个，以及何时更新后端的监听状态 |

从玩家能听到的结果来看，声源侧提供播放内容和声源参数，监听器侧提供监听位置、朝向等信息。空间声音怎样使用二者计算最终听感，还要继续阅读具体子类及音频后端，不能从 AudioBehaviour 的名字推导出来。

另外，继承的 enabled 与 AudioSource 自己的 Play、Pause、Stop 是不同的接口。前者连接 Behaviour 的活动状态管理，后几者直接控制播放过程；修改 enabled 最终怎样影响已有声音，需要结合子类实现和调用路径判断。

源码定位：声源播放与控制入口（`UnityEngine.AudioSource.cs:218`、`UnityEngine.AudioSource.cs:229`、`UnityEngine.AudioSource.cs:247`、`UnityEngine.AudioSource.cs:595`）、监听器总音量、选择与后端更新（`UnityEngine.AudioListener.cs:14`、`UnityEngine.AudioListener.cs:36`、`UnityEngine.AudioListener.cs:65`）。

当前进度：AudioBehaviour 本层没有新增成员，其共同类型作用与 Behaviour 管理连接已说明。继续阅读 [AudioSource](26-audiosource.md) 与 [AudioListener](27-audiolistener.md)，分别展开播放状态、空间更新、监听选择和后端调用顺序。
