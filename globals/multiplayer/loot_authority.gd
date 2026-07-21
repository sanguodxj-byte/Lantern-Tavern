extends RefCounted
## LootAuthority（docs/25 §5.2 / §8.3 / §9.2）—— 服务器端掉落裁决。
## 仅服务器调用；客户端绝不决定掉落内容（§5.1）。
##
## 纯逻辑、可用种子化 RNG 单测。掉落表格式：
##   {"goblin_tooth": {"kind":"material","weight":10,"min":1,"max":3}, ...}
##
## roll_loot(table, rng, max_items) -> Dictionary(id -> amount)
##
## 设计要点：同一个 id 可能在一次抽取中多次出现，按 amount 累加；
## rng 由调用方 seed，便于确定性测试与（未来）可重连的掉落回放。

## 加权抽取 max_items 个条目。rng 必须已 seed（调用方负责）。
func roll_loot(table: Dictionary, rng: RandomNumberGenerator, max_items: int = 4) -> Dictionary:
	var out: Dictionary = {}
	if table.is_empty() or rng == null or max_items <= 0:
		return out
	var entries: Array = []
	var total_weight: float = 0.0
	for id in table.keys():
		var spec: Dictionary = table[id]
		var w: float = float(spec.get("weight", 0))
		if w <= 0.0:
			continue
		entries.append({"id": id, "weight": w, "min": int(spec.get("min", 1)), "max": int(spec.get("max", 1))})
		total_weight += w
	if entries.is_empty():
		return out
	for _i in range(max_items):
		var roll: float = rng.randf() * total_weight
		var acc: float = 0.0
		for e in entries:
			acc += e["weight"]
			if roll <= acc:
				var amt: int = rng.randi_range(e["min"], e["max"])
				var id: String = e["id"]
				out[id] = int(out.get(id, 0)) + amt
				break
	return out
