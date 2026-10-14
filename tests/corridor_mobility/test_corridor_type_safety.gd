extends RefCounted
const F = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const M = preload("res://game/core/player_mobility.gd")
func run(t) -> void:
	var s := F.make(t)
	F.step(s)
	for value in [false,true,null,"0","zero",[],{},Vector2.ZERO,-1.0,NAN,INF]:
		for field in ["height","schema_version","geometry_revision","world_stage","world_fingerprint"]:
			var bad: Dictionary = s.state.duplicate(true)
			match field:
				"height": bad.player_mobility.path[0].height = value
				"schema_version": bad.player_mobility.schema_version = value
				"geometry_revision": bad.player_mobility.path[0].geometry_revision = value
				"world_stage": bad.world.stage = value
				"world_fingerprint": bad.world.content_fingerprint = value
			var errors: Array[String] = M.validate(bad)
			t.check(not errors.is_empty(),"malformed mobility "+field+" rejects type "+str(typeof(value))+" value "+str(value))
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_over_interior.json"))
	var legacy_core := F.F.Core.new(F.F.Provider.new())
	for value in [false,true,null,"0","zero",[],{},Vector2.ZERO,-1.0,NAN,INF]:
		var bad: Dictionary = packet.state.duplicate(true)
		bad.player_mobility.path[0].geometry_revision = value
		t.check(not M.validate(bad).is_empty(),"legacy malformed path revision rejects before admission dispatch: "+str(value))
		t.check(not legacy_core.restore(bad,packet.hydration).get("ok",false),"legacy malformed path revision never migrates: "+str(value))
