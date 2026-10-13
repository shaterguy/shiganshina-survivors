class_name LoadoutPanel
extends VBoxContainer
const Card = preload("res://game/ui/growth_card.gd")
const Icons = preload("res://game/ui/skill_icons.gd")
const Shop = preload("res://game/ui/supply_shop_panel.gd")
signal loadout_changed(selection: Dictionary, view_revision: int)
signal character_selected(character_id: String, view_revision: int)
signal run_start_requested
var _view: Dictionary = {}
var _selection: Dictionary = {}
var _buttons: Array[Button] = []
var _options: Dictionary = {}
var _start: Button
var _status: Label
var _pending := false
var _pending_revision := -1
func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
func present(view: Dictionary) -> void:
	_view = view.duplicate(true)
	_selection = view.get("loadout",{}).duplicate(true)
	if int(view.get("view_revision",-1)) != _pending_revision: _pending = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_options.clear()
	_present_characters(view)
	var groups := {"doctrines":"doctrine_id","targets":"target_evolution_id","supplies":"supply_item_id"}
	var titles := {"doctrines":"활성 교리 · 하나만 장착","targets":"목표 진화 · 출격 후에는 변경할 수 없습니다","supplies":"소모 보급 · 0–1개 장착"}
	for group in groups:
		_label(titles[group]).add_theme_font_size_override("font_size",18)
		var key: String = groups[group]
		for option in view.get("loadout_options",{}).get(group,[]):
			var id := str(option.get("id",""))
			var selected := str(_selection.get(key,"")) == id
			var lines: Array[String] = [("[장착] " if selected else "")+str(option.get("name",id))]
			if group != "targets": lines.append(Card.player_text(str(option.get("description",""))))
			var tradeoff := str(option.get("tradeoff_text",""))
			if not tradeoff.is_empty() and group != "targets": lines.append("대가 · "+Card.player_text(tradeoff))
			if group == "targets":
				if option.has("seal_cost") and int(option.seal_cost) > 0:
					lines.append("보스 처치로 획득한 전술 개조권 %d개 소비" % int(option.seal_cost))
			if option.has("owned") and not id.is_empty(): lines.append("보유 %d" % int(option.owned))
			var reason := str(option.get("blocked_reason",""))
			if not reason.is_empty(): lines.append(Shop.reason_text(reason))
			var button := _button("\n".join(lines),"loadout:"+key+":"+id)
			button.set_meta("art_id","icon_"+id)
			if group == "targets":
				button.set_meta("skill_icon_id",str(option.get("icon_id","skill_"+id)))
				button.icon = Icons.texture_for(str(button.get_meta("skill_icon_id")))
				button.add_theme_constant_override("icon_max_width",32)
				button.tooltip_text = Card.player_text(str(option.get("description","")))+"\n"+Card.player_text(tradeoff)
				var requirements := VBoxContainer.new()
				requirements.name = "Requirements_"+id
				Icons.append_requirements(requirements,option.get("requirements",[]))
				add_child(requirements)
			button.disabled = _pending or not bool(option.get("can_select",false))
			button.pressed.connect(func(): _change(key,id))
			_options[key+":"+id] = button
	_label("장착한 소모 보급은 출격 시 1개 소비됩니다. 사용하지 않아도 반환되지 않습니다.")
	_status = _label("출격 준비 저장 중…" if _pending else "장착 변경은 저장 확인 후 적용됩니다.")
	_start = _button("준비 완료 · 출격","run_start")
	_start.disabled = _pending or not bool(view.get("can_start",false))
	_start.pressed.connect(_request_start)
	if not bool(view.get("can_start",false)): _label(Shop.reason_text(str(view.get("start_blocked_reason","active_run"))))
func _present_characters(view: Dictionary) -> void:
	if view.get("character_options",[]).is_empty(): return
	_label("재도전 캐릭터 · 클리어한 시나리오").add_theme_font_size_override("font_size",18)
	for option in view.character_options:
		var id := str(option.get("id",""))
		var selected := bool(option.get("is_selected",false))
		var lines: Array[String] = [("[선택] " if selected else "")+str(option.get("name",id)),str(option.get("trait_text",""))]
		if option.get("art_status","") != "ready": lines.append("전용 원화 미구현"+(" · 임시 외형" if option.get("implementation_status","") == "prototype" else ""))
		if option.get("unique_skill",{}).get("implementation_status","") == "implemented": lines.append("고유 · 집중 연격 · 자동 3타 · 재사용 12초 (초기 수치)")
		var unfinished: Array[String] = []
		if option.get("unique_skill",{}).get("implementation_status","") == "planned": unfinished.append("고유 공격 미구현")
		if option.get("signature_ultimate",{}).get("implementation_status","") == "planned": unfinished.append("대표 궁극 미구현")
		if not unfinished.is_empty(): lines.append(" · ".join(unfinished))
		var reason := str(option.get("blocked_reason",""))
		if not reason.is_empty(): lines.append(Shop.reason_text(reason))
		elif not selected: lines.append("A · 다음 출격 캐릭터 선택")
		var button := _button("\n".join(lines),"character:"+id)
		button.add_theme_font_size_override("font_size",15)
		button.tooltip_text = str(option.get("description",""))
		button.disabled = _pending or selected or not bool(option.get("can_select",false))
		button.pressed.connect(func(): _select_character(id))
		_options["character_id:"+id] = button
func _select_character(id: String) -> void:
	var button := option_button("character_id",id)
	if _pending or button == null or button.disabled: return
	_pending = true
	_pending_revision = int(_view.get("view_revision",0))
	for action in _buttons: action.disabled = true
	_status.text = "캐릭터 선택 저장 중…"
	character_selected.emit(id,_pending_revision)
func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color",Color("f0dfba"))
	add_child(label)
	return label
func _button(value: String, id: String) -> Button:
	var button := Button.new()
	button.text = value
	button.set_meta("semantic_id",id)
	button.custom_minimum_size = Vector2(0,48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(button)
	_buttons.append(button)
	return button
func _change(key: String, id: String) -> void:
	var button := option_button(key,id)
	if _pending or button == null or button.disabled: return
	var candidate := _selection.duplicate(true)
	candidate[key] = id
	_pending = true
	_pending_revision = int(_view.get("view_revision",0))
	for action in _buttons: action.disabled = true
	_status.text = "출격 준비 저장 중…"
	loadout_changed.emit(candidate,_pending_revision)
func _request_start() -> void:
	if _pending or _start.disabled: return
	_pending = true
	_pending_revision = int(_view.get("view_revision",0))
	for action in _buttons: action.disabled = true
	_status.text = "출격 저장 중…"
	run_start_requested.emit()
func present_action_result(result: Dictionary) -> void:
	_pending = true # Require a newly presented authority revision to rearm.
	_status.text = str(result.get("message","준비 저장 완료 · 최신 정보 확인 중" if bool(result.get("ok",false)) else Shop.reason_text(str(result.get("error_code","write_failed")))))
	for action in _buttons: action.disabled = true
func selection() -> Dictionary:
	return _selection.duplicate(true)
func action_buttons() -> Array[Button]:
	return _buttons.duplicate()
func option_button(key: String, id: String) -> Button:
	return _options.get(key+":"+id)
func start_button() -> Button:
	return _start
func display_text() -> String:
	var lines: Array[String] = []
	for child in get_children():
		if child is Label or child is Button: lines.append(child.text)
		elif child is VBoxContainer and str(child.name).begins_with("Requirements_"):
			for row in child.get_children(): lines.append(row.get_node("Text").text)
	return "\n".join(lines)
