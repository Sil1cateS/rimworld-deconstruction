# Transform：对象怎样确定位置、朝向和父子关系（讨论稿）

状态：Component 的空间分支，2026-10-24。依据工作区 RimWorld 1.7.4982 rev1280 的兼容层与游戏代码整理。上接 [Component](20-component.md)；管理记录的前置说明见 [UnityWorld 概览](19-unityworld-overview.md)，完整类型树见 [对象与组件模式](16-gameobject-component-model.md)。

## 一、相对于 Component 增加了什么

Component 已经提供所属 GameObject、所属 Transform 以及组件查询接口。Transform 在这一层增加空间变换、父子关系和相应的访问方法，同时实现 IEnumerable，使代码可以通过 foreach 遍历它的直接子 Transform。

| 本层增加的内容 | 主要接口 |
| --- | --- |
| 本地位置、旋转和缩放 | localPosition、localRotation、localScale |
| 世界位置和旋转 | position、rotation |
| 朝向与角度表示 | forward、right、up、eulerAngles、localEulerAngles |
| 本地与世界之间的转换 | localToWorldMatrix、worldToLocalMatrix，以及 TransformPoint 等方法 |
| 父子对象关系 | parent、SetParent、childCount、GetChild、IsChildOf |
| 层级中的查找与排列 | Find、GetSiblingIndex、SetSiblingIndex 等 |
| 变换是否发生变化 | hasChanged |
| 修改空间状态的工具 | Translate、Rotate、RotateAround、LookAt 等 |

这里的“父子”指 Transform 所连接的对象层级；Transform 在类型继承树上的父类始终是 Component。

源码定位：类型声明与接口（`UnityEngine.Transform.cs:8`）、主要空间属性（`UnityEngine.Transform.cs:95`、`UnityEngine.Transform.cs:112`、`UnityEngine.Transform.cs:139`、`UnityEngine.Transform.cs:206`）、遍历器（`UnityEngine.Transform.cs:63`、`UnityEngine.Transform.cs:548`）。

## 二、数据分别保存在哪里

和 Component 相比，Transform 确实新增了自己的字段。以下保留三项本地空间数据的原始声明，只省略反编译标注：

```csharp
private Vector3 _localPosition;
private Vector3 _localScale = new Vector3(1f, 1f, 1f);
private Quaternion _localRotation = Quaternion.identity;
```

初始本地位置是零向量，本地缩放是各轴 1 倍，本地旋转是 Quaternion.identity，也就是不施加额外旋转。

父子关系则保存在 UnityWorld 的 UnityTransformState 记录中：Parent 指向父 Transform 的记录，Children 保存直接子 Transform 的记录列表。它还继承组件记录中的 GameObject，从而知道这个 Transform 属于哪个实际对象。

因此，当前实现的分工是：

| 数据 | 保存位置 |
| --- | --- |
| 本地位置、旋转、缩放 | 实际 Transform 实例的字段 |
| 父子关系 | UnityWorld 中的 UnityTransformState 记录 |
| 世界位置和旋转 | 通过本地数据与父对象链计算 |

读取世界变换时，两处信息会合在一起使用。不能将“兼容层另有管理记录”理解为所有空间数值都保存在 UnityWorld 中。

源码定位：本地字段（`UnityEngine.Transform.cs:530`）、管理记录中的 Children 与 Parent（`Waylith.UnityCompat.UnityWorld.cs:1798`）。

## 三、本地坐标和世界坐标怎样联系起来

### 3.1 先从只包含平移的情况看起

localPosition 表示对象原点在父对象坐标系中的位置；没有父对象时，直接使用它作为世界位置。position 表示对象原点在世界坐标系中的位置。

先用一个仅作讲解的数值例子，假定父对象没有旋转，缩放为各轴 1 倍：

| 数据 | 数值 |
| --- | --- |
| 父对象的世界位置 | (10, 0, 20) |
| 子对象的 localPosition | (2, 0, 3) |
| 子对象的 position | (12, 0, 23) |

父对象再沿世界 x 轴移动 5，子对象的 localPosition 仍可以保持 (2, 0, 3)，但重新读取 position 时会得到 (17, 0, 23)。父对象的旋转与缩放也会作用于子对象的本地位置，所以一般情况需要完整变换，不能只将两个位置相加。

### 3.2 矩阵怎样沿父对象链组合

localToWorldMatrix 属性把这个过程写得很直接：

```csharp
public Matrix4x4 localToWorldMatrix
{
    get
    {
        Matrix4x4 matrix4x = Matrix4x4.TRS(this._localPosition, this._localRotation, this._localScale);
        Transform parentTransform = this.GetParentTransform();
        if (!(parentTransform == null))
        {
            return parentTransform.localToWorldMatrix * matrix4x;
        }
        return matrix4x;
    }
}
```

TRS 将本地平移、旋转和缩放组合成一个矩阵，可以把矩阵暂时理解为“一套将坐标换算到另一套坐标系的规则”。作用于一个本地点时，这套本地规则先施加缩放，再旋转，最后平移；若还有父对象，就继续应用父对象到世界的规则。

这里的 parentTransform.localToWorldMatrix 会继续读取父对象的同名属性，一直沿父链向上，直到没有父对象。当前 getter 按需递归计算，没有在本类中保存一份等待 Update 刷新的世界矩阵缓存。因此，父对象的变换字段改变后，后续查询就会通过这条链计算新结果。

可以将源码的三步与变换范围对应起来：

| 源码中的动作 | 得到的规则 |
| --- | --- |
| Matrix4x4.TRS(this._localPosition, this._localRotation, this._localScale) | 从当前对象的本地空间换算到父对象的本地空间；若没有父对象，这一层直接通向世界空间 |
| parentTransform.localToWorldMatrix | 从父对象的本地空间换算到世界空间，包含更上层父对象的影响 |
| parentTransform.localToWorldMatrix * matrix4x | 将两段规则接起来，从当前对象的本地空间换算到世界空间 |

这里父矩阵写在乘号左侧。在这份实现使用的矩阵与点乘法约定下，组合矩阵作用于点时，右侧矩阵先作用，再由左侧矩阵继续转换。源码中的 matrix4x 是本地到父对象的变换，父矩阵则把结果继续换算到世界。

假设有 A → B → C 三层对象，A 是根对象，B 是 A 的子对象，C 是 B 的子对象。A、B、C 只是本例的对象名称。读取 C 的世界矩阵时，会先逐层读取父对象的属性，再逐层组合并返回结果：

![读取 C 的世界矩阵时，沿父对象链递归读取并返回结果的过程](figures/transform-matrix-chain.png)

[SVG 矢量图](figures/transform-matrix-chain.svg)；[可编辑图源](figures/transform-matrix-chain.dot)。图中的“本地矩阵”“世界矩阵”是解释用名称，对应当前层的 TRS 结果和 localToWorldMatrix 返回值。

这个过程发生在属性的 getter 中。读取属性可以触发实际计算；看到 position 或 localToWorldMatrix 的属性语法时，需要继续查看其 getter，才能知道它的工作和开销。

### 3.3 读取 position 和设置 position 是两个方向

position 的读取从这个矩阵取出平移部分。赋值则沿相反方向换算：

```csharp
public Vector3 position
{
    get
    {
        return this.localToWorldMatrix.GetPosition();
    }
    set
    {
        Transform parentTransform = this.GetParentTransform();
        this._localPosition = ((parentTransform == null) ? value : parentTransform.worldToLocalMatrix.MultiplyPoint3x4(value));
        this.MarkChanged();
    }
}
```

若有父对象，设置 position 会把传入的世界坐标，通过父对象的 worldToLocalMatrix 换算为本地位置，再存入 _localPosition。worldToLocalMatrix 就是对应 localToWorldMatrix 的逆矩阵。上述换算以变换可逆等正常条件为前提；本轮先使用非零缩放的例子。

所以，代码可以直接指定一个世界位置，最终保存的仍是适合当前父对象的本地数值。

### 3.4 加入父对象缩放，再对照一次读写

下面仍是讲解用例子：父对象是根对象，位置为 (10, 0, 20)，没有旋转，本地缩放为 (2, 1, 2)。子对象没有额外旋转，缩放为各轴 1 倍。

| 动作或数据 | 结果 |
| --- | --- |
| 子对象 localPosition 为 (2, 0, 3) | 父对象将偏移换算为 (4, 0, 6)，再加父对象位置，得到世界位置 (14, 0, 26) |
| 将子对象的 position 设置为 (18, 0, 30) | setter 通过父逆矩阵换算，保存新的 _localPosition 为 (4, 0, 5) |
| 再次读取子对象的 position | 根据新本地位置计算，得到刚才指定的 (18, 0, 30) |

这里需要区分是谁的缩放：父对象的缩放会改变子对象相对于父原点的世界偏移；子对象自己的 localScale 作用于自己的本地点，且不会改变自己的本地原点。因而在 localPosition 和父对象链不变时，单独改变子对象自己的 localScale，不会移动它的世界原点。

这也能接回相机代码：CameraDriver 写入 MyCamera.transform.position，是指定相机应处于的世界位置；Transform 再根据当前父关系确定应保存的本地值。谁决定目标位置与怎样将位置存入当前层级，是两个相接的步骤。

源码定位：本地位置（`UnityEngine.Transform.cs:206`）、组合矩阵（`UnityEngine.Transform.cs:95`）、世界位置（`UnityEngine.Transform.cs:112`）、逆矩阵（`UnityEngine.Transform.cs:253`）、TRS 与点变换（`UnityEngine.Matrix4x4.cs:560`、`UnityEngine.Matrix4x4.cs:358`）。

## 四、旋转、朝向与三种转换对象

旋转有相同的本地与世界区别。当前 rotation getter 组合父对象的 rotation 与自己的 _localRotation；setter 则先通过父旋转的逆，计算要保存的本地旋转。

localRotation 和 rotation 使用 Quaternion 保存和传递旋转。localEulerAngles、eulerAngles 将旋转表示为三个角度，赋值时仍会通过 Quaternion.Euler 转成四元数。这一层先认识它们是同一旋转的不同表示方式，四元数运算的推导留给空间模块需要时展开。

forward、right、up 分别用世界 rotation 旋转基础方向向量。它们描述世界朝向，不包含位置平移，也没有乘上 localScale。

坐标转换接口还区分了三种输入：

| 接口 | 输入的含义 | 参与的变换 |
| --- | --- | --- |
| TransformPoint | 一个位置点 | 缩放、旋转、平移，以及父对象链 |
| TransformVector | 一个包含长度的位移向量 | 变换矩阵的线性部分，包含缩放和旋转；不加平移 |
| TransformDirection | 一个方向向量 | 使用世界 rotation 旋转；不加平移，也不应用缩放 |

各自的 Inverse 方法做反向转换。这也帮助理解 Translate、Rotate、LookAt 等工具：它们最后仍会通过本地或世界属性修改空间数据；例如默认 Translate 按当前朝向解释位移，带 Space.World 的版本直接使用世界位移。

源码定位：旋转（`UnityEngine.Transform.cs:139`）、方向（`UnityEngine.Transform.cs:85`、`UnityEngine.Transform.cs:128`、`UnityEngine.Transform.cs:160`）、角度表示（`UnityEngine.Transform.cs:191`、`UnityEngine.Transform.cs:297`）、点、向量和方向转换（`UnityEngine.Transform.cs:310`、`UnityEngine.Transform.cs:316`、`UnityEngine.Transform.cs:382`、`UnityEngine.Transform.cs:388`）、平移与旋转工具（`UnityEngine.Transform.cs:444`、`UnityEngine.Transform.cs:480`）。

## 五、改变父对象时，哪些数值保持不变

parent 属性的赋值和单参数 SetParent 都默认调用 SetParent(parent, true)。双参数方法的原始主体如下：

```csharp
public void SetParent(Transform parent, bool worldPositionStays)
{
    if (UnityRuntime.Current == null)
    {
        return;
    }
    Vector3 position = this.position;
    Quaternion rotation = this.rotation;
    UnityRuntime.Current.World.SetTransformParent(this, parent);
    if (worldPositionStays)
    {
        this.position = position;
        this.rotation = rotation;
    }
    this.MarkChanged();
}
```

它先保存旧的世界位置和旋转，再请 UnityWorld 修改父子记录。如果 worldPositionStays 为 true，就将保存的世界值重新赋给 position、rotation；这两个 setter 会依据新的父对象，计算新的本地数值。

![SetParent 改变父对象并按参数选择是否恢复世界位置和旋转的流程](figures/transform-set-parent-flow.png)

[SVG 矢量图](figures/transform-set-parent-flow.svg)；[可编辑图源](figures/transform-set-parent-flow.dot)。图示从运行时已存在的情况开始。

继续使用仅有平移的讲解例子：子对象原来没有父对象，世界位置为 (12, 0, 23)；新父对象世界位置为 (10, 0, 20)，没有旋转和额外缩放。

| 调用参数 | 新 localPosition | 新 position |
| --- | --- | --- |
| true | (2, 0, 3) | (12, 0, 23)，保留原世界位置 |
| false | (12, 0, 23)，保留原本地位置 | (22, 0, 43)，随新父对象换算 |

当前实现有一个需要明确的边界：这段代码只保存和恢复世界位置、世界旋转，localScale 没有重新计算。若新父对象带有缩放，true 也可能使最终世界矩阵中的缩放发生变化，不能据此认为完整世界变换都会保持不变。

UnityWorld.SetTransformParent 除了修改 Parent 和 Children，还会从旧父对象的 Children 或根对象列表移除记录，再加入新的位置。接到新父对象时，它将该对象及其后代的场景名改为新父对象的场景名；随后重新检查层级活动状态，必要时处理等待激活的 Behaviour。解除父关系时重新加入根对象列表，此处没有另外重设场景名。

因此，层级关系同时连接着空间换算、场景归属和活动状态。这里先标出这些连接，具体生命周期调用仍在 Behaviour 部分展开。

源码定位：默认参数路径（`UnityEngine.Transform.cs:27`、`UnityEngine.Transform.cs:238`）、双参数 SetParent（`UnityEngine.Transform.cs:277`）、重接管理记录（`Waylith.UnityCompat.UnityWorld.cs:566`）、递归设置场景（`Waylith.UnityCompat.UnityWorld.cs:1351`）、层级活动判断（`Waylith.UnityCompat.UnityWorld.cs:1318`）。

## 六、hasChanged 怎样考虑父对象的变化

Transform 还保存 _changedAt、_clearedAt，并共用静态 _changeCounter。位置、旋转、缩放等 setter 调用 MarkChanged，用递增计数标记发生变化的时刻；这里的“时刻”是计数顺序，不是现实时间或帧编号。

读取 hasChanged 时，getter 从自己开始沿父对象链检查：只要某个 _changedAt 大于当前实例的 _clearedAt，就返回 true。这让它能够识别“本地数值没改，但父对象发生变化”的情况。

设置 hasChanged=false 会推进计数并记录新的 _clearedAt，表示此实例已经确认此前的变化；之后自己或父对象再改变，读取结果又可以变成 true。源码给每个实例的 _changedAt 初始值为 1，所以正常新建实例初次读取时就会报告变化。

这个标记供其他代码读取和处理。Transform 本层没有声明 Update，也不会因 hasChanged 为 true 就自动执行一段组件 Update。

源码定位：变化判断与清除（`UnityEngine.Transform.cs:35`）、MarkChanged（`UnityEngine.Transform.cs:57`）、计数字段（`UnityEngine.Transform.cs:539`）。

## 七、父子查询和排列还有哪些入口

childCount、GetChild 通过管理记录查询直接子对象；IEnumerable 的遍历器同样逐个调用 GetChild，所以一层 foreach 遍历的是直接子 Transform。GetComponentInChildren 的后代查询则另有递归过程。

GetSiblingIndex、SetSiblingIndex 调整同一父对象下的 Children 顺序；根对象对应 _rootGameObjects 中的位置。这种顺序是对象层级中的排列，是否影响某条绘制或调用路径，还要继续看使用它的代码。

IsChildOf 从当前 Transform 自身开始检查，再沿 parent 向上。因此，当前实现中将自己作为参数，也可以返回 true。

Find 按 '/' 分段逐级比较子 Transform 的 name。这里应保留当前实现的实际含义：比较的是 child.name，而 UnityWorld 初始化默认 Transform 时给其记录的名称是 "Transform"；本层没有覆写 name 来转向 GameObject.name。单凭这个接口，不能直接假定按所属 GameObject 的名称设置路径就能找到目标。实际使用时还要查看 Transform 是否另行命名。

源码定位：直接子对象与遍历（`UnityEngine.Transform.cs:70`、`UnityEngine.Transform.cs:183`、`UnityEngine.Transform.cs:548`）、同级排列（`UnityEngine.Transform.cs:400`、`Waylith.UnityCompat.UnityWorld.cs:536`）、IsChildOf（`UnityEngine.Transform.cs:262`）、Find（`UnityEngine.Transform.cs:353`）、默认 Transform 名称（`Waylith.UnityCompat.UnityWorld.cs:149`）、读取记录名称（`Waylith.UnityCompat.UnityWorld.cs:400`）。

## 八、游戏案例：子相机怎样对齐它的父对象

SubcameraDriver.Init 中建立子相机的连续节选如下，变量名保持原样：

```csharp
Camera camera2 = new GameObject
{
    name = subcameraDef.defName,
    transform =
    {
        parent = base.transform,
        localPosition = Vector3.zero,
        localScale = Vector3.one,
        localRotation = Quaternion.identity
    }
}.AddComponent<Camera>();
```

transform = { ... } 是嵌套对象初始化语法：它取得 GameObject 已经具有的 Transform，再设置其中的属性。这里继续使用构造过程建立的那个 Transform。

执行顺序也有实际意义：先将 parent 设为当前 SubcameraDriver 所属对象的 Transform，然后将本地位置归零、缩放设为各轴 1 倍、旋转设为单位旋转。虽然 parent 的默认 setter 先保留旧世界位置和旋转，后面这些本地赋值又将子对象明确对齐到父坐标系中。完成后，子对象的 localToWorldMatrix 与父对象的 localToWorldMatrix 相同。

这个父对象是 Bootstrap 中承载 SubcameraDriver 的 "Subcameras" 对象。主 Camera 建在另一个 GameObject 上；两者的后续协调要沿相机控制代码继续追踪，不能仅凭“子相机”这个称呼假定它直接挂在主 Camera 对象下。

回到之前的 CameraDriver 案例，设置 MyCamera.transform.position 会改变相机的世界位置。其他功能也会读取空间接口：MeshRenderer 在绘制入口取得 transform.localToWorldMatrix；AudioListener 向音频后端传入 transform.position、forward、up。Transform 由此把同一套空间状态交给具体使用者，绘制和音频细节留在各自模块。

源码定位：子相机初始化（`Verse.SubcameraDriver.cs:24`）、建立 Subcameras 对象（`RimWorldWaylith.Bootstrap.cs:801`）、控制主相机位置（`Verse.CameraDriver.cs:418`）、网格绘制入口（`UnityEngine.MeshRenderer.cs:29`）、监听位置与方向（`UnityEngine.AudioListener.cs:65`）。

当前进度：已建立 Transform 的数据分工、本地与世界变换、换父对象、变化判断和实际使用案例的第一轮说明。下一组进入 [MeshFilter 与 Renderer 分支](22-mesh-renderer-components.md)；相机控制与更深入的空间计算可在相应模块接回这些接口。
