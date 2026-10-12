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
static func profile(entity: Dictionary, definitions: Dictionary = {}) -> Dictionary:
	if entity.get("enemy_id") == "armored_titan": return definitions.get("armored_titan",{}).get("action_profile",{})
	var id := str(entity.enemy_id)
	if id == "boss_abnormal" or entity.get("behavior","") == "combo":
		var charge: bool = int(entity.get("pattern_index",0)) % 2 == 0 if entity.get("action_state","move") == "move" else entity.get("attack_kind","charge") == "charge"
		return PROFILES.abnormal_charge if charge else PROFILES.abnormal_sweep
	if PROFILES.has(id): return PROFILES[id]
	var behavior := str(entity.get("behavior","chase"))
	var key: String = {"runner":"runner","brute":"brute","sweep":"sweeper","grab":"grabber","charge":"boss_charger","leap":"boss_leaper"}.get(behavior,"walker")
	return PROFILES[key]

static func final_definition_valid(definition: Variant) -> bool:
	if not definition is Dictionary or definition.get("behavior") != "final_armored" or definition.get("xp") != 0 or not definition.get("action_profile") is Dictionary: return false
	var p: Dictionary = definition.action_profile
	var fields := ["kind","trigger_range","warning_ticks","active_ticks","brake_ticks","recovery_ticks","cooldown_ticks","length","width","rush_start_speed","rush_speed","shoulder_forward","preparation_forward","shoulder_radius","structure_damage","structure_reach","structure_admission_interval_ticks","max_structure_attacks"]
	if p.size() != fields.size() or not p.has_all(fields) or p.kind != "charge": return false
	for key in fields:
		if key == "kind": continue
		if not (p[key] is int or p[key] is float) or not is_finite(float(p[key])) or p[key] <= 0 or p[key] > 3600: return false
	for key in ["warning_ticks","active_ticks","brake_ticks","recovery_ticks","cooldown_ticks","structure_damage","structure_reach","structure_admission_interval_ticks","max_structure_attacks"]:
		if float(p[key]) != floor(float(p[key])) or p[key] > 600: return false
	# The separate probe is explicitly bounded; it is no longer body-contained.
	var travel: float = (p.rush_start_speed+p.rush_speed)*0.5*p.active_ticks/60.0
	return definition.radius == 32 and p.shoulder_forward == 56 and p.preparation_forward == 81 and p.shoulder_radius == 16 and p.structure_reach <= definition.radius+1 and p.rush_start_speed <= p.rush_speed and p.width == definition.radius*2.0 and p.length+p.width*0.5 >= travel+p.shoulder_forward+p.shoulder_radius
