extends RefCounted
const F = preload("res://tests/ui/grabber_attack_view_fixture.gd")
const View = preload("res://game/presentation/world_view.gd")
func run(t) -> void:
	var view = View.new()
	var snapshot := F.snapshot(t)
	view.present(snapshot)
	for field in ["ok","run_id","tick","scene_id","origin_revision","world_revision"]:
		for value in [{},[],true,"bad",2.5]:
			var packet := F.packet(snapshot)
			packet[field] = value
			# bool true is the one valid discriminator in this probe set.
			if field == "ok" and value is bool: continue
			view.present_enemy_attacks(F.packet(snapshot))
			var result = view.present_enemy_attacks(packet)
			t.check(result is Dictionary and result.get("ok") == false and view._enemy_attack_packet.is_empty(),"typed packet identity rejection: "+field+"/"+str(typeof(value)))
	for field in ["role_id","source_id","phase","position"]:
		for value in [{},[],2]:
			var packet := F.packet(snapshot)
			packet.attacks[0][field] = value
			view.present_enemy_attacks(F.packet(snapshot))
			var result = view.present_enemy_attacks(packet)
			t.check(result is Dictionary and result.get("ok") == false and view._enemy_attack_packet.is_empty(),"typed attack rejection: "+field+"/"+str(typeof(value)))
	view.free()
