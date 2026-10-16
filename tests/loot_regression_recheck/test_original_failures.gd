extends RefCounted
# Re-run the original failing test bodies without skipping their assertions.
func run(t) -> void:
	for path in ["res://tests/progression/test_growth_offers.gd","res://tests/core/test_rebuild_streamed_rebase.gd","res://tests/core/test_rebuild_world_commit_adoption.gd"]:
		print("LOOT_ORIGINAL_RECHECK_BEGIN "+path)
		var script = load(path)
		t.check(script != null and script.can_instantiate(),"original failure body loads: "+path)
		if script != null and script.can_instantiate(): await script.new().run(t)
		print("LOOT_ORIGINAL_RECHECK_END "+path)
