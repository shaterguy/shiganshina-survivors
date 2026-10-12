extends RefCounted
# Product regression: real default Controller + Core + stores, no worker opt-in.
const Controller = preload("res://game/app/run_controller.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
func run(t) -> void:
	var available: bool = await _default_save(t)
	# The RED baseline lacks the worker API. Default-save assertions remain
	# behavioral failures rather than script errors in that baseline.
	if not available: return
	await _retained_growth(t)
	await _schema_two_ack(t)
	await t.create_timer(1.0).timeout
func _fixture(t,label: String):
	var directory := "user://async_product_%d_%d_%s/saves" % [OS.get_process_id(),Time.get_ticks_usec(),label]
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var initialized: Dictionary = Save.new(directory,Callable(runtime,"validate_checkpoint")).initialize_game({},"0123456789abcdef0123456789abcdef")
	t.check(initialized.get("ok",false),"async product fixture initializes "+label)
	if not initialized.get("ok",false): return null
	var app := Controller.new()
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	t.check(configured.get("ok",false),"async product fixture configures current city "+label)
	if not configured.get("ok",false): app.free(); return null
	t.root.add_child(app)
	app.set_process(false); app.world.set_process(false)
	app.start_run(42)
	t.check(not app.state.is_empty(),"async product fixture starts real city "+label)
	if app.state.is_empty(): app.free(); return null
	return app
func _drain(t,app) -> void:
	if not app.has_method("_poll_autosave_worker"): return
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread == null,"default worker resolves within test observation window")
func _default_save(t) -> bool:
	var app = _fixture(t,"default")
	if app == null: return false
	var core = app.simulation
	var before: int = app.game_save.store_revision
	var snapshot: Dictionary = app.state.duplicate(true)
	app._save_checkpoint()
	t.check(app.game_save.store_revision == before,"default city save returns before durable revision adoption")
	t.check(app.simulation == core,"default city save submission preserves live Core")
	await _drain(t,app)
	t.check(app.game_save.store_revision == before+1,"default city save confirms exactly one durable revision")
	t.check(app.simulation == core and app.state == snapshot,"default city completion preserves full live Core and state")
	var available: bool = app.has_method("_poll_autosave_worker")
	app.free()
	return available
func _retained_growth(t) -> void:
	var app = _fixture(t,"growth")
	if app == null: return
	app.state.player.xp = int(app.state.rules.progression.base_xp)
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(not app.state.upgrade_offer.is_empty(),"default worker growth fixture opens actual Core offer")
	if app.state.upgrade_offer.is_empty(): app.free(); return
	var offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	var revision: int = app.game_save.store_revision
	app._save_checkpoint()
	# Complete the predecessor without polling it: this is a deterministic
	# postcommit reservation, without depending on injected delays or faults.
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and app._autosave_thread.is_alive() and Time.get_ticks_usec() < deadline:
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread != null and not app._autosave_thread.is_alive(),"growth input targets a completed unadopted worker")
	if app._autosave_thread == null or app._autosave_thread.is_alive(): app.free(); return
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(app.state.upgrade_offer.offer_id == offer.offer_id,"accepted growth choice does not mutate under writer reservation")
	await _drain(t,app)
	t.check(app._autosave_intent.is_empty() and app._failed_growth.is_empty() and app.state.upgrade_offer.is_empty(),"retained growth choice completes without a second user action")
	t.check(app.game_save.store_revision == revision+2,"duplicate pending growth input commits exactly once after predecessor")
	var saved: Dictionary = app.game_save.duplicate(true)
	for i in 4: app.advance_frame(0)
	t.check(app.game_save == saved and app._autosave_pending.is_empty(),"late autosave cannot overwrite confirmed growth")
	app.free()
func _schema_two_ack(t) -> void:
	var app = _fixture(t,"schema_two")
	if app == null: return
	app.state.player.position = [384.0,384.0]
	app.state.player.attack_ready_ticks = {"blade_slash":1000000}
	app.state.active_tick = 17999; app.state.survival_tick = 17999
	app.state.drops = [{"id":100,"position":[-1152.0,384.0],"xp":7}]
	app.state.next_entity_id = 101
	var command := {"command_id":"async-product-far-boss","kind":"spawn_boss","origin_revision":0,"payload":{"entity_id":"async-product-far-boss","enemy_id":"boss_charger","boss_id":"ch01_b05","position":[-1154.0,384.0],"scheduled_tick":18000}}
	var commands: Array[Dictionary] = [command]
	var needed: Dictionary = Helper.requirements(app.state,commands)
	t.check(needed.get("ok",false),"schema2 product fixture has bounded verified requirements")
	if not needed.get("ok",false): app.free(); return
	var hydrated: Dictionary = app._world_delta_store.hydrate(app.state.world.delta_root,needed.chunks)
	t.check(hydrated.get("ok",false),"schema2 product fixture hydrates exact root")
	if not hydrated.get("ok",false): app.free(); return
	var prepared: Dictionary = app.simulation.prepare_world(app.state,hydrated.deltas,commands)
	t.check(prepared.get("ok",false),"schema2 worker fixture prepares real parked population")
	if not prepared.get("ok",false): app.free(); return
	app.simulation.step(app.state,Vector2.ZERO,commands)
	commands.clear(); app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.state.world.schema_version == 2 and app.state.world.dormant.entities.size() == 1 and app.state.world.dormant.drops.size() == 1,"real Core parks boss and XP into schema2")
	var helper = app.simulation._streamed
	var target := {}
	for prop in helper._world.localized_chunk("0,0").props:
		if prop.destructible and not prop.destroyed: target = prop; break
	t.check(not target.is_empty(),"schema2 dirty ack uses a real destructible city prop")
	if target.is_empty(): app.free(); return
	var tick: int = app.state.active_tick
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"async-product-damage","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":tick,"expires_tick":tick,"structure_damage":1}
	var damage: Dictionary = helper.destruction_proposal(app.state,attack,{"prop_id":target.prop_id,"reached":true,"tick":tick,"fraction":1.0})
	t.check(damage.get("ok",false),"schema2 Core proposes actual structural damage")
	if not damage.get("ok",false): app.free(); return
	app.state.world = damage.world
	t.check(helper._world.apply_props(app.state.world.dirty_chunks,int(app.state.world.world_revision)).get("ok",false),"schema2 physical damage is installed")
	helper._remember_identity(app.state)
	var dormant := var_to_bytes(app.state.world.dormant)
	var core = app.simulation
	var revision: int = app.game_save.store_revision
	app._save_checkpoint(); await _drain(t,app)
	t.check(app.game_save.store_revision == revision+1 and app.state.world.dirty_chunks.is_empty(),"schema2 async save commits and clears only acknowledged dirty metadata")
	t.check(app.simulation == core and helper.matches(app.state) and helper.readiness(app.state).get("ok",false),"schema2 ack preserves current geometry identity and Core")
	t.check(var_to_bytes(app.state.world.dormant) == dormant,"schema2 ack preserves every parked boss and XP record")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick+1 and app.simulation == core and app._city_render_error.is_empty(),"next real schema2 tick needs no repair or Core replacement")
	app.free()
