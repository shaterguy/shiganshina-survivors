extends "res://game/world/streamed_world.gd"
var sweep_calls:=0
func sweep(position:Vector2,delta:Vector2,radius:float)->Dictionary:
 sweep_calls+=1
 if sweep_calls==2:return {"ok":false,"error_code":"future_injected_sweep_failure","position":position,"fraction":0.0,"hit_prop_id":""}
 return super.sweep(position,delta,radius)
