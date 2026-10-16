extends RefCounted
const Feedback = preload("res://game/ui/reward_feedback.gd")
func run(t) -> void:
	var view := Feedback.new()
	t.root.add_child(view)
	view.set_process(false)
	view.size = Vector2(320,200)
	view.consume([_event(1,"loot_collected",{"reward":"gold","amount":5})],"run:1")
	t.check(view.rows.size() == 1 and view.row_text(view.rows[0]) == "골드 +5","POTION visible reward kind and amount")
	view.consume([_event(1,"loot_collected",{"reward":"gold","amount":5})],"run:1")
	t.check(view.rows[0].amount == 5,"POTION replay cannot duplicate feedback")
	view.consume([_event(2,"potion_dropped",{"potion_id":"bottle","amount":1}),_event(3,"potion_collected",{"potion_id":"bottle","amount":1,"healed_amount":7.0})],"run:1")
	t.check(view.rows.size() == 2 and view.row_text(view.rows[1]) == "회복 포션 ×1 · HP +7","POTION immediate collection shows actual heal, no duplicate spawn toast")
	view.consume([_event(4,"loot_collected",{"reward":"skill","amount":1})],"run:1")
	t.check(view.row_text(view.rows[2]) == "스킬 선택 1회","POTION choice is not labelled acquired skill")
	view.confirmed_skill("가벼운 발걸음 1/5",null)
	t.check(view.rows[2].kind == "confirmed" and view.row_text(view.rows[2]) == "가벼운 발걸음 1/5","POTION confirmed skill replaces queued selection")
	var nodes := view.get_child_count()
	for i in range(200): view.consume([_event(5+i,"loot_collected",{"reward":"gold","amount":5})],"run:1")
	t.check(view.rows.size() <= 4 and view.get_child_count() == nodes,"POTION feedback retains bounded slots without nodes")
	view.active = false
	view._process(100.0)
	t.check(not view.rows.is_empty(),"POTION paused/selection feedback waits for play")
	view.active = true
	view._process(3.0)
	t.check(view.rows.is_empty(),"POTION fixed feedback expires")
	view.consume([_event(300,"loot_collected",{"reward":"gold","amount":5})],"run:1")
	view.reset_run("other:1")
	t.check(view.rows.is_empty() and view.event_seq == 0,"POTION new run clears old feedback")
	view.reset_run("run:1")
	var foreign := _event(99,"potion_collected",{"potion_id":"a"})
	foreign.event_id = "foreign:99"
	view.consume([_event(1,"potion_dropped",{"potion_id":"a"}),foreign],"run:1")
	t.check(view.drop_ids.has("a"),"POTION foreign collection cannot suppress drop")
	view.consume([_event(2,"potion_dropped",{"potion_id":"b"}),_event(1,"potion_collected",{"potion_id":"b"})],"run:1")
	t.check(view.drop_ids.size() == 2,"POTION replayed collection cannot suppress drop")
	view.consume([_event(3,"potion_collected",{"potion_id":"a","healed_amount":20.0})],"run:1")
	t.check(view.drop_ids.size() == 1 and view.drop_ids.has("b"),"POTION one collection retains other uncollected notification")
	var drop_rows := 0
	for row in view.rows:
		if row.kind == "drop":
			drop_rows += 1
			t.check(row.amount == 1,"POTION remaining aggregate counts one bottle")
	t.check(drop_rows == 1,"POTION independent drop notification retained")
	view.rows.clear()
	view.confirmed_skill("가벼운 발걸음 · 궁극의 돌진 베기 6/6",null)
	view._push("gold","스킬 포화 · 골드",2147483647,0.0,view.GOLD)
	view._push("potion","회복 포션",5,0.0001,view.POTION)
	for row in view.rows:
		t.check(row.lines.size() <= 2,"POTION 360px HUD meaningful text fits two lines")
		var reconstructed := ""
		for line in row.lines:
			reconstructed += line
			t.check(view.get_theme_default_font().get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x <= view.size.x-45,"POTION wrapped line stays enclosed")
		t.check(reconstructed == view.row_text(row),"POTION wrapping preserves full text")
	view.reset_run("malformed-reset")
	view.reset_run("run:1")
	view.consume([null,[],{"event_id":12},{"event_id":"run:1:1","payload":[]},{"event_id":"run:1:01","payload":{}}],"run:1")
	t.check(view.event_seq == 0 and view.rows.is_empty(),"POTION malformed event envelopes do not consume sequence or draw")
	view.free()
func _event(serial: int, kind: String, payload: Dictionary) -> Dictionary:
	return {"event_id":"run:1:"+str(serial),"type":kind,"payload":payload}
