extends Node

@onready var hud = $"../HUD"

func add_car_to_slot(car):
	if not slot1.occupied:
		slot1.place_car(car)
		hud.add_car(car.name)
	elif not slot2.occupied:
		slot2.place_car(car)
		hud.add_car(car.name)

func _on_car_repair_progress(car):
	var progress_percent = car.progress / car.total_repairs * 100
	hud.update_progress(car.name, progress_percent)

func _on_car_repair_done(car):
	hud.remove_car(car.name)
	if not waiting_slot.occupied:
		waiting_slot.place_car(car)
