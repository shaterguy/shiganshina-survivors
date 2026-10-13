extends RefCounted
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var parsed: Dictionary = JSON.parse_string('{"schema_version":2}')
	var schema = parsed.schema_version
	print("EVOLUTION_SCHEMA_DIAGNOSTIC ",JSON.stringify({"schema":schema,"type":typeof(schema),"membership":schema in [1,2],"number_equality":schema == 2}))
	var current := Catalog.new()
	var legacy_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/run_final_evolution/fixtures/dev4-evolutions.json"))
	var legacy := Catalog.new(null,null,legacy_data)
	print("EVOLUTION_CATALOG_DIAGNOSTIC ",JSON.stringify({"current_base_errors":current._base_errors,"current_recipe_errors":current.evolutions._errors,"legacy_base_errors":legacy._base_errors,"legacy_recipe_errors":legacy.evolutions._errors}))
	t.check(current.validate().is_empty(),"current catalog diagnostic remains a real failing assertion")
	t.check(legacy.validate().is_empty(),"legacy catalog diagnostic remains a real failing assertion")
