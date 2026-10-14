extends RefCounted
const Controller = preload("res://game/app/run_controller.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Motion = preload("res://game/core/player_mobility.gd")
const LegacyFixture = preload("res://tests/terrain_mobility/motion_fixture.gd")
const CorridorFixture = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const CAREER := "0123456789abcdef0123456789abcdef"
static func same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true)) == JSON.parse_string(JSON.stringify(b,"",true,true))
static func packet(phase: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_"+phase+".json"))
static func seed_save(t, snapshot: Dictionary, provider, label: String, envelope: Dictionary = {}) -> Dictionary:
	var directory := "user://corridor_save_%d_%d_%s/saves" % [OS.get_process_id(),Time.get_ticks_usec(),label]
	var disk = Disk.new(directory.path_join("world"))
	var runtime = Runtime.new(provider,disk)
	var store = Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var initial: Dictionary = store.initialize_game({},CAREER)
	t.check(initial.get("ok",false),"save fixture initializes isolated authority: "+label)
	if not initial.get("ok",false): return {}
	var staged: Dictionary = disk.prepare(snapshot.world.delta_root,[],int(snapshot.world.world_revision))
	t.check(staged.get("ok",false),"save fixture persists genuine world root: "+label)
	if not staged.get("ok",false): return {}
	var raw: Dictionary = initial.game_save.duplicate(true) if envelope.is_empty() else envelope.duplicate(true)
	raw.next_run_serial = 2
	raw.checkpoint = snapshot.duplicate(true)
	# Nonzero envelope sentinels are test data, not claims of natural earning.
	# The genuine legacy motion/geometry/clock/RNG bytes are left untouched.
	raw.profile.supply_credits = 431
	var text := JSON.stringify(raw,"  ",true,true)+"\n"
	var path := directory.path_join("game_save.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text); file.close()
	return {"directory":directory,"disk":disk,"runtime":runtime,"store":store,"provider":provider,"raw":raw,"text":text,"path":path,"sha256":text.sha256_text()}
static func controller(t, f: Dictionary, asynchronous := false):
	var provider = City.new() if asynchronous else f.provider
	var disk = Disk.new(f.directory.path_join("world"))
	var runtime = Runtime.new(provider,disk)
	var app = Controller.new()
	app.autosave_worker_enabled = asynchronous
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,f.directory)
	t.check(configured.get("ok",false),"cold save controller configures actual runtime")
	if not configured.get("ok",false): app.free(); return null
	t.root.add_child(app)
	app.set_process(false); app.world.set_process(false)
	return app
static func drain(t, app) -> void:
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread == null,"real default autosave worker reaches its terminal result")
static func assert_migration(t, before: Dictionary, after: Dictionary, core, label: String) -> void:
	t.check(after.player_mobility.schema_version == 2 and after.player_mobility.phase == "ground",label+": migration grounds version-one motion before resume")
	t.check(after.player.velocity == [0.0,0.0],label+": migration clears velocity")
	var safe: Dictionary = core._streamed.walkable(Vector2(after.player.position[0],after.player.position[1]),8.0)
	t.check(safe.get("ok",false) and safe.get("walkable",false),label+": migrated position has ordinary ground clearance")
	var sample: Dictionary = Motion.visual_sample(after)
	t.check(is_zero_approx(float(sample.get("height",-1))) and sample.get("roof_prop_id","").is_empty(),label+": migrated presentation has no roof height or depth owner")
	for field in ["cast_id","started_tick","cooldown_until","roll","hit_ids"]:
		t.check(same(before.player_mobility[field],after.player_mobility[field]),label+": migration preserves mobility "+field)
	var old := before.duplicate(true)
	var current := after.duplicate(true)
	for value in [old,current]:
		value.erase("player_mobility")
		value.player.erase("position")
		value.player.erase("velocity")
	t.check(same(old,current),label+": migration preserves all other state including stats, clocks, RNG, combat and economy inputs")
