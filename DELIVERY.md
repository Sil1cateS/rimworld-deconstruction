# 交付报告

项目：**rimworld-deconstruction** — RimWorld 1.7 游戏进程规则解构
版本基线：`1.7.4982 rev1280` · `Assembly-CSharp 1.7.9787.38423` · .NET 10 · 引擎 Waylith
报告时间：2026-10-21（v3 全量完成）

---

## 1. 一句话交付

把 RimWorld 1.7 的五个程序集解构成 **两套 24 卷机制文档**：v1（6286 行 / 621 断言，冻结归档）与 **v3（11589 行 / 451 断言，面向人读的重写）**；每条断言都能用一条命令回到语料复核，外加一套可重跑的工具链（反编译、索引、断言核对、结构检查、回测）。

## 2. v3 卷清单（`docs/mechanisms-v3/`）

| 卷 | 主题 | 行数 | 断言 |
|---|---|---:|---:|
| V00 | 程序集、主链与卷地图 | 336 | 9 |
| V01 | 帧循环与 tick 泵 | 568 | 25 |
| V02 | 时间与历法 | 387 | 17 |
| V03 | 地图、网格与寻路（含 A* 本体） | 785 | 32 |
| V04 | Thing 生命周期与分桶 | 444 | 18 |
| V05 | Pawn 构成与状态 | 411 | 18 |
| V06 | AI：ThinkTree / Job / Toil | 354 | 14 |
| V07 | 工作与生产：WorkGiver / Bill | 393 | 15 |
| V08 | 战斗与伤害（格式基准卷） | 2748 | 91 |
| V09 | 故事叙述者与事件 | 334 | 13 |
| V10 | 世界、地块与远行队 | 262 | 10 |
| V11 | 派系、社交与关系 | 353 | 14 |
| V12 | 经济、价格与贸易 | 321 | 12 |
| V13 | 需求与心情 | 331 | 14 |
| V14 | 医疗、身体与伤势 | 341 | 13 |
| V15 | Def 与 XML 管线 | 282 | 11 |
| V16 | 存档与序列化 | 307 | 12 |
| V17 | UI 与渲染桥接 | 427 | 16 |
| V18 | DLC 增量 | 213 | 10 |
| V19 | 空间构建：区域与房间 | 271 | 12 |
| V20 | Ideology | 289 | 13 |
| V21 | 渲染树与绘制管线 | 245 | 11 |
| V22 | Waylith 运行模式 | 512 | 18 |
| V23 | 单 tick 全景（24 位点） | 675 | 33 |
| **合计** | | **11589** | **451** |

每卷七节骨架：`Where it sits` / `Evolution` / `Stage detail` / `Branches` / `Contracts` / `Evidence` / `Open questions`；每段源码前有「这一段做什么」、后有「这一段怎么走」。

## 3. 验收

| 编号 | 标准 | 判定手段 | 结果 |
|---|---|---|---|
| D1 | v3 七节锚点齐全、顺序正确 | `lint-docs.ps1 -Profile v3` | 24/24 |
| D2 | 断言 100% 命中语料 | `verify-claims.ps1 -DocsRoot docs/mechanisms-v3` | **451/451 PASS** |
| D3 | 源码与伪代码语句数一一对应 | 同上 lint | errors=0 |
| D4 | 每段源码前有功能说明 | 同上 lint（introduction 规则） | errors=0 |
| D5 | 每卷 ≥1 张 Mermaid、≥2 个 Stage 子节 | 结构审计脚本 | 24/24 |
| D6 | claim 编号唯一、无缺口、三行式完整 | 结构审计脚本 | 0 例外 |
| D7 | v1 零回归 | `lint-docs.ps1`（默认档） | 24 卷 / 621 断言 / errors=0 |

最近一次全量复核：`docs=24 claims=451 mermaid=26 errors=0`；`claims=451 pass=451 fail=0`。

## 4. 工具链（`scripts/`）

| 脚本 | 作用 |
|---|---|
| `decompile.ps1` | 反编译 5 个程序集到 `analysis/decompiled/` |
| `dump-waylith.ps1` | Waylith 逐类型反编译（超时 + IL 回退） |
| `list-types.ps1` | 从语料抽 `types.tsv` / `namespaces.tsv` |
| `list-types-meta.ps1` | 从 ECMA-335 元数据枚举类型（PS7 + ALC 隔离） |
| `probe-type.ps1` | 单类型直取 |
| `dump-types.ps1` | 按清单逐类型导出 |
| `decompile-diagnose.ps1` | 反编译卡点诊断 |
| `verify-claims.ps1` | 断言逐条核对 |
| `lint-docs.ps1` | 结构检查（`-Profile v1|v3`） |
| `backtest.ps1` | 从 DLL 重编译做独立回测 |

## 5. 复现步骤

```powershell
# 1) 自备游戏副本到 RimWorld/（只读，不入库）
# 2) 反编译（约 6 分钟）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\decompile.ps1
# 3) 索引
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\list-types.ps1
# 4) 双检
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\lint-docs.ps1 -Profile v3 -DocsRoot docs\mechanisms-v3
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-claims.ps1 -DocsRoot docs\mechanisms-v3
```

## 6. 已知边界

1. **无 PDB**：游戏只带 `glfw3.pdb`，语料无局部变量名与源码行号；断言以 `Token RID` + 语料行号定位。
2. **`Bc7BlockEncoder` 只有 IL**：dnSpy 的 C# 前端在该类型上死循环，保留 IL 版本；其余 Waylith 类型为 `.cs`。
3. **重复锚点**：38 条断言的 `match` 在目标文件中出现 2–9 次，已用 `note:` 标注次数与所属方法；验证取首次命中。
4. **`runtime-only` 问题**：抖动抑制、区域扫描成本、IMGUI 重入、队列满语义等需实测，未在静态文档中定论。
5. **v3 Open questions**：每卷 3 条，共 72 条，尚未并入 `analysis/index/open-questions.tsv`。

## 7. 与 v1 的关系

- v1（`docs/mechanisms/`）为第一轮交付，24 卷 / 6286 行 / 621 断言，**冻结不再改动**，作为对照与历史基线保留。
- v3 覆盖同样的 24 个主题，但重排为演进叙事体、补齐类结构与伪代码、统一口径（如单 tick 的「24 位点」）。
- 两套文档各自独立校验；v3 的断言编号按卷命名（如 `V23-C01`），与 v1 同名卷不一一对应。

## 8. 状态

v3 已完成并全量复核；仓库整理（说明文件、临时文件清理）完成后可发布。后续改动应保持「改一卷 → 跑该卷断言 + 全量 lint」的节奏。
