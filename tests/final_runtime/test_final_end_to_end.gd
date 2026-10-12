extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t, worker: bool = true) -> void:
	var f := S.make(t,"",worker)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f)
	t.check(app.state.phase == "evacuation" and app.state.active_tick == 108000 and app.state.world.stage == "city","real Director boundary enters final while outside passage")
	t.check(S.count_actions(app,"passage_selection") == 1 and app.game_save.checkpoint.world.evacuation == app.state.world.evacuation,"passage selection commits exactly once through product Controller")
	var final_actor_id = app.state.entities[0].id
	var selected: Dictionary = app.state.world.evacuation.duplicate(true)
	var before_motion: int = app.state.active_tick
	app.input_router.set_touch_vector(Vector2.DOWN)
	for frame in 180:
		app.advance_frame(1.0/60.0)
		if app.state.world.stage == "dock": break
	t.check(app.state.world.stage == "dock" and app.state.active_tick > before_motion and S.count_actions(app,"dock_transition") == 1,"real movement into selected passage commits one dock transition")
	if app.state.world.stage != "dock": app.free(); return
	t.check(app.state.final_started_tick == 108000 and app.state.world.evacuation.selected_tick == selected.selected_tick and app.state.player.position == [0.0,0.0],"dock changes no final clock and entry is exact authored point")
	t.check(app.state.world.dormant == {"entities":[],"drops":[]} and app.game_save.checkpoint.world == app.state.world,"dock transition durably keeps world-v2 dormant empty")
	var saved: Dictionary = app.game_save.duplicate(true)
	var cold := S.make(t,f.directory,worker)
	t.check(cold.app.state.is_empty() and cold.app.pending_checkpoint.world.stage == "dock","cold startup offers the actual durable dock checkpoint")
	cold.app.request_resume()
	t.check(cold.app.state.world.stage == "dock" and cold.app.state.active_tick == saved.checkpoint.active_tick and cold.app.simulation._streamed.readiness(cold.app.state).ok,"cold resume adopts matching dock Core at original tick")
	cold.app.free()
	# Use the original prepared Controller after proving read-only cold restore.
	# The cold resume may have written a byte-identical checkpoint revision;
	# reload that authority without replacing original live simulation.
	var disk_authority: Dictionary = app.save_store.read_game()
	app._install_authority(disk_authority.game_save)
	var start_hp: float = app.state.player.max_hp
	var early_exit_checked := false
	var paused_checked := false
	var guard := 0
	while int(app.state.active_tick)-108000 < 4500 and app.state.phase == "evacuation" and guard < 4600:
		guard += 1
		# This is a timer/route/store fixture, not a combat balance/survival test.
		app.state.player.hp = start_hp
		var age: int = int(app.state.active_tick)-108000
		if age < 500:
			app.input_router.set_touch_vector(Vector2.DOWN if app.state.player.position[1] < 348 else Vector2.ZERO)
		else:
			app.input_router.set_touch_vector(Vector2.UP if app.state.player.position[1] > 0 else Vector2.ZERO)
		if age == 400:
			early_exit_checked = app.state.player.position[1] >= 320 and app.state.phase == "evacuation" and not app.state.evacuation_ready
		if age == 900 and not paused_checked:
			app._latch_lifecycle_pause("controller_lost")
			var paused_tick: int = app.state.active_tick
			for frame in 8: app.advance_frame(1.0/60.0)
			t.check(app.state.active_tick == paused_tick,"lifecycle pause consumes no survival ticks in final dock")
			app.request_resume()
			paused_checked = true
		app.advance_frame(1.0/60.0)
		if app._worker_reserved():
			# An actual background save remains single-writer; no duplicate final
			# scenario action is allowed while waiting for its durable ack.
			await t.process_frame
	print("FINAL_LOOP ",JSON.stringify({"guard":guard,"tick":app.state.get("active_tick"),"phase":app.state.get("phase"),"position":app.state.get("player",{}).get("position"),"pause":app.state.get("pause_reasons"),"worker":app._autosave_blocker,"intent":app._autosave_intent,"final_error":app._final_error,"startup":app._startup_view,"pending":not app._pending_transaction.is_empty()}))
	t.check(early_exit_checked,"physical dock exit before 75 seconds cannot win")
	t.check(guard < 4600 and app.state.active_tick == 112500 and app.state.evacuation_ready and app.state.phase == "evacuation","4500 actual final ticks alone cannot win outside physical exit")
	t.check(S.count_events(app,"boss_spawned") == 1 and S.count_events(app,"phase_changed") == 1 and S.count_events(app,"run_ended") == 0,"final threat/phase events are not replayed by passage dock or autosaves")
	app.input_router.set_touch_vector(Vector2.DOWN)
	for frame in 300:
		app.state.player.hp = start_hp
		app.advance_frame(1.0/60.0)
		if app._worker_reserved(): await t.process_frame
		if app.state.phase == "won": break
	for frame in 1000:
		if int(app.game_save.settled_through_serial) == 1: break
		await t.process_frame
		app.advance_frame(0)
	t.check(app.state.phase == "won" and app.state.player.position[1] >= 320 and S.count_events(app,"run_ended") == 1,"actual post-deadline movement into physical exit emits one win")
	t.check(int(app.game_save.settled_through_serial) == 1 and app.game_save.settlement_receipts.size() == 1 and S.count_actions(app,"settlement") == 1,"actual win commits existing SupplyService settlement once")
	t.check(app.state.entities.size() == 1 and app.state.entities[0].id == final_actor_id and app.state.entities[0].enemy_id == "armored_titan" and app.state.entities[0].hp == app.state.entities[0].max_hp,"all4500 actual ticks and physical exit preserve one invulnerable final actor")
	var final_authority: Dictionary = app.game_save.duplicate(true)
	app._record_result(); app.advance_frame(1.0/60.0)
	t.check(app.game_save == final_authority,"terminal replay cannot award or save settlement twice")
	app.free()
	var complete := S.make(t,f.directory,worker)
	t.check(complete.app.state.get("phase") == "won" and complete.app.game_save == final_authority and complete.app.simulation._streamed.readiness(complete.app.state).ok,"cold terminal reload confirms full won authority and dock geometry")
	complete.app.free()
