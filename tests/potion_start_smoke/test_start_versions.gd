extends RefCounted
const Matrix = preload("res://tests/loot/test_loot_store.gd")
const Support = preload("res://tests/loot_city/loot_city_support.gd")
func run(t) -> void:
	# Fail early at the real Store boundary before any long city/capture suite.
	for version in [1,2]:
		var matrix := Matrix.new()
		matrix._version = version
		var prepared: Dictionary = matrix._prepare(t,"early_smoke")
		t.check(not prepared.is_empty(),"POTION real Store accepts exact v%d initial ledger" % version)
	var app = Support.new().make(t,"early_start_smoke")
	t.check(app != null,"POTION real city Controller starts and commits v2")
	if app != null: app.free()
