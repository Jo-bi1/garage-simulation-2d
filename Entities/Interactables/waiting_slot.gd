extends Area2D

var waiting_car_ids: Array[String] = []  # IDs Firestore des voitures en attente

func add_car(car_id: String) -> void:
	if not waiting_car_ids.has(car_id):
		waiting_car_ids.append(car_id)
		print("Voiture ID %s ajoutée en attente" % car_id)

func remove_car(car_id: String) -> void:
	if waiting_car_ids.has(car_id):
		waiting_car_ids.erase(car_id)
		print("Voiture ID %s libérée de attente" % car_id)

func has_car(car_id: String) -> bool:
	return waiting_car_ids.has(car_id)
