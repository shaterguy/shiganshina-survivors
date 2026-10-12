extends RefCounted
const Store = preload("res://game/persistence/game_save_store.gd")
const Core = preload("res://game/core/run_simulation.gd")
func run(t) -> void:
	var directory := "user://read_only_store_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec()]
	var validator = Core.new()
	var store = Store.new(directory,Callable(validator,"restore"))
	t.check(store.has_method("read_game"),"Store exposes a mutex-protected existing-authority read without migration")
	if not store.has_method("read_game"): return
	var read: Dictionary = store.read_game()
	t.check(not read.ok and read.error_code == "not_found","read-only Store reports absent authority without initial creation")
	t.check(not FileAccess.file_exists(directory.path_join("game_save.json")),"read-only Store never manufactures a fresh career")
	var loaded: Dictionary = store.load_game()
	t.check(loaded.ok,"explicit initial load remains available for a fresh install")
	read = store.read_game()
	t.check(read.ok and read.game_save.career_id == loaded.game_save.career_id,"read-only Store retrieves the same confirmed initial authority")
