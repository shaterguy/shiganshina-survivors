class_name SupplyShopPanel
extends VBoxContainer
# Economics are supplied DTO facts. This component emits no price or request ID.
signal purchase_requested(item_id: String, view_revision: int)
var _view: Dictionary = {}
var _buttons: Array[Button] = []
var _items: Dictionary = {}
var _balance: Label
var _status: Label
var _pending := false
var _awaiting_fresh_view := false
var _pending_revision := -1
const REASONS := {
	"insufficient_funds":"보급금 부족", "already_owned":"이미 보유한 영구 교리",
	"inventory_full":"보급품 재고 한도", "active_run":"진행 중인 출격이 있어 구매할 수 없습니다",
	"not_owned":"보유하지 않음", "stale_revision":"정보가 바뀌었습니다. 최신 보급소를 확인하세요",
	"write_failed":"저장에 실패했습니다. 잔액은 최신 저장 확인 후 갱신됩니다",
	"verify_failed":"저장 확인에 실패했습니다", "backup_failed":"저장 백업에 실패했습니다",
	"replace_failed":"저장 교체에 실패했습니다", "commit_outcome_unknown":"구매 결과 확인 중입니다. 다시 구매하지 마세요",
	"read_failed":"저장 정보를 읽을 수 없습니다", "invalid_loadout":"출격 준비를 확인하세요"
}
func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
func present(view: Dictionary) -> void:
	_view = view.duplicate(true)
	if int(view.get("view_revision",-1)) != _pending_revision:
		_pending = false
		_awaiting_fresh_view = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_items.clear()
	_balance = _label("보급금 · 잔액 %d" % int(view.get("balance",0)))
	_balance.add_theme_font_size_override("font_size",20)
	if not bool(view.get("can_shop",false)): _label(reason_text(str(view.get("lock_reason","active_run"))))
	for item in view.get("items",[]):
		var id := str(item.get("item_id",""))
		var button := Button.new()
		button.set_meta("semantic_id","purchase:"+id)
		button.set_meta("art_id","icon_"+id)
		button.custom_minimum_size = Vector2(0,48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",16)
		var kind := "영구 교리 해금" if str(item.get("kind","")) == "doctrine" else "소모 보급"
		var lines: Array[String] = [str(item.get("name",id))+" · "+kind,str(item.get("description","")),"가격 %d · 구매 후 %d" % [int(item.get("price",0)),int(item.get("balance_after",view.get("balance",0)))]]
		var tradeoff := str(item.get("tradeoff_text",""))
		if not tradeoff.is_empty(): lines.append("대가 · "+tradeoff)
		lines.append("보유 %d/%d" % [int(item.get("owned",0)),int(item.get("max_owned",1))])
		var reason := str(item.get("blocked_reason",""))
		if not bool(view.get("can_shop",false)): reason = str(view.get("lock_reason","active_run"))
		if not reason.is_empty(): lines.append(reason_text(reason))
		button.disabled = not bool(view.get("can_shop",false)) or not bool(item.get("can_purchase",false)) or _pending or _awaiting_fresh_view
		lines.append("A · 구매" if not button.disabled else "구매 불가")
		button.text = "\n".join(lines)
		button.pressed.connect(func(): _purchase(id))
		add_child(button)
		_buttons.append(button)
		_items[id] = button
	_status = _label("최신 저장 정보를 확인하는 중입니다" if _awaiting_fresh_view else ("구매 저장 중…" if _pending else "구매한 교리는 출격 준비에서 따로 장착합니다."))
func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color",Color("f0dfba"))
	add_child(label)
	return label
func _purchase(id: String) -> void:
	if _pending or _awaiting_fresh_view or not _items.has(id) or _items[id].disabled: return
	_pending = true
	_pending_revision = int(_view.get("view_revision",0))
	for button in _buttons: button.disabled = true
	_status.text = "구매 저장 중…"
	purchase_requested.emit(id,_pending_revision)
func present_action_result(result: Dictionary) -> void:
	_pending = false
	_awaiting_fresh_view = true
	# Success is shown only as a result; balances still come from the next view.
	_status.text = str(result.get("message","구매 완료 · 최신 저장 확인 중" if bool(result.get("ok",false)) else reason_text(str(result.get("error_code","write_failed")))))
	for button in _buttons: button.disabled = true
func action_buttons() -> Array[Button]:
	return _buttons.duplicate()
func item_button(id: String) -> Button:
	return _items.get(id)
func display_text() -> String:
	var lines: Array[String] = []
	for child in get_children():
		if child is Label or child is Button: lines.append(child.text)
	return "\n".join(lines)
static func reason_text(reason: String) -> String:
	return str(REASONS.get(reason,"처리할 수 없습니다. 최신 정보를 확인하세요" if not reason.is_empty() else ""))
