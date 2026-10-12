extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const G = preload("res://tests/app_city_controller/grabber_controller_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
class HeldRuntime extends "res://game/app/prepared_city_runtime.gd":
	var blocked := true
	func refresh_coverage(snapshot: Dictionary, commands: Array = []) -> Dictionary:
		return {"ok":false,"error_code":"read_failed"} if blocked else super.refresh_coverage(snapshot,commands)
func run(t) -> void:
	t.check(Core.new().has_method("enemy_attack_view"),"real Core publishes a successful-tick hand packet for actual Controller proof")
	if not Core.new().has_method("enemy_attack_view"): return
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	var setup := G.arrange(t,app)
	if setup.is_empty():
		app.free()
		return
	var start: int = setup.started_tick
	var samples: Array = [app.world._enemy_attack_packet.duplicate(true)]
	t.check(app.world.enemy_attack_commands()[0].kind == "warning","actual warning reaches WorldView draw command")
	if not G.at_tick(t,app,start+60): app.free(); return
	var packet: Dictionary = app.world._enemy_attack_packet.duplicate(true)
	var terrain: Dictionary = app._city_terrain_view
	var first_hand: Array = packet.attacks[0].hand_pose.current.duplicate()
	t.check(packet.tick == app.state.active_tick and packet.attacks[0].phase == "attack" and app.world.enemy_attack_commands()[0].geometry.length <= 10.626,"actual first active tick renders short current hand rather than announced line")
	samples.append(packet)
	app.advance_frame(1.0/60.0)
	t.check(is_same(terrain,app._city_terrain_view) and app.world._enemy_attack_packet.attacks[0].hand_pose.current != first_hand,"unchanged cached terrain still receives changing hand endpoint every successful tick")
	var before: int = app.state.active_tick
	app.advance_frame(8.0/60.0)
	t.check(app.state.active_tick == before+8 and app.world._enemy_attack_packet.tick == before+8,"eight-tick catch-up presents only the final successful sample")
	t.check(app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"Controller forwards exact final Core packet without a second sample")
	packet = app.world._enemy_attack_packet.duplicate(true)
	app.simulation.set_pause(app.state,"user",true)
	app.advance_frame(1.0)
	t.check(app.state.active_tick == before+8 and app.world._enemy_attack_packet == packet,"pause preserves same tick and same hand without replay")
	app.simulation.set_pause(app.state,"user",false)
	# Real Core/terrain readiness refusal, with only the preparation failure injected.
	var good_core = app.simulation
	var helper = good_core._streamed
	var held := HeldRuntime.new(f.provider,f.disk)
	app._city_runtime = held
	good_core._streamed = null
	var failed_state: Dictionary = app.state.duplicate(true)
	app.advance_frame(1.0/60.0)
	t.check(app.state == failed_state and app._city_step_error == "read_failed","failed world preparation leaves actual state and attack clock untouched")
	t.check(good_core.enemy_attack_view(app.state) == packet and app.world.enemy_attack_commands().is_empty(),"failed tick retains last successful Core sample but unavailable terrain clears rendered hand")
	good_core._streamed = helper
	held.blocked = false
	app.request_resume()
	t.check(app.state.active_tick == int(failed_state.active_tick)+1 and app.world._enemy_attack_packet == app.simulation.enemy_attack_view(app.state),"explicit preparation retry publishes one matching successful tick")
	if not G.at_tick(t,app,start+76): app.free(); return
	samples.append(app.world._enemy_attack_packet.duplicate(true))
	t.check(app.world._enemy_attack_packet.attacks[0].phase == "recover" and app.world.enemy_attack_commands().is_empty(),"actual recovery has hand coordinates but no danger raster")
	t.check(app.state.player.hp == float(setup.hp)-12.0 and app.state.enemy_attack_instances[0].hit_target_ids == ["player"],"controlled real travelling hand records one accepted damage and one ledger hit")
	var hp: float = app.state.player.hp
	var event_seq: int = app.state.event_seq
	var cold_packet: Dictionary = app.world._enemy_attack_packet.duplicate(true)
	app._city_runtime = f.runtime
	app._save_checkpoint()
	t.check(app.game_save.checkpoint.active_tick == app.state.active_tick,"actual Store commits the recovering grabber")
	app.free()
	var cold := S.make(t,f.directory)
	app = cold.app
	app.request_resume()
	t.check(not app.state.is_empty() and app.world._enemy_attack_packet == cold_packet,"cold actual Controller reconstructs the exact harmless current sample")
	t.check(app.state.player.hp == hp and app.state.event_seq == event_seq and app.world._effects.is_empty() and app.world._enemy_hits.is_empty() and app.world._hit_until == 0.0,"cold restore does not replay damage events or hit effects")
	if G.at_tick(t,app,start+160):
		t.check(app.world._enemy_attack_packet.attacks.is_empty() and app.world.enemy_attack_commands().is_empty(),"cooldown removes completed hand packet")
	print("GRABBER_CONTROLLER_EVIDENCE "+JSON.stringify({"controlled":true,"setup":setup,"samples":samples,"recovery_hp":hp,"event_seq":event_seq},"",true,true))
	app.free()
	_main_scene(t)
func _main_scene(t) -> void:
	var scene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var boot = scene.instantiate()
	boot.save_directory = "user://grabber_main_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]
	t.root.add_child(boot)
	t.check(boot.startup_result.get("ok",false) and is_instance_valid(boot.app),"actual configured main scene starts real city Controller")
	if not is_instance_valid(boot.app): boot.free(); return
	var app = boot.app
	app.set_process(false); app.world.set_process(false)
	# This setup controls timing and writes; async behavior has its own suite.
	app.autosave_worker_enabled = false
	var setup := G.arrange(t,app)
	if not setup.is_empty() and G.at_tick(t,app,int(setup.started_tick)+76):
		t.check(app.world._enemy_attack_packet.attacks[0].phase == "recover" and app.world.enemy_attack_commands().is_empty(),"actual main path reaches W/A/R without alternate Core or WorldView")
	boot.free()
