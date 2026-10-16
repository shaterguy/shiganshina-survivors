extends RefCounted
const Existing = preload("res://tests/chest_potion/test_reward_feedback.gd")
const Feedback = preload("res://game/ui/reward_feedback.gd")
func run(t) -> void:
	Existing.new().run(t)
	var view := Feedback.new()
	view.theme = Theme.new()
	view.theme.default_font = load("res://assets/fonts/NotoSansKR-wght.ttf")
	t.root.add_child(view)
	view.set_process(false)
	view.size = Vector2(320,200)
	for screen in [Vector2(960,432),Vector2(450,800),Vector2(360,800)]:
		view.size.x = minf(320.0,screen.x-16.0)
		view.rows.clear()
		view._push("gold","골드",5,0.0,view.GOLD)
		view._push("potion","회복 포션",1,7.0,view.POTION)
		view._push("skill","스킬 선택",1,0.0,view.SKILL)
		view._push("drop","회복 포션 출현",1,0.0,view.POTION)
		var bottom := 0.0
		var geometry: Array = []
		for row in view.rows:
			t.check(row.lines.size() == 1 and row.height == 32.0,"POTION short receipt uses compact 32px row")
			t.check(row.width < view.size.x and row.width >= 80.0,"POTION background follows actual text instead of full-width panel")
			t.check(row.top >= bottom,"POTION compact receipt rows do not overlap")
			bottom = row.top+row.height
			geometry.append([row.top,row.width,row.height])
		t.check(bottom == 134.0,"POTION maximum four short rows use 134px instead of 200px")
		var nodes := view.get_child_count()
		view.active = true
		for frame in range(24):
			view._process(1.0/60.0)
			var observed: Array = []
			for row in view.rows: observed.append([row.top,row.width,row.height])
			t.check(observed == geometry and view.get_child_count() == nodes,"POTION continuous frames keep receipt geometry and nodes stable")
		view.rows[0].seconds = 0.0
		view._process(1.0/60.0)
		t.check(view.rows.size() == 3 and view.rows[0].top == 0.0,"POTION expiration closes vacated row without stale gaps")
	view.rows.clear()
	view.confirmed_skill("가벼운 발걸음 · 궁극의 돌진 베기 6/6",null)
	var title: String = view.row_text(view.rows[0])
	var measured: float = view.get_theme_default_font().get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	print("POTION_WRAP_PROBE ",JSON.stringify({"text":title,"measured_width":measured,"available_width":view.size.x-45.0,"lines":view.rows[0].lines}))
	# The prior fixture assumed that this name exceeded 275px; font shaping
	# can keep it on one line. Preserve that original case and explicitly cross
	# its measured boundary rather than changing production wrapping.
	if measured <= view.size.x-45.0:
		t.check(view.rows[0].lines.size() == 1 and view.rows[0].height == 32.0,"POTION original name fits its measured single-line width")
	view.size.x = ceil(measured*0.65)+45.0
	view._layout_rows()
	t.check(view.rows[0].lines.size() == 2 and view.rows[0].height == 48.0,"POTION long skill preserves two full lines in 48px row")
	t.check("".join(view.rows[0].lines) == title,"POTION wrapped skill preserves every character")
	view.free()
