extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
class HiddenStore:
	extends "res://game/persistence/game_save_store.gd"
	var hide_load := false
	func read_game() -> Dictionary:
		return {"ok":false,"error_code":"read_failed"} if hide_load else super.read_game()
func run(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var app = f.app
	app.start_run(42)
	support.evolution_offer(app)
	var store = HiddenStore.new(f.directory,Callable(app.simulation,"restore"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hide_load = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	var offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(not app._pending_transaction.is_empty() and app.ui._growth_waiting_result,"unknown durable outcome keeps growth choice pending")
	t.check(app.ui.confirmed_upgrade_text().is_empty() and not app.ui.get_node("ProgressionHUD").display_text().contains("6/6"),"unknown result never publishes speculative success or evolved HUD")
	for card in app.ui._growth_cards:
		if card.is_visible_in_tree(): t.check(card.disabled,"pending save leaves every visible growth card disabled")
	store.hide_load = false
	store._fault_injector = Callable()
	app.resolve_pending_transaction()
	t.check(app.ui.confirmed_upgrade_text().contains("진화 6/6") and not app.ui._growth_waiting_result,"readback confirmation alone releases lock and publishes evolved sixth-level feedback")
	app.free()
