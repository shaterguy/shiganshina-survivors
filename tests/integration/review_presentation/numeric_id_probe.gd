extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Catalog = preload("res://game/director/chapter_catalog.gd")
const Save = preload("res://game/persistence/save_store.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NUMERIC_ID_FAIL "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sim := Sim.new()
	var chapter: Dictionary = Catalog.new().load_chapter("chapter_01_shiganshina").chapter
	var state: Dictionary = sim.new_run(chapter,67)
	sim.step(state,Vector2.ZERO,[{"command_id":"actor","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":"runner","position":[160.0,0.0]}}])
	var raw: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
	var normalized := raw.duplicate(true)
	sim._normalize_saved_numbers(normalized)
	var store := Save.new("user://review_numeric_id_"+str(OS.get_process_id()))
	var saved: Dictionary = store.save_checkpoint(state)
	var original := sim.restore(state)
	var result := sim.restore(raw)
	var normalized_result := sim.restore(normalized)
	print("NUMERIC_ID_DIAG ",JSON.stringify({"action":state.entities[0].action_state,"original_error":original.get("error_code",""),"original_errors":original.get("errors",[]),"json_bad":bad_json(state),"core_original":sim._core_payload_valid(state),"behavior_original":sim._behavior_state_valid(state,state.entities[0]),"owned_original":sim._owned_behavior_hazards_valid(state),"original_ok":original.ok,"roundtrip_ok":result.ok,"roundtrip_error":result.get("error_code",""),"runtime_id_string":str(state.entities[0].id),"parsed_id_string":str(raw.entities[0].id),"source_id":raw.telegraphs[0].source_id,"normalized_ok":normalized_result.ok,"save_result":saved}))
	check(original.ok,"runtime-generated behavior snapshot restores")
	check(result.ok and result.get("state",{}) == state,"numeric actor JSON restores exactly")
	check(saved.ok,"runtime-generated behavior checkpoint writes")
	var loaded: Dictionary = store.load_checkpoint()
	check(loaded.ok and loaded.get("snapshot",{}) == state,"behavior checkpoint reloads exactly")
	for kind in ["actor_id","hazard_id","clock","next_entity_id"]:
		var corrupted := raw.duplicate(true)
		match kind:
			"actor_id": corrupted.entities[0].id = 1.5
			"hazard_id": corrupted.telegraphs[0].id = 2.5
			"clock": corrupted.active_tick = 1.5
			"next_entity_id": corrupted.next_entity_id = 3.5
		var before := corrupted.duplicate(true)
		check(not sim.restore(corrupted).ok and corrupted == before,"fractional "+kind+" rejected without mutation")
	print("NUMERIC_ID_REVIEW checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func bad_json(v: Variant,p := "root") -> Array:
	var out: Array = []
	if v is Dictionary:
		for k in v:
			if not k is String: out.append(p+" key "+str(k)+" type="+str(typeof(k)))
			out.append_array(bad_json(v[k],p+"."+str(k)))
	elif v is Array:
		for i in v.size(): out.append_array(bad_json(v[i],p+"["+str(i)+"]"))
	elif not (v == null or v is String or v is bool or v is int or v is float): out.append(p+" type="+str(typeof(v))+" value="+str(v))
	return out
