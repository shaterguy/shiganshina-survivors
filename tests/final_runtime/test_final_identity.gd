extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
const Flow = preload("res://game/app/final_evacuation_flow.gd")
const Faults = preload("res://tests/app_city_controller/test_city_controller_transactions.gd")
func run(t) -> void:
	_contract_boundaries(t)
	_unknown_changed_authority(t)
	_changed_authority_before_selection(t)
func _contract_boundaries(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,384.0])
	var command: Dictionary = Flow.transition_command(app.state)
	var stable: Dictionary = app.state.duplicate(true)
	stable.world.origin_revision += 1
	var current: Dictionary = Flow.transition_command(stable)
	t.check(command.command_id == current.command_id and command.origin_revision != current.origin_revision,"dock command identity is stable while origin stamp follows current geometry")
	var stale: Dictionary = app.simulation._streamed.dock_transition_proposal(stable,command,app.chapter.authored_dock)
	t.check(stale.get("error_code") == "stale_origin_revision","old-origin command cannot transition city geometry")
	var dead: Dictionary = app.state.duplicate(true)
	dead.player.hp = 0
	var refused: Dictionary = Flow.prepare(app.simulation,dead,app.game_save,app.chapter)
	t.check(refused.get("error_code") == "player_dead","dead player cannot receive dock candidate")
	var corrupt: Dictionary = app.state.duplicate(true)
	corrupt.world.dormant.drops.append({"chunk":["0","0"],"record":{"id":900,"position":[384.0,384.0],"xp":1}})
	var preserved: Dictionary = corrupt.duplicate(true)
	refused = Flow.prepare(app.simulation,corrupt,app.game_save,app.chapter)
	t.check(not refused.get("ok",false) and corrupt == preserved,"unrelated dormant XP is rejected rather than erased while final actor parking stays legal")
	app.free()
func _unknown_changed_authority(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,384.0])
	var store := Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return": store.hidden = true; return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.advance_frame(1.0/60.0)
	var a = app.simulation
	var live: Dictionary = app.state.duplicate(true)
	store.hidden = false; store._fault_injector = Callable()
	var changed: Dictionary = store.read_game().game_save
	changed.checkpoint.player.hp = 61.0
	var file := FileAccess.open(f.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(changed,"",true,true)); file.close()
	t.check(not app.resolve_pending_transaction() and app.state == live and app.simulation == a,"unknown final rejects same-revision changed full authority without publishing prepared dock")
	t.check(app._startup_view.get("error_code") == "authority_mismatch" and not app._final_intent.is_empty(),"changed final authority retains original intent until explicit recovery choice")
	app.retry_save_recovery()
	t.check(app._final_intent.is_empty() and app._pending_transaction.is_empty() and app.state.is_empty() and app.pending_checkpoint.player.hp == 61.0,"explicit recovery discards stale final intent and adopts changed checkpoint for separate resume")
	app.request_resume()
	t.check(app.state.world.stage == "dock" and app.state.player.hp == 61.0,"explicit resume uses changed authority's prepared dock instead of old frozen candidate")
	app.free()

func _changed_authority_before_selection(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var other: Dictionary = app.game_save.duplicate(true)
	other.checkpoint.player.hp = 63.0
	var written: Dictionary = app.save_store.commit_game(other,int(other.store_revision))
	t.check(written.get("ok",false),"final selection conflict fixture has a different durable authority")
	app.state.active_tick = 107999; app.state.survival_tick = 107999
	app.state.player.position = [384.0,384.0]
	app.advance_frame(1.0/60.0)
	t.check(app.state.is_empty() and app.pending_checkpoint.player.hp == 63.0 and app._final_intent.is_empty(),"pre-selection authority conflict quarantines old run and requests explicit resume without further scene access")
	app.free()
