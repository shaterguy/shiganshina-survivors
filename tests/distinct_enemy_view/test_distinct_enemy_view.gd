extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
const View = preload("res://game/presentation/world_view.gd")
const Encounter = preload("res://tests/titan_encounters/test_distinct_attacks.gd")
# Draw adapter only: actual WorldView validation/commands/telegraph slicing run.
class Capture extends "res://game/presentation/world_view.gd":
	var hazards: Array = []
	var sprites: Array = []
	func _draw_telegraph(hazard: Dictionary) -> void: hazards.append(hazard.duplicate(true))
	func _sprite(asset_id: String, point: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
		sprites.append({"asset_id":asset_id,"position":point,"animation":animation,"scale":scale_value,"flip":flip,"seconds":seconds})
func run(t) -> void:
	for role in ["grabber","quadruped","stone_thrower"]:
		_lifecycle(t,role)
		_validation(t,role)
	_wall(t)
	_projectile_draw_contract(t)
func _begin(role: String) -> Dictionary:
	var f := G.setup()
	F.step(f.sim,f.state,Vector2.ZERO,[G.spawn(71,[140.0,0.0] if role != "stone_thrower" else [240.0,0.0],role)])
	return f
func _lifecycle(t,role: String) -> void:
	var f := _begin(role)
	var state: Dictionary = f.state
	t.check(state.enemy_attack_instances.size() == 1,"actual Core begins "+role)
	if state.enemy_attack_instances.is_empty(): return
	var view = Capture.new()
	view.load_manifest()
	view._assets.erase("enemy_stone_projectile") # Explicit missing-art boundary, even after art integration.
	var finish := int(state.enemy_attack_instances[0].recover_ends_tick)
	var seen := {}
	while int(state.active_tick) <= finish:
		var packet: Dictionary = f.sim.enemy_attack_view(state)
		var before := state.duplicate(true)
		view.present(state.duplicate(true))
		var result: Dictionary = view.present_enemy_attacks(packet)
		t.check(result.ok,"actual Core sample is accepted: "+role+":"+str(state.active_tick))
		if not result.ok: break
		t.check(view._enemy_attack_packet == packet and state == before,"view copies exact optional Core packet without changing authority")
		var commands: Array = view.enemy_attack_commands()
		view.reduce_effects = true
		t.check(view.enemy_attack_commands() == commands,"reduced effects retain complete warning/sweep/projectile commands")
		view.reduce_effects = false
		if not packet.attacks.is_empty():
			var attack: Dictionary = packet.attacks[0]
			seen[attack.phase] = true
			var geometry: Array = attack.telegraph_geometry if attack.phase == "windup" else attack.damage_geometry
			var footprints := commands.filter(func(c): return c.has("geometry"))
			t.check(footprints.size() == geometry.size(),"only current phase damage/warning footprint is published")
			for index in footprints.size():
				var kind: String = "warning" if attack.phase == "windup" else {"grabber":"hand_sweep","quadruped":"body_sweep","stone_thrower":"projectile_sweep"}[role]
				t.check(footprints[index].kind == kind and footprints[index].get("role_id","") == role and footprints[index].geometry == geometry[index],"role command is exactly the actual Core geometry")
			var rocks := commands.filter(func(c): return c.kind == "projectile")
			var visible: bool = attack.get("projectile_pose",{}).get("visible",false)
			t.check(rocks.size() == (1 if visible else 0),"only visible rock produces projectile draw command")
			if visible:
				t.check(rocks[0].position == attack.projectile_pose.current and rocks[0].radius == 7.0 and rocks[0].asset_id == "enemy_stone_projectile" and rocks[0].get("diagnostic") == "enemy_projectile_art_unavailable","rock position/radius retain missing-original-art diagnostic")
			view.hazards.clear(); view.sprites.clear(); view._draw_enemy_attacks()
			t.check(view.hazards.size() == geometry.size() and view.sprites.is_empty(),"actual draw emits footprint but never substitutes warning art for absent rock")
			for hazard in view.hazards:
				t.check(hazard.active_from_tick == state.active_tick+(1 if attack.phase == "windup" else 0),"actual draw preserves warning versus active opacity selector")
		else: t.check(commands.is_empty(),"finished attack leaves no ghost commands")
		if int(state.active_tick) == finish: break
		F.step(f.sim,state,Vector2.ZERO)
	t.check(seen.has_all(["windup","attack","recover"]),"view traverses actual complete lifecycle: "+role)
	view.free()
func _validation(t,role: String) -> void:
	var f := _begin(role)
	var view = View.new()
	view.present(f.state.duplicate(true))
	var packet: Dictionary = f.sim.enemy_attack_view(f.state)
	for field in ["run_id","tick","scene_id","origin_revision","world_revision"]:
		var invalid := packet.duplicate(true)
		invalid[field] = "foreign" if field in ["run_id","scene_id"] else 999
		t.check(not view.present_enemy_attacks(invalid).ok and view._enemy_attack_packet.is_empty(),"all roles reject stale "+field+": "+role)
	for change in ["owner_role","source","duplicate","position","phase","geometry","missing_pose","unexpected_pose","nonfinite_pose","pose_type","radius","visible_blocked","inactive_visible"]:
		var invalid := packet.duplicate(true)
		var attack: Dictionary = invalid.attacks[0]
		match change:
			"owner_role": attack.role_id = "grabber" if role != "grabber" else "quadruped"
			"source": attack.source_id = "other"
			"duplicate": invalid.attacks.append(attack.duplicate(true))
			"position": attack.position[0] = INF
			"phase": attack.phase = "recover"
			"geometry": attack.telegraph_geometry[0].length = NAN
			"missing_pose":
				if role == "quadruped": continue
				attack.erase("hand_pose" if role == "grabber" else "projectile_pose")
			"unexpected_pose": attack["hand_pose" if role != "grabber" else "projectile_pose"] = {}
			"nonfinite_pose":
				if role == "quadruped": continue
				attack["hand_pose" if role == "grabber" else "projectile_pose"].current[0] = NAN
			"pose_type":
				if role != "stone_thrower": continue
				attack.projectile_pose.visible = 1
			"radius":
				if role != "stone_thrower": continue
				attack.projectile_pose.radius = -1.0
			"visible_blocked":
				if role != "stone_thrower": continue
				attack.projectile_pose.visible = true; attack.projectile_pose.blocked = true
			"inactive_visible":
				if role != "stone_thrower": continue
				attack.projectile_pose.visible = true
		view.present_enemy_attacks(packet)
		t.check(not view.present_enemy_attacks(invalid).ok and view.enemy_attack_commands().is_empty(),"reject malformed "+role+":"+change)
	t.check(view.present_enemy_attacks(packet).ok,"valid retransmit clears all-role rejection")
	if view._enemy_attack_packet.is_empty(): view.free(); return
	if role != "quadruped":
		var pose := "hand_pose" if role == "grabber" else "projectile_pose"
		packet.attacks[0][pose].current[0] = 9999
		t.check(view._enemy_attack_packet.attacks[0][pose].current[0] != 9999,"role-specific optional pose is deeply copied")
	var next: Dictionary = f.state.duplicate(true); next.active_tick += 1
	view.present(next)
	t.check(view.enemy_attack_commands().is_empty(),"new snapshot clears old role packet")
	view.present(f.state.duplicate(true)); view.present_enemy_attacks(f.sim.enemy_attack_view(f.state)); view.reset_presentation()
	t.check(view._enemy_attack_packet.is_empty(),"reset clears role packet: "+role)
	var dead: Dictionary = f.state.duplicate(true); dead.phase = "dead"
	view.present(dead)
	t.check(not view.present_enemy_attacks(f.sim.enemy_attack_view(f.state)).ok,"terminal snapshot rejects nonempty packet: "+role)
	view.free()
func _wall(t) -> void:
	var provider := Encounter.GeometryProvider.new({"bounds":[-500,-500,1000,1000],"obstacles":[[-30,-120,20,240]]})
	var sim = load("res://game/core/run_simulation.gd").new(provider)
	var state: Dictionary = sim.new_run(provider.chapter,42,F.run_config())
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	F.step(sim,state,Vector2.ZERO,[G.spawn(71,[-240.0,0.0],"stone_thrower")])
	t.check(state.enemy_attack_instances.size() == 1,"actual wall rock starts")
	if state.enemy_attack_instances.is_empty(): return
	var view = Capture.new(); view.load_manifest()
	var end := int(state.enemy_attack_instances[0].recover_ends_tick)
	var saw_first := false; var saw_expired := false
	for tick in range(2,end+1):
		F.step(sim,state,Vector2.ZERO)
		view.present(state.duplicate(true))
		var packet: Dictionary = sim.enemy_attack_view(state)
		t.check(view.present_enemy_attacks(packet).ok,"actual wall-blocked sample remains renderable")
		if packet.attacks.is_empty(): continue
		var attack: Dictionary = packet.attacks[0]
		if not attack.projectile_pose.blocked: continue
		if attack.damage_geometry.is_empty(): saw_expired = true
		else: saw_first = true
		t.check(view.enemy_attack_commands().filter(func(c): return c.kind == "projectile").is_empty(),"wall block never emits ghost rock, including collision tick")
	t.check(saw_first and saw_expired and state.player.hp == state.player.max_hp,"wall impact has final clipped sweep then expires harmlessly")
	view.free()

func _projectile_draw_contract(t) -> void:
	var f := _begin("stone_thrower")
	var active := int(f.state.enemy_attack_instances[0].active_from_tick)
	while int(f.state.active_tick) < active: F.step(f.sim,f.state,Vector2.ZERO)
	var view = Capture.new()
	view.present(f.state.duplicate(true))
	t.check(view.present_enemy_attacks(f.sim.enemy_attack_view(f.state)).ok,"actual active rock supplies draw-contract sample")
	# Test-only atlas dimensions drive the capture adapter; no new art is
	# generated, registered, approved, or substituted in the production manifest.
	view._assets["enemy_stone_projectile"] = {"cell_w":32,"cell_h":32,"columns":1,"anchor_px":[16,16],"animations":{"idle":{"frames":[0],"fps":1,"loop":true}},"export_blocked":false}
	var commands: Array = view.enemy_attack_commands()
	var rock: Dictionary = commands.filter(func(c): return c.kind == "projectile")[0]
	t.check(not rock.has("diagnostic"),"registered unblocked projectile metadata selects dedicated stone draw contract")
	rock.position[0] = 9999
	t.check(view.enemy_attack_commands().filter(func(c): return c.kind == "projectile")[0].position[0] != 9999,"projectile command deeply copies optional pose")
	view._draw_enemy_attacks()
	t.check(view.sprites.size() == 1 and view.sprites[0].asset_id == "enemy_stone_projectile" and view.sprites[0].scale == 14.0/32.0 and view.sprites[0].position == Vector2(f.sim.enemy_attack_view(f.state).attacks[0].projectile_pose.current[0],0.0),"dedicated projectile draw uses actual point and 14px diameter, never danger-line raster")
	view._assets.enemy_stone_projectile.export_blocked = true
	view.sprites.clear(); view._draw_enemy_attacks()
	t.check(view.sprites.is_empty() and view.enemy_attack_commands().filter(func(c): return c.kind == "projectile")[0].diagnostic == "enemy_projectile_art_unavailable","blocked projectile art remains explicit and undrawn")
	view.free()
