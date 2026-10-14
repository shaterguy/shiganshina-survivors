extends RefCounted
const F = preload("res://tests/corridor_mobility/corridor_fixture.gd")
class Capture extends "res://game/presentation/world_view.gd":
	var emitted: Array = []
	var overlap_calls: Dictionary = {}
	func _draw_city_ground(_command: Dictionary) -> void: pass
	func _draw_mobility_wire(_wire: Dictionary) -> void: emitted.append({"kind":"wire"})
	func _draw_mobility_travel(_travel: Dictionary) -> void: emitted.append({"kind":"travel"})
	func _draw_player_outline(_command: Dictionary,_style: Dictionary) -> void: emitted.append({"kind":"outline"})
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"kind":"danger"})
	func _sprite(asset_id: String,point: Vector2,_pose: String,_scale: float,_flip := false,_seconds := -1.0) -> void:
		emitted.append({"kind":"sprite","asset":asset_id,"point":point,"tint":_actor_draw_tint})
	func _city_rasters_overlap(player: Dictionary,occluder: Dictionary) -> bool:
		overlap_calls[occluder.id] = int(overlap_calls.get(occluder.id,0))+1
		return super._city_rasters_overlap(player,occluder)
	func capture() -> Array:
		emitted.clear(); overlap_calls.clear(); _draw(); return emitted.duplicate(true)
func _terrain(s: Dictionary) -> Dictionary:
	var result: Dictionary = s.core.world_render_view(s.state)
	result.world_revision = s.core.world_status().world_revision
	return result
func run(t) -> void:
	var s := F.make(t,[F.AF.slot("above","house_narrow",[144,160]),F.AF.slot("below","house_narrow",[144,272])],[64.0,190.0])
	F.step(s,Vector2.RIGHT); F.step(s,Vector2.RIGHT)
	t.check(s.state.player_mobility.phase == "boost","occlusion test uses real horizontal corridor boost")
	var snapshot: Dictionary = s.core.snapshot(s.state)
	var terrain := _terrain(s)
	var frozen := var_to_bytes([snapshot,terrain])
	var view := Capture.new()
	view.load_manifest(); view._viewport_size = Vector2(800,450)
	for reduced in [false,true]:
		view.reduce_effects = reduced
		view.present_city(snapshot,terrain)
		var drawn: Array = view.capture()
		var lower: Array = drawn.filter(func(c):return c.get("asset","") == "house_narrow" and c.point == Vector2(144,272))
		var upper: Array = drawn.filter(func(c):return c.get("asset","") == "house_narrow" and c.point == Vector2(144,160))
		t.check(lower.size() == 1 and lower[0].tint.a > 0.0 and lower[0].tint.a <= 0.30,"only foreground building covering boost body becomes translucent")
		t.check(upper.size() == 1 and upper[0].tint.a == 1.0,"rear anchor building remains opaque")
		t.check(not drawn.any(func(c):return c.kind == "outline"),"translucent-only occlusion does not redraw roof-like cyan body silhouette")
		var player: Array = drawn.filter(func(c):return c.get("asset","") == "garrison_01")
		t.check(player.size() == 1 and player[0].point == Vector2(80,190) and player[0].tint.a == 1.0,"actual player stays opaque at its single ground-plane position")
		t.check(drawn.filter(func(c):return c.kind == "wire").size() == 2,"translucency keeps both side wires")
		t.check(view.overlap_calls.values().all(func(count):return count == 1),"draw and outline reuse each foreground overlap result once")
	# Multiple real foreground rasters must fade without any second scene search.
	var double := terrain.duplicate(true)
	for chunk in double.chunks:
		for prop in chunk.props.duplicate():
			if prop.prop_id == "city:city_v1:0:0:below":
				var copy: Dictionary = prop.duplicate(true)
				copy.prop_id = "fixture:second-front-house"
				copy.position += Vector2(1,1); copy.depth_y += 1.0; copy.render_bounds.position += Vector2(1,1)
				chunk.props.append(copy)
	view.present_city(snapshot,double)
	var twice: Array = view.capture()
	t.check(twice.filter(func(c):return c.get("asset","") == "house_narrow" and c.tint.a < 1.0).size() == 2,"both overlapping foreground buildings fade in the same draw traversal")
	t.check(not twice.any(func(c):return c.kind == "outline") and view.overlap_calls.values().all(func(count):return count == 1),"multiple faded buildings do not create a second silhouette or duplicate queries")
	# A real opaque enemy in front still needs the existing visibility marker.
	var with_enemy := snapshot.duplicate(true)
	with_enemy.entities = [{"id":"occluding-enemy","enemy_id":"basic","position":[80.0,206.0],"velocity":[0.0,0.0],"hp":100.0,"action_state":"move","action_started_tick":0}]
	with_enemy.rules.enemy_catalog.basic = {"art_id":"titan_basic"}
	view.present_city(with_enemy,terrain)
	var mixed: Array = view.capture()
	t.check(mixed.any(func(c):return c.kind == "outline"),"opaque enemy occlusion retains player visibility outline during boost")
	t.check(mixed.filter(func(c):return c.get("asset","") == "titan_basic").all(func(c):return c.tint.a == 1.0),"enemy alpha is never changed by building treatment")
	F.step(s,Vector2.ZERO)
	view.present_city(s.core.snapshot(s.state),_terrain(s))
	var grounded: Array = view.capture()
	t.check(s.state.player_mobility.phase == "ground" and grounded.filter(func(c):return c.get("asset","") == "house_narrow").all(func(c):return c.tint.a == 1.0),"interruption immediately restores ordinary opaque buildings")
	t.check(grounded.any(func(c):return c.kind == "outline"),"ordinary ground occlusion keeps its original visibility marker")
	t.check(var_to_bytes([snapshot,terrain]) == frozen,"boost occlusion changes no Core or terrain bytes")
	view.free()
