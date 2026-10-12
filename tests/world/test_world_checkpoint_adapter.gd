extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Helpers = preload("res://tests/world/test_world_delta_store.gd")
class TraceStore:
	extends RefCounted
	var events: Array
	func _init(log: Array) -> void: events = log
	func verify_root(_root: Dictionary) -> Dictionary:
		events.append("verify")
		return {"ok":true}
	func hydrate(_root: Dictionary, _chunks: Array) -> Dictionary:
		events.append("hydrate")
		return {"ok":true,"deltas":{"0,0":[]}}
func shape(snapshot: Dictionary) -> Dictionary:
	if not snapshot.get("world") is Dictionary or not snapshot.world.get("dirty_chunks") is Array or not snapshot.world.get("delta_root") is Dictionary: return {"ok":false,"error_code":"invalid_snapshot"}
	return {"ok":true,"chunks":[["0","0"]]}
func restore(snapshot: Dictionary, hydrated: Dictionary) -> Dictionary:
	for props in hydrated.values():
		for prop in props:
			if prop.slot_id != "house_1" or prop.hp > 3 or prop.destroyed != (prop.hp == 0): return {"ok":false,"error_code":"invalid_snapshot"}
	return {"ok":true,"state":snapshot.duplicate(true)}
func world(root: Dictionary, dirty: Array = [], revision: int = 1) -> Dictionary:
	return {"world_revision":revision,"delta_root":root,"dirty_chunks":dirty}
func run(t) -> void:
	var path := "res://game/app/world_checkpoint_adapter.gd"
	t.check(FileAccess.file_exists(path),"world checkpoint adapter exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	if not script.can_instantiate(): return
	var events := []
	var trace := TraceStore.new(events)
	var requirements := func(snapshot):
		events.append("shape")
		return shape(snapshot)
	var core := func(snapshot,hydrated):
		events.append("restore")
		return restore(snapshot,hydrated)
	var adapter = script.new(trace,requirements,core)
	var snapshot := {"world":world(Codec.empty_root())}
	var original := snapshot.duplicate(true)
	t.check(adapter.validate_checkpoint(snapshot).ok and snapshot == original and events == ["shape","verify","hydrate","restore"],"validator order shape verification hydration pure restore; input immutable")
	events.clear()
	t.check(not adapter.validate_checkpoint({}).ok and events == ["shape"],"invalid shallow shape makes no disk calls")
	events.clear()
	var dirty := [Helpers.new().record(0)]
	t.check(not adapter.validate_checkpoint({"world":world(Codec.empty_root(),dirty)}).ok and events == ["shape"],"dirty persisted checkpoint rejected before traversal")
	var helpers := Helpers.new()
	var directory := helpers.directory("adapter")
	var disk := Disk.new(directory.path_join("world"))
	var staged := disk.prepare(Codec.empty_root(),dirty,1)
	t.check(staged.ok,"receipt fixture staged")
	if not staged.ok: return
	var live := world(Codec.empty_root(),dirty)
	var before := live.duplicate(true)
	var json_live: Dictionary = JSON.parse_string(JSON.stringify(live))
	t.check(script.accept_receipt(json_live,staged.receipt).ok,"receipt accepts canonical JSON numeric root revision")
	var json_empty: Dictionary = JSON.parse_string(JSON.stringify(Codec.empty_root()))
	var fresh_json := Disk.new(directory.path_join("json_root"))
	t.check(fresh_json.prepare(json_empty,[],0).ok,"parsed canonical empty root can initialize page store")
	var accepted: Dictionary = script.accept_receipt(live,staged.receipt)
	t.check(accepted.ok and live == before and accepted.world.dirty_chunks.is_empty() and accepted.world.delta_root == staged.receipt.candidate_root,"receipt returns candidate without mutation")
	var changed := live.duplicate(true)
	changed.dirty_chunks[0].props[0].hp = 1
	changed.world_revision += 1
	var later := changed.duplicate(true)
	t.check(not script.accept_receipt(changed,staged.receipt).ok and changed == later,"hit after staging keeps later dirty changes")
	var digest_changed := live.duplicate(true)
	digest_changed.dirty_chunks[0].props[0].hp = 1
	t.check(not script.accept_receipt(digest_changed,staged.receipt).ok,"same-revision changed digest rejects stale receipt")
	t.check(not script.accept_receipt(accepted.world,staged.receipt).ok,"unproven repeated receipt rejected rather than reapplying damage")
	var real = script.new(disk,Callable(self,"shape"),Callable(self,"restore"))
	var fixture := Fixture.new()
	var game_store := Save.new(directory,Callable(real,"validate_checkpoint"))
	# NEW fixture bootstrap: the real Store creates the career authority first.
	# The test-only run factory remains shape-only; it proves no Core semantics.
	var initial: Dictionary = game_store.load_game()
	t.check(initial.ok,"adapter fixture initializes real career authority")
	if not initial.ok: return
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina")
	var service := Service.new(Callable(fixture,"make_run"))
	var started: Dictionary = service.prepare_run_start(initial.game_save,chapter.chapter,7,"start:%s:1" % initial.game_save.career_id,int(initial.game_save.store_revision))
	t.check(started.ok,"adapter fixture creates a legal run-start transition")
	if not started.ok: return
	started.candidate.checkpoint.world = accepted.world
	var committed := game_store.commit_game(started.candidate,int(initial.game_save.store_revision))
	t.check(committed.ok,"existing E commits player and prepared world in one save")
	if not committed.ok: return
	var committed_revision: int = int(committed.game_save.store_revision)
	var later_stage := disk.prepare(accepted.world.delta_root,[helpers.record(0,1)],2)
	t.check(game_store.load_game().game_save == committed.game_save,"durable pages before GameSave commit still restore previous player/world")
	var candidate: Dictionary = committed.game_save.duplicate(true)
	candidate.checkpoint.world = world(later_stage.receipt.candidate_root,[],2)
	candidate.checkpoint.player.hp = 73
	for failure_stage in ["write","flush","verify","backup","replace"]:
		var failing_e := Save.new(directory,Callable(real,"validate_checkpoint"),func(stage): return ERR_CANT_CREATE if stage == failure_stage else OK)
		var failed_e := failing_e.commit_game(candidate,committed_revision)
		t.check(not failed_e.ok and game_store.load_game().game_save == committed.game_save,"E fault retains old whole player/world pair: "+failure_stage)
	var unknown := Save.new(directory,Callable(real,"validate_checkpoint"),func(stage): return ERR_CANT_CREATE if stage == "after_replace_before_return" else OK)
	var result := unknown.commit_game(candidate,committed_revision)
	t.check(not result.ok and result.error_code == "commit_outcome_unknown","existing E uncertain commit remains explicit")
	var loaded := game_store.load_game()
	t.check(loaded.ok and loaded.game_save.store_revision == committed_revision+1 and loaded.game_save.checkpoint.player.hp == 73 and loaded.game_save.checkpoint.world.delta_root.root_hash == candidate.checkpoint.world.delta_root.root_hash,"load reconciliation restores complete new player/world pair")
	var new_hash: String = candidate.checkpoint.world.delta_root.root_hash
	var world_path := directory.path_join("world/pages").path_join(new_hash.substr(0,2)).path_join(new_hash+".json")
	var saved_world_bytes := FileAccess.get_file_as_bytes(world_path)
	var corrupt_world := FileAccess.open(world_path,FileAccess.WRITE)
	corrupt_world.store_string("{}")
	corrupt_world.close()
	var cold_adapter = script.new(Disk.new(directory.path_join("world")),Callable(self,"shape"),Callable(self,"restore"))
	var broken_closure := Save.new(directory,Callable(cold_adapter,"validate_checkpoint")).load_game()
	t.check(broken_closure.ok and broken_closure.recovered and broken_closure.game_save == committed.game_save,"valid primary metadata with broken world closure recovers whole backup")
	var restored_world := FileAccess.open(world_path,FileAccess.WRITE)
	restored_world.store_buffer(saved_world_bytes)
	restored_world.close()
	var primary := directory.path_join("game_save.json")
	var broken := FileAccess.open(primary,FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	var recovered := game_store.load_game()
	t.check(recovered.ok and recovered.recovered and recovered.game_save == committed.game_save,"backup restores complete previous player/world pair")
	# Future world revision must block ordinary backup fallback through E.
	var future: Dictionary = loaded.game_save.duplicate(true)
	future.checkpoint.world.delta_root.format_revision = 2
	var future_file := FileAccess.open(primary,FileAccess.WRITE)
	future_file.store_string(JSON.stringify(future,"",true,true))
	future_file.close()
	var incompatible := game_store.load_game()
	t.check(not incompatible.ok and incompatible.error_code == "unsupported_schema","E preserves future-world compatibility class instead of silently loading older backup")
	var invalid_slots := disk.prepare(Codec.empty_root(),[{"chunk":["0","0"],"props":[{"slot_id":"unknown","hp":99,"destroyed":false}]}],3)
	t.check(not real.validate_checkpoint({"world":world(invalid_slots.receipt.candidate_root)}).ok,"injected immutable catalog validation rejects unknown slots and HP on hydration")
	var summary_disk := Disk.new(directory.path_join("summary"))
	var initial_summary := summary_disk.prepare(Codec.empty_root(),[helpers.record(0)],1)
	var actual_written: int = summary_disk.diagnostics().pages_written
	var retry_summary := summary_disk.prepare(Codec.empty_root(),[helpers.record(0)],1)
	t.check(initial_summary.get("write_summary",{}) == {"page_write_calls":1,"sequence_digest":"ae358b06a3c8ac3583fad7efea11652b4c707e6ca90b841c717ec5cf91cc78a9"} and retry_summary.get("write_summary",{}) == initial_summary.get("write_summary",{}) and not retry_summary.has("written_hashes"),"store forwards complete bounded index write summary")
	t.check(summary_disk.diagnostics().pages_written == actual_written,"reused write callback summary is not a count of unique newly stored pages")
	helpers.remove_fixture(directory)
