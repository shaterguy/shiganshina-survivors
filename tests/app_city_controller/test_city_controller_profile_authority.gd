extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Faults = preload("res://tests/app_city_controller/test_city_controller_transactions.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	var different: Dictionary = app.game_save.duplicate(true)
	different.store_revision += 1
	different.profile.settings.reduce_effects = true
	var store := Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hidden = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.start_run(42)
	t.check(not app._pending_transaction.is_empty(),"profile-only conflict fixture begins with actual uncertain city start")
	store.hidden = false
	store._fault_injector = Callable()
	var file := FileAccess.open(f.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(different,"",true,true)); file.close()
	t.check(store.read_game().get("ok",false),"changed profile-only authority is a valid real Store envelope")
	app.resolve_pending_transaction()
	app.retry_save_recovery()
	t.check(app._pending_transaction.is_empty() and app.state.is_empty() and app.pending_checkpoint.is_empty() and app.profile.settings.reduce_effects,"explicit changed profile-only choice clears old run intent without fabricating a checkpoint")
	app.start_run(43)
	t.check(not app.state.is_empty() and app.state.seed == 43 and app.state.run_serial == 1,"profile-only choice permits explicitly requested new city run without a permanent lock")
	app.free()
	_readback_change(t,false)
	_readback_change(t,true)

class SwappingStore:
	extends "res://game/persistence/game_save_store.gd"
	var replacement := ""
	var reads := 0
	func read_game() -> Dictionary:
		var result := super.read_game()
		reads += 1
		if reads == 1 and not replacement.is_empty():
			var file := FileAccess.open(_directory.path_join("game_save.json"),FileAccess.WRITE)
			file.store_string(replacement); file.close()
		return result
func _readback_change(t, bytes_only: bool) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	var original: Dictionary = app.game_save.duplicate(true)
	var chosen := original.duplicate(true)
	chosen.store_revision += 1
	chosen.profile.settings.reduce_effects = true
	var hidden := Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	hidden._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			hidden.hidden = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = hidden
	app.start_run(42)
	hidden.hidden = false
	hidden._fault_injector = Callable()
	var source := JSON.stringify(chosen,"",true,true)
	var file := FileAccess.open(f.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(source); file.close()
	app.resolve_pending_transaction()
	var store := SwappingStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	chosen.profile.settings.audio_master = 0.4
	store.replacement = source+" " if bytes_only else JSON.stringify(chosen,"",true,true)
	app.save_store = store
	app.retry_save_recovery()
	t.check(store.reads == 2 and app.game_save == original and not app._pending_transaction.is_empty() and app._startup_view.get("error_code") == "authority_mismatch","profile-only choice rejects changed "+("source bytes" if bytes_only else "full authority")+" between explicit readbacks")
	t.check(FileAccess.get_file_as_string(f.directory.path_join("game_save.json")) == store.replacement,"profile-only readback refusal never overwrites externally changed authority")
	app.retry_save_recovery()
	t.check(app._pending_transaction.is_empty() and app.game_save.checkpoint == null and app.profile.settings.reduce_effects,"later explicit retry may confirm stable changed profile without permanent lock")
	app.free()
