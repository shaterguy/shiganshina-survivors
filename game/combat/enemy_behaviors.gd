class_name EnemyBehaviors
extends RefCounted
# Read-only tuning profiles. RunSimulation alone updates actor/action state.
const PROFILES := {
	"walker":{"kind":"none","trigger_range":0.0,"warning_ticks":0,"active_ticks":0,"recovery_ticks":0,"cooldown_ticks":0},
	"runner":{"kind":"charge","trigger_range":220.0,"warning_ticks":45,"active_ticks":20,"recovery_ticks":60,"cooldown_ticks":90,"length":80.0,"width":32.0,"rush_speed":240.0},
	"brute":{"kind":"slam","trigger_range":110.0,"warning_ticks":60,"active_ticks":12,"recovery_ticks":90,"cooldown_ticks":120,"radius":72.0},
	"sweeper":{"kind":"sweep","trigger_range":130.0,"warning_ticks":60,"active_ticks":12,"recovery_ticks":75,"cooldown_ticks":90,"radius":100.0,"arc_degrees":90.0},
	"grabber":{"kind":"grab","trigger_range":160.0,"warning_ticks":60,"active_ticks":16,"recovery_ticks":75,"cooldown_ticks":90,"length":125.0,"width":40.0,"rush_speed":150.0},
	"boss_charger":{"kind":"charge","trigger_range":420.0,"warning_ticks":75,"active_ticks":50,"recovery_ticks":90,"cooldown_ticks":90,"length":300.0,"width":64.0,"rush_speed":360.0},
	"boss_sweeper":{"kind":"sweep","trigger_range":240.0,"warning_ticks":75,"active_ticks":16,"recovery_ticks":90,"cooldown_ticks":75,"radius":180.0,"arc_degrees":150.0},
	"boss_leaper":{"kind":"leap","trigger_range":600.0,"warning_ticks":75,"airborne_ticks":30,"active_ticks":12,"recovery_ticks":105,"cooldown_ticks":90,"radius":80.0},
	"boss_grabber":{"kind":"grab","trigger_range":300.0,"warning_ticks":90,"active_ticks":20,"recovery_ticks":105,"cooldown_ticks":75,"length":210.0,"width":60.0,"rush_speed":180.0},
	"abnormal_charge":{"kind":"charge","trigger_range":420.0,"warning_ticks":60,"active_ticks":35,"recovery_ticks":75,"cooldown_ticks":60,"length":175.0,"width":72.0,"rush_speed":300.0},
	"abnormal_sweep":{"kind":"sweep","trigger_range":240.0,"warning_ticks":60,"active_ticks":16,"recovery_ticks":75,"cooldown_ticks":60,"radius":160.0,"arc_degrees":140.0}
}
static func profile(entity: Dictionary) -> Dictionary:
	var id := str(entity.enemy_id)
	if id == "boss_abnormal" or entity.get("behavior","") == "combo":
		var charge: bool = int(entity.get("pattern_index",0)) % 2 == 0 if entity.get("action_state","move") == "move" else entity.get("attack_kind","charge") == "charge"
		return PROFILES.abnormal_charge if charge else PROFILES.abnormal_sweep
	if PROFILES.has(id): return PROFILES[id]
	var behavior := str(entity.get("behavior","chase"))
	var key: String = {"runner":"runner","brute":"brute","sweep":"sweeper","grab":"grabber","charge":"boss_charger","leap":"boss_leaper"}.get(behavior,"walker")
	return PROFILES[key]
