# 从种子到落点（二）· 从生成步骤到地块降雨量

逐段研究笔记，2026-11-16。依据工作区 RimWorld 1.7.4982 rev1280 的源码与原版 XML。承接[生成世界的入口](58-world-generation-entry.md)。

选址时点开一个地块，地形页已经能显示降雨量。这个数值在 `WorldGenerator.GenerateWorld` 执行期间就写进了地块。本节沿创建世界、运行生成步骤、写入地块和界面读取这条线，追到那一行带 `mm` 的文字。

## 一、先准备世界，再逐层生成

`GenerateWorld` 收到上一节参数页传来的设置，创建 `World` 和它的 `WorldInfo`，把种子、覆盖率、气候档位等存进去。生成步骤通过 `Find.World` 访问此时放在 `Current.CreatingWorld` 里的对象，也就能读到这些设置。

| 生成阶段 | 完成后有什么 |
| --- | --- |
| 执行 `GameSetupStepDef` 指定的准备步骤 | `WorldGrid`、`WorldPathGrid`、剧本要求的 `PlanetLayer`，以及世界组件等基础对象。 |
| 按层的编号调用 `GeneratePlanetLayer` | 每层拿自己的 `WorldGenStepDef` 列表生成内容。以地表为例，先有带海拔、气候和生物群系的地块，后续步骤再补湖泊、河流、派系等数据。 |
| 收尾并返回 `World` | `StandardizeTileData()` 会检查没有地块记录的层，`World.FinalizeInit(false)` 计算世界寻路代价并初始化世界组件。接着通知剧本世界已生成，最后把 `World` 返回给参数页登记。 |

准备步骤里的 `Grids` 会创建 `WorldGrid` 并调用 `GenerateFreshWorld()`。`WorldGrid` 根据剧本中的 `ScenPart_PlanetLayer` 创建需要的层，例如地表层。这里的 `PlanetLayer` 对象保存地块的几何网格和后续要填写的 `Tiles` 列表。地块有多少个可由网格确定，地块的温度、降雨等字段则在逐层生成时写入。

源码位置见 `RimWorld.Planet.WorldGenerator.cs:14`、`:30`、`RimWorld.Planet.GameSetupStep_Grids.cs:21`、`RimWorld.Planet.WorldGrid.cs:194`、`:211`、`:950`、`RimWorld.Planet.PlanetLayer.cs:114`、`:124`、`:445` 和 `RimWorld.Planet.World.cs:218`。

## 二、每个生成步骤从哪里取得种子

玩家输入的 `seedString` 先经 `GenText.StableStringHash` 转成整数 `seedFromSeedString`。开始时 `Rand.PushState()` 保存原有的种子和随机序列进度。接下来的 `Rand.Seed` 赋值会设置种子并把序列进度归零。生成器退出时，`finally` 里的 `Rand.PopState()` 恢复原来的随机状态。

准备步骤从 `DefDatabase<GameSetupStepDef>` 取出，先按 `order`，再按 `index` 排序。`gameSetupStepDef.setupStep` 是该 Def 所指定的步骤对象。每次调用它的 `GenerateFresh()` 之前，生成器都会把世界种子和步骤的 `SeedPart` 混合，重新给 `Rand` 设置起点。

```csharp
foreach (GameSetupStepDef gameSetupStepDef in WorldGenerator.GameSetupStepsInOrder)
{
    Rand.Seed = Gen.HashCombineInt(seedFromSeedString, gameSetupStepDef.setupStep.SeedPart);
    gameSetupStepDef.setupStep.GenerateFresh();
}
```

逐层生成时也逐步重设 `Rand.Seed`。这次的 `genStepsInOrder` 来自当前层的 `PlanetLayerDef.GenStepsInOrder`，`i` 是其中要执行的步骤编号。`seed` 是从入口传下来的世界种子整数，`seedString` 还是玩家输入的字符串。

```csharp
Rand.Seed = Gen.HashCombineInt(seed, WorldGenerator.GetSeedPart(genStepsInOrder, i));
genStepsInOrder[i].worldGenStep.GenerateFresh(seedString, layer);
```

`GetSeedPart` 会数同一列表里排在当前步骤之前、且使用相同 `SeedPart` 的步骤，把这个数量加到原值上。比如列表里两次遇到同一个 `SeedPart`，第一次用原值，第二次用原值加一。前一步即使多取了几次随机数，下一步也会从自己算出的种子重新开始。不过，后一步仍然可能读取前一步产生的数据，例如河流生成会读地块的山地程度。

源码位置见 `RimWorld.Planet.WorldGenerator.cs:33`、`:95`、`:200`、`:215`、`Verse.GenText.cs:305`、`Verse.Rand.cs:18`、`:513`、`:526` 和 `RimWorld.Planet.WorldGenStep_Rivers.cs:70`。

## 三、地表的 Terrain 步骤逐格创建 SurfaceTile

原版 `Surface` 是一个 `PlanetLayerDef`。它的 `<worldGenSteps>` 用名字引用 `Terrain`、`Lakes`、`Rivers` 等 `WorldGenStepDef`。运行时按这些 Def 自身的 `order` 和 `index` 排序。排在最前面的 `Terrain` 的 `order` 是 `0`，它指定的代码类是 `WorldGenStep_Terrain`。

```xml
<WorldGenStepDef>
  <defName>Terrain</defName>
  <order>0</order>
  <worldGenStep Class="WorldGenStep_Terrain"/>
</WorldGenStepDef>
```

`WorldGenStep_Terrain` 继承 `WorldGenStep_Tiles`。它的 `GenerateFresh()` 先准备计算海拔、气温偏移、降雨、丘陵和沼泽程度的函数，再调用 `base.GenerateFresh(seed, layer)`。下面是父类的实现。`layer.TilesCount` 是当前层网格中的地块数，`new PlanetTile(i, layer)` 用所在层和层内编号指明正在处理哪一格。`GenerateTileFor` 是可重写的方法，所以在这条地表路径中实际调用的是 `WorldGenStep_Terrain.GenerateTileFor`。

```csharp
public override void GenerateFresh(string seed, PlanetLayer layer)
{
    layer.Tiles.Clear();
    for (int i = 0; i < layer.TilesCount; i++)
    {
        Tile tile = this.GenerateTileFor(new PlanetTile(i, layer), layer);
        layer.Tiles.Add(tile);
    }
}
```

地表版本的 `GenerateTileFor` 为这一格创建 `SurfaceTile`，取地块中心的位置，计算海拔、山地程度、气温、降雨等，再确定它的主要生物群系。整个地表逐格处理完后，`Tiles` 就能供后续的湖泊、河流等步骤查询。

原版定义见 `Core/Defs/PlanetLayerDefs/PlanetLayers.xml` 中的 `Surface` 和 `Core/Defs/WorldGeneration/WorldGenerator.xml` 中的 `Terrain`。源码位置见 `RimWorld.PlanetLayerDef.cs:99`、`RimWorld.Planet.WorldGenStep_Terrain.cs:34`、`:174` 和 `RimWorld.Planet.WorldGenStep_Tiles.cs:20`。

## 四、把降雨滑杆接到选址页的 mm 数值

`Terrain` 的 `SetupRainfallNoise()` 建立一个按坐标求降雨量的函数。基础值来自按种子生成的噪声，也就是随位置连续变化的数值，再乘上纬度和海拔对应的系数。函数把结果换算成毫米，最后根据 `WorldInfo.overallRainfall` 选择是否用一条曲线调整它。玩家设置的整体降雨档位就在这一步起作用。

以一格的基础降雨量恰好为 `1000` 毫米为例。`OverallRainfall.Normal` 会让它保持 `1000`。`OverallRainfall.High` 用 `Curve_High` 调整，其中有一个点是 `(1000, 2800)`，于是同一基础值在这个档位下会变成 `2800` 毫米。这里的数值用于演示原版曲线的输入和输出。

生成这个地块时，`tileCenter` 是它的中心坐标。`noiseRainfall` 已经包含适用的曲线，取值后直接写到地块的 `rainfall` 字段。

```csharp
surfaceTile.rainfall = this.noiseRainfall.GetValue(tileCenter);
```

玩家在选址时选中这个地块，`WITab` 通过 `Find.WorldGrid[SelPlanetTile]` 取得对应的数据对象。`WorldGrid` 由 `PlanetTile` 找到所在层，再用 `tileId` 取出 `Tiles` 里的那格。地形页 `WITab_Terrain` 把取到的 `Tile` 传进 `ListTemperatureDetails`。在下面这行里，`ws` 就是该地块的数据对象，`listing` 负责绘制一行标签和值。

```csharp
listing.LabelDouble("Rainfall".Translate(), ws.rainfall.ToString("F0") + "mm", null);
```

所以这个例子中，`2800` 从生成线程写入 `SurfaceTile.rainfall` 后，一直留在地块数据里。等玩家在选址界面点开地形页，代码将它格式化为 `2800mm` 并显示。点击另一格时，界面换用另一条地块记录。

源码位置见 `RimWorld.Planet.WorldGenStep_Terrain.cs:89`、`:233`、`RimWorld.Planet.OverallRainfallUtility.cs:24`、`:140`、`RimWorld.Planet.WITab.cs:22`、`:37`、`RimWorld.Planet.WorldGrid.cs:165` 和 `RimWorld.Planet.WITab_Terrain.cs:158`、`:168`。

下一段沿同一个 `PlanetTile` 查找地块和定居点，再追到选址和玩家据点的创建。[世界数据与开局选址](60-world-data-and-starting-site.md)
