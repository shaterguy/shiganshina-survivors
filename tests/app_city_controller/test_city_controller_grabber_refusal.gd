extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const G = preload("res://tests/app_city_controller/grabber_controller_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	t.check(app._city_render_error.is_empty(),"empty title snapshot does not create an attack-display error")
	var setup := G.arrange(t,app)
	if setup.is_empty(): app.free(); return
	var packet: Dictionary = app.simulation.enemy_attack_view(app.state)
	var before: Dictionary = app.state.duplicate(true)
	# Corrupt only the transient cache to exercise an actual Core getter refusal.
	app.simulation._attack_view_cache.tick += 1
	app._present()
	t.check(app._city_render_error == "attack_view_stale" and app.world.enemy_attack_commands().is_empty(),"actual hand refusal is surfaced as the existing rendering hold")
	app.advance_frame(1.0/60.0)
	t.check(app.state == before,"invisible hand packet failure cannot advance damage or simulation ticks")
	app.simulation._attack_view_cache = packet.duplicate(true)
	app._present()
	t.check(app._city_render_error.is_empty() and not app.world.enemy_attack_commands().is_empty(),"same-identity valid packet retransmission clears the hold without permanent lock")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == int(before.active_tick)+1,"normal ticks resume after matching hand redisplay")
	app.simulation._attack_view_cache.tick += 1
	app._present()
	var retry_tick: int = app.state.active_tick
	app.request_resume()
	t.check(app._city_render_error.is_empty() and app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"explicit existing Continue preparation reconstructs the matching packet")
	t.check(app.state.active_tick == retry_tick,"display-only retry never replays a combat tick")
	app.free()
	_finite_refusal(t)
func _finite_refusal(t) -> void:
	var f: Dictionary = load("res://tests/app/controller_test_support.gd").new().make(t)
	var app = f.app
	app.start_run(42)
	app.state.player.attack_ready_ticks.blade_slash = 1000
	var commands: Array[Dictionary] = [{"command_id":"finite-display-grabber","kind":"spawn_enemy","payload":{"entity_id":77,"enemy_id":"grabber","position":[170.0,0.0],"spawned_tick":0}}]
	app.simulation.step(app.state,Vector2.ZERO,commands)
	app._present()
	t.check(not app.world.enemy_attack_commands().is_empty(),"standalone finite Controller presents an actual Core grabber sample")
	app.simulation._attack_view_cache.scene_id = "other"
	app._present()
	var before: Dictionary = app.state.duplicate(true)
	app.advance_frame(1.0/60.0)
	t.check(app._city_render_error == "attack_view_stale" and app.state == before,"finite packet refusal holds the same simulation boundary")
	app.request_resume()
	t.check(app._city_render_error.is_empty() and app.state == before and app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"finite Continue reconstructs harmless current sample without clock or ledger replay")
	var expected: Dictionary = app.world._enemy_attack_packet.duplicate(true)
	app._save_checkpoint()
	app.free()
	app = load("res://tests/app/controller_test_support.gd").new().restart(t,f.directory)
	app.request_resume()
	t.check(app.state == before and app._city_render_error.is_empty() and app.world._enemy_attack_packet == expected,"finite cold Controller explicitly prepares the adopted hand sample before presentation")
	t.check(app.world._effects.is_empty() and app.world._enemy_hits.is_empty() and app.world._hit_until == 0.0,"finite cold adoption does not replay combat effects")
	app.free()
