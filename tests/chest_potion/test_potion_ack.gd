extends RefCounted
const Support = preload("res://tests/loot_city/loot_city_support.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
var support := Support.new()
func run(t) -> void:
	await _late_ack(t)
	await _unknown_ack(t)
	await t.create_timer(0.3).timeout
func _opened(t,label: String):
	var app = support.make(t,"potion_"+label)
	if app == null: return null
	var chest := support.field(t,app)
	if chest.is_empty() or not support.collect(t,app,chest.id): app.free();return null
	t.check(app.state.loot.potions.size() == 1 and app.state.loot.potions[0].status == "placed","POTION ACK full HP keeps actual field bottle")
	return app
func _heal(t,app) -> void:
	app.state.player.hp = float(app.state.player.max_hp)-7.0
	var events: Array[Dictionary] = []
	app.simulation._collect_potions(app.state,events)
	t.check(app.state.loot.potions[0].status == "claimed" and app.state.loot.potions[0].healed_amount == 7.0 and app.state.player.hp == app.state.player.max_hp,"POTION ACK real resident Core applies seven HP once")
func _late_ack(t) -> void:
	var app = _opened(t,"late")
	if app == null: return
	var placed: Dictionary = app.state.loot.duplicate(true)
	app._save_checkpoint()
	if not await support.finished_unpolled(t,app,"potion predecessor"): app.free();return
	_heal(t,app)
	var live: Dictionary = app.state.duplicate(true)
	if not await support.drain(t,app,"potion older ACK"): app.free();return
	t.check(support.same(app.game_save.checkpoint.loot,placed) and app.state == live,"POTION ACK old placed save never rewinds live healing")
	app._save_checkpoint()
	if not await support.drain(t,app,"potion latest claim"): app.free();return
	support.cold_read(t,app,live.loot,"potion claimed")
	var directory: String = app.save_store._directory
	var revision: int = app.game_save.store_revision
	app.free()
	var cold = await support.reopen(t,directory,live.loot,revision)
	if cold == null: return
	cold.state.player.hp -= 30.0
	var hp: float = cold.state.player.hp
	var events: Array[Dictionary] = []
	cold.simulation._collect_potions(cold.state,events)
	t.check(cold.state.player.hp == hp and events.is_empty(),"POTION ACK actual cold Continue cannot consume bottle twice")
	cold.free()
func _unknown_ack(t) -> void:
	var app = _opened(t,"unknown")
	if app == null: return
	_heal(t,app)
	var live: Dictionary = app.state.duplicate(true)
	var revision: int = app.game_save.store_revision
	app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint()
	if not await support.drain(t,app,"potion unknown ACK"): app.free();return
	t.check(not app._autosave_unknown.is_empty() and app.game_save.store_revision == revision and app.state == live,"POTION unknown ACK keeps live heal and unconfirmed durable revision")
	support.cold_read(t,app,live.loot,"potion unknown replaced save")
	var path: String = app.save_store._directory.path_join("game_save.json")
	var committed := FileAccess.get_sha256(path)
	app.autosave_test_fault = {}
	app.retry_save_recovery()
	if not await support.drain(t,app,"potion recovery"): app.free();return
	t.check(app._autosave_unknown.is_empty() and app.game_save.store_revision == revision+1 and app.state == live,"POTION readback reconciles one revision without replay")
	app.retry_save_recovery()
	for index in 4: app.advance_frame(0)
	t.check(FileAccess.get_sha256(path) == committed and app.state == live,"POTION duplicate recovery leaves exact bytes and HP unchanged")
	app.free()
