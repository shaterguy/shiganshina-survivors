extends RefCounted
const World = preload("res://game/presentation/world_view.gd")
const Frames = preload("res://tests/visual_interpolation/test_render_interpolation.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const RendererFixture = preload("res://tests/presentation_vfx/test_renderer.gd")
const CatalogFixture = preload("res://tests/presentation_vfx/test_catalog.gd")

func run(t) -> void:
	var view = World.new()
	view.load_manifest()
	if not view.has_method("observe_render_tick"):
		t.check(false,"VFX interpolation requires successful-tick render history"); view.free(); return
	var a: Dictionary = Frames.new()._state(0,0)
	var b: Dictionary = Frames.new()._state(1,8)
	view.observe_render_tick(a); view.begin_render_frame(1.0); view.present(a)
	view.consume_combat_events([],a)
	view.observe_render_tick(b)
	var events: Array[Dictionary] = [{"event_id":b.run_id+":1","tick":1,"type":"damage","payload":{"target_id":"player","amount":1}}]
	view.consume_combat_events(events,b)
	view.begin_render_frame(0.5); view.present(b)
	var bytes := var_to_bytes([b,events])
	var commands: Array = view.combat_vfx_commands()
	var shell: Array = commands.filter(func(c): return c.get("projectile_id") == 7 and c.get("component") == "main" and not c.has("diagnostic"))
	var hit: Array = commands.filter(func(c): return c.get("target_id") == "player" and c.get("component") == "main" and not c.has("diagnostic"))
	t.check(shell.size() == 1 and shell[0].world_anchor == Vector2(154,220),"Core-bound projectile VFX uses interpolated projectile point")
	if shell.size() == 1:
		t.check(shell[0].contact_geometry.origin == [158.0,220.0],"projectile contact geometry retains current authoritative point")
		t.check(shell[0].world_bounds.has_point(shell[0].world_anchor),"VFX bounds follow displayed anchor before culling")
	t.check(hit.size() == 1 and hit[0].world_anchor == Vector2(4,210),"actor-bound hit feedback follows the same interpolated actor")
	var watermark: Dictionary = view._combat_bridge.debug_stats()
	view.set_render_alpha(0.75); view.combat_vfx_commands()
	t.check(view._combat_bridge.debug_stats().bridge_tick == watermark.bridge_tick and view._combat_bridge.debug_stats().event_seq == watermark.event_seq,"no-tick visual updates never advance or rewind VFX event clocks")
	t.check(var_to_bytes([b,events]) == bytes,"spatial override cannot change Core snapshot or damage events")
	view.present(b)
	commands = view.combat_vfx_commands()
	shell = commands.filter(func(c): return c.get("projectile_id") == 7 and c.get("component") == "main" and not c.has("diagnostic"))
	t.check(shell.size() == 1 and shell[0].world_anchor == Vector2(158,220),"default alpha-one VFX projection preserves current Core anchor")
	_wire_contact(t)
	view.free()

func _wire_contact(t) -> void:
	# The wire recipe is not registered as approved live art. This existing
	# metadata fixture tests only the pure command adapter, not live visibility.
	var metadata: Dictionary = CatalogFixture.new().manifest_fixture(Catalog.new()).assets
	var effect: Dictionary = RendererFixture.new().effect_fixture(Catalog.new(),"odm_dash",{"shape":"line","origin":[0,0],"direction":[1,0],"length":100.0,"width":20.0,"radius":100.0,"wire_anchor":[100,0],"target_id":"enemy"})
	var original := var_to_bytes(effect)
	var effects: Array[Dictionary] = [effect]
	var context := {"tick":10,"asset_metadata":metadata,"origin_revision":0,"target_positions":{"enemy":Vector2(96,0)}}
	var commands: Array = Renderer.new().commands(effects,context)
	var wire: Array = commands.filter(func(c): return c.get("component") == "wire" and not c.has("diagnostic"))
	t.check(wire.size() == 1 and wire[0].contact_size == Vector2(96,2),"target-bound wire follows displayed target before size and bounds calculation")
	t.check(wire.size() == 1 and wire[0].contact_geometry.wire_anchor == [100,0] and var_to_bytes(effect) == original,"wire spatial interpolation never rewrites contact geometry or effect source")
