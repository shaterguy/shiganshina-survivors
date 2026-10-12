extends RefCounted
# A2 legitimately replaces the old phase-owned remote-circle assumptions with
# one real actor and its original warning/physical shoulder sweep ownership.
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,384.0])
	var original: Dictionary = app.state.entities[0].duplicate(true)
	var warning: Dictionary = app.state.telegraphs[0].duplicate(true)
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app.state.entities.size() == 1,"real final actor survives product dock transaction")
	if app.state.world.stage != "dock": app.free(); return
	var hp: float = app.state.player.hp
	while int(app.state.active_tick) < int(warning.active_from_tick): app.advance_frame(1.0/60.0)
	t.check(app.state.player.hp == hp,"warning activation itself never recreates remote circle damage at dock entry")
	var damaged := false
	for step in 100:
		app.advance_frame(1.0/60.0)
		if app.state.player.hp < hp:
			damaged = true
			break
	t.check(damaged and S.count_events(app,"damage") >= 1,"preserved actor's real shoulder sweep subsequently reaches and damages player")
	var actor: Dictionary = app.state.entities[0]
	t.check(actor.id == original.id and actor.hp == actor.max_hp and app.state.entities.size() == 1,"physical impact retains one unbeatable actor with no duplicate spawn")
	t.check(S.count_events(app,"boss_spawned") == 1 and S.count_events(app,"phase_changed") == 1 and app.state.final_started_tick == 108000,"actor handoff and damage never replay final phase or reset timer")
	for step in 240:
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
	t.check(app.state.entities.size() == 1 and app.state.entities[0].id == original.id,"later charge cycles use the original final actor")
	t.check(not app.state.command_ids_applied.any(func(id): return str(id).begins_with("final_") and str(id).trim_prefix("final_").is_valid_int()),"removed Director remote-circle producer never adds timed final-number commands")
	t.check(not app.state.telegraphs.any(func(h): return str(h.source_id) != str(original.id)) and app.state.stats.kills == 0 and app.state.reward_ids_claimed.is_empty(),"only actor-owned warnings exist and unbeatable cycles award no kill or reward")
	app.free()
