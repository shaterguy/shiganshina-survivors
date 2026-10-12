extends RefCounted
const S = preload("res://tests/app/controller_test_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
func run(t) -> void:
	for role in ["grabber","quadruped","stone_thrower"]: _city_controller(t,role)
	for role in ["grabber","quadruped","stone_thrower"]:
		var fixture: Dictionary = S.new().make(t)
		var app = fixture.app
		app.start_run(42)
		app.state.player.attack_ready_ticks.blade_slash = 1000
		F.step(app.simulation,app.state,Vector2.ZERO,[G.spawn(77,[140.0,0.0] if role != "stone_thrower" else [240.0,0.0],role)])
		app._present()
		t.check(app._city_render_error.is_empty() and app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"actual finite Controller forwards "+role+" warning to actual WorldView")
		if not app._city_render_error.is_empty(): app.free(); continue
		var attack: Dictionary = app.state.enemy_attack_instances[0].duplicate(true)
		var snapshots := {}
		while int(app.state.active_tick) < int(attack.recover_ends_tick):
			var previous := int(app.state.active_tick)
			app.advance_frame(1.0/60.0)
			t.check(app.state.active_tick == previous+1 and app._city_render_error.is_empty(),"actual Controller does not deadlock on "+role+" packet")
			if int(app.state.active_tick) != previous+1: break
			if app.state.active_tick in [attack.active_from_tick,attack.attack_ends_tick,attack.recover_ends_tick]:
				t.check(app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"actual Controller forwards exact boundary packet: "+role+":"+str(app.state.active_tick))
				snapshots[app.state.active_tick] = true
		t.check(snapshots.size() == 3 and app.world.enemy_attack_commands().is_empty(),"actual Controller traverses W/A/R and removes ghost role drawing: "+role)
		app.free()
func _city_controller(t,role: String) -> void:
	var fixture: Dictionary = load("res://tests/app_city_controller/controller_city_support.gd").make(t)
	if fixture.is_empty(): return
	var app = fixture.app
	app.start_run(42)
	# Arrange a known generated-city lane, preserving real geometry and runtime.
	app.state.player.position = [554.0,384.0]
	app.state.player.attack_ready_ticks.blade_slash = 1000
	var command := G.spawn(77,[404.0,384.0],role)
	command.origin_revision = 0
	var prepared: Dictionary = app._city_runtime.refresh_coverage(app.state,[command])
	t.check(prepared.get("ok",false),"actual city Controller fixture prepares: "+role)
	if not prepared.get("ok",false): app.free(); return
	app.simulation = prepared.simulation; app.state = prepared.state
	F.step(app.simulation,app.state,Vector2.ZERO,[command])
	app._present()
	t.check(app.state.enemy_attack_instances.size() == 1 and app._city_render_error.is_empty() and app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"actual city Controller installs Core warning: "+role)
	if app.state.enemy_attack_instances.is_empty() or not app._city_render_error.is_empty(): app.free(); return
	var attack: Dictionary = app.state.enemy_attack_instances[0].duplicate(true)
	while int(app.state.active_tick) < int(attack.active_from_tick)+1:
		var previous := int(app.state.active_tick)
		app.advance_frame(1.0/60.0)
		if int(app.state.active_tick) != previous+1:
			t.check(false,"actual city Controller advances role without rendering hold: "+role); app.free(); return
	t.check(app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state) and app.world._enemy_attack_packet.attacks[0].phase == "attack","actual city Controller installs changing active sample: "+role)
	var packet: Dictionary = app.world._enemy_attack_packet.duplicate(true)
	app.simulation.set_pause(app.state,"user",true)
	app.advance_frame(1.0)
	t.check(app.world._enemy_attack_packet == packet,"actual city pause preserves exact attack clock: "+role)
	app.free()
