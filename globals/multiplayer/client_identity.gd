extends RefCounted
## ClientIdentity —— 客户端稳定身份的持久化来源（架构审查 P0-1）。
##
## 背景：大厅默认固定 GUID（"host"/"client"）会让多个真实客户端共用同一身份，
## 后加入连接可覆盖服务器 _guid_to_peer 身份索引 → 错误重连接管 / 结算账本串账。
##
## 本模块在客户端首次启动时生成随机 GUID 并持久化到 user://lantern_identity.cfg，
## 之后每次启动复用同一 GUID（跨进程/跨重启稳定，供重连锚定）。禁止任何固定默认值。
##
## 纯逻辑、无场景树依赖；存储路径可用参数覆盖（测试隔离）。

const DEFAULT_STORE_PATH := "user://lantern_identity.cfg"
const KEY := "client_guid"

## 加载或创建本机稳定身份 GUID（首次生成并持久化）。
## store_path 覆盖存储路径（单测隔离）；返回非空 GUID。
static func load_or_create(store_path: String = DEFAULT_STORE_PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(store_path) == OK:
		var existing: String = String(cfg.get_value("identity", KEY, ""))
		if not existing.is_empty():
			return existing
	var guid := generate()
	cfg.set_value("identity", KEY, guid)
	cfg.save(store_path)
	return guid

## 生成随机 GUID（128 位十六进制，本机唯一；不经网络传输，无隐私泄露）。
static func generate() -> String:
	var out := ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(8):
		out += "%08x" % rng.randi()
	return out
