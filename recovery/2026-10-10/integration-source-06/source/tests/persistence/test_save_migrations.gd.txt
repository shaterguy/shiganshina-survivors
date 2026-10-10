extends RefCounted
# NEW E2a pure migration checks. No Core, world, disk authority or archive proof.
const Migrations = preload("res://game/persistence/save_migrations.gd")
const CAREER := "0123456789abcdef0123456789abcdef"
func run(t) -> void:
	print("E2a PURE MIGRATION ONLY: no Core, disk authority or legacy archive proof")
	_preservation_cases(t)
	_default_cases(t)
	_validation_cases(t)
	_preflight_cases(t)
func _profile() -> Dictionary:
	return {"schema_version":1,"settings":{"deadzone":0.25,"audio_master":0.65,"screen_shake":0.0,"reduce_effects":true,"legacy_control":{"layout":"left","buttons":["A","B"]}},"cleared_chapter_ids":["chapter_01_shiganshina","legacy_chapter_02"],"unlocked_character_ids":["garrison_01","legacy_character"],"best_runs":{"chapter_01_shiganshina":{"survival_tick":108000.0,"kills":177,"won":true,"legacy_history":[{"seed":42,"note":"physically escaped"}]},"legacy_chapter_02":{"survival_tick":4800}},"legacy_profile_note":{"revision":"original"}}
func _preservation_cases(t) -> void:
	var input := _profile()
	var before := input.duplicate(true)
	var migration = Migrations.new()
	var result: Dictionary = migration.from_v1(input,true,CAREER)
	t.check(result.get("ok") == true,"E2a supported v1 migrates successfully")
	t.check(input == before,"E2a migration does not mutate v1 input")
	if result.get("ok") != true: return
	var save: Dictionary = result.game_save
	t.check(save.keys().size() == 10,"E2a exact GameSave envelope without invented recovery receipt")
	t.check(save.schema_version == 2 and save.career_id == CAREER,"E2a assigned career identity is preserved")
	t.check(save.store_revision == 0 and save.next_run_serial == 1 and save.settled_through_serial == 0,"E2a only a never-started career can have migrated null checkpoint")
	t.check(save.checkpoint == null and save.legacy_checkpoint_present == true,"E2a legacy presence is metadata, never a playable checkpoint")
	t.check(save.purchase_receipts == [] and save.settlement_receipts == [],"E2a migration invents no receipts or settlement")
	t.check(save.profile.schema_version == 2 and save.profile.supply_credits == 0,"E2a historical performance grants zero backpay")
	t.check(save.profile.owned_doctrine_ids == ["doctrine_standard"] and save.profile.consumables == {"field_bandage":0},"E2a no inferred ownership or consumables")
	t.check(save.profile.loadout == {"doctrine_id":"doctrine_standard","target_evolution_id":"evo_wing_cut","supply_item_id":""},"E2a default loadout is the approved standard wing-cut target")
	for key in ["settings","cleared_chapter_ids","unlocked_character_ids","best_runs","legacy_profile_note"]:
		t.check(save.profile[key] == before[key],"E2a preserves supported v1 " + key)
	t.check(typeof(save.profile.best_runs.chapter_01_shiganshina.survival_tick) == TYPE_FLOAT,"E2a history representations are not silently coerced")
	var repeated: Dictionary = migration.from_v1(input,true,CAREER)
	t.check(repeated == result,"E2a pure migration is deterministic for identical inputs")
	save.profile.settings.legacy_control.buttons.append("X")
	save.profile.best_runs.chapter_01_shiganshina.legacy_history[0].note = "changed"
	save.profile.cleared_chapter_ids.append("changed")
	save.profile.unlocked_character_ids.append("changed")
	save.profile.legacy_profile_note.revision = "changed"
	t.check(input == before,"E2a nested returned migration cannot alias the legacy profile")
	t.check(repeated.game_save.profile == migration.from_v1(input,true,CAREER).game_save.profile,"E2a separate calls do not share mutable output")
	input.best_runs.chapter_01_shiganshina.legacy_history[0].note = "source edit"
	t.check(repeated.game_save.profile.best_runs.chapter_01_shiganshina.legacy_history[0].note == "physically escaped","E2a later source edits cannot mutate prior output")
func _default_cases(t) -> void:
	var input := {"schema_version":1.0,"settings":{},"cleared_chapter_ids":[],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	var before := input.duplicate(true)
	var result: Dictionary = Migrations.new().from_v1(input,false,CAREER)
	t.check(result.get("ok") == true,"E2a integral JSON schema and omitted known settings are supported")
	if result.get("ok") != true: return
	t.check(result.game_save.profile.settings == {"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false},"E2a missing settings use exact preserved SaveStore defaults")
	t.check(not result.game_save.legacy_checkpoint_present,"E2a absent legacy checkpoint flag is preserved")
	t.check(input == before,"E2a adding defaults leaves input untouched")
	for deadzone in [0.10,0.35]:
		var boundary := _profile()
		boundary.settings.deadzone = deadzone
		boundary.settings.audio_master = 0
		boundary.settings.screen_shake = 1
		t.check(Migrations.new().from_v1(boundary,false,CAREER).get("ok") == true,"E2a inclusive setting boundaries migrate")

func _failure(t, value: Variant, legacy: Variant, career: Variant, code: String, label: String) -> void:
	var result: Dictionary = Migrations.new().from_v1(value,legacy,career)
	t.check(result.get("ok") == false and result.get("error_code") == code,"E2a " + label)
	t.check(not result.has("game_save"),"E2a " + label + " emits no fresh authority")
func _validation_cases(t) -> void:
	for schema in [null,false,true,"1",[],{},0,2,99,-1,1.5,INF,-INF,NAN,2147483648]:
		var input := _profile()
		input.schema_version = schema
		_failure(t,input,false,CAREER,"unsupported_schema","unsupported schema fails closed " + str(schema))
	var missing_schema := _profile()
	missing_schema.erase("schema_version")
	_failure(t,missing_schema,false,CAREER,"unsupported_schema","missing schema is not a fresh installation")
	for legacy in [null,0,1,"false",[],{},Vector2.ZERO]:
		_failure(t,_profile(),legacy,CAREER,"invalid_game_save","legacy presence must be a real boolean " + str(legacy))
	for career in [null,0,false,[],{},Vector2.ZERO,"","0123456789abcdef0123456789abcde","0123456789abcdef0123456789abcdef0","ABCDEF0123456789abcdef0123456789","0123456789abcdef0123456789abcdeg","0123456789abcdef0123456789abcde "]:
		_failure(t,_profile(),false,career,"invalid_game_save","career ID must be exactly lowercase hex " + str(career))
	for field in ["deadzone","audio_master","screen_shake"]:
		var bad_values: Array = [null,true,false,"0.2",[],{},Vector2.ZERO,INF,-INF,NAN,-0.001,1.001]
		if field == "deadzone": bad_values.append_array([0.0,0.099999,0.350001,1.0])
		for value in bad_values:
			var input := _profile()
			input.settings[field] = value
			_failure(t,input,false,CAREER,"invalid_profile","invalid present setting " + field + " " + str(value))
	for value in [null,0,1,"true",[],{},Vector2.ZERO]:
		var input := _profile()
		input.settings.reduce_effects = value
		_failure(t,input,false,CAREER,"invalid_profile","reduce_effects cannot be coerced " + str(value))
	for field in ["survival_tick","kills"]:
		for value in [null,true,false,"10",[],{},Vector2.ZERO,INF,-INF,NAN,-1,0.5,2147483648]:
			var input := _profile()
			input.best_runs.chapter_01_shiganshina[field] = value
			_failure(t,input,false,CAREER,"invalid_profile","invalid present history counter " + field + " " + str(value))
	for value in [null,0,1,"true",[],{},Vector2.ZERO]:
		var input := _profile()
		input.best_runs.chapter_01_shiganshina.won = value
		_failure(t,input,false,CAREER,"invalid_profile","history won cannot be coerced " + str(value))
	for value in [null,true,1,"run",[],Vector2.ZERO]:
		var input := _profile()
		input.best_runs.chapter_01_shiganshina = value
		_failure(t,input,false,CAREER,"invalid_profile","malformed best-run record fails closed " + str(value))
	for field in ["cleared_chapter_ids","unlocked_character_ids"]:
		for ids in [[""],["same","same"],[1],[true],[null],[{}],[Vector2.ZERO]]:
			var input := _profile()
			input[field] = ids
			_failure(t,input,false,CAREER,"invalid_profile","malformed unique ID list " + field + " " + str(ids))
	for field in ["supply_credits","owned_doctrine_ids","consumables","loadout"]:
		var input := _profile()
		input[field] = 999
		_failure(t,input,false,CAREER,"invalid_profile","v1 cannot smuggle existing v2 economics " + field)
	var max_history := _profile()
	max_history.best_runs.chapter_01_shiganshina.survival_tick = 2147483647.0
	max_history.best_runs.chapter_01_shiganshina.kills = 2147483647
	t.check(Migrations.new().from_v1(max_history,false,CAREER).get("ok") == true,"E2a valid max history counters migrate without inferred credits")

func _preflight_cases(t) -> void:
	for value in [null,false,true,1,1.0,"profile",[],Vector2.ZERO,Callable()]:
		_failure(t,value,false,CAREER,"invalid_profile","non-dictionary root is rejected before operators " + str(value))
	for field in ["settings","best_runs","cleared_chapter_ids","unlocked_character_ids"]:
		var missing := _profile()
		missing.erase(field)
		_failure(t,missing,false,CAREER,"invalid_profile","missing required v1 field " + field)
		var bad_values: Array = [null,true,1,"container",Vector2.ZERO,Callable()]
		bad_values.append([] if field in ["settings","best_runs"] else {})
		for value in bad_values:
			var input := _profile()
			input[field] = value
			_failure(t,input,false,CAREER,"invalid_profile","required container type " + field + " " + str(value))
	for key in ["",1,true,&"chapter"]:
		var input := _profile()
		input.best_runs[key] = {"survival_tick":10,"kills":1,"won":false}
		_failure(t,input,false,CAREER,"invalid_profile","best-run history has a real nonempty string key " + str(key))
	for unsafe in [Vector2.ZERO,Callable(),PackedStringArray(["not-json-array"]),INF,NAN]:
		var input := _profile()
		input.best_runs.chapter_01_shiganshina.legacy_history.append({"unsupported":unsafe})
		_failure(t,input,false,CAREER,"invalid_profile","unknown history extensions still require JSON-safe values " + str(unsafe))
	for key in [1,true,&"setting"]:
		var input := _profile()
		input.settings[key] = "value"
		_failure(t,input,false,CAREER,"invalid_profile","JSON object keys cannot be coerced " + str(key))
	var deep := _profile()
	var cursor: Dictionary = deep
	for _i in range(66):
		cursor["child"] = {}
		cursor = cursor.child
	_failure(t,deep,false,CAREER,"invalid_profile","over-deep extensions reject before copying")
	var cyclic := _profile()
	cyclic["loop"] = cyclic
	_failure(t,cyclic,false,CAREER,"invalid_profile","cyclic extensions reject without recursive duplication")
	cyclic.erase("loop")
	var wide := _profile()
	var values: Array = []
	values.resize(262144)
	values.fill(null)
	wide["extension"] = values
	_failure(t,wide,false,CAREER,"invalid_profile","profile preflight has a bounded value budget")
	var oversized := _profile()
	oversized["extension"] = "x".repeat(16*1024*1024)
	_failure(t,oversized,false,CAREER,"invalid_profile","oversize serialized profile cannot be migrated")
	var invalid := _profile()
	invalid.best_runs.chapter_01_shiganshina.kills = -1
	var before := invalid.duplicate(true)
	_failure(t,invalid,false,CAREER,"invalid_profile","invalid history is rejected without mutation")
	t.check(invalid == before,"E2a rejected profile remains untouched")
