extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Frames = preload("res://tests/visual_interpolation/test_render_interpolation.gd")
const City = preload("res://tests/city_presentation/test_world_view_city.gd")
class CountedView:
	extends "res://game/presentation/world_view.gd"
	var sample_calls := 0
	var record_calls := 0
	var position_calls := 0
	var alpha_queries := 0
	func _armored_opaque(point: Vector2) -> bool:
		alpha_queries += 1
		return super._armored_opaque(point)
	func _render_sample(snapshot: Dictionary) -> Dictionary:
		sample_calls += 1
		return super._render_sample(snapshot)
	func _render_record(actor: Dictionary, identity: Array) -> Dictionary:
		record_calls += 1
		return super._render_record(actor,identity)
	func _render_position(group: String, id: Variant, point: Vector2) -> Vector2:
		position_calls += 1
		return super._render_position(group,id,point)
func run(t) -> void:
	_reuse_and_boundary(t)
	_armored_edge_and_pixels(t)
func _reuse_and_boundary(t) -> void:
	var w := CountedView.new()
	w.load_manifest()
	var a: Dictionary = Frames.new()._state(0,0)
	a.entities.clear()
	for i in 180: a.entities.append(City.new()._enemy(i+1,200.0+i))
	var b := a.duplicate(true)
	b.active_tick = 1; b.event_seq = 1; b.player.position[0] = 8.0
	w.observe_render_tick(a); w.observe_render_tick(b)
	w.sample_calls = 0; w.record_calls = 0
	for i in 100:
		w.begin_render_frame(0.5); w.present(b)
	t.check(w._camera.x == 4.0,"cached 180-entity frame retains fractional camera")
	t.check(w.sample_calls == 0 and w.record_calls == 0,"100 same-tick interpolation presents allocate no spatial samples or actor records")
	b.player.position[0] = 700.0
	w.begin_render_frame(0.0); w.present(b)
	t.check(w._camera.x == 700.0 and w.sample_calls == 1,"unobserved same-tick player replacement invalidates spatial cache")
	b.view_revision = 1
	b.entities[0].position[0] = 900.0
	w.begin_render_frame(0.0); w.present(b)
	t.check(w.sample_calls == 2 and w._render_position("entities",1,Vector2(900,200)) == Vector2(900,200),"same-tick accepted view revision seeds a snapped actor map")
	w.sample_calls = 0; w.record_calls = 0
	for i in 100: w.present(b)
	t.check(w.sample_calls == 0 and w.record_calls == 0 and w._render_current.is_empty(),"ordinary alpha-one API does not allocate unused interpolation maps")
	w.observe_render_tick(a); w.observe_render_tick(b)
	w.begin_render_frame(0.0)
	w.present_city(b,{"ok":false})
	w.present(b)
	t.check(w._camera.x == 700.0 and not w._render_frame_pending,"invalid terrain cannot leak pending alpha into the next ordinary call")
	w.free()
func _armored_edge_and_pixels(t) -> void:
	var f := S.make(); S.begin(f); S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
	for n in 100:
		var actor := S.actor(f.state)
		if actor.action_state == "attack" and f.state.active_tick-actor.action_started_tick == 12: break
		S.step(f)
	var w := CountedView.new()
	t.root.add_child(w); w.set_process(false)
	w._viewport_size = Vector2(200,1000)
	var b: Dictionary = f.core.snapshot(f.state)
	w.present(b)
	t.check(w.armored_raster_status().supported,"edge fixture has a real validated armored raster")
	var bounds: Rect2 = w._armored_world_transform()*w._armored_raster.local_bounds()
	b.player.position = [bounds.end.x+104.0,bounds.get_center().y]
	b.player.velocity = [480.0,0.0]
	var a := b.duplicate(true)
	a.active_tick -= 1; a.event_seq = maxi(0,int(a.event_seq)-1); a.player.position[0] -= 8.0
	w.observe_render_tick(a); w.observe_render_tick(b)
	w.begin_render_frame(0.25); w.present(b)
	t.check(w._armored_raster._actor_visible and not w._armored_raster._dirty,"interpolated camera retains armored raster at the viewport edge")
	var requests: int = w._armored_raster.debug_stats().update_requests
	for n in 20:
		w.begin_render_frame(0.25); w.present(b)
	t.check(w._armored_raster.debug_stats().update_requests == requests and not w._armored_raster._dirty,"unchanged edge frames never toggle visibility through alpha-one or request reraster")
	# Pad with 179 ordinary actors. An entity scan/lerp inside each alpha query
	# would increment position_calls; the cached render root must be query-only.
	for n in 179: b.entities.push_front(City.new()._enemy(1000+n,0))
	w.begin_render_frame(0.25); w.present(b)
	w.position_calls = 0
	for n in 500: w._armored_opaque(bounds.get_center())
	t.check(w.position_calls == 0,"500 armored alpha queries with 180 actors do no entity lookup or interpolation")
	var sample := Image.create(1,1,false,Image.FORMAT_RGBA8); sample.fill(Color.WHITE)
	w._assets["overlap_fixture"] = {"cell_w":1,"cell_h":1,"columns":1}
	w._raster_images["overlap_fixture"] = sample
	w._city_draw_data = {"actor":{"boss":{"armored_raster":true}}}
	var player := {"asset_id":"overlap_fixture","pose":"idle","seconds":0.0,"render_bounds":bounds,"flip":false}
	var other := {"id":"actor:boss","source_id":"boss","asset_id":"overlap_fixture","pose":"idle","render_bounds":bounds}
	w.alpha_queries = 0; w.position_calls = 0
	t.check(w._city_rasters_overlap(player,other) and w.alpha_queries > 0 and w.position_calls == 0,"real armored pixel-overlap loop uses cached root even with boss last among 180 actors")
	var before: Vector2 = w._render_armored_root()
	w.set_render_alpha(1.0)
	t.check(w._render_armored_root() == w._armored_display.root_position and before == w._armored_display.root_position,"alpha changes refresh cached root while stationary actor remains exact")
	w.free()
