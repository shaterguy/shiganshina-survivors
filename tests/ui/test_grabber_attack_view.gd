extends RefCounted
const F = preload("res://tests/ui/grabber_attack_view_fixture.gd")
const View = preload("res://game/presentation/world_view.gd")
# Records actual draw traversal, not native/GPU readability.
class Capture extends "res://game/presentation/world_view.gd":
	var layers: Array[String] = []
	var emitted: Array = []
	func _draw_city() -> void: layers.append("ground")
	func _draw_telegraph(hazard: Dictionary) -> void:
		layers.append("warning")
		emitted.append(hazard.duplicate(true))
	func _sprite(asset_id: String, _position: Vector2, _animation: String, _scale_value: float, _flip := false, _seconds := -1.0) -> void:
		layers.append(asset_id)
# Real telegraph slicing and modulation, captured before raster emission. This
# checks API data and draw order; it does not establish native color readability.
class RasterCapture extends "res://game/presentation/world_view.gd":
	var pieces: Array = []
	func _world_transform(_position: Vector2, _rotation:=0.0, _scale_value:=Vector2.ONE) -> void: pass
	func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color:=Color.WHITE) -> void:
		pieces.append({"texture_size":texture.get_size(),"rect":rect,"region":region,"color":color})
func run(t) -> void:
	var view = View.new()
	view.load_manifest()
	t.check(view.has_method("present_enemy_attacks") and view.has_method("enemy_attack_commands"),"WorldView has a live hand packet boundary and raster projection")
	if not view.has_method("present_enemy_attacks") or not view.has_method("enemy_attack_commands"):
		view.free()
		return
	var snapshot := F.snapshot(t)
	var before := snapshot.duplicate(true)
	view.present(snapshot)
	var packet := F.packet(snapshot)
	t.check(view.present_enemy_attacks(packet).get("ok",false),"matching successful windup packet is accepted")
	var commands: Array = view.enemy_attack_commands()
	t.check(commands.size() == 1 and commands[0].kind == "warning" and commands[0].geometry == F.line(40,210),"windup projects the entire locked 170px capsule with width44")
	t.check(snapshot == before and view._snapshot.entities[0].position == [0.0,0.0],"presenting a hand never translates the torso or mutates the snapshot")
	packet.attacks[0].hand_pose.current[0] = 999.0
	packet.attacks[0].telegraph_geometry[0].length = 999.0
	commands[0].geometry.length = 777.0
	t.check(view._enemy_attack_packet.attacks[0].hand_pose.current == [40.0,0.0] and view.enemy_attack_commands()[0].geometry.length == 170.0,"packet and command consumers cannot mutate owned presentation data")
	view.reduce_effects = true
	t.check(view.enemy_attack_commands()[0].geometry == F.line(40,210),"reduced effects retains the complete warning information")
	packet = F.packet(snapshot,"attack")
	t.check(view.present_enemy_attacks(packet).ok,"same-tick active fixture packet is accepted")
	commands = view.enemy_attack_commands()
	t.check(commands.size() == 1 and commands[0].kind == "hand_sweep" and commands[0].geometry == F.line(40,50.625),"active phase removes whole warning and projects only the real 10.625px hand sweep")
	t.check(view._enemy_attack_packet.attacks[0].hand_pose == packet.attacks[0].hand_pose,"display hand points are exactly the supplied collision sample")
	view.reduce_effects = false
	t.check(view.enemy_attack_commands() == commands,"reduced effects cannot change or hide the active sweep")
	view.present_enemy_attacks(F.packet(snapshot,"recover"))
	t.check(view.enemy_attack_commands().is_empty() and view._enemy_attack_packet.attacks[0].hand_pose.current == [207.976190476,0.0],"harmless recovery retains actual hand DTO and emits no danger or substitute icon")
	for field in ["run_id","tick","scene_id","origin_revision","world_revision"]:
		view.present_enemy_attacks(F.packet(snapshot))
		var stale := F.packet(snapshot)
		stale[field] = "foreign" if field in ["run_id","scene_id"] else 999
		t.check(not view.present_enemy_attacks(stale).ok and view.enemy_attack_commands().is_empty(),"stale "+field+" packet clears previous geometry")
	view.present_enemy_attacks(F.packet(snapshot))
	t.check(not view.present_enemy_attacks({"ok":false,"attacks":[]}).ok and view.enemy_attack_commands().is_empty(),"Core refusal clears cached hand data")
	for change in ["nonfinite","source","duplicate","wrong_phase"]:
		var invalid := F.packet(snapshot)
		match change:
			"nonfinite": invalid.attacks[0].hand_pose.current[0] = NAN
			"source": invalid.attacks[0].source_id = "8"
			"duplicate": invalid.attacks.append(invalid.attacks[0].duplicate(true))
			"wrong_phase": invalid.attacks[0].phase = "recover"
		t.check(not view.present_enemy_attacks(invalid).ok and view.enemy_attack_commands().is_empty(),"malformed packet rejected: "+change)
	view.present_enemy_attacks(F.packet(snapshot))
	var next := snapshot.duplicate(true)
	next.active_tick += 1
	view.present(next)
	t.check(view.enemy_attack_commands().is_empty(),"new snapshot cannot draw previous tick before its packet is installed")
	view.present_enemy_attacks(F.packet(next))
	view.reset_presentation()
	t.check(view.enemy_attack_commands().is_empty() and view._enemy_attack_packet.is_empty(),"reset removes all hand ownership")
	var city := F.city(snapshot)
	t.check(view.present_city(city,F.terrain(city)).ok,"interface fixture installs matching city terrain")
	t.check(view.present_enemy_attacks(F.packet(city,"attack")).ok and view.enemy_attack_commands() == commands,"finite and city project identical collision DTO without alternate geometry")
	var rebased := city.duplicate(true)
	rebased.world.origin_revision += 1
	view.present_city(rebased,F.terrain(rebased))
	t.check(view.enemy_attack_commands().is_empty() and not view.present_enemy_attacks(F.packet(city)).ok,"origin rebase rejects old-coordinate hand packets")
	view.present_enemy_attacks(F.packet(rebased))
	t.check(not view.present_city(rebased,{}).ok and view.enemy_attack_commands().is_empty(),"terrain failure cannot leave a plausible old hand on screen")
	view.present(snapshot)
	view.present_enemy_attacks(F.packet(snapshot))
	var terminal := snapshot.duplicate(true)
	terminal.phase = "dead"
	view.present(terminal)
	t.check(view.enemy_attack_commands().is_empty() and not view.present_enemy_attacks(F.packet(terminal)).ok,"terminal snapshot rejects live hand geometry")
	var empty := F.packet(terminal)
	empty.attacks = []
	t.check(view.present_enemy_attacks(empty).ok,"terminal success may publish its exact empty packet")
	view.free()
	_draw_contract(t,snapshot)
	_raster_contract(t,snapshot)
func _draw_contract(t,snapshot: Dictionary) -> void:
	var view = Capture.new()
	view.load_manifest()
	for phase in ["windup","attack","recover"]:
		view.present(snapshot)
		view.present_enemy_attacks(F.packet(snapshot,phase))
		view.layers.clear(); view.emitted.clear()
		view._draw()
		t.check(view.emitted.size() == (0 if phase == "recover" else 1),"real finite draw emits one phase-specific capsule: "+phase)
		if phase != "recover":
			t.check(view.layers.find("warning") > view.layers.find("titan_grabber") and view.layers.find("warning") < view.layers.find("garrison_01"),"hand raster stays above enemies and below player")
			t.check(view.emitted[0].length == (170.0 if phase == "windup" else 10.625),"actual draw does not retain full line during active hand")
	var city := F.city(snapshot)
	view.present_city(city,F.terrain(city))
	view.present_enemy_attacks(F.packet(city,"attack"))
	view.layers.clear(); view.emitted.clear()
	view._draw()
	t.check(view.emitted.size() == 1 and view.emitted[0].length == 10.625 and view.layers.find("warning") > view.layers.find("titan_grabber"),"actual city draw consumes same short sweep above upright enemies")
	view.free()
func _raster_contract(t, snapshot: Dictionary) -> void:
	var view = RasterCapture.new()
	view.load_manifest()
	for reduced in [false,true]:
		view.reduce_effects = reduced
		for phase in ["windup","attack","recover"]:
			view.present(snapshot)
			view.present_enemy_attacks(F.packet(snapshot,phase))
			view.pieces.clear()
			view._draw_enemy_attacks()
			t.check(view.pieces.size() == (0 if phase == "recover" else 3),"real diagnostic raster emits only phase-appropriate slices, reduced="+str(reduced)+" phase="+phase)
			if phase == "recover": continue
			var length := 170.0 if phase == "windup" else 10.625
			t.check(view.pieces[0].rect == Rect2(-22,-22,22,44) and view.pieces[1].rect == Rect2(0,-22,length,44) and view.pieces[2].rect == Rect2(length,-22,22,44),"actual three-slice footprint preserves hand capsule width and current length")
			t.check(view.pieces[1].texture_size == Vector2(128,32) and view.pieces[1].region == Rect2(16,0,96,32),"diagnostic draw uses the existing approved danger_line raster without altered art")
			if phase == "attack": t.check(is_equal_approx(view.pieces[1].color.a,0.98),"active hand remains visible in both effects settings")
			elif reduced: t.check(is_equal_approx(view.pieces[1].color.a,0.70),"reduced-effects windup retains steady nonzero warning opacity")
	view.free()
