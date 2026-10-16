extends RefCounted
const Loot = preload("res://game/loot/loot_rules.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
class ObservedController:
	extends "res://game/app/run_controller.gd"
	var recorded_events: Array = []
	var published_actions: Array = []
	var worker_diagnostics: Array = []
	func _admit_worker_result(result: Dictionary, job: Dictionary) -> String:
		var code: String = super._admit_worker_result(result,job)
		if not code.is_empty():
			var accepted: Dictionary = preload("res://game/app/world_checkpoint_adapter.gd").accept_receipt(job.snapshot.world,result.get("receipt",{}))
			var expected: Dictionary = job.authority.duplicate(true)
			expected.store_revision = int(expected.store_revision)+1
			expected.checkpoint = job.snapshot.duplicate(true)
			if accepted.get("ok",false): expected.checkpoint.world = accepted.world
			for reason in ["background","controller_lost"]: expected.checkpoint.pause_reasons.erase(reason)
			var diagnostic := {"code":code,"receipt_ok":accepted.get("ok",false),"authority_equal":_same_json(expected,result.get("authority",{})),"source_matches":result.get("source_sha256") == JSON.stringify(result.get("authority",{}),"",true,true).sha256_text(),"result":result.duplicate(true),"job":job.duplicate(true),"expected":expected}
			print("ENVELOPE_DETAIL ",diagnostic.receipt_ok," ",diagnostic.authority_equal," ",diagnostic.source_matches)
			worker_diagnostics.append(diagnostic)
			var file := FileAccess.open("user://final-envelope-repro.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(worker_diagnostics,"",true,true)); file.close()
		return code
	func _step_city_tick() -> Dictionary:
		var result: Dictionary = super._step_city_tick()
		if result.get("ok",false): recorded_events.append_array(result.events.duplicate(true))
		return result
	func _publish_transaction(authority: Dictionary, transaction: Dictionary, pair: Dictionary = {}) -> void:
		super._publish_transaction(authority,transaction,pair)
		if game_save == authority: published_actions.append({"action":transaction.action,"tick":state.get("active_tick",-1),"revision":game_save.store_revision})
static func make(t, directory: String = "", worker: bool = true) -> Dictionary:
	if directory.is_empty(): directory = "user://final_runtime_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]
	var app := ObservedController.new()
	app.autosave_worker_enabled = worker
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	t.check(configured.get("ok",false),"final fixture configures actual Controller and city store")
	if not configured.get("ok",false): app.free(); return {}
	t.root.add_child(app)
	app.set_process(false); app.world.set_process(false)
	return {"app":app,"provider":provider,"disk":disk,"runtime":runtime,"directory":directory}
static func boundary(f: Dictionary, position: Array = [384.0,280.0]) -> void:
	f.app.start_run(42)
	f.app.state.active_tick = 107999
	f.app.state.survival_tick = 107999
	f.app.state.world.schema_version = 2
	f.app.state.world.dormant = {"entities":[],"drops":[]}
	f.app.state.player.position = position.duplicate()
	if Loot.enabled(f.app.state):
		for index in range(Loot.FIELD_TICKS.size()):
			f.app.simulation._add_loot(f.app.state,Loot.field_spec(index),Vector2(position[0],position[1]))
	f.app.advance_frame(1.0/60.0)
static func count_events(app, type: String) -> int:
	return app.recorded_events.filter(func(event): return event.type == type).size()
static func count_actions(app, action: String) -> int:
	return app.published_actions.filter(func(entry): return entry.action == action).size()
