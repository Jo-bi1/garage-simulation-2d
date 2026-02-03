extends Area2D

var waiting_car_ids: Array[int] = []

func add_car(car_id: int):
	waiting_car_ids.append(car_id)
	print("Voiture ID %d ajoutée en attente" % car_id)

func remove_car(car_id: int):
	waiting_car_ids.erase(car_id)
	print("Voiture ID %d libérée de attente" % car_id)

func has_car(car_id: int) -> bool:
	return car_id in waiting_car_ids
