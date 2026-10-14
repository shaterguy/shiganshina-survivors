extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
const L = preload("res://game/core/legacy_player_mobility_v1.gd")
func run(t) -> void:
	for phase in ["ground","glide","rise","over","over_interior","land"]:
		var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_"+phase+".json"))
		var original: Dictionary = packet.state.duplicate(true)
		var core := F.Core.new(F.Provider.new())
		t.check(L.validate(packet.state).is_empty(),"genuine dev7 v1 fixture remains admitted: "+phase)
		var result: Dictionary = core.restore(packet.state,packet.hydration)
		t.check(result.get("ok",false),"full v1 validation then v2 migration succeeds: "+phase)
		if not result.get("ok",false): print(result); continue
		var state: Dictionary = result.state
		t.check(M.same(original,packet.state),"legacy restore does not mutate caller input: "+phase)
		t.check(state.player_mobility.schema_version == 2 and state.player_mobility.phase == "ground" and state.player.velocity == [0.0,0.0],"legacy phase grounds with zero velocity: "+phase)
		for field in ["cast_id","started_tick","cooldown_until","roll","hit_ids"]:
			t.check(M.same(state.player_mobility[field],original.player_mobility[field]),"migration preserves "+field+": "+phase)
		for key in original:
			if not key in ["player","player_mobility"]: t.check(M.same(original[key],state[key]),"migration preserves unrelated "+key+": "+phase)
		t.check(core.prepare_world(state,packet.hydration).get("ok",false),"migrated authority can explicitly adopt helper: "+phase)
		t.check(core._streamed.walkable(M.vec(state.player.position),8.0).get("walkable",false),"migrated position is normal legal ground: "+phase)
		if phase != "ground":
			var current_safe: bool = core._streamed.walkable(M.vec(original.player.position),8.0).get("walkable",false)
			t.check(state.player.position == (original.player.position if current_safe else original.player_mobility.path[0].local),"migration uses safe current coordinate before stored start: "+phase)
		var wire: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
		var roundtrip: Dictionary = core.restore(wire,packet.hydration)
		t.check(roundtrip.get("ok",false) and M.same(state,roundtrip.get("state",{})),"migrated v2 JSON roundtrip remains exact: "+phase)
		if phase != "ground":
			for kind in ["roll","path","clock","geometry","unrelated"]:
				var bad: Dictionary = original.duplicate(true)
				match kind:
					"roll": bad.player_mobility.roll += 1
					"path": bad.player_mobility.path[1].local[0] += 3.0
					"clock": bad.player_mobility.travel_ticks += 1
					"geometry": bad.player_mobility.anchor.geometry_revision = "f".repeat(64)
					"unrelated": bad.player.max_hp += 1
				t.check(not core.restore(bad,packet.hydration).get("ok",false),"migration never repairs corrupt old "+kind+": "+phase)
			t.check(M.advance(original,Vector2.UP,core._streamed).get("status") == "refused","legacy runtime motion cannot execute: "+phase)
