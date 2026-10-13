extends RefCounted
# Exact archived dev4 checkpoint/definitions, copied only into unique test dirs.
# Economic values below are explicit test arrangements, not historical receipts.
const ROOT := "res://tests/dev5_legacy_compatibility/fixtures/"
const FINGERPRINT := "01ad1adb8da30c904fd5feb5d7fb9ce0da0b959d206560d76b382ff1e2b7eae7"
const Chapters = preload("res://game/director/chapter_catalog.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
class PinnedProvider:
	extends RefCounted
	var _chapter: Dictionary
	func _init(chapter: Dictionary) -> void: _chapter = chapter.duplicate(true)
	func load_chapter(id: String) -> Dictionary:
		return {"ok":true,"chapter":_chapter.duplicate(true)} if id == Chapters.CHAPTER_ID else {"ok":false,"error_code":"unknown_chapter"}
	func rules_version() -> String: return "dev4"
static func provenance() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOT+"provenance.json"))
static func inputs() -> Dictionary:
	var result := {}
	for path in provenance().definition_sha256:
		result[path] = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"inputs/"+path))
	return result
static func legacy_core():
	var definitions := inputs()
	var base := {}
	for path in Chapters.PATHS: base[path] = definitions[path]
	var loaded := Chapters.new().from_definitions(Chapters.CHAPTER_ID,base)
	if not loaded.get("ok",false): return null
	var city := City.new().from_definitions(loaded.chapter,definitions["chapters/chapter_01/city_templates.json"],definitions["data/world_props.json"],definitions["assets/manifest.json"],definitions["chapters/chapter_01/authored_dock.json"])
	if not city.get("ok",false): return null
	return Core.new(PinnedProvider.new(city.chapter),null,definitions)
static func install(label: String) -> String:
	var directory := "user://dev5_legacy_%s_%d_%d/saves" % [label,OS.get_process_id(),Time.get_ticks_usec()]
	for path in provenance().save_sha256:
		write(directory.path_join(path),FileAccess.get_file_as_string(ROOT+"active_save/"+path))
	return directory
static func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
static func bytes(directory: String) -> Dictionary:
	var result := {}
	var dir := DirAccess.open(directory)
	if dir == null: return result
	for name in dir.get_files(): result[name] = FileAccess.get_file_as_bytes(directory.path_join(name))
	for name in dir.get_directories(): result[name+"/"] = bytes(directory.path_join(name))
	return result
static func legacy_authority(directory: String) -> Dictionary:
	var core = legacy_core()
	if core == null: return {}
	var disk := Disk.new(directory.path_join("world"))
	var adapter := Adapter.new(disk,Callable(Helper,"requirements"),Callable(core,"restore"))
	var store := Save.new(directory,Callable(adapter,"validate_checkpoint"))
	return {"core":core,"disk":disk,"adapter":adapter,"store":store}
static func enrich(directory: String) -> Dictionary:
	var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("game_save.json")))
	save.profile.supply_credits = 137
	save.profile.permanent_upgrades = {"permanent_might":1,"permanent_vitality":2}
	save.profile.cleared_chapter_ids = [Chapters.CHAPTER_ID]
	save.profile.unlocked_character_ids = ["garrison_01","mikasa_01"]
	save.profile.selected_character_id = "mikasa_01"
	save.purchase_receipts = [{"request_id":"purchase:%s:0:permanent_might" % save.career_id,"item_id":"permanent_might","expected_revision":0,"price":20,"balance_after":137,"owned_after":1}]
	write(directory.path_join("game_save.json"),JSON.stringify(save,"",true,true))
	return save
static func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true)) == JSON.parse_string(JSON.stringify(b,"",true,true))
