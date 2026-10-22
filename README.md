# rimworld-deconstruction

RimWorld 1.7（`1.7.4982 rev1280`，逻辑程序集 `Assembly-CSharp` `1.7.9787.38423`，.NET 10，引擎 Waylith）游戏进程规则的**静态解构**项目：把「一帧 → 一个 tick → 一个子系统」的推进路径拆成可机器核对的文档。

本仓库只包含**分析文档与工具脚本**；游戏本体、DLC 数据与反编译语料均不入库（见 `.gitignore`）。

## 我们最新的给碳基生物读的版本已经全方位超越了老式的机读版本！
| 主题 |  |  |
|---|---|---|
|Waylith引擎的运行|[完整版](docs/readable/chapters/01-waylith/article.md)|[简略版](docs/readable/chapters/01-waylith/release.md)


## 以下是机读版本，不建议阅读
## 两条文档线

| 线 | 位置 | 状态 | 规模 |
|---|---|---|---|
| **v3（当前）** | `docs/mechanisms-v3/` | 24 卷全部完成，七节骨架 | **11589 行 / 451 条可核断言 / 26 张图** |
| v1（归档） | `docs/mechanisms/` | 冻结，不再改动（[归档说明](docs/ARCHIVE-v1.md)） | 6286 行 / 621 条断言 / 55 张图 |

v3 是面向人读的重写：每卷按「**Where it sits → Evolution → Stage detail → Branches → Contracts → Evidence → Open questions**」组织，每段源码前有功能说明、后有流程小结；断言用 `src / file / match` 三行式，可逐条回到语料核对。

## 先读这三份

| 文件 | 用途 |
|---|---|
| [DELIVERY.md](DELIVERY.md) | 交付报告：v3 卷清单、验收对照、复现步骤、已知边界 |
| [HANDOFF.md](HANDOFF.md) | 交接说明：证据体系、阅读顺序、各卷一句话索引、环境坑、未结项 |
| [docs/STYLE.md](docs/STYLE.md) | v3 写作规范：七节骨架、类结构格式、源码/伪代码对齐规则 |

## 阅读起点

1. **V00 总览**：程序集、主链、卷地图与检索路径。
2. **V23 单 tick**：`DoSingleTick` 的 24 个执行位点（含「18/20/22 步」口径澄清）。
3. **V22 帧源**：Waylith 的 `RunLoop`、渲染线程与有界队列。
4. **V01 tick 泵**：`Game.UpdatePlay`、倍率八种取值、暂停六个来源。
5. 之后按域进卷：V03 地图/寻路（含 A* 本体）→ V04 Thing → V05 Pawn → V06/V07 AI 与工作 → V08 战斗 → 其余。

## 目录

```text
docs/
  STYLE.md                 # v3 写作规范
  mechanisms/              # v1 24 卷（冻结归档）
  mechanisms-v3/           # v3 24 卷（当前）
scripts/
  decompile.ps1            # 反编译 5 个程序集（需自备游戏）
  dump-waylith.ps1         # Waylith 逐类型反编译（超时 + IL 回退）
  list-types.ps1           # 从语料抽类型索引
  list-types-meta.ps1      # 从 ECMA-335 元数据枚举类型
  probe-type.ps1           # 单类型直取
  dump-types.ps1           # 按清单逐类型导出
  decompile-diagnose.ps1   # 反编译卡点诊断
  verify-claims.ps1        # 断言逐条核对
  lint-docs.ps1            # 结构检查（-Profile v1|v3）
  backtest.ps1             # 独立回测
analysis/                  # 语料与索引（decompiled/ 与 diag/ 不入库）
logs/GATE.log              # 机器证据（只追加）
project.log                # 协作记录（只追加）
state.md                   # 当前快照
```

## 校验

所有脚本为纯 ASCII Windows PowerShell，按文件执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\lint-docs.ps1 -Profile v3 -DocsRoot docs\mechanisms-v3
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-claims.ps1 -DocsRoot docs\mechanisms-v3
```

- v3 现状：`docs=24 claims=451 mermaid=26 errors=0`；断言 `451/451 PASS`。
- v1 回归：`docs=24 claims=621 mermaid=55 errors=0`。

## 从零复现

1. 自备 RimWorld 1.7 安装目录，放到 `RimWorld/`（只读，不入库）。
2. 安装 dnSpyEx 6.6，把 `dnSpy.Console.exe` 放进 `PATH`，或设置环境变量 `DNSPY_CONSOLE` 指向它。
3. `scripts/decompile.ps1` 反编译 5 个程序集到 `analysis/decompiled/`（约 6 分钟；Waylith 必须走逐类型）。
4. `scripts/list-types.ps1` 生成 `analysis/index/types.tsv`。
5. 跑上面的两条校验命令。

所有脚本的路径参数都可覆盖（如 `-GameRoot`、`-DnSpy`、`-DocsRoot`），默认值相对仓库根解析。

## 已知限制

1. 反编译产物无 PDB（游戏只带 `glfw3.pdb`），**无局部变量名与源码行号**；文档以 `Token RID` + 语料行号定位。
2. `Waylith.Rendering.Bc7BlockEncoder` 无法反编译为 C#，仅有 IL 版本（31207 行）；其余 Waylith 类型均为 `.cs`。
3. 断言锚定「语料中的唯一文本片段」；若某片段在文件中重复，会在断言下用 `note:` 标出现次数与所属方法。
4. 需实际运行才能回答的问题（抖动、扫描成本、IMGUI 重入等）在 `HANDOFF.md` 列为 `runtime-only`。

## 声明

### AI 使用声明

- 本项目文档在 **AI 辅助**下完成：卷结构与改写、源码摘录与伪代码、校验脚本的编写均有 AI 参与，由人工确定方向、规则与验收标准。
- 每条结论都以 claim 三行式（`src` / `file` / `match`）锚定反编译语料，并由 `scripts/verify-claims.ps1` 机器核对（当前 451/451 通过）。
- **断言通过只证明「该字符串存在于该文件」**，不等于语义解释必然正确；AI 仍可能误读控制流、遗漏分支或把巧合当因果。
- 阅读与引用时请以源码和脚本为准；发现错误欢迎提 issue 指正。

### 游戏本体声明

- 本仓库**不包含** RimWorld 游戏本体、DLC 数据、反编译语料、美术、音频或任何游戏资源；`RimWorld/` 与 `analysis/decompiled/` 均被 `.gitignore` 排除。
- 复现需要你**自备合法购买的游戏副本**；反编译仅用于互操作性与机制研究，本项目不再分发由此得到的代码。
- 请勿使用本项目获取、传播或再分发游戏资源。

### 使用限制

- 本项目**仅供学习与参考**，禁止基于此进行任何**利益相关行为**（包括但不限于销售、收费、付费课程、商业集成、以本项目内容牟利）。
- 文中观点仅为技术分析，不代表任何组织或厂商立场；RimWorld 的名称、商标与游戏内容归 Ludeon Studios 所有。
- 引用或转载本项目内容时，请保留本声明并注明来源。

## 版权与范围

文档是对运行行为与代码结构的**原创分析**；仓库不含 Ludeon 的游戏代码、资源或数据。复现需要用户自备合法游戏副本。RimWorld 及相关名称归 Ludeon Studios 所有。
