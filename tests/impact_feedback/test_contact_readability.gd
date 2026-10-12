extends RefCounted
const View = preload("res://game/presentation/world_view.gd")
const F = preload("res://tests/city_presentation/test_world_view_city.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
class Capture extends "res://game/presentation/world_view.gd":
	var colors: Array[Color] = []
	func _world_transform(_position: Vector2, _rotation:=0.0, _scale_value:=Vector2.ONE) -> void: pass
	func _world_region(_texture: Texture2D, _rect: Rect2, _region: Rect2, color:=Color.WHITE) -> void: colors.append(color)
func run(t) -> void:
	_armored_and_finite(t)
	var view := Capture.new()
	Engine.get_main_loop().root.add_child(view)
	view.set_process(false)
	view.load_manifest()
	var state: Dictionary = F.new()._state()
	view.present_city(state,F.new()._terrain())
	var point := Vector2(100,220)
	var before: Dictionary = view._actor_view("rear","titan_basic",point,"move",1.0,false,0.0)
	var events: Array[Dictionary] = [{"event_id":state.run_id+":1","tick":10,"type":"damage","payload":{"target_id":"rear","hp":10,"source_id":"blade_slash"}}]
	view.consume_events(events)
	var hit: Dictionary = view._actor_view("rear","titan_basic",point,"hit",1.0,false,0.0)
	t.check(hit.get("tint",Color.WHITE) != Color.WHITE,"actual damage brightens only damaged actor")
	t.check(hit.position == before.position and hit.render_bounds == before.render_bounds,"hit feedback never moves actor or changes bounds")
	t.check(view._actor_view("other","titan_basic",point,"move",1.0,false,0.0).get("tint",Color.WHITE) == Color.WHITE,"unhit actor stays unchanged")
	var packet: Dictionary = view._city_render_packet()
	view._draw_upright_with_vfx(packet.upright,[])
	t.check(view.colors.any(func(color): return color != Color.WHITE),"real actor draw adapter forwards damaged-actor modulation")
	t.check(view._actor_draw_tint == Color.WHITE,"draw tint cannot leak into later actors or VFX")
	view.reduce_effects = true
	t.check(view._actor_view("rear","titan_basic",point,"hit",1.0,false,0.0).get("tint",Color.WHITE) != Color.WHITE,"reduced effects retains single short hit-color cue")
	view._process(6.0/60.0)
	t.check(view._actor_view("rear","titan_basic",point,"hit",1.0,false,0.0).get("tint",Color.WHITE) == Color.WHITE,"five-tick flash retires before old hit-pose lifetime")
	view.reset_presentation()
	t.check(view._actor_view("rear","titan_basic",point,"move",1.0,false,0.0).get("tint",Color.WHITE) == Color.WHITE,"new run and cold restore cannot replay a past hit")
	view.free()
	var director := Director.new()
	director._damage({"target_id":"rear"},10)
	t.check(director._effects.size() == 1 and director._effects[0].geometry.radius == 9.0,"real target contact is readable at 18px without enlarging attack geometry")
	t.check(director._effects[0].role == "impact" and director._effects[0].shape_binding == "point" and director._effects[0].end_tick == 16,"contact feedback never creates an attack or a lasting hazard")
	var catalog := Catalog.new()
	for pair in [["blade_slash",""],["spin_slash",""],["blade_slash","evo_wing_cut"]]:
		var recipe: Dictionary = catalog.recipe(pair[0],pair[1],"cast")
		for layer in recipe.layers:
			t.check(layer.render_pass == "contact_overlay","main blade silhouette remains above large actor bodies: "+str(pair))

func _armored_and_finite(t) -> void:
	var S = load("res://tests/armored_actor/armored_support.gd")
	var f: Dictionary = S.make()
	S.begin(f)
	S.arrange_windup(f,Vector2(-210,0),Vector2(160,0))
	for n in 100:
		var actor: Dictionary = S.actor(f.state)
		if actor.action_state == "attack" and f.state.active_tick-actor.action_started_tick == 12: break
		S.step(f)
	var view := Capture.new()
	t.root.add_child(view)
	view.set_process(false)
	var snapshot: Dictionary = f.core.snapshot(f.state)
	view.present(snapshot)
	var status: Dictionary = view.armored_raster_status()
	t.check(status.supported and not view._city_active,"actual finite path has supported armored SubViewport actor")
	if not status.supported: view.free(); return
	# Presentation-boundary probe only: final boss is currently invulnerable.
	# This injected notification does not claim Core permits damaging the boss.
	var actor_id = S.actor(f.state).id
	var event: Array[Dictionary] = [{"event_id":snapshot.run_id+":probe","tick":snapshot.active_tick,"type":"damage","payload":{"target_id":actor_id,"hp":100,"source_id":"blade_slash"}}]
	view.consume_events(event)
	var packet: Dictionary = view._city_render_packet()
	view._armored_split.begin_frame()
	view._draw_upright_with_vfx(packet.upright,[])
	var surface = view._armored_split.get_node("ArmoredPremultiplied")
	t.check(surface.commands.size() == 2 and surface.commands[1][4] != Color.WHITE,"actual finite depth traversal forwards flash to retained premultiplied actor draw")
	t.check(view._actor_draw_tint == Color.WHITE,"armored early return cannot leak modulation to foreground")
	var geometry = surface.commands[1][1]
	view._clock += 6.0/60.0
	packet = view._city_render_packet()
	view._armored_split.begin_frame()
	view._draw_upright_with_vfx(packet.upright,[])
	t.check(surface.commands[1][4] == Color.WHITE and surface.commands[1][1] == geometry,"actual raster returns to white after five ticks without geometry change")
	view.reset_presentation()
	t.check(surface.commands.is_empty(),"reset clears old premultiplied flash command")
	view.free()
