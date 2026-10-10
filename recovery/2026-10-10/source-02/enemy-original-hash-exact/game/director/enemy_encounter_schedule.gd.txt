class_name EnemyEncounterSchedule
extends RefCounted
# Pure opt-in selector. SpawnDirector, seeded positions, wave caps, bosses and
# the 30-minute survival/75-second evacuation clock remain owned by integration.
const ROLE_IDS := ["walker","runner","grabber","sweeper","brute","leaper"]
const UNLOCK_TICKS := [0,2100,4500,7200,10800,23400]
const INTRO_TICKS := 600
const EVACUATION_TICK := 108000
const PAIRS := [["walker","runner"],["walker","grabber"],["walker","sweeper"],["brute","runner"],["leaper","walker"]]
static func available_roles(survival_tick: int) -> Array[String]:
	var result: Array[String] = []
	if survival_tick < 0 or survival_tick >= EVACUATION_TICK: return result
	for index in ROLE_IDS.size():
		if survival_tick >= UNLOCK_TICKS[index]: result.append(ROLE_IDS[index])
	return result
static func choose_roles(survival_tick: int, ordinal: int, requested_count: int) -> Array[String]:
	var result: Array[String] = []
	if ordinal < 0 or requested_count <= 0: return result
	var available := available_roles(survival_tick)
	if available.is_empty(): return result
	var latest := available.size()-1
	if latest > 0 and survival_tick < UNLOCK_TICKS[latest]+INTRO_TICKS:
		result.append(ROLE_IDS[latest])
		while result.size() < requested_count: result.append("walker")
		return result
	var choices: Array = []
	for pair in PAIRS:
		if pair[0] in available and pair[1] in available: choices.append(pair)
	var pair: Array = ["walker","walker"] if choices.is_empty() else choices[ordinal%choices.size()]
	# A count-one wave must alternate within its selected pair across pair
	# cycles; always taking pair[0] permanently starves learned second roles.
	# Multi-enemy batches already include both members; retain their order.
	var first := int(ordinal/choices.size())%2 if requested_count == 1 and not choices.is_empty() else 0
	for index in requested_count: result.append(pair[(index+first)%2])
	return result
