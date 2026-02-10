extends Area2D
class_name RepairSlot

@export var car_scene: PackedScene
@export var slot_id: int = 1

var is_busy: bool = false
var repair_type: String = ""
var player_inside: bool = false
var current_car_id: String = ""

var car_instance: Area2D = null
const CAR_SCENE := preload("res://Entities/Vehicles/Car.tscn") # si tu veux forcer ce prefab

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
	return str(current_car_id) != ""

func clear_slot() -> void:
	current_car_id = ""
	is_busy = false

	if car_instance and car_instance.is_inside_tree():
		car_instance.queue_free()
		car_instance = null

	get_parent()._update_car_list()

func place_car(car_id: String) -> void:
	if car_id == "":
		print("❌ ID invalide: ", car_id)
		return

	# Supprimer une éventuelle voiture déjà présente
	if car_instance and car_instance.is_inside_tree():
		car_instance.queue_free()
		car_instance = null

	current_car_id = car_id
	is_busy = false

	# Instancier la voiture
	var scene_to_use: PackedScene = car_scene if car_scene != null else CAR_SCENE
	car_instance = scene_to_use.instantiate() as Area2D
	add_child(car_instance)

	# Position locale dans le slot
	car_instance.position = Vector2.ZERO

	print("Voiture ID ", car_id, " placée dans slot ", slot_id)
	get_parent()._update_car_list()
