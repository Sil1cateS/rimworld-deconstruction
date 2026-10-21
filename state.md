# 当前状态（state.md）

快照时间：2026-10-21T13:45+08:00

## 阶段

| 项 | 值 |
|---|---|
| 项目 | rimworld-deconstruction（RimWorld 1.7 游戏进程规则解构） |
| **当前阶段** | **v3 细化周期 · 24 卷完成并通过全量复核** —— `docs/mechanisms-v3/`：24 卷 / 11589 行 / **451 断言全部 PASS** / 26 张 Mermaid / 每卷七节骨架齐全；v1 24 卷冻结未动 |
| 交付物 | v1：`DELIVERY.md`、`HANDOFF.md`、`README.md`、`docs/mechanisms/` 24 卷（冻结）；v3：`docs/STYLE.md` + `docs/mechanisms-v3/` 24 卷（V00–V23 全覆盖） |
| OQ 状态 | resolved **98** · resolved-partial 6 · runtime-only 5 · resolved-analytic 1 · note 1 · blocked/phased/deferred 全为 0 |
| 下一步 | 收尾二项：①汇总 v3 各卷 Open questions 成「真正未结」清单（每卷 3 条）；②24 卷 451 条断言已全量重跑通过，后续改动需重跑 |
| 记录封存 | 本周期 `project.log`（1292 行）/ `logs/GATE.log`（57 行）只追加不改写 |
| 登记表 | `analysis/index/open-questions.tsv`（**111 条** + status 列，机器可读） |
| heavy | **true**（游戏本体 1161 MB + 语料 45.6 MB，11340 文件） |

## 已交付文档

| 卷 | 文件 | 规模 | claim 数 | 校验 |
|---|---|---|---:|---|
| V00 | `docs/mechanisms/V00-overview.md` | 155 行 | 7 | 通过 |
| V01 | `docs/mechanisms/V01-tick-pipeline.md` | 381 行 | 42 | 通过 |
| V02 | `docs/mechanisms/V02-time-and-calendar.md` | 259 行 | 28 | 通过 |
| V03 | `docs/mechanisms/V03-map-and-pathfinding.md` | 219 行 | 20 | 通过 |
| V04 | `docs/mechanisms/V04-thing-lifecycle.md` | 261 行 | 25 | 通过 |
| V05 | `docs/mechanisms/V05-pawn.md` | 219 行 | 24 | 通过 |
| V06 | `docs/mechanisms/V06-ai-and-jobs.md` | 229 行 | 21 | 通过 |
| V07 | `docs/mechanisms/V07-work-and-production.md` | 211 行 | 20 | 通过 |
| V08 | `docs/mechanisms/V08-combat-and-damage.md` | 213 行 | 19 | 通过 |
| V09 | `docs/mechanisms/V09-storyteller-and-quests.md` | 205 行 | 20 | 通过 |
| V10 | `docs/mechanisms/V10-world-and-caravans.md` | 199 行 | 18 | 通过 |
| V11 | `docs/mechanisms/V11-factions-and-social.md` | 165 行 | 15 | 通过 |
| V12 | `docs/mechanisms/V12-economy-and-trade.md` | 201 行 | 20 | 通过 |
| V13 | `docs/mechanisms/V13-needs-and-mood.md` | 193 行 | 18 | 通过 |
| V14 | `docs/mechanisms/V14-medical-and-genes.md` | 259 行 | 28 | 通过 |
| V15 | `docs/mechanisms/V15-def-and-xml-pipeline.md` | 221 行 | 23 | 通过 |
| V17 | `docs/mechanisms/V17-ui-and-rendering.md` | 169 行 | 12 | 通过 |
| V18 | `docs/mechanisms/V18-dlc-mechanics.md` | 183 行 | 17 | 通过 |
| V16 | `docs/mechanisms/V16-save-and-serialization.md` | 212 行 | 20 | 通过 |
| V17 | `docs/mechanisms/V17-ui-and-rendering.md` | 169 行 | 12 | 通过 |
| V18 | `docs/mechanisms/V18-dlc-mechanics.md` | 183 行 | 17 | 通过 |
| 合计 | **19 卷** | 4153 行 / 46 张 Mermaid | **397** | 397/397 PASS，lint 0 error |

## 关键参数

- 输入：`RimWorld/`（只读）；版本 `1.7.4982 rev1280`；`Assembly-CSharp 1.7.9787.38423`；.NET 10；引擎 Waylith（非 Unity）
- 工具：dnSpyEx 6.6 的 `dnSpy.Console.exe`（PATH 或 `DNSPY_CONSOLE`），`-t <Type> <asm>`；`exit 0` = 存在，`exit 1` + usage = 不存在
- 语料：`analysis/decompiled/<Asm>/<Namespace>/<Type>.cs`，**11347 文件 / 46.3 MB**
  - `Assembly-CSharp` 9263 文件 · `UnityStubs` 704 · **`Waylith` 1323（887/887 类型，含 1 个 `.il`）** · `RimWorld` 49 · `Waylith.UnityCompat` 8
- 索引：`analysis/index/types.tsv`（**12234 类型**，R24 重建）、`namespaces.tsv`（111 命名空间）、`waylith-types.tsv`（887 类型，元数据权威）
- 脚本调用：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<动作>.ps1`（进程级；本机工具进程为 AllSigned）
- PowerShell 7：`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`（7.6.6 / .NET 10）

## 回退点

- 方案回退：改 `01_PROJECT_PLAN.md` 并重新确认。
- 语料回退：`scripts/decompile.ps1` 可整目录重建（覆盖前先删自身目标目录）；`Waylith` 必须用 `scripts/dump-waylith.ps1`（逐类型 + 超时 + IL 回退），项目级反编译会在 `Bc7BlockEncoder` 上挂死。
- 索引回退：`scripts/list-types.ps1` 幂等重建。
- 环境事实：工作区**不是 git 仓库**，无版本回退；`git init` 需单独确认。

## 已知限制 / 未解问题

1. ~~`Waylith.dll` 无法整程序集反编译~~ → **R19 已解除**：卡点定位为 `Waylith.Rendering.Bc7BlockEncoder`（RID 56，190 方法），dnSpy 的 C# 前端在该类型上无限循环（0 字节文件即标记，IL 模式可正常导出 31207 行）。用 `scripts/dump-waylith.ps1` 逐类型提取后 887/887 类型全覆盖；该类型只有 IL 版本（1.9 MB）。
2. **无 PDB**（游戏仅带 `glfw3.pdb`）→ 无局部变量名、无源码行号；文档以 Token RID 定位。
3. **PowerShell 7 加载 `System.Reflection.Metadata` 需要 ALC 隔离**：PS7 自带的是不含类型的 facade；已用私有 `AssemblyLoadContext` 加载 .NET 10 共享框架的真实现（见 `scripts/list-types-meta.ps1`）。注意两处 API：`PEReader` 在 `System.Reflection.PortableExecutable`，`GetMetadataReader` 是扩展方法。
4. `-File` 传数组参数会被拼成 `"a,b"` 单串 → 脚本内统一按逗号拆分。
5. shell 内 HTTPS 不可用；需要抓网页走 `web_fetch`。`ops_bash` 在本机无输出，命令一律走 `pwsh`。
6. 控制台代码页 936：读 UTF-8 文件必须显式 `-Encoding UTF8`。

## v3 细化周期（进行中）

| 项 | 值 |
|---|---|
| 目标 | 24 卷改写为**演进叙事体**：以子系统演进主线组织章节，面向人读，单卷逻辑闭环，可追溯底层演进细节 |
| 已定决定 | D5 换七节骨架；D6 样张选 V08；D7「演进」= 运行期状态演进 + 1.7 内层积/遗留痕迹（不做跨版本，语料只有 1.7）；D8 样张必审、之后按批汇报 |
| 目录 | v1 `docs/mechanisms/`（冻结）；v3 `docs/mechanisms-v3/`；规范 `docs/STYLE.md` |
| 骨架 | `Where it sits` / `Evolution` / `Stage detail` / `Branches` / `Contracts` / `Evidence` / `Open questions` |
| P0–P6 状态 | **已完成**：24 卷（V00–V23）全部落盘，合计 11589 行 / 451 断言 / 26 图；V08 为格式基准（2746 行 / 91 断言 / 37 组源码-伪代码） |
| 校验 | `verify-claims.ps1 -DocsRoot docs/mechanisms-v3` → **451/451 PASS**（exit 0）；`lint-docs.ps1 -Profile v3` → docs=24 claims=451 mermaid=26 **errors=0**；v1 默认档 24 卷 621 断言 errors=0 零回归 |
| 下一步 | 收尾：v3 的 72 条 Open questions（24 卷 × 3）尚未并入 `analysis/index/open-questions.tsv`；`docs/TRACES.md`、`docs/GLOSSARY.md`、`docs/CONSTANTS.md` 仍未建 |
| 待建 | `docs/TRACES.md`（三条端到端追踪）、`docs/GLOSSARY.md`、`docs/CONSTANTS.md`；本表上方 24 卷统计仍是 v1 旧数据，R1 重建 |
