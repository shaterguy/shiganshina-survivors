extends SceneTree
var checks=0
var failures=0
func check(value:bool,message:String):
 checks+=1
 if not value:failures+=1;push_error("FAIL: "+message)
func _initialize():
 load("res://tests/city_continuity/test_director_final_boundary.gd").new().run(self)
 print("DIRECTOR_FINAL_BOUNDARY_RESULT checks=%d failures=%d"%[checks,failures])
 quit(0 if failures==0 else 1)
