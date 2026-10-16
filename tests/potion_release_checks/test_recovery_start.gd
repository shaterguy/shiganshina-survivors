extends RefCounted
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	# Reuse the exact existing real Core/Store recovery scenarios affected by the
	# version-specific initial-ledger gate; no weakened historical assertions.
	var cases := Recovery.new()
	cases._test_preserved_real_start(t)
	cases._test_unknown_same_id_retry(t)
	cases._test_prewrite_same_candidate_retry(t)
	cases._test_lifecycle_during_adoption(t)
