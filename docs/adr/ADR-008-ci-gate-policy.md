# ADR-008: CI 门禁策略（orphan 与测试退出码）

- 状态：**Accepted（已实施，2026-08-03）**
- 关联：架构审查 P2-5（orphan 101 无条件转绿）、P2-3（解析门禁）、基线阶段 D

## 背景

`run_ci.ps1` 曾把 gdUnit4 的 orphan 泄漏退出码 101 无条件转 GREEN；`tools/load_check.gd` 曾把依赖编译错误误报为成功。

## 决策

1. **orphan 门禁分档**：
   - 默认模式：101 = YELLOW（warn，退出 0）——兼容存量渲染类泄漏套件；
   - `-FailOnOrphan` 严格模式：101 = RED（退出 1）——新测试/干净基线必须使用；
   - 存量泄漏套件由 `tools/run_all_gdunit_batched.ps1` 逐套件识别（PASS_ORPHAN 分类），不隐藏计数。
2. **解析门禁**：`tools/load_check.gd` 增加 GDScript 源码真实性校验（source_code 非空 + can_instantiate），编译失败以退出码 1 结束；`-s` 模式缺 autoload 属工具环境限制，完整解析门禁以编辑器扫描 + 退出码为准。
3. **报告隔离**：并行批次经 `run_all_gdunit_batched.ps1` 逐套件独立输出 + `merge_gdunit_results.ps1` 归并（PASS_ORPHAN/FAIL/CRASH/TIMEOUT 分类），不再共享报告目录。
4. **门禁基线**：审查相关套件必须 0 assertion failure、0 orphan、退出 0（当前 23+ 套件满足）。
5. **测试行为化硬规则（2026-08-03 架构检查补充）**：新测试禁止用 `source_code`/`get_file_as_string` 字符串断言证明行为（允许少量禁止模式扫描）；存量源码字符串断言（243 文件）随功能改动渐进转换，不安排独立重构迭代。

## 后果

- 新引入的泄漏立刻可见（严格模式）；存量债不隐藏但可追溯。
- CI 的"通过"含义分层：GREEN（全绿）/ YELLOW（仅存量 orphan）/ RED（断言/脚本/预设失败）。
