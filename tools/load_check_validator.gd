extends SceneTree

## load_check 的子进程验证器。
## 父进程 tools/load_check.gd 对每个目标脚本 spawn 本脚本；引擎在解析目标及其
## 完整依赖图（含 .tscn 内嵌脚本）时的任何 Compile Error / Parse Error / SCRIPT ERROR
## 都会打印到 stderr，由父进程捕获判定——规避「目标自身 OK、深层依赖编译失败」
## 的假阳性（架构审查 A7）。
## Usage（由父进程调用）：godot --headless --path <proj> --script res://tools/load_check_validator.gd <target_path>

func _init() -> void:
	# --script 之后的目标路径出现在 OS.get_cmdline_args() 末尾（不在 user args 中）。
	var args := OS.get_cmdline_args()
	var target := ""
	if args.size() > 1:
		target = String(args[args.size() - 1])
	if target.is_empty():
		quit(2)
		return
	var res := load(target)
	quit(0 if res != null else 1)
