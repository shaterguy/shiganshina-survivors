extends RefCounted
# Oracle was produced by the exact original dev4 Core on the approved local
# engine, not by the compatibility implementation under test.
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const ROOT := F.ROOT+"reference_dev4/"
func run(t) -> void:
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"reference_receipt.json"))
	t.check(FileAccess.get_sha256(ROOT+"reference_receipt.json") == "27c4027ce4d5ec8d5fc3a1e10103626316ee2faa2e81fdf5f550c2491a420396" and receipt.core_sha256 == "3a9168d0f03ec87ab4703aeea1f5458df86746c2f11364f28afdc1569b41b7da","dev4 reference receipt binds the original Core and local engine result")
	t.check(receipt.active_positive_control and receipt.terminal_positive_control and receipt.replay_ticks == 12,"original dev4 validated actual active and terminal authorities before replay export")
	for path in receipt.files:
		if path.begins_with("active/"): continue
		t.check(FileAccess.get_sha256(ROOT+path) == receipt.files[path],"recovered dev4 reference bytes: "+path)
	_terminal(t,receipt)
	_replay(t)
func _terminal(t, receipt: Dictionary) -> void:
	var directory := "user://dev5_legacy_original_terminal_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec()]
	for path in receipt.files:
		if path.begins_with("terminal/saves/"):
			F.write(directory.path_join(path.trim_prefix("terminal/saves/")),FileAccess.get_file_as_string(ROOT+path))
	var old := F.legacy_authority(directory)
	var control: Dictionary = old.store.read_game()
	t.check(control.get("ok",false) and control.game_save.checkpoint.phase == "abandoned","original dev4 terminal also passes pinned positive-control restore")
	if not control.get("ok",false): return
	var before := F.bytes(directory)
	var runtime := Runtime.new(F.City.new(),F.Disk.new(directory.path_join("world")))
	var store := F.Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var loaded: Dictionary = store.read_game()
	t.check(loaded.get("ok",false) and F.same(loaded.game_save,control.game_save),"current runtime opens actual original-dev4 terminal and settlement receipt exactly")
	t.check(F.bytes(directory) == before,"actual dev4 terminal read leaves primary backup and pages unchanged")
func _replay(t) -> void:
	var directory := F.install("original_replay")
	var runtime := Runtime.new(F.City.new(),F.Disk.new(directory.path_join("world")))
	var store := F.Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var loaded: Dictionary = store.read_game()
	if not loaded.get("ok",false): return
	var prepared := runtime.prepare_load(loaded.game_save)
	t.check(prepared.get("ok",false),"legacy replay prepares original world pages")
	if not prepared.get("ok",false): return
	var pair := runtime.confirm_candidate(store)
	if not pair.get("ok",false): t.check(false,"legacy replay confirms exact authority"); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"replay.json"))
	t.check(F.same(pair.state,oracle.initial),"legacy replay starts at the exact original dev4 state")
	var commands: Array[Dictionary] = []
	for index in oracle.frames.size():
		var events: Array = pair.simulation.step(pair.state,Vector2.RIGHT,commands)
		t.check(pair.simulation.step_status().get("ok",false) and F.same(pair.state,oracle.frames[index].state) and F.same(events,oracle.frames[index].events),"legacy state and events match original dev4 tick "+str(index+1))
		t.check(not pair.state.has("player_mobility"),"legacy replay never gains current mobility authority")
