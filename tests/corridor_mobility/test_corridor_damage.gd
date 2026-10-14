extends RefCounted
const F = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
class BreakAfterMovement:
	extends "res://game/core/run_simulation.gd"
	var side := 0
	func _move_enemies(state: Dictionary, events: Array[Dictionary]) -> Array[int]:
		var waiting := super._move_enemies(state,events)
		if not _mobility_cast.is_empty() and _mobility_cast.get("phase") == "boost":
			_streamed._world._props[_mobility_cast.anchors[side].prop_id].hp -= 1
		return waiting
func run(t) -> void:
	var s := F.make(t)
	var command: Dictionary = F.F.F.spawn("corridor_target",[180.0,243.0],"walker")
	command.origin_revision = 0
	var events := F.step(s,Vector2.UP,[command])
	var hits: Array = events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility")
	t.check(hits.size() == 1,"real accepted ground sweep applies exactly one path damage hit")
	t.check(s.state.player_mobility.hit_ids == ["corridor_target"],"Core owns per-cast path hit history")
	for tick in 35:
		events = F.step(s)
		hits.append_array(events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility"))
	t.check(hits.size() == 1,"overlapping consecutive ground sweeps never hit an entity twice")
	t.check(s.state.player_mobility.damage == 12.0 and s.state.player_mobility.width == 20.0,"path attack preserves approved fixed damage and width")
	for side in 2:
		var broken := F.make(t)
		var core := BreakAfterMovement.new(broken.provider)
		core.side = side
		t.check(core.prepare_world(broken.state,broken.hydration).get("ok",false),"post-movement interruption fixture prepares")
		broken.core = core
		events = F.step(broken,Vector2.UP,[command])
		t.check(events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").is_empty(),"either anchor breaking after proposal suppresses same-tick damage")
		t.check(broken.state.active_tick == 1 and broken.state.player_mobility.phase == "ground" and broken.state.player.velocity == [0.0,0.0],"post-move stale anchor ends at accepted ground point without tick rollback")
		t.check(broken.state.player.position == [180.0,248.0],"pre-break accepted movement remains a normal ground sweep")
