extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Mobility = preload("res://game/core/player_mobility.gd")
class Counter:
	extends RefCounted
	var helper
	var calls := {}
	func _init(value): helper=value
	func _add(id): calls[id]=int(calls.get(id,0))+1
	func mobility_geometry(state, rectangle):
		_add("mobility_geometry");return helper.mobility_geometry(state,rectangle)
	func walkable(position,radius):
		_add("walkable");return helper.walkable(position,radius)
	func mobility_pair_check(state,anchors):
		_add("mobility_pair_check");return helper.mobility_pair_check(state,anchors)
	func sweep(position,delta,radius):
		_add("sweep");return helper.sweep(position,delta,radius)
func _measure(state, helper, phase) -> Dictionary:
	var proxy=Counter.new(helper)
	var times=[]
	for sample in 120:
		var started=Time.get_ticks_usec()
		var proposal: Dictionary = Mobility.advance(state,Vector2.UP,proxy)
		if proposal.get("status") == "refused": proxy._add("refused")
		times.append(Time.get_ticks_usec()-started)
	times.sort()
	print("MOBILITY_DIAGNOSTIC "+JSON.stringify({"phase":phase,"samples":times.size(),"us_p50":times[times.size()/2],"us_p95":times[int(times.size()*.95)],"us_max":times[-1],"calls":proxy.calls,"enemy_count":state.entities.size(),"limits":"fixed fixture, cloud headless CPU only"}))
	return proxy.calls
func run(t):
	var s=F.make(t)
	if s.is_empty():return
	var plan_state: Dictionary = s.state.duplicate(true)
	plan_state.active_tick = 1
	var planned: Dictionary = _measure(plan_state,s.core._streamed,"ground_planning")
	t.check(planned.get("mobility_geometry",0) == 120 and not planned.has("refused"),"eligible ground planning performs one bounded geometry query per proposal")
	F.step(s)
	t.check(s.state.player_mobility.phase == "boost","genuine zero-enemy paired boost started")
	var before: Dictionary = s.state.duplicate(true)
	var active: Dictionary = _measure(s.state,s.core._streamed,"boost")
	t.check(active.get("mobility_pair_check",0) == 120 and active.get("sweep",0) == 120 and not active.has("mobility_geometry") and not active.has("refused"),"active boost checks exactly two resident anchors and one normal sweep per proposal")
	t.check(F.same(s.state,before),"diagnostic repeated proposals never mutate live authority")
	F.step(s,Vector2.ZERO)
	t.check(s.state.player_mobility.phase == "ground","release returns immediately to grounded cooldown")
	var stopped: Dictionary = _measure(s.state,s.core._streamed,"ground_cooldown")
	t.check(stopped.is_empty(),"cooldown performs no anchor or collision queries")
