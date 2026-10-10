extends RefCounted
const PATH := "res://game/presentation/combat_vfx_renderer.gd"
const CatalogTests = preload("res://tests/presentation_vfx/test_catalog.gd")
# Catch center/range drift, actor sprite rotation, invented anchors, unsafe art,
# animation wall-clock, reduced-mode shape removal and viewport clipping errors.
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "combat VFX renderer exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(), "combat VFX renderer loads")
	if script == null or not script.can_instantiate(): return
	var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
	var r = script.new()
	var fixture = CatalogTests.new()
	var metadata: Dictionary = fixture.manifest_fixture(catalog).assets
	var context := {"tick":10,"reduce_effects":false,"asset_metadata":metadata,"actor_positions":{"player":Vector2(8,9)},"origin_revision":0}
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized()]:
		for pair in [["blade_slash","sector"],["spin_slash","circle"],["odm_dash","line"],["wall_cannon","projectile"],["reentry_combo","targeted"]]:
			var geometry := {"shape":pair[1],"origin":[20,30],"position":[70,80],"direction":[direction.x,direction.y],"radius":4.0 if pair[1] == "projectile" else 54.0,"length":112.0,"width":28.0,"arc_degrees":150.0}
			var effect := effect_fixture(catalog,pair[0],geometry)
			var commands: Array[Dictionary] = r.commands(_effects([effect]),context)
			var main := _main(commands)
			t.check(not main.is_empty(), "main raster command exists "+str(pair)+str(direction))
			if main.is_empty(): continue
			t.check(main.world_anchor == (Vector2(70,80) if pair[1] == "targeted" else Vector2(20,30)), "command anchors to actual core center "+str(pair))
			t.check(main.contact_geometry == geometry, "command preserves actual contact geometry "+str(pair))
			t.check(is_equal_approx(main.rotation,0.0 if pair[1] in ["circle","targeted"] else direction.angle()), "only VFX aligns to attack direction "+str(pair))
			var expected := Vector2(112,28) if pair[1] == "line" else (Vector2(8,8) if pair[1] == "projectile" else Vector2(108,108))
			t.check(main.contact_size.is_equal_approx(expected), "raster bounds use actual geometry not nominal range "+str(pair))
			t.check(main.alpha >= 0 and main.alpha <= 1 and main.scale.x > 0 and main.scale.y > 0, "finite draw alpha and scale")
	var dash := effect_fixture(catalog,"odm_dash",{"shape":"line","origin":[0,0],"direction":[1,0],"length":100.0,"width":20.0,"radius":100.0})
	t.check(_component_count(r.commands(_effects([dash]),context),"wire") == 0, "no anchor means no invented wire")
	dash.geometry.wire_anchor = [100,0]
	t.check(_component_count(r.commands(_effects([dash]),context),"wire") == 1, "explicit actual anchor enables wire")

	var wire := _component(r.commands(_effects([dash]),context),"wire")
	t.check(is_equal_approx(wire.scale.y,1.0) and wire.contact_size == Vector2(100,2), "wire normalization retains two-pixel authored thickness")
	var wing := effect_fixture(catalog,"blade_slash",{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":88.0})
	wing.merge(catalog.recipe("blade_slash","evo_wing_cut","cast"),true)
	wing.stage_index = 0
	var first := _main(r.commands(_effects([wing]),context))
	wing.stage_index = 1
	var second := _main(r.commands(_effects([wing]),context))
	t.check(first.asset_id == "vfx_wing_first_arc" and second.asset_id == "vfx_wing_second_arc", "wing stages choose genuinely different curvature rasters")
	var basic := effect_fixture(catalog,"blade_slash",{"shape":"sector","origin":[20,30],"direction":[1,0],"radius":54.0})
	var unknown := context.duplicate(true)
	unknown.asset_metadata = {}
	var diagnostics: Array[Dictionary] = r.commands(_effects([basic]),unknown)
	t.check(diagnostics.size() > 0 and diagnostics[0].diagnostic == "missing_art", "missing art emits explicit diagnostics instead of final placeholder")
	unknown.asset_metadata = metadata.duplicate(true)
	unknown.asset_metadata[basic.art_id].vfx_approved = false
	t.check(r.commands(_effects([basic]),unknown)[0].diagnostic == "unapproved_art", "unapproved art is never drawn")
	_review_metadata_rejection(t,r,catalog,basic,context)
	var normal: Array[Dictionary] = r.commands(_effects([basic]),context)
	var reduced := context.duplicate(true)
	reduced.reduce_effects = true
	var low: Array[Dictionary] = r.commands(_effects([basic]),reduced)
	t.check(not _main(low).is_empty() and low.size() <= normal.size(), "reduced mode retains main raster and removes optional detail")
	var end := context.duplicate(true)
	end.tick = 20
	t.check(r.commands(_effects([basic]),end).is_empty(), "expired effects cannot draw")
	var late := context.duplicate(true)
	late.tick = 19
	t.check(_main(r.commands(_effects([basic]),late)).alpha < _main(normal).alpha, "recovery fades on active ticks")
	t.check(_main(r.commands(_effects([basic]),late)).atlas_region != _main(normal).atlas_region, "atlas frame follows active ticks")
	var clipped := context.duplicate(true)
	clipped.visible_rect = Rect2(1000,1000,10,10)
	t.check(r.commands(_effects([basic]),clipped).is_empty(), "offscreen raster commands are culled by transformed bounds")
	var translated := basic.duplicate(true)
	translated.origin -= Vector2(100,200)
	translated.geometry.origin = [-80,-170]
	translated.origin_revision = 1
	var shifted_context := context.duplicate(true)
	shifted_context.origin_revision = 1
	t.check(_main(r.commands(_effects([translated]),shifted_context)).world_anchor == Vector2(-80,-170), "renderer honors rebased world origin")
	var actor := basic.duplicate(true)
	actor.coordinate_space = "actor"
	actor.actor_id = "player"
	actor.actor_offset = Vector2(2,3)
	t.check(_main(r.commands(_effects([actor]),context)).world_anchor == Vector2(10,12), "actor attachment consumes actor position without rotating actor")
func effect_fixture(catalog, base: String, geometry: Dictionary) -> Dictionary:
	var phase := "projectile" if geometry.shape == "projectile" else "cast"
	var recipe: Dictionary = catalog.recipe(base,"",phase)
	var result := recipe.duplicate(true)
	result.merge({"effect_id":"test:"+base,"attack_id":"test:0","start_tick":10,"end_tick":10+int(recipe.duration_ticks),"coordinate_space":"world","origin":Vector2(geometry.origin[0],geometry.origin[1]),"direction":Vector2(geometry.direction[0],geometry.direction[1]),"geometry":geometry.duplicate(true),"intensity_tier":1,"origin_revision":0},true)
	return result
func _main(commands: Array) -> Dictionary:
	for c in commands:
		if c.get("component","") == "main" and not c.has("diagnostic"): return c
	return {}
func _component_count(commands: Array, component: String) -> int:
	return commands.filter(func(c): return c.get("component","") == component and not c.has("diagnostic")).size()

func _effects(values: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values: output.append(value)
	return output

func _component(commands: Array, name: String) -> Dictionary:
	for command in commands:
		if command.get("component","") == name and not command.has("diagnostic"): return command
	return {}

func _review_metadata_rejection(t, renderer, catalog, basic: Dictionary, context: Dictionary) -> void:
	var fixture = CatalogTests.new()
	t.check(catalog.has_method("validate_art_metadata"), "V3 renderer shares catalog structural metadata authority")
	if catalog.has_method("validate_art_metadata"):
		for change in fixture.malformed_metadata_cases():
			var malformed := context.duplicate(true)
			malformed.asset_metadata = fixture.manifest_fixture(catalog).assets
			if change.field == "__raw_asset":
				malformed.asset_metadata.vfx_blade_crescent = change.value
			else:
				malformed.asset_metadata.vfx_blade_crescent[change.field] = change.value
			var rejected: Array[Dictionary] = renderer.commands(_effects([basic]),malformed)
			t.check(rejected.size() == 1 and rejected[0].has("diagnostic"), "V3 all malformed arrays and numeric metadata fail closed "+change.field+str(change.value))
	# These remain well-shaped arrays, so RED proves a missing rejection rather
	# than being obscured by pre-existing short-array indexing crashes.
	for change in [{"field":"anchor_px","value":[0,0]},{"field":"animations","value":{"attack":{"frames":[0,1,2,3,4,5,6,999],"loop":false}}},{"field":"vfx_bounds_px","value":[1,0,127,128]},{"field":"sha256","value":"z".repeat(64)},{"field":"width","value":511},{"field":"vfx_approved","value":"true"}]:
		var bad := context.duplicate(true)
		bad.asset_metadata = fixture.manifest_fixture(catalog).assets
		bad.asset_metadata.vfx_blade_crescent[change.field] = change.value
		var output: Array[Dictionary] = renderer.commands(_effects([basic]),bad)
		t.check(output.size() == 1 and output[0].has("diagnostic"), "V3 renderer fails closed for approved malformed metadata "+change.field)
