extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	var sim = Fixture.simulation(t)
	var state: Dictionary = sim.new_run(Fixture.chapter(),42,Fixture.run_config())
	state.player.xp = 3
	state.entities = [{"boss_id":"ch01_b05","enemy_id":"boss_charger","hp":750,"max_hp":1000}]
	ui.present(state)
	t.check(ui.has_node("XP"),"HUD shows progress to next growth")
	t.check(ui.has_node("BossHealth"),"HUD shows boss health")
	t.check(ui.has_node("TouchBase") and ui.has_node("TouchKnob"),"touch controls have original raster feedback")
	if ui.has_node("XP"): t.check(ui.get_node("XP").value == 3,"XP follows actual snapshot")
	if ui.has_node("BossHealth"): t.check(ui.get_node("BossHealth").value == 750 and ui.get_node("BossHealth").visible,"boss HP follows actual snapshot")
	t.check(ui._health.position.y+ui._health.size.y < ui._xp.position.y,"health bar cannot bleed behind XP bar")
	ui.free()
