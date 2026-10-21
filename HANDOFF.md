# 交接说明（给下一位接手者）

目标：10 分钟内知道这是什么、证据在哪、怎么复核、按什么顺序读、哪些坑不能再踩。

交付报告见 [DELIVERY.md](DELIVERY.md)；写作规范见 [docs/STYLE.md](docs/STYLE.md)。

---

## 1. 项目是什么

**RimWorld 1.7 的运行规则解构**：不是攻略，而是「每帧 / 每 tick 到底按什么顺序做了什么」的源码级说明。

- 输入：`RimWorld/`（只读游戏本体，1161 MB，**不入库**）
- 语料：`analysis/decompiled/`（5 个程序集，11347 个 `.cs`，**不入库**，可由脚本重建）
- 产出：v3 24 卷（`docs/mechanisms-v3/`）+ v1 24 卷归档（`docs/mechanisms/`）+ `scripts/` 证据工具链
- 纪律：**每条结论都要能回到源码那一行**；没有断言的「结论」不算结论

## 2. 证据体系

### 2.1 claim 三行式

```text
[claim:V01-C07] 每帧 tick 数受「倍率×2」限制。
  src: Verse.TickManager.TickManagerUpdate
  file: analysis/decompiled/Assembly-CSharp/Verse/TickManager.cs
  match: while (this.realTimeToTickThrough > 0f && (float)this.ticksThisFrame < tickRateMultiplier * 2f)
```

- `src`：类型.方法
- `file`：语料路径（相对项目根）
- `match`：该文件中**逐字出现**的字符串
- `note:`：可选；用于标注「该匹配在文件中出现 N 次」或上下文说明

`verify-claims.ps1` 拿 `match` 做字面量查找。**claim 的强度 = match 的严格度**：过短会误命中，过长会跨行。重复锚点必须加 `note:`。

### 2.2 复核命令

```powershell
$P='powershell -NoProfile -ExecutionPolicy Bypass -File'
& $P scripts\verify-claims.ps1 -DocsRoot docs\mechanisms-v3   # 451 条 → claims=451 pass=451 fail=0
& $P scripts\lint-docs.ps1 -Profile v3 -DocsRoot docs\mechanisms-v3  # docs=24 claims=451 mermaid=26 errors=0
& $P scripts\lint-docs.ps1                                    # v1 回归：docs=24 claims=621 errors=0
```

`backtest.ps1` 是唯一不信任语料的检查：从 DLL 重新反编译再核对 `match`。语料可能过期，DLL 不会。

## 3. 推荐阅读顺序

### 路径 A：先建骨架（约 1 小时）

1. **V00** 程序集、主链、卷地图
2. **V23** 单 tick 全景（24 位点；附「18/20/22 步」口径澄清）
3. **V22** 帧从哪来、线程怎么分、有界队列反压
4. **V01** tick 泵：倍率八种取值、暂停六个来源、双闸门

### 路径 B：按域深入

| 想搞清 | 读 |
|---|---|
| 地图与寻路 | V03（含 `PathFinderJob` 的 A*）→ V19（房间） |
| 物体与分桶 | V04 → V05 → V06/V07 |
| 战斗 | V08（格式基准卷，最详细） |
| 时间与日历 | V02 → V13（需求） |
| 世界与故事 | V10 → V09 → V11 |
| 表现层 | V17 → V21 → V22 |
| 数据与存档 | V15 → V16 |
| DLC | V18（总表）→ V20（Ideology） |

### 路径 C：按数字反查

`analysis/index/types.tsv` 按类型名查文件 → 在语料里 `Select-String` → 回到卷里的 claim。

## 4. 各卷一句话

| 卷 | 一句话 |
|---|---|
| V00 | 五个程序集 + 一条主链 + 卷地图 |
| V01 | `Game.UpdatePlay` → 泵 → 七个帧级通道；倍率/暂停 |
| V02 | 四个换算常量把 tick 变成日期；150 tick 需求量子 |
| V03 | 17 个网格叠加；寻路是批量作业，A* 在 `PathFinderJob` |
| V04 | `DoTick` 四段；哈希分桶；进出地图镜像 |
| V05 | 22 个组件分两条链；需求 150 量子 |
| V06 | 30 tick 决策；`DriverTick` 推 Toil |
| V07 | `JobGiver_Work` 选活；`Bill` 门控与排产 |
| V08 | 举枪→暖机→发射→掷骰→飞行→落地→伤口→护甲 |
| V09 | 1000 tick 生成；833 tick 重试相位 |
| V10 | 世界 tick 七行；坐标委托给层 |
| V11 | 派系关系成对表；好感即时计算；互动带冷却 |
| V12 | 价格是属性；活体因子连乘/连加；交易汇总后扣货币 |
| V13 | 需求追赶即时值；三条阈值（1/7、4/7、1） |
| V14 | Hediff 副本遍历；出血率负缓存；年龄按 delta |
| V15 | Def 装载两阶段；重名改名；`ushort` 上限 65535 |
| V16 | `InitLoading` 五模式；值序列化四道守卫 |
| V17 | `Update`/`OnGUI` 双通道；窗口暂停倒灌；网格脏标记 |
| V18 | 五个 DLC 布尔；在既有链上插 `if` |
| V19 | 脏块两阶段重建；异常也清脏 |
| V20 | 确定性按心情曲线漂移；戒律是过滤器 |
| V21 | 区块+层；`ulong` 位脏标记；打脏与重建分离 |
| V22 | 主线程/渲染线程；有界队列；睡眠+自旋限速 |
| V23 | 24 位点；三层桶；`GameComponentTick` 唯一无 try |

## 5. 加新内容时

1. 先改 `docs/STYLE.md`（若规则要变），再改文档；
2. 每段源码前写「这一段做什么」，后写「这一段怎么走」；
3. 源码与伪代码**语句数必须一一对应**（lint 会查）；
4. 新增断言从该卷下一个编号开始，写完单独验一次；
5. 改完跑：该卷断言 → 全量 lint（v3）→ 需要时 `backtest.ps1`；
6. 记录三件套：`project.log`（追加）、`logs/GATE.log`（一行）、`state.md`（快照）。

## 6. 环境坑

1. `pwsh` 工具实际是 **Windows PowerShell 5.1**；PS7 在 `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`。
2. 读 UTF-8 必须 `-Encoding UTF8`（控制台 936）。
3. 中文 `.ps1` 在 5.1 下会静默乱码 → 用 PS7 或写 UTF-8 BOM。
4. shell 内 HTTPS 不可用；抓网页走 `web_fetch`。
5. `-File` 传数组会拼成 `"a,b"`，脚本内自己拆。
6. 反编译无 PDB：没有局部变量名与源码行号，靠 Token RID。

## 7. 未结项

- **v3 Open questions 72 条**（每卷 3 条）未并入 `analysis/index/open-questions.tsv`。
- **38 条重复锚点**已加 `note:`，未改成唯一行；若要彻底消除，需在 STYLE 里定义「签名 + 邻近唯一行」双锚点格式。
- **`runtime-only`**：抖动抑制、区域扫描成本、IMGUI 重入、队列满语义等需实测。
- `docs/TRACES.md`、`docs/GLOSSARY.md`、`docs/CONSTANTS.md` 仍未建。

## 8. 不要做

1. 不要改 `RimWorld/`（只读输入）。
2. 不要手工编辑 `analysis/decompiled/`（用脚本重建）。
3. 不要改 v1 卷（冻结归档）；新内容进 v3。
4. 不要在没有 `match` 的情况下写结论。
5. 不要把 `logs/*.log`、语料、游戏本体提交进仓库。
