# 本轮架构审查概要

## 已完成
- 从当前工作树的源码、`project.godot`、测试与 CI 脚本重新审查 Lantern Tavern。
- 没有使用旧审查报告或项目记忆形成判断。
- Godot 4.7 无头编辑器扫描退出码 0。
- 关键架构测试 8 套件 / 135 用例通过，0 failure、0 orphan；stderr 仍有重复 signal connect 错误。
- 完整报告：`outputs/architecture_review_from_scratch_2026-08-06-1528.md`。

## 关键结论
1. `run_ci.ps1` 在单元测试成功后提前 `exit 0`，真实 ENet 分支永久不可达。
2. Listen 与 Dedicated 两个真实 ENet runner 在 FAIL 后仍无条件 `exit 0`，无法阻断交付。
3. 联机技能只兑现伤害、移动、自 buff，数据中的击退、眩晕、抓取等权威语义未闭环。
4. 联机撤离方法已存在，但生产 multiplayer 场景未发现传送门请求与结算完成的装配调用；现有集成测试直接调用 driver。
5. 当前量化：294 个生产 GDScript、512 个测试 GDScript、33 个 Autoload、195 个文件/源码内容型测试候选。

## 后续优先级
先修 CI/runner 退出码并让真实 ENet 门禁真正执行；再补联机撤离生产接线和技能完整效果事务；随后收紧 SessionRoot service 端口、Autoload 生命周期与巨型脚本边界。
