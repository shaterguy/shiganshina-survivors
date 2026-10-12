extends RefCounted
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const F = preload("res://tests/core/core_fixture.gd")
class GuardDisk:
	extends "res://game/persistence/world_delta_store.gd"
	var refused_boundary := ""
	func verify_root(root: Dictionary) -> Dictionary:
		return {"ok":false,"error_code":"world_read_failed"} if refused_boundary == "verify" else super.verify_root(root)
	func hydrate(root: Dictionary, chunks: Array) -> Dictionary:
		return {"ok":false,"error_code":"world_read_failed"} if refused_boundary == "hydrate" else super.hydrate(root,chunks)
class CountingRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	var validation_calls := 0
	func validate_checkpoint(snapshot: Dictionary) -> Dictionary:
		validation_calls += 1
		return super.validate_checkpoint(snapshot)
func run(t) -> void:
	var directory := "/tmp/prepared_validation_reuse_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var disk := GuardDisk.new(directory.path_join("world"))
	var runtime := CountingRuntime.new(provider,disk)
	var store := Store.new(directory,Callable(runtime,"validate_checkpoint"))
	var loaded := store.load_game()
	t.check(loaded.get("ok",false),"reuse real city fixture initializes whole authority")
	if not loaded.get("ok",false): return
	var config := F.run_config()
	config.run_id = loaded.game_save.career_id+":1"
	var state := runtime.new_run(chapter,42,config)
	var staged := disk.prepare(state.world.delta_root,[],0)
	t.check(staged.get("ok",false),"reuse real city fixture publishes durable empty root")
	if not staged.get("ok",false): return
	var save: Dictionary = loaded.game_save.duplicate(true)
	save.next_run_serial = 2
	save.checkpoint = state
	runtime.validation_calls = 0
	var prepared := runtime.prepare_commit(save)
	t.check(prepared.get("ok",false),"reuse prepared private pair still passes full actual Core and world validation")
	t.check(runtime.validation_calls == 1,"reuse adapter preparation validates and normalizes checkpoint once")
	var committed := store.commit_game(save,int(save.store_revision))
	t.check(committed.get("ok",false),"reuse prepared pair commits through actual authority fences")
	if not committed.get("ok",false): return
	var confirmed := runtime.confirm_candidate(store)
	t.check(confirmed.get("ok",false) and confirmed.game_save == committed.game_save,"reuse confirmed pair matches complete persisted canonical authority")
	var invalid := save.duplicate(true)
	invalid.checkpoint.player.radius = 9.0
	t.check(not runtime.prepare_commit(invalid).get("ok",false),"reuse changed checkpoint cannot reuse the prior preparation proof")
	for boundary in ["verify","hydrate"]:
		disk.refused_boundary = boundary
		t.check(runtime.prepare_load(committed.game_save).get("error_code") == "world_read_failed","reuse unchanged checkpoint still performs current "+boundary+" boundary")
	disk.refused_boundary = ""
	var root_hash: String = state.world.delta_root.root_hash
	var root_path := directory.path_join("world/pages").path_join(root_hash.substr(0,2)).path_join(root_hash+".json")
	var file := FileAccess.open(root_path,FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	t.check(not runtime.prepare_load(committed.game_save).get("ok",false),"fresh world boundary rejects poisoned root bytes in the same warmed runtime")
	t.check(not runtime.refresh_coverage(state).get("ok",false),"fresh private pair boundary rejects poisoned root bytes in warmed coverage refresh")
	var cold := Runtime.new(provider,Disk.new(directory.path_join("world")))
	t.check(not cold.prepare_load(committed.game_save).get("ok",false),"reuse cold unchanged checkpoint must detect poisoned root bytes")
