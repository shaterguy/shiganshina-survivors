class_name ProgressionHUD
extends Control
# Eight fixed presentation slots. All numbers and eligibility come from the DTO.
signal details_requested
const Icons = preload("res://game/ui/skill_icons.gd")
var _slots: Array[Control] = []
var _entry: Button
var _target: Label
var _target_icon: TextureRect
var _signature: Label
var _signature_visible := false
var _display := ""
var _content: Dictionary = {}
var _highlight_id := ""
var _highlight_seconds := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry = Button.new()
	_entry.name = "OwnedSkillsEntry"
	_entry.flat = true
	_entry.focus_mode = Control.FOCUS_NONE
	_entry.tooltip_text = "보유 기술 · 전투를 멈추고 효과와 진화 조건 보기"
	_entry.custom_minimum_size = Vector2(48,48)
	_entry.pressed.connect(func(): details_requested.emit())
	add_child(_entry)
	for index in 8:
		var slot := Panel.new()
		slot.name = ("Equipment" if index < 4 else "Passive")+str(index%4)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("18211dd9")
		style.border_color = Color("665d40")
		style.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel",style)
		add_child(slot)
		_slots.append(slot)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)
		for label_name in ["Name","Status"]:
			var label := Label.new()
			label.name = label_name
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size",12 if label_name == "Name" else 13)
			label.add_theme_color_override("font_color",Color("f0dfba"))
			if label_name == "Name": label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			slot.add_child(label)
	_target = Label.new()
	_target.name = "TargetRequirements"
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.add_theme_font_size_override("font_size",13)
	# Noto's two-line natural height is 43px with the default spacing. Keep
	# the reserved 39px row without reducing the readable font size.
	_target.add_theme_constant_override("line_spacing",-1)
	_target.add_theme_color_override("font_color",Color("e6c88d"))
	_target.add_theme_color_override("font_shadow_color",Color("18211d"))
	_target.add_theme_constant_override("shadow_offset_x",1)
	_target.add_theme_constant_override("shadow_offset_y",1)
	_target.add_theme_constant_override("shadow_outline_size",0)
	add_child(_target)
	_target_icon = TextureRect.new()
	_target_icon.name = "TargetIcon"
	_target_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_target_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_target_icon)
	_signature = Label.new()
	_signature.name = "CharacterSkill"
	_signature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signature.add_theme_font_size_override("font_size",13)
	_signature.add_theme_color_override("font_color",Color("e6c88d"))
	_signature.hide()
	add_child(_signature)
	set_process(false)
	reflow(Vector2(288,108))
func reflow(bounds: Vector2) -> void:
	size = bounds
	_entry.size = Vector2(bounds.x,108)
	var slot_width := (bounds.x-6.0)/4.0
	for index in _slots.size():
		var slot := _slots[index]
		slot.position = Vector2((index%4)*(slot_width+2),int(index/4)*34)
		slot.size = Vector2(slot_width,33)
		var title: Label = slot.get_node("Name")
		title.hide()
		var icon: TextureRect = slot.get_node("Icon")
		icon.position = Vector2(3,4)
		icon.size = Vector2(24,24)
		var status: Label = slot.get_node("Status")
		status.position = Vector2(30,6)
		status.size = Vector2(slot_width-33,21)
	_target.position = Vector2(20 if _target_icon.texture != null else 0,69)
	_target.size = Vector2(bounds.x-_target.position.x,39)
	_target_icon.position = Vector2(0,70)
	_target_icon.size = Vector2(16,16)
	_signature.position = Vector2(0,108)
	_signature.size = Vector2(bounds.x,24)
func present_signature(view: Dictionary) -> bool:
	var visible_now := bool(view.get("visible",false))
	var changed := visible_now != _signature_visible
	_signature_visible = visible_now
	_signature.visible = visible_now
	var text := str(view.get("text",""))
	if _signature.text != text: _signature.text = text
	return changed
func signature_visible() -> bool:
	return _signature_visible
func present(view: Dictionary) -> void:
	var content := {"owned":view.get("owned",{}),"target":view.get("target",{}),"evolutions":view.get("evolutions",[])}
	if content == _content: return
	_content = content.duplicate(true)
	var lines: Array[String] = []
	for index in 8:
		var rows: Array = content.owned.get("equipment" if index < 4 else "passives",[])
		var row: Dictionary = rows[index%4] if index%4 < rows.size() else {}
		var title := str(row.get("name",""))
		var status := ""
		if not row.is_empty():
			status = "%d/%d" % [int(row.get("display_level",row.get("level",0))),int(row.get("display_max_level",row.get("max_level",0)))]
			if row.get("is_evolved",false): title = str(row.get("evolution_name",evolution_name(view,str(row.get("evolution_id","")))))
		_slots[index].set_meta("item_id",str(row.get("item_id","")))
		_slots[index].modulate.a = 0.3 if row.is_empty() else 1.0
		_slots[index].get_node("Icon").texture = null if row.is_empty() else Icons.texture_for(Icons.icon_id_for(row))
		_slots[index].tooltip_text = "" if row.is_empty() else title+" · "+level_text(row)
		_slots[index].get_node("Name").text = ""
		_slots[index].get_node("Status").text = status
		if not status.is_empty(): lines.append(status)
	_target_icon.texture = Icons.texture_for("skill_"+str(content.target.get("evolution_id","")))
	_target.text = target_summary(content.target) if content.has("owned") and not content.owned.is_empty() else "기술 정보 확인 중"
	_target.visible = not _target.text.is_empty()
	_target_icon.visible = _target.visible and _target_icon.texture != null
	_target.tooltip_text = target_text(content.target)
	_entry.tooltip_text = "보유 기술 · 전투를 멈추고 효과와 진화 조건 보기\n"+_target.tooltip_text
	if _target.visible: lines.append(_target.text)
	_display = "\n".join(lines)
	reflow(size)
func slot_controls() -> Array[Control]:
	return _slots.duplicate()
func display_text() -> String:
	return _display
func highlight(item_id: String) -> void:
	_highlight_id = item_id
	_highlight_seconds = 0.2
	for slot in _slots:
		if slot.get_meta("item_id","") == item_id: slot.get_theme_stylebox("panel").border_color = Color("f4c36b")
	set_process(true)
func _process(delta: float) -> void:
	_highlight_seconds = maxf(0,_highlight_seconds-delta)
	if _highlight_seconds > 0: return
	for slot in _slots: slot.get_theme_stylebox("panel").border_color = Color("665d40")
	_highlight_id = ""
	set_process(false)
static func level_text(row: Dictionary) -> String:
	var level := int(row.get("display_level",row.get("level",0)))
	var cap := int(row.get("display_max_level",row.get("max_level",0)))
	if row.get("is_evolved",false): return "진화 %d/%d" % [level,cap]
	return ("MAX %d/%d" if row.get("is_max",false) else "Lv %d/%d") % [level,cap]
static func evolution_name(view: Dictionary, id: String) -> String:
	for recipe in view.get("evolutions",[]):
		if recipe.get("evolution_id","") == id: return str(recipe.get("name",id))
	return id
static func target_text(target: Dictionary) -> String:
	if target.is_empty(): return "보유 기술 · 눌러서 효과 확인"
	var conditions: Array[String] = []
	var blocked := false
	for requirement in target.get("requirements",[]):
		blocked = blocked or requirement.get("blocked_reason","") in ["equipment_slots","passive_slots"]
		conditions.append(Icons.requirement_text(requirement))
	var heading := str(target.get("name","목표 진화"))
	if blocked: heading = "필수 슬롯 없음"
	elif target.get("status","") == "ready": heading = "진화 준비 완료 · 다음 성장 선택"
	elif target.get("status","") == "evolved": return heading+" · 진화 완료\n보유 기술 · 눌러서 효과 확인"
	if conditions.is_empty(): return heading
	if target.get("status","") == "ready": return heading+"\n"+" · ".join(conditions)
	return heading+" · "+conditions[0]+"\n"+" · ".join(conditions.slice(1))
static func target_summary(target: Dictionary) -> String:
	if target.is_empty() or target.get("status","") == "evolved": return ""
	var heading := str(target.get("name","목표 진화"))
	var status := str(target.get("status",""))
	var state := str({"ready":"준비","blocked":"조건 제한"}.get(status,"재료 부족"))
	for requirement in target.get("requirements",[]):
		if requirement.get("blocked_reason","") in ["equipment_slots","passive_slots"]: state = "슬롯 부족"
	return heading+" · "+state
