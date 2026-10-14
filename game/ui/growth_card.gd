class_name GrowthCard
extends Button
# Presentation only. Conditions and effects arrive from ProgressionView.
signal chosen(option_id: String)
const Icons = preload("res://game/ui/skill_icons.gd")
var _option: Dictionary = {}
var _display := ""
var _requirements: VBoxContainer
var _information: Button
var _inline_styles: Dictionary = {}
var _inline_padding := Vector4.ZERO
var _inline_queued := false
const ITEM_NAMES := {
	"blade_slash":"쌍검 전방 베기", "spin_slash":"회전 베기", "odm_dash":"입체기동 돌진",
	"reentry_combo":"재진입 연격", "wall_cannon":"성벽 포격", "ally_cover":"동료 엄호",
	"movement":"가벼운 발걸음", "fire_interval":"신속한 재장전", "damage":"단련된 검술",
	"max_health":"병사의 체력", "recovery":"응급 처치", "pickup_radius":"보급 회수",
	"attack_range":"기동 거리", "armor":"방어 자세", "tactical_seal":"전술 개조권"
}
const REASONS := {
	"missing_weapon":"필요 무기 미보유", "missing_passive":"필요 패시브 미보유",
	"weapon_level":"무기 레벨 부족", "passive_level":"패시브 레벨 부족",
	"seal_required":"전술 개조권 부족", "equipment_slots":"장비 슬롯이 모두 찼습니다",
	"passive_slots":"패시브 슬롯이 모두 찼습니다", "chapter_not_allowed":"현재 시나리오에서 사용할 수 없습니다",
	"already_evolved":"진화 완료"
}
func _init() -> void:
	custom_minimum_size = Vector2(0,48)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	expand_icon = true
	add_theme_color_override("font_color",Color("f0dfba"))
	add_theme_font_size_override("font_size",15)
	add_theme_constant_override("icon_max_width",40)
	pressed.connect(_choose)
func attach_inline_controls(requirements: VBoxContainer, information: Button) -> void:
	_requirements = requirements
	_information = information
	# Each card owns its style copies; content reservation never changes the
	# shared theme or the native information button's independent hit target.
	for state in ["normal","hover","focus","pressed","disabled"]:
		var style: StyleBox = get_theme_stylebox(state).duplicate()
		_inline_styles[state] = style
		add_theme_stylebox_override(state,style)
	var base: StyleBox = _inline_styles.normal
	_inline_padding = Vector4(base.get_margin(SIDE_LEFT),base.get_margin(SIDE_TOP),base.get_margin(SIDE_RIGHT),base.get_margin(SIDE_BOTTOM))
	resized.connect(_queue_inline_layout)
	_requirements.minimum_size_changed.connect(_queue_inline_layout)
	# Wrapped prerequisite rows settle after native container sorting. A reused
	# card must release the temporary narrow-width height from its first bind.
	_requirements.sort_children.connect(_queue_inline_layout)
	sync_inline_layout()
func _queue_inline_layout() -> void:
	if _inline_queued or not is_inside_tree(): return
	_inline_queued = true
	call_deferred("sync_inline_layout")
func sync_inline_layout() -> void:
	_inline_queued = false
	if not is_instance_valid(_requirements) or not is_instance_valid(_information) or not is_inside_tree(): return
	var has_requirements := _requirements.get_child_count() > 0
	# Narrow landscape grid cells need a full-width summary; reserving half
	# of a 338px card leaves only ~103px after the native skill icon.
	var right_column := has_requirements and size.x >= 480
	var inner_width := maxf(1,size.x-_inline_padding.x-_inline_padding.z)
	var requirement_width := floorf((inner_width-8)/2) if right_column else inner_width
	_requirements.size.x = requirement_width
	var requirement_height: float = _requirements.get_combined_minimum_size().y if has_requirements else 0.0
	_information.size = Vector2(48,48)
	_information.position = Vector2(size.x-_inline_padding.z-48,_inline_padding.y)
	var reserve_right := requirement_width+8 if right_column else 56.0
	var reserve_bottom := requirement_height+6 if has_requirements and not right_column else 0.0
	for style in _inline_styles.values():
		var right: float = _inline_padding.z+reserve_right
		var bottom: float = _inline_padding.w+reserve_bottom
		if style.content_margin_right != right: style.content_margin_right = right
		if style.content_margin_bottom != bottom: style.content_margin_bottom = bottom
	_requirements.position = Vector2(size.x-_inline_padding.z-requirement_width if right_column else _inline_padding.x,_inline_padding.y+54 if right_column else maxf(_inline_padding.y,size.y-_inline_padding.w-requirement_height))
	_requirements.size.y = requirement_height
	var height: float = _inline_padding.y+48+_inline_padding.w+(requirement_height+6 if right_column else 0)
	if custom_minimum_size.y != height: custom_minimum_size.y = height
func present(option: Dictionary, summary_text: String = "") -> void:
	_option = option.duplicate(true)
	set_meta("semantic_id",str(option.get("option_id","")))
	icon = Icons.texture_for(Icons.icon_id_for(option))
	var parts: Array[String] = [str(option.get("name","성장"))]
	if str(option.get("kind","")) == "evolution":
		parts.append("진화 · "+level_change_text(option)+" · "+("진화 완료" if str(option.get("status","")) == "evolved" else ("선행조건 충족" if bool(option.get("can_select",true)) else "선행조건 확인")))
	elif option.has("level"):
		parts.append(level_change_text(option))
	var description := str(option.get("description",""))
	if not description.is_empty(): parts.append(description)
	var delta := effect_text(option.get("effect_delta",{}))
	if not delta.is_empty() and not description.contains(delta): parts.append(delta)
	if option.has("evolution_previews"):
		var preview := evolution_previews_text(option.evolution_previews,_selected_attack_id(option))
		if not preview.is_empty(): parts.append(preview)
	else:
		var requirements := requirements_text(visible_requirements(option.get("requirements",[]),_selected_attack_id(option)))
		if not requirements.is_empty():
			var heading := "진화 선행조건" if str(option.get("kind","")) == "evolution" else "목표 진화 조건"
			parts.append(heading+"\n"+requirements)
	var warning := str(option.get("slot_warning",option.get("last_slot_warning","")))
	if not warning.is_empty(): parts.append(warning)
	var tradeoff := str(option.get("tradeoff_text",""))
	if not tradeoff.is_empty(): parts.append("대가 · "+tradeoff)
	disabled = str(option.get("status","")) == "evolved" or not bool(option.get("can_select",true))
	if disabled:
		parts.append("진화 완료" if str(option.get("status","")) == "evolved" else reason_text(str(option.get("blocked_reason",""))))
	else:
		parts.append("A · 선택")
	_display = player_text("\n\n".join(parts))
	text = summary(option) if summary_text.is_empty() else summary_text
	tooltip_text = _display
func clear() -> void:
	_option = {}
	_display = ""
	text = ""
	icon = null
	tooltip_text = ""
	set_meta("semantic_id","")
	disabled = true
func display_text() -> String:
	return _display
func _choose() -> void:
	if not disabled: chosen.emit(str(_option.get("option_id","")))
static func evolution_requirement_text(requirement: Dictionary) -> String:
	var title := str(requirement.get("name",requirement.get("item_id","조건")))
	var required := int(requirement.get("required",0))
	if not requirement.has("current"): return "%s · 필요 Lv %d" % [title,required]
	var current := int(requirement.current)
	var status := "충족 ✓" if requirement.get("met",false) else ("미보유" if current == 0 else "부족")
	if requirement.get("kind","") == "seal": return "%s · %d/%d · %s" % [title,current,required,status]
	return "%s · Lv %d/%d · %s" % [title,current,required,status]
static func _selected_attack_id(option: Dictionary) -> String:
	return str(option.get("item_id","")) if option.get("kind","") in ["equipment","evolution"] else ""
static func visible_requirements(requirements: Array, selected_attack_id: String = "") -> Array:
	# Presentation only: keep the authoritative base-level gate in the DTO.
	# Other attacks, passives and costs still show their exact required progress.
	return requirements.filter(func(required): return selected_attack_id.is_empty() or required.get("kind","") != "equipment" or required.get("item_id","") != selected_attack_id or required.get("requirement_type","") != "base_level")
static func evolution_previews_text(previews: Array, selected_attack_id: String = "") -> String:
	var parts: Array[String] = []
	for detail in previews:
		var lines: Array[String] = ["궁극 · "+str(detail.get("name",""))]
		for required in visible_requirements(detail.get("requirements",[]),selected_attack_id): lines.append(evolution_requirement_text(required))
		if detail.get("status","") == "unavailable": lines.append(reason_text("chapter_not_allowed"))
		elif detail.get("status","") == "evolved": lines.append("진화 완료")
		parts.append("\n".join(lines))
	return "\n\n".join(parts)
static func append_evolution_requirements(container: VBoxContainer, option: Dictionary) -> void:
	if not option.has("evolution_previews"):
		Icons.append_requirements(container,visible_requirements(option.get("requirements",[]),_selected_attack_id(option)))
		return
	Icons.append_requirements(container,[])
	for detail in option.evolution_previews:
		var title := Label.new()
		title.text = "궁극 · "+str(detail.get("name",""))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size",13)
		title.add_theme_color_override("font_color",Color("f0dfba"))
		container.add_child(title)
		var rows := VBoxContainer.new()
		var requirements := visible_requirements(detail.get("requirements",[]),_selected_attack_id(option))
		Icons.append_requirements(rows,requirements)
		var index := 0
		for row in rows.get_children():
			row.get_node("Text").text = evolution_requirement_text(requirements[index])
			rows.remove_child(row)
			container.add_child(row)
			index += 1
		rows.free()
	container.visible = not option.evolution_previews.is_empty()
static func requirements_text(requirements: Array) -> String:
	var lines: Array[String] = []
	for requirement in requirements:
		var id := str(requirement.get("item_id",""))
		var item_name := str(requirement.get("name",ITEM_NAMES.get(id,id)))
		var named: Dictionary = requirement.duplicate()
		named.name = item_name
		var line := Icons.requirement_text(named)
		var reason := str(requirement.get("blocked_reason",""))
		if reason in ["equipment_slots","passive_slots","chapter_not_allowed","missing_weapon","missing_passive"]: line += "\n"+reason_text(reason)
		lines.append(line)
	return "\n".join(lines)
static func reason_text(reason: String) -> String:
	return str(REASONS.get(reason,"선택할 수 없습니다" if not reason.is_empty() else ""))
static func level_change_text(option: Dictionary) -> String:
	var level := int(option.get("display_level",option.get("level",0)))
	var next := int(option.get("display_next_level",option.get("next_level",level)))
	# Older DTO fixtures remain readable; UI never invents a catalog cap.
	if not option.has("display_max_level") and not option.has("max_level"): return "Lv %d → %d" % [level,next]
	var cap := int(option.get("display_max_level",option.get("max_level",0)))
	if level == 0: return "신규 습득 · Lv %d/%d → %d/%d" % [level,cap,next,cap]
	if next == cap: return "Lv %d/%d → MAX %d/%d" % [level,cap,next,cap]
	return "Lv %d/%d → %d/%d" % [level,cap,next,cap]
static func summary(option: Dictionary) -> String:
	var parts: Array[String] = [str(option.get("name","성장"))]
	var levels := level_change_text(option).replace("신규 습득 · Lv ","신규 습득 ").replace("MAX ","")
	if str(option.get("kind","")) == "evolution": parts.append(levels.trim_prefix("Lv "))
	elif option.has("level"): parts.append(levels)
	var effect := brief_effect_text(option.get("effect_delta",{}))
	if not effect.is_empty(): parts.append(effect)
	var warning := str(option.get("slot_warning",option.get("last_slot_warning","")))
	if not warning.is_empty(): parts.append("주의 · "+warning)
	if option.get("kind","") == "evolution":
		for requirement in option.get("requirements",[]):
			if requirement.get("kind","") == "seal" and int(requirement.get("required",0)) > 0:
				parts.append("개조권 %d개 소비" % int(requirement.required))
	var done := str(option.get("status","")) == "evolved"
	var blocked := done or not bool(option.get("can_select",true))
	if blocked: parts.append("진화 완료" if done else reason_text(str(option.get("blocked_reason",""))))
	return player_text("\n".join(parts))
static func brief_effect_text(delta: Dictionary) -> String:
	# The selection face names one real change. Complete effect geometry and
	# authored descriptions stay in display_text() and the information modal.
	if delta.has("stat") and delta.has("before") and delta.has("after"):
		var names := {"damage_multiplier":"피해","cooldown_multiplier":"간격","move_multiplier":"이동","max_hp":"체력","regen_per_second":"회복/초","pickup_radius":"수집 반경","range_multiplier":"공격 범위","armor":"피해 감소"}
		return "%s %s→%s" % [names.get(str(delta.stat),str(delta.stat)),str(delta.before).trim_suffix(".0"),str(delta.after).trim_suffix(".0")]
	if delta.has("damage_before") and delta.has("damage_after"):
		return "피해 %s→%s" % [str(delta.damage_before).trim_suffix(".0"),str(delta.damage_after).trim_suffix(".0")]
	return effect_text(delta).split("\n")[0]
static func effect_text(delta: Dictionary) -> String:
	if delta.has("text"): return str(delta.text)
	var names := {"damage":"피해", "cooldown_ticks":"공격 간격", "cooldown":"공격 간격", "range":"공격 범위", "radius":"반경", "move_speed":"이동 속도", "max_hp":"최대 체력", "value":"효과", "attack_range":"공격 범위", "pickup_radius":"수집 반경"}
	var lines: Array[String] = []
	if delta.has("stat") and delta.has("before") and delta.has("after"):
		var stats := {"damage_multiplier":"공격 피해 배율","cooldown_multiplier":"공격 간격 배율","move_multiplier":"이동 속도 배율","max_hp":"최대 체력","regen_per_second":"초당 체력 회복","pickup_radius":"수집 반경","range_multiplier":"공격 범위 배율","armor":"피해 감소"}
		lines.append("%s %s → %s" % [stats.get(str(delta.stat),str(delta.stat)),str(delta.before),str(delta.after)])
	for key in delta:
		if str(key).ends_with("_before"):
			var prefix := str(key).trim_suffix("_before")
			if delta.has(prefix+"_after"):
				var before := seconds_text(delta[key]) if prefix in ["cooldown","cooldown_ticks"] else str(delta[key])
				var after := seconds_text(delta[prefix+"_after"]) if prefix in ["cooldown","cooldown_ticks"] else str(delta[prefix+"_after"])
				lines.append("%s %s → %s" % [names.get(prefix,prefix),before,after])
	if delta.has("stages"): lines.append("연속 타격 %d회" % int(delta.stages))
	if delta.has("stage_damage"): lines.append("단계별 피해 "+_number_list(delta.stage_damage))
	if delta.has("stage_delays"):
		var times: Array[String] = []
		for tick in delta.stage_delays: times.append(seconds_text(tick))
		lines.append("타격 시점 "+" / ".join(times))
	if delta.has("radius") and (not delta.has("length") or float(delta.radius) > 0): lines.append("반경 %s" % str(delta.radius))
	for field in ["length","width","advance_step","radius_step"]:
		if delta.has(field):
			var label: String = {"length":"직선 길이","width":"직선 폭","advance_step":"타격당 전진","radius_step":"타격당 반경 증가"}[field]
			lines.append(label+" "+str(delta[field]))
	if delta.has("cooldown_ticks"): lines.append("공격 간격 "+seconds_text(delta.cooldown_ticks))
	if delta.has("acquisition_range"): lines.append("목표 탐색 범위 %s" % str(delta.acquisition_range))
	if delta.has("arc_degrees"): lines.append("베기 범위 %s도" % str(delta.arc_degrees))
	if delta.has("point_offset"): lines.append("좌우 지점 간격 ±%s" % str(delta.point_offset))
	return "\n".join(lines)
static func seconds_text(ticks: float) -> String:
	return String.num(ticks/60.0,2)+"초"
static func player_text(value: String) -> String:
	# Authored recipes may describe fixed simulation ticks. Only the displayed
	# units change; the source DTO and combat timing stay untouched.
	var pattern := RegEx.new()
	pattern.compile("([0-9]+(?:\\.[0-9]+)?)틱")
	var result := value
	var matches := pattern.search_all(value)
	matches.reverse()
	for item in matches:
		result = result.left(item.get_start())+seconds_text(float(item.get_string(1)))+result.substr(item.get_end())
	return result
static func _number_list(values: Array) -> String:
	var parts: Array[String] = []
	for value in values: parts.append(str(value))
	return " / ".join(parts)
