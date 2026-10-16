extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var ui := UI.new()
	t.root.add_child(ui)
	ui.set_process(false)
	var sim = F.simulation(t)
	if sim == null: ui.free(); return
	var config: Dictionary = F.run_config()
	config.loot_rules_version = 1
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	ui.present(state)
	var count: int = ui.get_child_count()
	var id: int = ui._loot_hud.get_instance_id()
	ui.consume_loot_events([_xp(state.run_id,1,9),_xp(state.run_id,2,10)],state.run_id)
	ui.present(state)
	t.check(ui._loot_hud.visible and ui._loot_hud.text == "획득 골드 0 · +19 XP","LOOT UI presents coalesced real XP amounts")
	ui.consume_loot_events([_xp(state.run_id,2,10)],state.run_id)
	t.check(ui._xp_feedback_amount == 19,"LOOT UI replayed event cannot inflate feedback")
	ui.consume_loot_events([_xp("unrelated",999,180),_xp(state.run_id,3,80)],state.run_id)
	t.check(ui._xp_feedback_amount == 99,"LOOT UI ignores foreign run and coalesces next pickup")
	ui._process(0.8)
	ui.present(state)
	t.check(ui._loot_hud.text == "획득 골드 0","LOOT UI feedback expires in bounded time")
	ui.consume_loot_events([_xp(state.run_id,4,2147483647),_xp(state.run_id,5,1)],state.run_id)
	t.check(ui._xp_feedback_amount == 2147483647,"LOOT UI aggregate is bounded")
	for i in range(100):
		ui.consume_loot_events([_xp(state.run_id,6+i,4)],state.run_id)
		ui.present(state)
	t.check(ui.get_child_count() == count and ui._loot_hud.get_instance_id() == id,"LOOT UI repeated pickups reuse one fixed HUD node")
	var legacy: Dictionary = sim.new_run(F.v2_chapter(),42,F.run_config())
	legacy.run_id = "legacy-ui-run"
	ui.present(legacy)
	t.check(ui._xp_feedback_seconds == 0 and ui._xp_feedback_amount == 0 and ui._loot_hud.text.is_empty(),"LOOT UI new authority clears old XP and does not invent legacy gold")
	ui.free()
func _xp(run_id: String, serial: int, amount: int) -> Dictionary:
	return {"event_id":run_id+":"+str(serial),"type":"xp_gained","payload":{"amount":amount}}
