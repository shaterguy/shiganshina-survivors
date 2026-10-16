extends RefCounted
const Support = preload("res://tests/loot_city/loot_city_support.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
var support := Support.new()
func run(t) -> void:
	var app = support.make(t,"potion_rebase")
	if app == null: return
	var chest := support.field(t,app)
	if chest.is_empty() or not support.collect(t,app,chest.id): app.free();return
	t.check(app.state.loot.potions.size() == 1 and app.state.loot.potions[0].status == "placed","POTION rebase starts from actual full-HP bottle")
	var expected: Dictionary = app.state.loot.duplicate(true)
	var old_local: Vector2 = Loot.local_position(app.state,app.state.loot.potions[0]).position
	app.state.player.position = [1152.0,384.0]
	if not support.refresh(t,app,"potion rebase window"): app.free();return
	var old_origin: Array = app.state.world.origin_chunk.duplicate()
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation.step_status().get("ok",false) and app.state.world.origin_chunk != old_origin,"POTION actual Core step rebases origin")
	t.check(support.same(app.state.loot,expected),"POTION rebase preserves bottle and parent ledger exactly")
	var localized := Loot.local_position(app.state,app.state.loot.potions[0])
	t.check(localized.get("ok",false) and localized.position.distance_to(old_local-Vector2(768,0)) < 0.001,"POTION stable address shifts local position exactly once")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(app.state,"",true,true))
	var prepared: Dictionary = app._city_runtime.refresh_coverage(decoded)
	t.check(prepared.get("ok",false) and support.same(prepared.get("state",{}).get("loot",{}),expected),"POTION post-rebase precise JSON cold restore retains address and status")
	if not prepared.get("ok",false): app.free();return
	app._adopt_city_simulation(prepared.simulation);app.state = prepared.state
	app.state.player.position = [localized.position.x,localized.position.y]
	app.state.player.hp -= 7.0
	if not support.refresh(t,app,"potion return to old address"): app.free();return
	var events: Array[Dictionary] = []
	app.simulation._collect_potions(app.state,events)
	t.check(app.state.loot.potions[0].status == "claimed" and app.state.loot.potions[0].healed_amount == 7.0,"POTION rehydrated original address remains collectible exactly once")
	app.free()
	await t.create_timer(0.3).timeout
