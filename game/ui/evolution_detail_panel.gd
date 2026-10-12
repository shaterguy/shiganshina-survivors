class_name EvolutionDetailPanel
extends VBoxContainer
const Card = preload("res://game/ui/growth_card.gd")
var _label: Label
var _display := ""
func present(detail: Dictionary) -> void:
	if not is_instance_valid(_label):
		_label = Label.new()
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_color_override("font_color",Color("f0dfba"))
		add_child(_label)
	var status := str(detail.get("status","unavailable"))
	var parts: Array[String] = [str(detail.get("name",detail.get("evolution_id","진화 레시피"))),str(detail.get("description",""))]
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
