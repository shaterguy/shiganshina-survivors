extends RefCounted
const PATH := "res://game/presentation/combat_vfx_catalog.gd"
# Production changes these catch: omitted skill, unsafe raster, mutable recipe,
# negative lifespan, unknown pass, duplicated identity or removed reduced-mode main shape.
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "combat VFX catalog exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(), "combat VFX catalog loads")
	if script == null or not script.can_instantiate(): return
	var catalog = script.new()
	var manifest := manifest_fixture(catalog)
	t.check(catalog.validate(manifest).is_empty(), "eight distinct raster recipes validate with approved metadata")
	var names: Array = []
	for pair in skill_pairs():
		var r: Dictionary = catalog.recipe(pair[0],pair[1],"cast")
		t.check(not r.is_empty(), "recipe exists: "+str(pair))
		if r.is_empty(): continue
		names.append(r.recipe_id)
		t.check(r.layers.size() > 0 and r.layers[0].reduce_mode == "preserve", "reduced mode preserves main form: "+r.recipe_id)
		t.check(r.shape_binding != "", "recipe binds actual core geometry: "+r.recipe_id)
	t.check(names.size() == 8 and _unique(names).size() == 8, "six base and two evolved recipe names are unique")
	t.check(catalog.recipe("blade_slash","","cast").duration_ticks == 10, "blade recovery is ten visual ticks")
	t.check(catalog.recipe("spin_slash","","cast").duration_ticks == 14, "spin recovery is fourteen visual ticks")
	t.check(catalog.recipe("blade_slash","","cast").art_id != catalog.recipe("spin_slash","","cast").art_id, "spin is separate art rather than slash recolor")
	var copy: Dictionary = catalog.recipe("blade_slash","","cast")
	copy.layers[0].art_id = "corrupted"
	t.check(catalog.recipe("blade_slash","","cast").layers[0].art_id != "corrupted", "recipe is a deep copy")
	t.check(catalog.recipe("blade_slash","evo_wing_cut","aim").is_empty(), "wing cannot expose completed slash as an invented windup")
	t.check(catalog.recipe("wall_cannon","evo_wing_cut","cast").is_empty(), "evolution cannot map to the wrong base")
	var empty_errors: Array = catalog.validate({"assets":{}})
	t.check(_contains(empty_errors,"missing_art:"), "missing raster is explicit and fails final validation")
	manifest.assets[catalog.recipe("blade_slash","","cast").art_id].vfx_approved = false
	t.check(_contains(catalog.validate(manifest),"unapproved_art:"), "unapproved raster is rejected")
	var source: Dictionary = catalog.definition_data()
	var bad: Dictionary = source.duplicate(true)
	bad.recipes.remove_at(0)
	t.check(_contains(script.new(bad).validate(manifest_fixture(catalog)),"missing_skill:"), "missing skill is rejected")
	bad = source.duplicate(true)
	bad.recipes[1].recipe_id = bad.recipes[0].recipe_id
	t.check(_contains(script.new(bad).validate(manifest_fixture(catalog)),"duplicate_recipe:"), "duplicate recipe ID rejected")
	bad = source.duplicate(true)
	bad.recipes[0].phases.cast.duration_ticks = -1
	t.check(_contains(script.new(bad).validate(manifest_fixture(catalog)),"invalid_duration:"), "negative lifetime rejected")
	bad = source.duplicate(true)
	bad.recipes[0].phases.cast.render_pass = "magic"
	t.check(_contains(script.new(bad).validate(manifest_fixture(catalog)),"invalid_pass:"), "unknown render pass rejected")
	_review_metadata_contract(t,catalog)
	var live = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(live is Dictionary, "real manifest readable for final raster diagnostic")
	if live is Dictionary:
		var actual: Array = catalog.validate(live)
		print("VFX_RASTER_VALIDATION ",actual)
func skill_pairs() -> Array:
	return [["blade_slash",""],["spin_slash",""],["odm_dash",""],["reentry_combo",""],["wall_cannon",""],["ally_cover",""],["blade_slash","evo_wing_cut"],["wall_cannon","evo_crossfire"]]
func manifest_fixture(catalog) -> Dictionary:
	var assets: Dictionary = {}
	for requirement in catalog.art_requirements():
		var cell: Array = requirement.cell_px
		assets[requirement.art_id] = {"path":"res://tests/fixture.png","kind":"effect","vfx_approved":true,"sha256":"a".repeat(64),"cell_w":cell[0],"cell_h":cell[1],"width":cell[0]*4,"height":cell[1]*2,"columns":4,"anchor_px":requirement.pivot_px,"vfx_bounds_px":requirement.contact_bounds_px,"animations":{"attack":{"frames":[0,1,2,3,4,5,6,7],"loop":false}}}
	return {"assets":assets}
func _unique(values: Array) -> Array:
	var output: Array = []
	for value in values:
		if not value in output: output.append(value)
	return output
func _contains(values: Array, prefix: String) -> bool:
	for value in values:
		if str(value).begins_with(prefix): return true
	return false

func malformed_metadata_cases() -> Array[Dictionary]:
	return [
		{"field":"cell_w","value":0},{"field":"cell_h","value":64},
		{"field":"width","value":511},{"field":"width","value":"512"},
		{"field":"height","value":INF},{"field":"columns","value":5},
		{"field":"anchor_px","value":[0,0]},{"field":"anchor_px","value":[64]},
		{"field":"anchor_px","value":[64,NAN]},
		{"field":"vfx_bounds_px","value":[-1,0,128,128]},
		{"field":"vfx_bounds_px","value":[0,0,128]},
		{"field":"vfx_bounds_px","value":[0,0,-1,128]},
		{"field":"vfx_bounds_px","value":[0,0,"128",128]},
		{"field":"vfx_bounds_px","value":[0,0,128,INF]},
		{"field":"animations","value":{"attack":{"frames":[-1,1,2,3,4,5,6,7],"loop":false}}},
		{"field":"animations","value":{"attack":{"frames":[0,1,2,3,4,5,6,999],"loop":false}}},
		{"field":"animations","value":{"attack":{"frames":[0],"loop":false}}},
		{"field":"animations","value":{"attack":{"frames":"bad","loop":false}}},
		{"field":"animations","value":"bad"},
		{"field":"sha256","value":"z".repeat(64)},{"field":"sha256","value":"a".repeat(32)},
		{"field":"vfx_approved","value":"true"},{"field":"kind","value":"sprite"},
		{"field":"contact_frame","value":1},{"field":"forward_axis","value":"-X"},
		{"field":"__raw_asset","value":[1,2]}
	]
func _review_metadata_contract(t, catalog) -> void:
	t.check(catalog.has_method("validate_art_metadata"), "V3 reusable structural metadata validator exists without approving art")
	for change in malformed_metadata_cases():
		var bad := manifest_fixture(catalog)
		if change.field == "__raw_asset":
			bad.assets.vfx_blade_crescent = change.value
		else:
			bad.assets.vfx_blade_crescent[change.field] = change.value
		t.check(not catalog.validate(bad).is_empty(), "V3 catalog rejects malformed approved metadata "+change.field+str(change.value))
	if catalog.has_method("validate_art_metadata"):
		t.check(not catalog.validate_art_metadata("vfx_blade_crescent",[1,2]).is_empty(), "V3 non-dictionary metadata is rejected without indexing or type errors")
	var approved := manifest_fixture(catalog)
	t.check(catalog.validate(approved).is_empty(), "V3 exact authored wire offset and all per-ID atlas contracts remain valid")
	var candidate_path := "res://docs/art/vfx/primary-runtime-candidate.json"
	if not FileAccess.file_exists(candidate_path):
		print("VFX_CANDIDATE_VALIDATION missing_candidate_metadata:",candidate_path," actual_art_review=incomplete")
		return
	var parser := JSON.new()
	var parsed := parser.parse(FileAccess.get_file_as_string(candidate_path))
	t.check(parsed == OK and parser.data is Dictionary, "V3 optional real candidate metadata is readable")
	if parsed != OK or not parser.data is Dictionary: return
	var candidate: Dictionary = parser.data
	t.check(candidate.get("assets") is Dictionary, "V3 optional real candidate has asset metadata")
	if not candidate.get("assets") is Dictionary: return
	if candidate is Dictionary:
		if catalog.has_method("validate_art_metadata"):
			for id in candidate.assets:
				t.check(catalog.validate_art_metadata(id,candidate.assets[id]).is_empty(), "V3 A candidate matches authoritative structure without gaining approval "+id)
		var before: Dictionary = candidate.duplicate(true)
		var result: Array = catalog.validate(candidate)
		t.check(_contains(result,"unapproved_art:"), "V3 A candidate metadata stays unapproved at production boundary")
		t.check(candidate == before, "V3 candidate approval flags and source metadata stay immutable")
