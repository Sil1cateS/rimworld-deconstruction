# v1 归档说明（冻结）

`docs/mechanisms/` 是项目第一轮交付的 24 卷机制文档（6286 行 / 621 条断言 / 55 张图）。

- **状态：冻结**，不再修改，保留作为历史基线与对照。
- 当前版本在 `docs/mechanisms-v3/`，覆盖同样的 24 个主题，按七节骨架重写。
- v1 的断言编号（如 `V01-C07`）与 v3 同名卷**不一一对应**；跨版本引用时请注明版本。

校验命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\lint-docs.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-claims.ps1
```
