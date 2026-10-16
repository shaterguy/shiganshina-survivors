extends Control
# Four retained drawing slots, no per-pickup nodes, tweens or timers.
const GOLD = preload("res://game/presentation/loot_art/gold.svg")
const SKILL = preload("res://game/presentation/loot_art/skill.svg")
const POTION = preload("res://game/presentation/loot_art/potion.svg")
const MAX_ROWS := 4
var rows: Array[Dictionary] = []
var active := false
var run_id := ""
var event_seq := 0
var drop_ids := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 3
	resized.connect(_layout_rows)

func reset_run(id: String) -> void:
	if run_id == id: return
	run_id = id
	event_seq = 0
	rows.clear()
	drop_ids.clear()
	queue_redraw()

func sync_snapshot(snapshot: Dictionary) -> void:
	reset_run(str(snapshot.get("run_id","")))
	var placed := {}
	for potion in snapshot.get("loot",{}).get("potions",[]):
		if potion.get("status","") == "placed": placed[str(potion.id)] = true
	var changed := false
	for id in drop_ids.keys():
		if not placed.has(id):
			drop_ids.erase(id)
			changed = true
	if changed: _sync_drops()

func consume(events: Array, id: String) -> void:
	reset_run(id)
	# Filter once before correlating drop/collection; foreign/replayed events
	# must not suppress a new notification.
	var valid: Array[Dictionary] = []
	var collected := {}
	for event in events:
		if not event is Dictionary or not event.get("event_id") is String or not event.get("payload",{}) is Dictionary: continue
		var identity: String = event.get("event_id","")
		var prefix := run_id+":"
		if not identity.begins_with(prefix): continue
		var suffix := identity.trim_prefix(prefix)
		if not suffix.is_valid_int(): continue
		var serial := int(suffix)
		if serial <= event_seq or str(serial) != suffix: continue
		event_seq = serial
		valid.append(event)
		if event.get("type","") == "potion_collected": collected[event.get("payload",{}).get("potion_id","")] = true
	for event in valid:
		var payload: Dictionary = event.get("payload",{})
		match str(event.get("type","")):
			"loot_collected":
				if payload.get("reward","") == "gold": _push("gold","스킬 포화 · 골드" if payload.get("reason","") == "skill_pool_empty" else "골드",int(payload.get("amount",0)),0.0,GOLD)
				else: _push("skill","스킬 선택",1,0.0,SKILL)
			"potion_dropped":
				var potion_id: String = payload.get("potion_id","")
				if not collected.has(potion_id) and not potion_id.is_empty() and drop_ids.size() < 5:
					drop_ids[potion_id] = true
					_sync_drops()
			"potion_collected":
				drop_ids.erase(str(payload.get("potion_id","")))
				_sync_drops()
				_push("potion","회복 포션",int(payload.get("amount",1)),float(payload.get("healed_amount",0.0)),POTION)

func _sync_drops() -> void:
	_remove("drop")
	if not drop_ids.is_empty(): _push("drop","회복 포션 출현",drop_ids.size(),0.0,POTION)

func confirmed_skill(title: String, icon: Texture2D) -> void:
	_remove("skill")
	_push("confirmed",title,1,0.0,icon if icon != null else SKILL)

func _remove(kind: String) -> void:
	var changed := false
	for index in range(rows.size()-1,-1,-1):
		if rows[index].kind == kind:
			rows.remove_at(index)
			changed = true
	if changed: _layout_rows()

func _push(kind: String, title: String, amount: int, healed: float, icon: Texture2D) -> void:
	for row in rows:
		if row.kind == kind and row.title == title:
			row.amount = mini(2147483647,int(row.amount)+amount)
			row.healed = float(row.healed)+healed
			row.seconds = 2.5
			_layout_rows()
			return
	if rows.size() >= MAX_ROWS: rows.pop_front()
	rows.append({"kind":kind,"title":title,"amount":amount,"healed":healed,"icon":icon,"seconds":2.5})
	_layout_rows()

func row_text(row: Dictionary) -> String:
	if row.kind == "gold": return "%s +%d" % [row.title,int(row.amount)]
	if row.kind == "confirmed": return row.title
	if row.kind == "skill": return "스킬 선택 %d회" % int(row.amount)
	if row.kind == "potion":
		# Floor display precision, never advertise more recovery than was applied.
		var healed: float = floor(float(row.healed)*100.0)/100.0
		var number := ("%.2f" % healed).trim_suffix("0").trim_suffix("0").trim_suffix(".")
		if healed == 0.0 and float(row.healed) > 0.0: number = "0.01 미만"
		return "회복 포션 ×%d · HP +%s" % [int(row.amount),number]
	return "%s ×%d" % [row.title,int(row.amount)]

func _process(delta: float) -> void:
	if not active or rows.is_empty(): return
	var changed := false
	for index in range(rows.size()-1,-1,-1):
		rows[index].seconds = maxf(0.0,float(rows[index].seconds)-delta)
		if float(rows[index].seconds) <= 0.0:
			rows.remove_at(index)
			changed = true
	if changed: _layout_rows()

func _layout_rows() -> void:
	var font := get_theme_default_font()
	var width := maxf(80.0,size.x-45.0)
	var top := 0.0
	for row in rows:
		var lines: Array[String] = []
		var line := ""
		for character in row_text(row):
			if not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x > width:
				lines.append(line)
				line = ""
			line += character
		lines.append(line)
		row.lines = lines
		var text_width := 0.0
		for value in lines: text_width = maxf(text_width,font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x)
		row.width = minf(size.x,maxf(80.0,text_width+47.0))
		row.height = 32.0 if lines.size() == 1 else 48.0
		row.top = top
		top += float(row.height)+2.0
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	for index in rows.size():
		var row: Dictionary = rows[index]
		var top := float(row.get("top",0.0))
		var width := float(row.get("width",size.x))
		var height := float(row.get("height",32.0))
		draw_rect(Rect2(0,top,width,height),Color("192230"))
		draw_rect(Rect2(0,top,3,height),Color("f5d489"))
		draw_texture_rect(row.icon,Rect2(7,top+(height-26.0)*0.5,26,26),false)
		var lines: Array = row.get("lines",[])
		for line in mini(2,lines.size()):
			draw_string(font,Vector2(39,top+20+float(line)*19.0),str(lines[line]),HORIZONTAL_ALIGNMENT_LEFT,width-45,15,Color("fff5df"))
