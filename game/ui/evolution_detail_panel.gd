class_name EvolutionDetailPanel
extends VBoxContainer
const Card = preload("res://game/ui/growth_card.gd")
const Icons = preload("res://game/ui/skill_icons.gd")
const HUD = preload("res://game/ui/progression_hud.gd")
var _label: Label
var _requirements: VBoxContainer
var _icon: TextureRect
var _display := ""
func present(detail: Dictionary) -> void:
	if not is_instance_valid(_label):
		_icon = TextureRect.new()
		_icon.name = "SkillIcon"
		_icon.custom_minimum_size = Vector2(32,32)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		_label = Label.new()
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_color_override("font_color",Color("f0dfba"))
		add_child(_label)
		_requirements = VBoxContainer.new()
		_requirements.name = "Requirements"
		add_child(_requirements)
	_icon.texture = Icons.texture_for(str(detail.get("icon_id","skill_"+str(detail.get("evolution_id","")))))
	Icons.append_requirements(_requirements,detail.get("requirements",[]))
	var status := str(detail.get("status","unavailable"))
	var parts: Array[String] = [str(detail.get("name",detail.get("evolution_id","진화 레시피"))),str(detail.get("description",""))]
	if detail.has("display_level") and detail.has("display_max_level"):
		parts[0] += " · %d/%d" % [int(detail.display_level),int(detail.display_max_level)]
	parts.append("상태 · "+str({"unavailable":"아직 준비되지 않음","collecting":"선행 기술 수집 중","blocked":"슬롯 또는 시나리오 제한","ready":"성장 선택에서 진화 가능","evolved":"진화 완료"}.get(status,status)))
	parts.append("선행조건\n"+Card.requirements_text(detail.get("requirements",[])))
	var effect := Card.effect_text(detail.get("effect_delta",{}))
	if not effect.is_empty(): parts.append("실제 변화\n"+effect)
	var tradeoff := str(detail.get("tradeoff_text",""))
	if not tradeoff.is_empty(): parts.append("대가 · "+tradeoff)
	parts.append("조건을 갖춘 뒤 성장 카드에서 선택합니다.")
	_display = Card.player_text("\n\n".join(parts))
	_label.text = _display
func display_text() -> String:
	return _display
func present_owned(row: Dictionary, evolution: Dictionary) -> void:
	# Reuse the existing recipe body and append only authoritative owned facts.
	present(evolution)
	var recipe_text := _display
	var level := HUD.level_text(row)
	var title := str(row.get("name","기술 정보 확인 중"))+" · "+level
	if row.get("is_evolved",false): title = str(row.get("evolution_name",evolution.get("name",row.get("name",""))))+" · "+level
	_icon.texture = Icons.texture_for(Icons.icon_id_for(row))
	var parts: Array[String] = [title,str(row.get("attack_summary","")),current_effect_text(row.get("effect_stats",{}))]
	if evolution.is_empty(): parts.append(("MAX · " if row.get("is_max",false) else "")+"추가 진화 없음")
	else: parts.append(recipe_text)
	_display = Card.player_text("\n\n".join(parts))
	_label.text = _display
static func current_effect_text(stats: Dictionary) -> String:
	var lines: Array[String] = []
	var labels := {"damage":"타격당 피해","total_damage":"총 피해","hits":"연속 타격 수","range":"공격 범위","splash_radius":"폭발 반경"}
	for key in labels:
		if stats.has(key): lines.append("%s %s" % [labels[key],str(stats[key])])
	if stats.has("stat") and stats.has("value"):
		var names := {"damage_multiplier":"공격 피해 배율","cooldown_multiplier":"공격 간격 배율","move_multiplier":"이동 속도 배율","max_hp":"최대 체력","regen_per_second":"초당 체력 회복","pickup_radius":"수집 반경","range_multiplier":"공격 범위 배율","armor":"피해 감소"}
		lines.append("%s %s" % [names.get(str(stats.stat),str(stats.stat)),str(stats.value)])
	var effect := Card.effect_text(stats)
	if not effect.is_empty(): lines.append(effect)
	return "\n".join(lines)
