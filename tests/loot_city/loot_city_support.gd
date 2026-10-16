extends RefCounted
# Test-only support. Uses the real Controller, Core, city generator and stores.
# Encounter clocks/positions are arranged; no natural-duration/device claim.
const Controller = preload("res://game/app/run_controller.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")

func make(t, label: String):
	var directory := "user://loot_city_%d_%d_%s/saves" % [OS.get_process_id(),Time.get_ticks_usec(),label]
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var initialized: Dictionary = Save.new(directory,Callable(runtime,"validate_checkpoint")).initialize_game({},"0123456789abcdef0123456789abcdef")
	t.check(initialized.get("ok",false),"LOOT CITY private authority initializes: "+label)
	if not initialized.get("ok",false): return null
	var app = _open(t,provider,runtime,disk,directory,label)
	if app == null: return null
	app.start_run(42)
	t.check(not app.state.is_empty(),"LOOT CITY actual Controller starts new run: "+label)
	if app.state.is_empty(): app.free(); return null
	t.check(app.state.get("run_config",{}).get("loot_rules_version") == 1 and app.state.get("loot",{}) == Loot.initial(),"LOOT CITY new-run marker and empty ledger: "+label)
	t.check(app.game_save.checkpoint.get("run_config",{}).get("loot_rules_version") == 1,"LOOT CITY new-run marker is durably committed: "+label)
	if not Loot.enabled(app.state): app.free(); return null
	app.state.player.position = [384.0,384.0]
	if not refresh(t,app,"reserved street "+label): app.free(); return null
	return app

func _open(t, provider, runtime, disk, directory: String, label: String):
	var app := Controller.new()
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	t.check(configured.get("ok",false),"LOOT CITY actual runtime configures: "+label)
	if not configured.get("ok",false): app.free(); return null
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	t.check(app.autosave_worker_enabled,"LOOT CITY default async worker remains enabled: "+label)
	return app

func refresh(t, app, label: String) -> bool:
	var prepared: Dictionary = app._city_runtime.refresh_coverage(app.state)
	t.check(prepared.get("ok",false),"LOOT CITY real resident preparation: "+label+" "+str(prepared.get("error_code","")))
	if not prepared.get("ok",false): return false
	app._adopt_city_simulation(prepared.simulation)
	app.state = prepared.state
	return true

func finished_unpolled(t, app, label: String) -> bool:
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and app._autosave_thread.is_alive() and Time.get_ticks_usec() < deadline:
		await t.create_timer(0.003).timeout
	var ready: bool = app._autosave_thread != null and not app._autosave_thread.is_alive()
	t.check(ready,"LOOT CITY real worker completes before adoption: "+label)
	return ready

func drain(t, app, label: String) -> bool:
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	var done: bool = app._autosave_thread == null
	t.check(done,"LOOT CITY worker resolves within observation deadline: "+label)
	return done

func field(t, app, index: int = 0) -> Dictionary:
	app.state.active_tick = Loot.FIELD_TICKS[index]
	app.state.survival_tick = Loot.FIELD_TICKS[index]
	var events: Array[Dictionary] = []
	app.simulation._update_loot(app.state,events)
	var chest := Loot.find_chest(app.state,Loot.chest_id(app.state.run_id,"field",str(Loot.FIELD_TICKS[index])))
	t.check(not chest.is_empty() and chest.status == "placed","LOOT CITY real resident field placement: "+str(index))
	return chest

func collect(t, app, chest_id: String) -> bool:
	var chest := Loot.find_chest(app.state,chest_id)
	var local := Loot.local_position(app.state,chest)
	t.check(local.get("ok",false),"LOOT CITY collection localizes stable address")
	if not local.get("ok",false): return false
	# Move the fixture player to the actual generated placement, never the chest.
	app.state.player.position = [local.position.x,local.position.y]
	if not refresh(t,app,"collect generated placement"): return false
	var events: Array[Dictionary] = []
	app.simulation._update_loot(app.state,events)
	var count := 0
	for event in events:
		if event.type == "loot_collected" and event.get("payload",{}).get("chest_id") == chest_id: count += 1
	t.check(count == 1,"LOOT CITY generated chest emits one pickup event")
	return true

func boss_offer(t, app) -> Dictionary:
	app.state.active_tick = 18000
	app.state.survival_tick = 18000
	var command := {"command_id":"loot-city:boss:ch01_b05","kind":"spawn_boss","origin_revision":int(app.state.world.origin_revision),"payload":{"entity_id":"loot-city:boss","enemy_id":"boss_charger","boss_id":"ch01_b05","position":[448.0,384.0],"scheduled_tick":18000}}
	var events: Array[Dictionary] = []
	app.simulation._apply_command(app.state,command,events)
	t.check(app.state.entities.size() == 1,"LOOT CITY actual Core admits authored boss")
	if app.state.entities.size() != 1: return {}
	var entity: Dictionary = app.state.entities[0]
	var rewards: Array[Dictionary] = []
	app.simulation._hit_entity(app.state,entity,float(entity.hp),"blade_slash",events,rewards)
	app.simulation._remove_dead(app.state)
	t.check(rewards.size() == 1,"LOOT CITY real lethal hit yields one boss reward")
	if rewards.size() != 1: return {}
	app.simulation._claim_boss_reward(app.state,rewards[0],events)
	app.simulation._update_loot(app.state,events)
	var id := Loot.chest_id(app.state.run_id,"boss","ch01_b05")
	var chest := Loot.find_chest(app.state,id)
	t.check(not chest.is_empty() and chest.status == "placed","LOOT CITY real boss death location places chest")
	if chest.is_empty() or chest.status != "placed": return {}
	if not collect(t,app,id): return {}
	t.check(app.simulation._activate_next_offer(app.state,events),"LOOT CITY boss pickup activates actual growth offer")
	var offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	t.check(offer.get("source") == "chest" and offer.get("chest_id") == id,"LOOT CITY actual offer binds boss chest")
	return offer if offer.get("source") == "chest" else {}

func cold_read(t, app, expected: Dictionary, label: String) -> Dictionary:
	# Fresh provider/runtime/Core and Store, not the writer's cached validator.
	var directory: String = app.save_store._directory
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var store := Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var observed: Dictionary = store.read_game()
	t.check(observed.get("ok",false) and not observed.get("recovered",false),"LOOT CITY fresh Store reads primary authority: "+label)
	if not observed.get("ok",false): return {}
	t.check(same(observed.game_save.checkpoint.loot,expected),"LOOT CITY durable loot equals expected ledger: "+label)
	t.check(observed.get("source_sha256") == FileAccess.get_sha256(directory.path_join("game_save.json")),"LOOT CITY readback SHA binds primary bytes: "+label)
	var prepared: Dictionary = runtime.prepare_load(observed.game_save)
	t.check(prepared.get("ok",false),"LOOT CITY fresh resident cold preparation: "+label)
	if not prepared.get("ok",false): return {}
	var confirmed: Dictionary = runtime.confirm_candidate(store)
	t.check(confirmed.get("ok",false),"LOOT CITY exact cold authority confirmation: "+label)
	if confirmed.get("ok",false): t.check(same(confirmed.state.loot,expected),"LOOT CITY fresh Core preserves loot: "+label)
	return confirmed

func reopen(t, directory: String, expected: Dictionary, expected_revision: int):
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var app = _open(t,provider,runtime,disk,directory,"cold Controller")
	if app == null: return null
	t.check(app.game_save.get("store_revision") == expected_revision and same(app.pending_checkpoint.get("loot",{}),expected),"LOOT CITY cold Controller offers exact durable loot checkpoint")
	app.request_resume()
	t.check(not app.state.is_empty() and same(app.state.get("loot",{}),expected),"LOOT CITY actual Continue adopts expected loot")
	await drain(t,app,"cold Continue checkpoint")
	return app

func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left,"",true,true)) == JSON.parse_string(JSON.stringify(right,"",true,true))

func ten_placed_chests(t, app) -> bool:
	# Optional shared fixed-workload arrangement; not invoked by this suite.
	# Five real authored spawn/death reward paths plus all five due field sources.
	# It deliberately jumps the clocks, suppresses Director/combat ticks, and keeps
	# the player on the reserved street. It is NOT a natural 27-minute encounter.
	if app.state.loot.chests.size() != 0 or not app.state.entities.is_empty():
		t.check(false,"LOOT TEN requires untouched private city fixture")
		return false
	var anchors := [Vector2(448,384),Vector2(320,384),Vector2(384,448),Vector2(384,320),Vector2(448,448)]
	var events: Array[Dictionary] = []
	for i in range(5):
		var authored: Dictionary = app.chapter.boss_schedule[i]
		app.state.active_tick = int(authored.tick)
		app.state.survival_tick = int(authored.tick)
		var command := {"command_id":"loot-ten:boss:"+str(i),"kind":"spawn_boss","origin_revision":int(app.state.world.origin_revision),"payload":{"entity_id":"loot-ten:boss:"+str(i),"enemy_id":authored.enemy_id,"boss_id":authored.boss_id,"position":[anchors[i].x,anchors[i].y],"scheduled_tick":int(authored.tick)}}
		app.simulation._apply_command(app.state,command,events)
		t.check(app.state.entities.size() == 1,"LOOT TEN actual authored boss admitted: "+str(i))
		if app.state.entities.size() != 1: return false
		var entity: Dictionary = app.state.entities[0]
		var rewards: Array[Dictionary] = []
		app.simulation._hit_entity(app.state,entity,float(entity.hp),"blade_slash",events,rewards)
		app.simulation._remove_dead(app.state)
		t.check(rewards.size() == 1,"LOOT TEN actual lethal boss reward: "+str(i))
		if rewards.size() != 1: return false
		app.simulation._claim_boss_reward(app.state,rewards[0],events)
	app.state.active_tick = 97200
	app.state.survival_tick = 97200
	for attempt in range(10):
		app.simulation._update_loot(app.state,events)
		var placed := 0
		for chest in app.state.loot.chests:
			if chest.status == "placed": placed += 1
		if placed == 10: break
		app.state.active_tick += Loot.PLACEMENT_RETRY_TICKS
		app.state.survival_tick += Loot.PLACEMENT_RETRY_TICKS
	var count := 0
	for chest in app.state.loot.chests:
		if chest.status == "placed": count += 1
	t.check(app.state.loot.chests.size() == 10 and count == 10 and app.state.upgrade_offer.is_empty() and app.state.pending_offers.is_empty(),"LOOT TEN all real sources placed without forced status/address")
	if count != 10: return false
	t.check(Loot.validate(app.state),"LOOT TEN complete source ledger validates")
	return refresh(t,app,"ten placed real sources cold validation")
