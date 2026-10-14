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
	func mobility_sweep(state,position,delta,radius,anchor,height):
		_add("mobility_sweep");return helper.mobility_sweep(state,position,delta,radius,anchor,height)
	func mobility_cancel_sweep(state,position,delta,radius,anchor,height):
		_add("mobility_cancel_sweep");return helper.mobility_cancel_sweep(state,position,delta,radius,anchor,height)
	func mobility_player_clearance(state, validate_contract):
		_add("mobility_player_clearance");return helper.mobility_player_clearance(state,validate_contract)
	func sweep(position,delta,radius):
		_add("sweep");return helper.sweep(position,delta,radius)
func _measure(state, helper, phase):
	var proxy=Counter.new(helper)
	var times=[]
	for sample in 120:
		var started=Time.get_ticks_usec()
		Mobility.advance(state,Vector2.UP,proxy)
		times.append(Time.get_ticks_usec()-started)
	times.sort()
	print("MOBILITY_DIAGNOSTIC "+JSON.stringify({"phase":phase,"samples":times.size(),"us_p50":times[times.size()/2],"us_p95":times[int(times.size()*.95)],"us_max":times[-1],"calls":proxy.calls,"enemy_count":state.entities.size(),"limits":"fixed fixture, cloud headless CPU only"}))
func run(t):
	var s=F.make(t)
	if s.is_empty():return
	_measure(s.state,s.core._streamed,"ground_planning")
	F.step(s)
	t.check(s.state.player_mobility.phase != "ground","genuine zero-enemy mobility cast started")
	_measure(s.state,s.core._streamed,s.state.player_mobility.phase)
	t.check(F.reach(s,"over"),"genuine mobility reached roof phase")
	_measure(s.state,s.core._streamed,"over")
