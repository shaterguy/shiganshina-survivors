extends SceneTree
# Same harness must run in the approved pre-LOOT baseline and integrated build.
# No Loot preload: absence of the new module on the baseline is intentional.
# Invocation (future approved MANUAL only): --headless --path PROJECT --script
# res://tests/loot/legacy_capture.gd -- --loot-capture-output=user://loot_legacy.json
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/core_fixture.gd")
var failures: Array[String] = []
func _init() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--loot-capture-output="): output = arg.trim_prefix("--loot-capture-output=")
	if output.is_empty():
		push_error("Explicit capture output required")
		quit(2)
		return
	var rows: Array = []
	var sim = Core.new()
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,F.run_config())
	check(not state.has("loot") and not state.run_config.has("loot_rules_version"),"legacy constructor unexpectedly opted in")
	_record(rows,"initial",state,[])
	for i in range(180):
		var move := Vector2.RIGHT if i < 60 else (Vector2.DOWN if i < 120 else Vector2.LEFT)
		var events: Array[Dictionary] = F.step(sim,state,move)
		_record(rows,"move:%d"%i,state,events)
		if i == 89:
			var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
			check(restored.get("ok",false),"legacy checkpoint restore failed")
			if restored.get("ok",false): state = restored.state
	var boss_state: Dictionary = F.evolution_ready_state(sim,F.v2_chapter(),F.run_config(2),42)
	check(not boss_state.is_empty(),"legacy authored boss receipt/offer path failed")
	if not boss_state.is_empty():
		_record(rows,"legacy_boss_offer",boss_state,[])
		var offer: Dictionary = boss_state.upgrade_offer
		var chosen: Dictionary = sim.choose_upgrade(boss_state,offer.offer_id,offer.selected_option_id)
		check(chosen.get("ok",false),"legacy growth choice failed")
		_record(rows,"legacy_boss_choice",boss_state,chosen.get("events",[]))
	var payload := {"format":"loot-legacy-capture-v1","rows":rows,"failures":failures}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("capture_write_failed")
		quit(2)
		return
	file.store_string(JSON.stringify(payload,"\t",true,true)+"\n")
	file.close()
	print("LOOT_LEGACY_CAPTURE "+output+" failures="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _record(rows: Array, label: String, state: Dictionary, events: Array) -> void:
	# Sorted full-precision serialization is the comparison contract for both runs.
	rows.append({"label":label,"state_sha256":JSON.stringify(state,"",true,true).sha256_text(),"events_sha256":JSON.stringify(events,"",true,true).sha256_text(),"rng_state":state.get("rng_state"),"progression_rng_state":state.get("progression_rng_state"),"offer":state.get("upgrade_offer",{}).duplicate(true)})
