extends RefCounted
const CoreFixture = preload("res://tests/core/core_fixture.gd")
# Only raster emission is recorded. All activation, conversion, culling, sorting
# and traversal run through the production WorldView and CityRender.
class Capture extends "res://game/presentation/world_view.gd":
	var emitted: Array[Dictionary] = []
	func _draw_city() -> void: emitted.append({"asset":"authored_ground"})
	func _draw_props() -> void: emitted.append({"asset":"legacy_props"})
	func _draw_city_ground(command: Dictionary) -> void: emitted.append({"asset":"chunk_ground","command":command})
	func _draw_player_outline(command: Dictionary, style: Dictionary) -> void: emitted.append({"asset":"player_outline","command":command,"style":style})
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"asset":"warning"})
	func _draw_vfx_command(command: Dictionary) -> void:
		emitted.append({"asset":command.asset_id,"world":command.world_anchor,"command":command.duplicate(true)})
	func _sprite(asset_id: String, world: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
		emitted.append({"asset":asset_id,"world":world,"pose":animation,"scale":scale_value,"flip":flip,"seconds":seconds})
	func capture() -> Array[Dictionary]:
		emitted.clear()
		_draw()
		return emitted.duplicate(true)
func run(t) -> void:
	var view := Capture.new()
	view.load_manifest()
	# This historical fixture explicitly tests the legacy projectile/depth
	# branch. Registered VFX are exercised separately through actual Core below.
	view._combat_bridge.set_asset_metadata({})
	t.check(view.has_method("present_city"),"WorldView has explicit prepared-terrain city presentation contract")
	if not view.has_method("present_city"): view.free(); return
	_depth_and_markers(t,view)
	_event_corpses(t,view)
	_raster_marker(t,view)
	_rebase_observations(t,view)
	_culling_and_rebase(t,view)
	_explicit_activation_and_dock(t,view)
	_real_prepared_terrain(t,view)
	view.free()
	_registered_cannon_traversal(t)
func _state() -> Dictionary:
	return {"seed":42,"run_id":"city-render-test","chapter_id":"chapter_01_shiganshina","content_revision":"ch01.3-rebuild.2","active_tick":0,"phase":"survival","pause_reasons":[],"world":{"mode":"streamed_city","stage":"city","origin_chunk":["0","0"],"origin_revision":0,"world_revision":0},"player":{"position":[100.0,210.0],"velocity":[0.0,0.0],"facing":[1.0,0.0],"hp":100.0},"entities":[_enemy("rear",200),_enemy("front",240)],"projectiles":[{"id":7,"item_id":"wall_cannon","position":[100.0,220.0],"velocity":[1.0,0.0]}],"telegraphs":[{"shape":"circle","origin":[100,210],"radius":56,"active_from_tick":95}],"drops":[],"rules":{"enemy_catalog":{"basic":{"art_id":"titan_basic"}}},"escape_zone":[0,0,0,0]}
func _enemy(id: Variant,y: float) -> Dictionary:
	return {"id":id,"enemy_id":"basic","position":[100.0,y],"velocity":[0.0,0.0],"hp":100.0,"action_state":"move","action_started_tick":0}
func _terrain() -> Dictionary:
	return {"ok":true,"stage":"city","scene_id":"city","origin_chunk":["0","0"],"origin_revision":0,"world_revision":0,"cache_identity":[1,0,0],"chunks":[{"chunk_id":"0,0","local_origin":Vector2.ZERO,"ground_variant":2,"props":[{"prop_id":"house","asset_id":"house_narrow","position":Vector2(100,224),"depth_y":224.0,"render_bounds":Rect2(20,32,160,192),"pose":"intact"}]}]}
func _depth_and_markers(t,view) -> void:
	var state := _state()
	var terrain := _terrain()
	var state_before := state.duplicate(true)
	var terrain_before := terrain.duplicate(true)
	t.check(view.present_city(state,terrain).get("ok",false),"explicit matching terrain accepted")
	view._corpses.append({"id":"fallen","asset":"titan_basic","position":[100.0,218.0],"started":0.0})
	var packet: Dictionary = view._city_render_packet()
	t.check(packet.upright.map(func(c): return c.id) == ["actor:s:rear","actor:s:player","corpse:s:fallen","projectile:i:7","house","actor:s:front"],"actual WorldView adapts player corpse projectile and enemies into one foot-depth order")
	var emitted: Array = view.capture()
	var house := emitted.map(func(c): return c.asset).find("house_narrow")
	var player := emitted.map(func(c): return c.asset).find("garrison_01")
	t.check(player < house and emitted[player].world == Vector2(100,210),"rear player body really draws behind house at its foot anchor")
	t.check(emitted[house+1].asset == "titan_basic" and emitted[house+1].world.y == 240,"front enemy really draws after house")
	t.check(emitted.filter(func(c): return c.asset == "garrison_01").size() == 1,"occlusion does not redraw full player body in foreground")
	t.check(emitted.filter(func(c): return c.asset == "player_outline").size() == 1,"occluded player gets separate outline marker")
	t.check(emitted.back().asset == "warning","existing warning raster remains above city props actors and location outline")
	t.check(state == state_before and terrain == terrain_before,"presentation does not mutate RunState or derived terrain")
	state.player.position[1] = 250.0
	view.present_city(state,terrain)
	t.check(view.capture().filter(func(c): return c.asset == "player_outline").is_empty(),"front player does not get always-on outline")
	# Changes in prepared geometry, including destroyed assets, come from the view.
	var ruin := terrain.duplicate(true)
	ruin.cache_identity = [1,0,1]
	ruin.chunks[0].props[0].asset_id = "burning_rubble"
	ruin.chunks[0].props[0].pose = "ruined"
	ruin.chunks[0].props[0].render_bounds = Rect2(52,128,96,96)
	view.present_city(state,ruin)
	t.check(view.capture().any(func(c): return c.asset == "burning_rubble") and not view.capture().any(func(c): return c.asset == "house_narrow"),"ruin uses prepared approved raster rather than regenerating intact prop")
func _culling_and_rebase(t,view) -> void:
	view.reset_presentation()
	var state := _state()
	state.player.position = [100.0,75.0]
	state.entities = []; state.projectiles = []; state.telegraphs = []
	view._viewport_size = Vector2(200,150)
	var terrain := _terrain()
	view.present_city(state,terrain)
	var first: Dictionary = view._city_render_packet()
	t.check(first.upright.any(func(c): return c.id == "house"),"roof remains visible while prop foot lies below real camera")
	var player: Dictionary = first.upright.filter(func(c): return c.id == "actor:s:player")[0]
	var art: Dictionary = view._assets.garrison_01
	t.check(player.render_bounds == Rect2(Vector2(100,75)-Vector2(art.anchor_px[0],art.anchor_px[1]),Vector2(art.cell_w,art.cell_h)),"actor culling uses current manifest anchor and cell bounds")
	view._viewport_size = Vector2(220,600)
	t.check(view._city_render_packet().upright.map(func(c): return c.id) == first.upright.map(func(c): return c.id),"portrait layout retains identical overlapping depth order")
	view._viewport_size = Vector2(200,150)
	var offset := Vector2(-768,768)
	var shifted := terrain.duplicate(true)
	shifted.origin_chunk = ["9223372036854775000","-9223372036854775000"]
	shifted.origin_revision = 1
	shifted.chunks[0].local_origin += offset
	for prop in shifted.chunks[0].props:
		prop.position += offset; prop.depth_y += offset.y; prop.render_bounds.position += offset
	state.world.origin_chunk = shifted.origin_chunk.duplicate()
	state.world.origin_revision = 1
	state.player.position = [100+offset.x,75+offset.y]
	view.present_city(state,shifted)
	var rebased: Dictionary = view._city_render_packet()
	t.check(rebased.upright.map(func(c): return c.id) == first.upright.map(func(c): return c.id),"negative local coordinates and huge string origin preserve order")
	for i in first.upright.size(): t.check(rebased.upright[i].position-view._camera == first.upright[i].position-Vector2(100,75),"origin-relative screen geometry invariant")
	state.player.position = [2000.0,2000.0]
	view.present_city(state,shifted)
	t.check(not view._city_render_packet().upright.any(func(c): return c.id == "house"),"off-art-bounds prop culled by real camera")
func _explicit_activation_and_dock(t,view) -> void:
	var state := _state()
	var wrong := _terrain()
	wrong.origin_revision = 1
	t.check(not view.present_city(state,wrong).get("ok",true) and view.capture().is_empty(),"mismatched geometry fails closed instead of finite fallback or stale city")
	t.check(not view.present_city(state,{}).get("ok",true) and view.capture().is_empty(),"missing prepared geometry does not render finite fallback")
	var stale := _terrain()
	state.world.world_revision = 1
	t.check(not view.present_city(state,stale).get("ok",true) and view.capture().is_empty(),"same-origin stale prop geometry rejects by world revision")
	state.world.world_revision = 0
	view.present(state)
	t.check(view.capture()[0].asset == "authored_ground","plain present retains finite path and never infers city activation")
	view._map = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/map.json"))
	state.world.stage = "dock"
	var dock := {"ok":true,"stage":"dock","scene_id":"authored_dock","origin_chunk":["0","0"],"origin_revision":0,"world_revision":0,"chunks":[]}
	t.check(view.present_city(state,dock).get("ok",false),"explicit authored dock accepted only with verified authored geometry")
	t.check(view.capture()[0].asset == "authored_ground" and not view.capture().any(func(c): return c.asset == "chunk_ground"),"explicit dock uses authored dock ground, never streamed city floor")
	dock.scene_id = "unknown"
	t.check(not view.present_city(state,dock).get("ok",true) and view.capture().is_empty(),"unknown dock scene fails closed")
func _real_prepared_terrain(t,view) -> void:
	var provider = load("res://game/director/streamed_chapter_provider.gd").new()
	var core = load("res://game/core/run_simulation.gd").new(provider)
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var fixture = load("res://tests/core/core_fixture.gd")
	var state: Dictionary = core.new_run(chapter,42,fixture.run_config())
	var helper = load("res://game/core/streamed_run_world.gd")
	var hydration: Dictionary = load("res://tests/core_world/new_streamed_helper_fixture.gd").hydration(helper.requirements(state))
	t.check(core.prepare_world(state,hydration).get("ok",false),"actual city Core prepares terrain for presentation")
	var terrain: Dictionary = core.world_render_view(state)
	terrain.world_revision = core.world_status().get("world_revision",state.world.world_revision)
	var before := state.duplicate(true)
	t.check(view.present_city(core.snapshot(state),terrain).get("ok",false),"actual Core snapshot plus its own prepared helper terrain reaches WorldView")
	var packet: Dictionary = view._city_render_packet()
	t.check(not packet.ground.is_empty() and packet.upright.any(func(c): return c.id.begins_with("city:city_v1:")),"actual generated visible chunks and props reach draw commands")
	var geometry = view._city_view
	for tick in range(1,6):
		fixture.step(core,state,Vector2.RIGHT)
		view.present_city(core.snapshot(state),terrain)
		t.check(is_same(geometry,view._city_view),"per-frame present retains immutable terrain reference without 49-chunk copy")
	t.check(state.active_tick == 5 and before.world == state.world,"real traversal advances Core only through Core ticks")
	var chunk: Dictionary = terrain.chunks[0]
	var prop: Dictionary = chunk.props.filter(func(p): return p.destructible)[0]
	state.world.world_revision = 1
	state.world.dirty_chunks = [{"chunk":chunk.chunk,"props":[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}]}]
	t.check(core.prepare_world(state,hydration).get("ok",false),"actual Core prepares changed same-origin destroyed geometry")
	t.check(not view.present_city(core.snapshot(state),terrain).get("ok",true),"actual prepared Core rejects earlier same-origin render geometry revision")
	var changed: Dictionary = core.world_render_view(state)
	changed.world_revision = core.world_status().world_revision
	t.check(view.present_city(core.snapshot(state),changed).get("ok",false),"new exact Core render geometry revision is accepted")
	t.check(changed.chunks[0].props.filter(func(p): return p.prop_id == prop.prop_id)[0].asset_id == "burning_rubble","actual prepared destroyed prop carries approved ruin asset")

func _raster_marker(t,view) -> void:
	view.reset_presentation()
	var state := _state()
	state.entities = []; state.projectiles = []; state.telegraphs = []
	state.player.position = [100.0,40.0]
	view.present_city(state,_terrain())
	t.check(view.capture().filter(func(c): return c.asset == "player_outline").is_empty(),"transparent roof rectangle overlap is not actual raster occlusion")
	state.player.position = [100.0,100.0]
	view.present_city(state,_terrain())
	t.check(view.capture().filter(func(c): return c.asset == "player_outline").size() == 1,"opaque house alpha really triggers player location outline")
	var region: Rect2 = view.frame_rect("garrison_01","idle",0)
	var mask: Texture2D = view._player_outline_texture(region)
	t.check(mask != null and mask == view._player_outline_texture(region),"raster-derived outline is cached by animation frame")
	if mask == null: return
	var source: Image = view._texture("garrison_01").get_image().get_region(Rect2i(region))
	var image := mask.get_image()
	var filled := 0
	var overlaps := 0
	var distinct := true
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.a > 0:
				filled += 1
				if source.get_pixel(x,y).a > 0.1: overlaps += 1
				if color.b <= color.r or color.g <= color.r: distinct = false
	t.check(filled > 0 and overlaps == 0,"location marker is only source-alpha contour, never a recolored full body")
	t.check(distinct,"cyan player marker is chromatically distinct from red/yellow hazard")
func _rebase_observations(t,view) -> void:
	view.reset_presentation()
	var state := _state()
	state.entities = []; state.projectiles = []; state.telegraphs = []
	var terrain := _terrain()
	view.present_city(state,terrain)
	view._corpses.append({"id":"persistent-death","asset":"titan_basic","position":[100.0,205.0],"started":0.0})
	view._effects.append({"asset":"slash_fx","position":[100.0,200.0],"started":0.0})
	var offset := Vector2(-768,768)
	var shifted := terrain.duplicate(true)
	shifted.origin_chunk = ["1","-1"]; shifted.origin_revision = 1
	shifted.chunks[0].local_origin += offset
	for prop in shifted.chunks[0].props:
		prop.position += offset; prop.depth_y += offset.y; prop.render_bounds.position += offset
	state.world.origin_chunk = shifted.origin_chunk.duplicate(); state.world.origin_revision = 1
	state.player.position = [100+offset.x,210+offset.y]
	view.present_city(state,shifted)
	t.check(Vector2(view._corpses[0].position[0],view._corpses[0].position[1])-view._camera == Vector2(0,-5),"whole-chunk rebase preserves local corpse screen position")
	t.check(Vector2(view._effects[0].position[0],view._effects[0].position[1])-view._camera == Vector2(0,-10),"whole-chunk rebase preserves transient effect screen position")
	t.check(view._city_render_packet().upright.any(func(c): return c.id == "corpse:s:persistent-death"),"rebase preserves corpse stable identity")

func _event_corpses(t,view) -> void:
	view.reset_presentation()
	var state := _state()
	view.present_city(state,_terrain())
	var events: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"rear","hp":0,"source_id":"blade_slash"}}]
	view.consume_events(events)
	t.check(view._corpses.size() == 1 and view._corpses[0].id == "rear:1","existing damage event produces stable corpse presentation identity")
	state.entities.remove_at(0)
	view.present_city(state,_terrain())
	var packet: Dictionary = view._city_render_packet()
	t.check(packet.upright.any(func(c): return c.id == "corpse:s:rear:1" and c.depth_y == 200 and c.pose == "death"),"death event corpse keeps foot depth after actor leaves live state")
	view.capture()
	t.check(view._city_render_packet().upright.any(func(c): return c.id == "corpse:s:rear:1"),"corpse ID does not depend on render frame or array order")

func _registered_cannon_traversal(t) -> void:
	var view := Capture.new()
	view.load_manifest()
	t.check(view._assets.get("vfx_cannon_shell",{}).get("vfx_approved",false), "registered cannon traversal uses actual approved manifest art")
	if not view._assets.get("vfx_cannon_shell",{}).get("vfx_approved",false): view.free(); return
	var provider = load("res://game/director/streamed_chapter_provider.gd").new()
	var core = load("res://game/core/run_simulation.gd").new(provider)
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var state: Dictionary = core.new_run(chapter,42,CoreFixture.run_config())
	state.equipment = {"wall_cannon":1}
	var helper = load("res://game/core/streamed_run_world.gd")
	var hydration: Dictionary = load("res://tests/core_world/new_streamed_helper_fixture.gd").hydration(helper.requirements(state))
	t.check(core.prepare_world(state,hydration).get("ok",false), "registered cannon case prepares real city Core")
	var point: Array = state.player.position
	var spawn := CoreFixture.spawn("registered-shell-target",[point[0]+48.0,point[1]],"brute")
	spawn.origin_revision = state.world.origin_revision
	var events: Array[Dictionary] = CoreFixture.step(core,state,Vector2.ZERO,[spawn])
	t.check(core.step_status().get("ok",false) and state.projectiles.size() == 1, "real successful city tick launches the registered wall cannon shell")
	if state.projectiles.size() != 1: view.free(); return
	var current: Dictionary = core.snapshot(state)
	var terrain: Dictionary = core.world_render_view(state)
	terrain.world_revision = core.world_status().world_revision
	var before := current.duplicate(true)
	view.consume_combat_events(events,current)
	t.check(view.present_city(current,terrain).get("ok",false), "registered projectile receives its same-tick prepared city presentation")
	var packet: Dictionary = view._city_render_packet()
	t.check(not packet.upright.any(func(c): return c.id.begins_with("projectile:")), "approved drawable shell removes its exact legacy city projectile")
	var emitted: Array = view.capture()
	var shells: Array = emitted.filter(func(c): return c.asset == "vfx_cannon_shell")
	t.check(shells.size() == 1 and not emitted.any(func(c): return c.asset == "debris_fx"), "actual registered source emits one captured raster with no duplicate generic shell")
	if shells.size() == 1:
		var shell: Dictionary = shells[0].command
		t.check(shell.world_anchor == Vector2(state.projectiles[0].position[0],state.projectiles[0].position[1]) and shell.projectile_id == state.projectiles[0].id, "registered raster command follows exact live Core projectile identity and position")
		t.check(shell.source_sha256 == view._assets.vfx_cannon_shell.sha256 and shell.render_pass == "world", "captured GPU command is bound to registered source hash and world pass")
	t.check(current == before, "registered presentation leaves the actual Core snapshot immutable")
	view.free()
