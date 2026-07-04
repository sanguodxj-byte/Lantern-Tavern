## GdUnit4CSharpApiLoader
##
## Stub — C# is not used in this project. Always returns "not available".
@static_unload
class_name GdUnit4CSharpApiLoader
extends RefCounted


static func is_engine_version_supported(_engine_version: int = 0) -> bool:
	return false


static func is_api_loaded() -> bool:
	return false


static func version() -> String:
	return "unavailable"


static func is_csharp_file(_resource_path: String) -> bool:
	return false


static func discover_tests(_source_script: Script) -> Array:
	return []


static func execute(_tests: Array) -> void:
	pass


static func create_test_suite(_source_path: String, _line_number: int, _test_suite_path: String):
	return GdUnitResult.error("C# not supported in this project.")
