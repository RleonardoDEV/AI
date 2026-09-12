extends Node
## Headless test runner.
##
##   godot --headless res://tests/test_runner.tscn
##   godot --headless res://tests/test_runner.tscn -- only=genetics
##
## Exits with code 1 if anything failed, so it can gate a build.

const SUITES: Array = [
	["genetics", "res://tests/test_genetics.gd"],
	["world", "res://tests/test_world.gd"],
	["creatures", "res://tests/test_creatures.gd"],
	["ecology", "res://tests/test_ecology.gd"],
	["simulation", "res://tests/test_simulation.gd"],
]

func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	var kit := TestKit.new()
	var total_tests := 0
	var t_start := Time.get_ticks_msec()
	print("PIXEL WORLD test suite")
	print("")

	for suite in SUITES:
		var suite_name: String = suite[0]
		if only != "" and only != suite_name:
			continue
		var script: GDScript = load(suite[1])
		var instance = script.new()
		var methods: Array = []
		for m in instance.get_method_list():
			var n: String = m["name"]
			if n.begins_with("test_"):
				methods.append(n)
		methods.sort()
		print("  %s (%d tests)" % [suite_name, methods.size()])
		for m in methods:
			kit.current = "%s/%s" % [suite_name, m]
			var before := kit.failures.size()
			var t0 := Time.get_ticks_msec()
			instance.call(m, kit)
			var dt := Time.get_ticks_msec() - t0
			total_tests += 1
			var failed := kit.failures.size() - before
			var mark := "ok  " if failed == 0 else "FAIL"
			print("    [%s] %-52s %5d ms" % [mark, m.substr(5), dt])
			if failed > 0:
				for i in range(before, kit.failures.size()):
					print("           - %s" % kit.failures[i])
		print("")

	var wall := Time.get_ticks_msec() - t_start
	print("--------------------------------------------------------------")
	print("%d tests, %d assertions, %d failures, %.1f s" % [
		total_tests, kit.checks, kit.failures.size(), float(wall) / 1000.0])
	if kit.failures.is_empty():
		print("ALL TESTS PASSED")
	else:
		print("FAILURES:")
		for f in kit.failures:
			print("  - %s" % f)
	# Godot's exit code lets CI gate on the result.
	get_tree().quit(0 if kit.failures.is_empty() else 1)
