class_name GrowthCard
extends Button
# Presentation only. Conditions and effects arrive from ProgressionView.
signal chosen(option_id: String)
var _option: Dictionary = {}
var _display := ""
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
	add_theme_color_override("font_color",Color("f0dfba"))
	add_theme_font_size_override("font_size",15)
	pressed.connect(_choose)
func present(option: Dictionary, summary_text: String = "") -> void:
	_option = option.duplicate(true)
	set_meta("semantic_id",str(option.get("option_id","")))
	var parts: Array[String] = [str(option.get("name","성장"))]
	if str(option.get("kind","")) == "evolution":
		parts.append("궁극 진화 · "+("진화 완료" if str(option.get("status","")) == "evolved" else ("선행조건 충족" if bool(option.get("can_select",true)) else "선행조건 확인")))
	elif option.has("level"):
		parts.append("Lv %d → %d" % [int(option.get("level",0)),int(option.get("next_level",option.get("level",0)))])
	var description := str(option.get("description",""))
	if not description.is_empty(): parts.append(description)
	var delta := effect_text(option.get("effect_delta",{}))
	if not delta.is_empty() and not description.contains(delta): parts.append(delta)
	var requirements := requirements_text(option.get("requirements",[]))
	if not requirements.is_empty(): parts.append("진화 선행조건\n"+requirements)
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
	text = _display if summary_text.is_empty() else summary_text
	tooltip_text = _display
func clear() -> void:
	_option = {}
	_display = ""
	text = ""
	tooltip_text = ""
	set_meta("semantic_id","")
	disabled = true
func display_text() -> String:
	return _display
func _choose() -> void:
	if not disabled: chosen.emit(str(_option.get("option_id","")))
static func requirements_text(requirements: Array) -> String:
	var lines: Array[String] = []
	for requirement in requirements:
		var id := str(requirement.get("item_id",""))
		var item_name := str(requirement.get("name",ITEM_NAMES.get(id,id)))
		var status := "충족" if bool(requirement.get("met",false)) else "부족"
		var line := "%s %d/%d · %s" % [item_name,int(requirement.get("current",0)),int(requirement.get("required",0)),status]
		var reason := str(requirement.get("blocked_reason",""))
		if reason in ["equipment_slots","passive_slots","chapter_not_allowed","missing_weapon","missing_passive"]: line += "\n"+reason_text(reason)
		lines.append(line)
	return "\n".join(lines)
static func reason_text(reason: String) -> String:
	return str(REASONS.get(reason,"선택할 수 없습니다" if not reason.is_empty() else ""))
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
	if delta.has("radius"): lines.append("반경 %s" % str(delta.radius))
	if delta.has("cooldown_ticks"): lines.append("공격 간격 "+seconds_text(delta.cooldown_ticks))
	if delta.has("acquisition_range"): lines.append("목표 탐색 범위 %s" % str(delta.acquisition_range))
	if delta.has("arc_degrees"): lines.append("베기 범위 %s도" % str(delta.arc_degrees))
	if delta.has("point_offset"): lines.append("포격 지점 간격 ±%s" % str(delta.point_offset))
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
