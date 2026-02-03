extends Area2D

@export var slot_id: int = 1
var current_car_id: int = -1
var is_busy: bool = false
var repair_type: String = ""
var player_inside: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	print("body_entered : ", body.name, " sur slot ", slot_id)
	if body.name == "Player":
		player_inside = true
		print("Player est dans le slot ", slot_id)

func _on_body_exited(body: Node) -> void:
	print("body_exited : ", body.name, " sur slot ", slot_id)
	if body.name == "Player":
		player_inside = false
		print("Player a quitté le slot ", slot_id)

func has_car() -> bool:
	return current_car_id != -1

func place_car(car_id: int) -> void:
	current_car_id = car_id
	print("Voiture ID ", car_id, " placée dans slot ", slot_id)
	# Dans add_car(), remove_car(), clear_slot()
	get_parent()._update_car_list()  # Direct
	if car_id <= 0:
		print("❌ ID invalide: ", car_id)
		return
	current_car_id = car_id
func clear_slot() -> void:
	current_car_id = -1
	is_busy = false
	repair_type = ""
