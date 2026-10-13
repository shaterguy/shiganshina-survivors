extends RefCounted
# Shared presentation mapping; gameplay identity and eligibility stay in the DTO.
const ART_IDS := {
	"blade_slash":"icon_twin_blades","spin_slash":"icon_spin_slash","odm_dash":"icon_omni_dash",
	"reentry_combo":"icon_reentry_combo","wall_cannon":"icon_wall_cannon","ally_cover":"icon_ally_cover",
	"damage":"icon_damage","fire_interval":"icon_cooldown","movement":"icon_movement",
	"max_health":"icon_health","recovery":"icon_regeneration","pickup_radius":"icon_pickup",
	"attack_range":"icon_range","armor":"icon_armor"
}
# All generated motifs use the same palette. Their geometry carries identity.
const SHAPES := {
	"chain_lightning":'<path d="M8 9h8l-5 10h9l-6 12 15-17h-9l5-9"/><circle cx="6" cy="9" r="2"/><circle cx="30" cy="14" r="2"/>',
	"fire_zone":'<path d="M17 4c3 8-5 8-1 14 1-3 4-3 5-6 7 7 8 13 1 17H11C3 23 6 17 11 13c-1 7 2 8 3 7-4-8 2-10 3-16z"/><path d="M5 32h26"/>',
	"evo_wing_cut":'<path d="M6 28L24 7l3-2-1 5L8 30zM12 31L30 10l3-2-1 5-18 20z"/><path d="M4 19l9-10M18 5l7-2"/>',
	"evo_whirlwind":'<path d="M5 18a13 13 0 1 1 10 13M5 18l-2-6M5 18l7-2M15 31l-5 2"/><path d="M11 25L25 10l2-1-1 3-13 15zM10 10l15 15M13 8L9 12M28 23l-4 4"/>',
	"evo_sky_lance":'<path d="M18 3l5 8-3 15-2 7-2-7-3-15z"/><path d="M4 30L12 7M32 30L24 7M3 29l5-4M33 29l-5-4M9 34l4-9M27 34l-4-9"/>',
	"evo_echo_assault":'<path d="M6 11l7-6 5 6-5 7zM15 18l7-6 5 6-5 7zM21 27l7-5 5 5-5 7z"/><path d="M4 22h8M3 27h11M8 32h10"/>',
	"evo_crossfire":'<path d="M4 7h7l16 22-4 3L7 12zM25 7h7l-3 5-16 20-4-3z"/><circle cx="6" cy="30" r="3"/><circle cx="30" cy="30" r="3"/><path d="M15 3v5M21 3v5"/>',
	"evo_wing_squad":'<circle cx="18" cy="9" r="4"/><circle cx="6" cy="13" r="3"/><circle cx="30" cy="13" r="3"/><path d="M12 27V19l6-5 6 5v8M2 29v-9l4-3 4 3v9M26 29v-9l4-3 4 3v9M9 32h18"/>',
	"evo_storm_chain":'<path d="M7 11c-5-1-4-7 1-7 1-5 8-5 10-1 5-2 9 0 9 4 7-1 8 6 2 7H8"/><path d="M11 15l-4 7h7l-3 11 12-16h-7l3-6M28 19l-3 7h5l-4 7"/>',
	"evo_inferno_zone":'<path d="M18 3c8 9 13 16 6 23H12C4 19 11 13 13 8c0 7 2 9 4 10-4-6 2-9 1-15z"/><path d="M3 30l8-2 7 5 7-5 8 2M4 22l-2-5M31 22l3-5M7 33l-2 1M29 33l2 1"/>',
	"tactical_seal":'<path d="M18 3l4 6 7 1 1 7-4 5 1 8-9-3-9 3 1-8-4-5 1-7 7-1z"/><path d="M12 17l4 4 8-10"/>'
}
static var _textures: Dictionary = {}
static var _manifest: Dictionary = {}
static func icon_id_for(row: Dictionary) -> String:
	var declared := str(row.get("icon_id",""))
	if not declared.is_empty(): return declared
	var id := str(row.get("evolution_id","")) if row.get("is_evolved",false) or row.get("kind","") == "evolution" else ""
	if id.is_empty(): id = str(row.get("item_id",row.get("id","")))
	return "skill_"+id if not id.is_empty() else ""
static func texture_for(icon_id: String) -> Texture2D:
	var id := icon_id.trim_prefix("skill_")
	if _textures.has(id): return _textures[id]
	var texture: Texture2D
	if ART_IDS.has(id):
		if _manifest.is_empty():
			var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
			if manifest is Dictionary: _manifest = manifest.get("assets",{})
		var path := str(_manifest.get(ART_IDS[id],{}).get("path",""))
		if ResourceLoader.exists(path): texture = load(path) as Texture2D
	elif SHAPES.has(id):
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 36 36"><g fill="none" stroke="#f0dfba" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+str(SHAPES[id])+'</g></svg>'
		if image.load_svg_from_string(svg) == OK: texture = ImageTexture.create_from_image(image)
	if texture != null: _textures[id] = texture
	return texture
static func requirement_text(requirement: Dictionary) -> String:
	var title := str(requirement.get("name",requirement.get("item_id","조건")))
	var required := int(requirement.get("required",0))
	# Preparation DTOs have no current run; do not invent owned/met facts.
	if not requirement.has("current"):
		return title+" · 필요 보유 1 이상" if requirement.get("requirement_type","") == "owned_skill" else "%s · 필요 Lv %d" % [title,required]
	var current := int(requirement.get("current",0))
	var met := bool(requirement.get("met",false))
	if requirement.get("requirement_type","") == "owned_skill":
		return title+" · "+("보유 ✓" if bool(requirement.get("owned",current >= 1)) else "미보유")
	var ownership := "보유 ✓" if current >= 1 else "미보유"
	if requirement.get("kind","") == "seal": ownership = "충족 ✓" if met else "부족"
	return "%s %d/%d · %s%s" % [title,current,required,ownership," · 레벨 부족" if current >= 1 and not met else ""]
static func append_requirements(container: VBoxContainer, requirements: Array) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_theme_constant_override("separation",2)
	for requirement in requirements:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation",4)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(18,18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = texture_for(str(requirement.get("icon_id","skill_"+str(requirement.get("item_id","")))))
		row.add_child(icon)
		var label := Label.new()
		label.name = "Text"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",13)
		label.add_theme_color_override("font_color",Color("f0dfba"))
		label.text = requirement_text(requirement)
		row.add_child(label)
		container.add_child(row)
	container.visible = not requirements.is_empty()
