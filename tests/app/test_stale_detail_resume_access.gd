extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var reader = f.app
	reader.start_run(42)
	support.evolution_offer(reader)
	var obsolete: String = reader.state.upgrade_offer.offer_id
	reader.ui.open_evolution_details("evo_wing_cut")
	t.check(reader.ui._mode == "evolution_detail","stale-detail fixture enters real recipe modal")
	var writer = support.restart(t,f.directory)
	writer.request_resume()
	writer.apply_upgrade(writer.state.upgrade_offer.offer_id,writer.state.upgrade_offer.options[0].option_id)
	var committed: Dictionary = writer.game_save.duplicate(true)
	# The actual background checkpoint request detects a replaced authority.
	reader._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.check(reader.state.is_empty() and reader.pending_checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and reader.pending_checkpoint.tactical_seals == 0,"stale recipe detail quarantines only confirmed evolution checkpoint")
	t.check(reader.ui._mode == "title" and reader.ui._detail_id.is_empty() and reader.ui._growth_view.is_empty(),"authority quarantine invalidates obsolete detail and growth presentation")
	reader._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	reader.ui.navigate("cancel")
	t.check(reader.ui._mode == "title" and reader.ui._checkpoint_available and reader.ui.focused_semantic_id() == "이어서 출격","focus return and B keep the fresh explicit resume reachable")
	reader.advance_frame(1.0/60.0)
	t.check(reader.state.is_empty() and reader.save_store.load_game().game_save == committed,"quarantined detail recovery advances zero ticks and leaves confirmed disk state intact")
	var choices: Array = []
	reader.ui.upgrade_chosen.connect(func(id,_option): choices.append(id))
	reader.ui.accept_released()
	reader.ui.navigate("accept")
	t.check(not reader.state.is_empty() and reader.state.evolutions.get("blade_slash") == "evo_wing_cut" and reader.state.tactical_seals == 0 and reader.state.upgrade_offer.is_empty(),"reachable UI continue restores confirmed evolution and spent seal")
	t.check(choices.is_empty() and not obsolete in choices and reader.ui._mode == "play","fresh resume never emits an obsolete growth choice")
	var disk: Dictionary = reader.save_store.load_game().game_save
	t.check(disk.checkpoint.evolutions.get("blade_slash") == "evo_wing_cut" and disk.checkpoint.tactical_seals == 0,"explicit UI resume persists confirmed evolution without restoring old seal")
	reader.free()
	writer.free()
