extends GdUnitTestSuite

# A6 regression test: tests/gdunit4_runner.gd must pre-validate '-a' paths so a
# typo'd / empty test path exits non-zero instead of gdUnit4 exiting 0 with
# "No test cases found".
const RUNNER_SCRIPT := "res://tests/gdunit4_runner.gd"
const MISSING_PATH := "res://tests/gdunit/__missing_architecture_review__.gd"
const VALID_TEST := "res://tests/gdunit/project_bootstrap_test.gd"
const VALID_DIR := "res://tests/gdunit/"
const NON_TEST_SCRIPT := "res://tests/gdunit4_runner.gd"


func _runner() -> GDScript:
	return load(RUNNER_SCRIPT)


## Converts an untyped literal into a typed Array[String] so the dynamic call
## through the GDScript base passes the typed-array runtime check.
func _args(values: Array) -> Array[String]:
	var typed: Array[String] = []
	for value in values:
		typed.append(str(value))
	return typed


func _validate(values: Array) -> Array[String]:
	return _runner().validate_paths(_args(values))


func test_missing_path_returns_error() -> void:
	assert_array(_validate(["-a", MISSING_PATH])).has_size(1)


func test_valid_test_file_returns_no_error() -> void:
	assert_array(_validate(["-a", VALID_TEST])).is_empty()


func test_valid_test_directory_returns_no_error() -> void:
	assert_array(_validate(["-a", VALID_DIR])).is_empty()


func test_relative_path_is_supported() -> void:
	assert_array(_validate(["-a", "tests/gdunit/project_bootstrap_test.gd"])).is_empty()


func test_non_test_script_file_returns_error() -> void:
	# Exists as a file but is not a GdUnit test suite -> zero cases -> must fail.
	assert_array(_validate(["-a", NON_TEST_SCRIPT])).has_size(1)


func test_empty_directory_returns_error() -> void:
	var empty_dir := "res://tests/gdunit/__runner_validation_tmp__"
	var fs_dir := ProjectSettings.globalize_path(empty_dir)
	assert_int(DirAccess.make_dir_recursive_absolute(fs_dir)).is_equal(OK)
	var errors := _validate(["-a", empty_dir])
	assert_array(errors).has_size(1)
	assert_int(DirAccess.remove_absolute(fs_dir)).is_equal(OK)


func test_missing_value_after_a_returns_error() -> void:
	assert_array(_validate(["-a"])).has_size(1)


func test_non_test_arguments_are_ignored() -> void:
	assert_array(_validate(["--ignoreHeadlessMode", "-a", VALID_TEST])).is_empty()
