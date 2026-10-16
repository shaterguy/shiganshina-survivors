extends RefCounted
# Real final-flow/Store transactions; clocks and boss receipt arranged explicitly.
const S = preload("res://tests/final_runtime/final_support.gd")
const Faults = preload("res://tests/app_city_controller/test_city_controller_transactions.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
func run(t) -> void:
	_case(t,false)
	_case(t,true)
func _case(t, unknown: bool) -> void:
	var f: Dictionary = S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	t.check(app.state.has("loot"),"LOOT dock actual new run opts in")
	if not app.state.has("loot"): app.free(); return
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	app.state.player.position = [384.0,384.0]
	app.state.boss_ids_fired.append("ch01_b05")
	app.state.stats.kills = 1
	var events: Array[Dictionary] = []
	app.simulation._claim_boss_reward(app.state,{"boss_id":"ch01_b05","entity_id":"loot-dock-boss","position":[684.0,384.0]},events)
	app.simulation._update_loot(app.state,events)
	var id: String = Loot.chest_id(app.state.run_id,"boss","ch01_b05")
	var prepared: Dictionary = f.runtime.refresh_coverage(app.state)
	t.check(prepared.get("ok",false),"LOOT dock real world refresh admits arranged boss source")
	if not prepared.get("ok",false): app.free(); return
	app.simulation = prepared.simulation; app.state = prepared.state
	app.advance_frame(1.0/60.0)
	t.check(app.state.phase == "evacuation" and S.count_actions(app,"passage_selection") == 1,"LOOT dock real final boundary selects passage")
	var before: Dictionary = app.state.duplicate(true)
	var original: Dictionary = Loot.find_chest(before,id)
	t.check(not original.is_empty() and original.status in ["pending","placed"],"LOOT dock boss remains uncollected before transfer")
	if original.is_empty() or not original.status in ["pending","placed"]: app.free(); return
	var old_authority: Dictionary = app.game_save.duplicate(true)
	var hidden = null
	if unknown:
		hidden = Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
		hidden._fault_injector = func(stage):
			if stage == "after_replace_before_return": hidden.hidden = true; return ERR_CANT_CREATE
			return OK
		app.save_store = hidden
	else:
		app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "replace" else OK
	app.advance_frame(1.0/60.0)
	t.check(not app._final_intent.is_empty() and app._final_intent.action == "dock_transition","LOOT dock failed ACK retains exact transition intent")
	if app._final_intent.is_empty(): app.free(); return
	var proposed: Dictionary = app._final_intent.candidate.checkpoint
	var boss: Dictionary = Loot.find_chest(proposed,id)
	t.check(boss.id == id and boss.stage == "dock" and boss.status == "pending","LOOT dock proposal transfers same boss ID pending")
	t.check(proposed.loot.chests.filter(func(c): return c.source == "field" and c.status == "expired").size() == 5,"LOOT dock proposal expires all five unclaimed field chests")
	t.check(app.state.world.stage == "city" and app.game_save == old_authority and Loot.find_chest(app.state,id).stage == "city","LOOT dock unconfirmed ACK preserves live city chest and authority")
	var disk_before: PackedByteArray = FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.retry_save_recovery()
	t.check(FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == disk_before,"LOOT dock blocked retry does not write a duplicate transition")
	if unknown:
		hidden.hidden = false; hidden._fault_injector = Callable()
		t.check(app.resolve_pending_transaction(),"LOOT dock unknown ACK resolves from actual readback")
	else:
		app.save_store._fault_injector = Callable(); app.retry_save_recovery()
	t.check(app._final_intent.is_empty() and app.state.world.stage == "dock" and S.count_actions(app,"dock_transition") == 1,"LOOT dock transition confirms once")
	t.check(Loot.find_chest(app.state,id).id == id and Loot.find_chest(app.state,id).status == "pending","LOOT dock confirmed state retains unclaimed boss identity")
	var loaded: Dictionary = app.save_store.load_game()
	t.check(loaded.get("ok",false) and app._same_json(loaded.game_save.checkpoint.loot,app.game_save.checkpoint.loot),"LOOT dock actual cold Store readback retains exact loot")
	var revision: int = app.game_save.store_revision
	app.retry_save_recovery()
	t.check(app.game_save.store_revision == revision and S.count_actions(app,"dock_transition") == 1,"LOOT dock postconfirm retry cannot repeat transition")
	app.free()
