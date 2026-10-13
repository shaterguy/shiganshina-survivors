extends SceneTree
# Run only with --path pointing at immutable dev4 b6e471f..., using this script
# by absolute path. All res:// preloads then resolve the original dev4 code.
# Arguments after -- are archived active_save source and a new output directory.
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const FINGERPRINT := "01ad1adb8da30c904fd5feb5d7fb9ce0da0b959d206560d76b382ff1e2b7eae7"
const DEV4_CORE_SHA256 := "3a9168d0f03ec87ab4703aeea1f5458df86746c2f11364f28afdc1569b41b7da"
var errors: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		_finish("expected archived active_save source and new output directory")
		return
	var source: String = args[0]
	var output: String = args[1]
	if FileAccess.get_sha256("res://game/core/run_simulation.gd") != DEV4_CORE_SHA256:
		_finish("reference exporter requires the exact original dev4 Core source")
		return
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		_finish("output must not exist; reference exporter never replaces existing data")
		return
	var provenance_path := source.get_base_dir().path_join("provenance.json")
	var provenance: Variant = JSON.parse_string(FileAccess.get_file_as_string(provenance_path))
	if not provenance is Dictionary or not provenance.get("save_sha256") is Dictionary:
		_finish("missing archived fixture provenance")
		return
	for path in provenance.save_sha256:
		if FileAccess.get_sha256(source.path_join(path)) != provenance.save_sha256[path]:
			_finish("archived fixture bytes changed: "+path)
			return
	for path in provenance.definition_sha256:
		if FileAccess.get_sha256("res://"+path) != provenance.definition_sha256[path]:
			_finish("selected project is not exact dev4 definitions: "+path)
			return
	var provider := City.new()
	var chapter := provider.load_chapter("chapter_01_shiganshina")
	if not chapter.get("ok",false) or chapter.chapter.content_fingerprint != FINGERPRINT:
		_finish("original dev4 provider fingerprint mismatch")
		return
	for label in ["active","terminal"]:
		for path in provenance.save_sha256:
			_write_bytes(output.path_join(label+"/saves/"+path),FileAccess.get_file_as_bytes(source.path_join(path)))
	if not errors.is_empty(): _finish(); return
	var active := _open(output.path_join("active/saves"))
	if not active.get("ok",false): _finish("original dev4 active restore failed: "+str(active)); return
	var pristine: Dictionary = active.pair.state.duplicate(true)
	var frames := []
	var commands: Array[Dictionary] = []
	for tick in 12:
		var events: Array = active.pair.simulation.step(active.pair.state,Vector2.RIGHT,commands)
		if not active.pair.simulation.step_status().get("ok",false):
			_finish("original dev4 reference tick refused")
			return
		frames.append({"state":active.pair.simulation.snapshot(active.pair.state),"events":events.duplicate(true)})
	_write_json(output.path_join("replay.json"),{"input":[1,0],"initial":pristine,"frames":frames})
	var terminal := _open(output.path_join("terminal/saves"))
	if not terminal.get("ok",false): _finish("original dev4 terminal source restore failed: "+str(terminal)); return
	terminal.pair.simulation.abandon_run(terminal.pair.state)
	var service := Service.new(Callable(terminal.runtime,"new_run"))
	var settled := service.prepare_settlement(terminal.pair.game_save,terminal.pair.simulation.snapshot(terminal.pair.state))
	if not settled.get("ok",false): _finish("original dev4 settlement failed: "+str(settled)); return
	var committed: Dictionary = terminal.store.commit_game(settled.candidate,int(terminal.pair.game_save.store_revision))
	if not committed.get("ok",false): _finish("original dev4 terminal commit failed: "+str(committed)); return
	var cold := _open(output.path_join("terminal/saves"))
	if not cold.get("ok",false) or cold.pair.state.phase != "abandoned": _finish("original dev4 cold terminal restore failed"); return
	_write_json(output.path_join("reference_receipt.json"),{"schema_version":1,"source_commit":provenance.source_commit,"content_fingerprint":FINGERPRINT,"engine":Engine.get_version_info().string,"core_sha256":FileAccess.get_sha256("res://game/core/run_simulation.gd"),"active_positive_control":true,"terminal_positive_control":true,"replay_ticks":12,"files":_hashes(output)})
	print("DEV4_REFERENCE_RESULT ok=true active=true terminal=true replay_ticks=12 output="+output)
	quit(0)
func _open(directory: String) -> Dictionary:
	var provider := City.new()
	var runtime := Runtime.new(provider,Disk.new(directory.path_join("world")))
	var store := Store.new(directory,Callable(runtime,"validate_checkpoint"))
	var loaded: Dictionary = store.read_game()
	if not loaded.get("ok",false): return loaded
	var prepared := runtime.prepare_load(loaded.game_save)
	if not prepared.get("ok",false): return prepared
	var pair := runtime.confirm_candidate(store)
	if not pair.get("ok",false): return pair
	return {"ok":true,"runtime":runtime,"store":store,"pair":pair}
func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: errors.append("cannot write "+path); return
	file.store_buffer(bytes)
	file.close()
func _write_json(path: String, value: Dictionary) -> void:
	_write_bytes(path,JSON.stringify(value,"",true,true).to_utf8_buffer())
func _hashes(directory: String, prefix: String = "") -> Dictionary:
	var result := {}
	var dir := DirAccess.open(directory)
	for file in dir.get_files(): result[prefix+file] = FileAccess.get_sha256(directory.path_join(file))
	for child in dir.get_directories(): result.merge(_hashes(directory.path_join(child),prefix+child+"/"))
	return result
func _finish(message: String = "") -> void:
	if not message.is_empty(): errors.append(message)
	for error in errors: push_error("DEV4_REFERENCE_ERROR: "+error)
	quit(1)
