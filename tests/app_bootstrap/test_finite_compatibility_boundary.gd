extends RefCounted
const MainTests = preload("res://tests/app_bootstrap/test_city_bootstrap.gd")
const Finite = preload("res://tests/app/controller_test_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Scope = preload("res://game/app/save_validation_scope.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	var support := MainTests.new()
	var fixture := Finite.new().make(t)
	fixture.app.start_run(713)
	var known: Dictionary = fixture.app.game_save.checkpoint.duplicate(true)
	t.check(Core.new().restore(known).get("ok",false),"known finite fixture is fully validated by unchanged default Core")
	fixture.app.free()
	var boot = support._main(t)
	if boot == null: return
	var directory := support._directory("compatibility_boundary")
	support._enter(t,boot,directory)
	var app = boot.app
	app.ui.run_start_requested.emit()
	var runtime = app._city_runtime
	var scope = Scope.create(runtime,directory,int(app.game_save.store_revision))
	t.check(scope != null,"real current city runtime supports unchanged transaction scope")
	var before: Dictionary = support._directory_bytes(directory)
	var known_source := JSON.stringify(known,"",true,true)
	var direct: Dictionary = runtime.validate_checkpoint(known)
	var scoped: Dictionary = runtime.validate_checkpoint_scoped(known,scope,{"slot":"A"},{})
	t.check(direct.get("ok") == false and direct.get("error_code") == "content_mismatch","only fully known valid finite checkpoint enters existing compatibility barrier")
	t.check(direct == scoped,"known finite classification is identical at direct and scoped entries")
	t.check(JSON.stringify(known,"",true,true) == known_source,"known finite compatibility classification never mutates caller snapshot")
	var samples: Array = []
	var malformed := known.duplicate(true)
	malformed.player.hp = "corrupt"
	samples.append({"name":"malformed finite hp","snapshot":malformed})
	var future := known.duplicate(true)
	future.schema_version = 3
	samples.append({"name":"future finite schema","snapshot":future})
	var fingerprint := known.duplicate(true)
	fingerprint.rules.content_fingerprint = "f".repeat(64)
	samples.append({"name":"unknown finite fingerprint","snapshot":fingerprint})
	var malformed_world := known.duplicate(true)
	malformed_world.world = {}
	samples.append({"name":"present malformed world","snapshot":malformed_world})
	for item in samples:
		var snapshot: Dictionary = item.snapshot
		var original := JSON.stringify(snapshot,"",true,true)
		var baseline: Dictionary = runtime._checkpoint.validate_checkpoint(snapshot)
		var actual: Dictionary = runtime.validate_checkpoint(snapshot)
		var actual_scoped: Dictionary = runtime.validate_checkpoint_scoped(snapshot,scope,{"slot":"A"},{})
		t.check(actual == baseline and actual_scoped == baseline and not actual.get("ok",false),"%s keeps original city-validator failure at both entries" % item.name)
		t.check(JSON.stringify(snapshot,"",true,true) == original,"%s validator leaves caller data unchanged" % item.name)
	var city: Dictionary = app.game_save.checkpoint.duplicate(true)
	var city_baseline: Dictionary = runtime._checkpoint.validate_checkpoint(city)
	var city_actual: Dictionary = runtime.validate_checkpoint(city)
	var city_scoped: Dictionary = runtime.validate_checkpoint_scoped(city,scope,{"slot":"A"},app.game_save)
	t.check(city_actual.get("ok",false) and city_actual == city_baseline and app._same_json(city_scoped,city_baseline),"valid current city passes unchanged direct and scoped world validation")
	t.check(support._directory_bytes(directory) == before,"all finite hostile and current city classification calls perform no save writes")
	scope.close()
	boot.free()
	_hostile_authorities(t,support)
func _hostile_authorities(t,support) -> void:
	var source_fixture := Finite.new().make(t)
	source_fixture.app.start_run(714)
	var original: Dictionary = source_fixture.app.game_save.duplicate(true)
	source_fixture.app.free()
	for kind in ["malformed","future_authority","future_checkpoint"]:
		var hostile := original.duplicate(true)
		if kind == "malformed": hostile.checkpoint.player.hp = "corrupt"
		elif kind == "future_authority": hostile.schema_version = 3
		else: hostile.checkpoint.schema_version = 3
		var directory: String = support._directory(kind)
		var source := JSON.stringify(hostile,"",true,true)
		support._write(directory.path_join("game_save.json"),source)
		support._write(directory.path_join("game_save.json.bak"),source)
		var before: Dictionary = support._directory_bytes(directory)
		var boot = support._main(t)
		if boot == null: return
		support._enter(t,boot,directory)
		t.check(boot.app._startup_view.get("kind") == "blocked" and boot.app.game_save.is_empty() and not Recovery.new()._button_ids(boot.app.ui).has("recovery_start"),"%s is blocked without finite compatibility promotion or reset" % kind)
		t.check(support._directory_bytes(directory) == before,"%s primary backup and full tree remain byte-identical" % kind)
		boot.free()
