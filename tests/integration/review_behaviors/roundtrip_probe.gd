extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Behavior = preload("res://tests/core/behavior_fixture.gd")
var differences := 0
func _initialize() -> void:
	var sim = Sim.new()
	for id in ["walker","runner","brute","boss_charger","boss_abnormal"]:
		var original: Dictionary = Behavior.run_with_enemy(sim,id,[-70.0,0.0])
		var saved_text := JSON.stringify(original)
		var restored: Dictionary = sim.restore(JSON.parse_string(saved_text))
		print("ROUNDTRIP ",id," accepted=",restored.ok," equal=",restored.ok and original==restored.state)
		if restored.ok: compare(original,restored.state,id)
	print("LEAF_DIFFERENCES ",differences)
	quit(0)
func compare(a: Variant,b: Variant,path: String) -> void:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if b.has(key): compare(a[key],b[key],path+"."+str(key))
	elif a is Array and b is Array:
		for i in mini(a.size(),b.size()): compare(a[i],b[i],path+"[%d]"%i)
	elif a != b:
		differences += 1
		if differences <= 20: print("DIFF ",path," a=",a," b=",b," type_a=",typeof(a)," type_b=",typeof(b)," numerical_delta=",float(b)-float(a) if (a is float or a is int) and (b is float or b is int) else null)
