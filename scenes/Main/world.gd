extends Node2D

@onready var player        = $Player
@onready var slot1         = $Slot_1
@onready var slot2         = $Slot_2
@onready var waiting_slot  = $WaitingSlot
@onready var http_request = $CanvasLayer/HTTPRequest  # Crée node HTTPRequest dans CanvasLayer

@onready var side_panel    = $CanvasLayer/SidePanel
@onready var car_list_repair = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListToRepair  # À réparer
@onready var car_list_waiting = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListWaiting  # Payables

@onready var repair_menu   = $CanvasLayer/RepairMenu
@onready var repair_list   = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairList
@onready var repair_close  = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairCloseButton
@onready var user_label = $CanvasLayer/UserLabel

@onready var progress1     = $CanvasLayer/ProgressSlot1
@onready var progress2     = $CanvasLayer/ProgressSlot2
@onready var btn_voitures  = $CanvasLayer/BoutonVoiture
@onready var firebase_auth = Firebase.Auth  # Global
var auth_token: String = ""
var user_email: String = ""
signal car_list_changed
var current_slot = null
var repair_blocked = false
var cars_data := {}

var REPAIRS: Dictionary = {}  # rempli depuis Firebase

func _ready() -> void:
	set_process_input(true)
	set_process_input(true)
	if user_label and user_email != "":
		user_label.text = "Connecté en tant que : " + user_email
	# Si tu veux ANONYMOUS ici, ok, sinon enlève cette ligne
	Firebase.Auth.login_anonymous()

	Firebase.Auth.login_succeeded.connect(_on_world_auth_ok)

	# Init voitures


	repair_menu.visible = false
	side_panel.visible = false

	if repair_list: repair_list.item_activated.connect(_on_repair_list_item_activated)
	if repair_close: repair_close.pressed.connect(_on_repair_close_pressed)
	if car_list_repair: car_list_repair.item_activated.connect(_on_car_list_activated_repair)
	if car_list_waiting: car_list_waiting.item_activated.connect(_on_car_list_activated_waiting)
	if btn_voitures: btn_voitures.pressed.connect(_toggle_car_list)

	_update_car_list()
	_update_car_count()

	progress1.value = 0
	progress2.value = 0

	print("🚗 cars_data démarrage:")
	for id in cars_data:
		print("  V%d: %s" % [id, cars_data[id]["repairs_left"]])
		
func _on_interventions_update(resource):
	if resource == null:
		print("⚠ Aucune intervention dans Firebase.")
		return

	var data: Dictionary = resource.data
	REPAIRS.clear()

	for id in data.keys():
		var item: Dictionary = data[id]
		var name: String = item.get("id", id)  # ex: "frein"
		var price: int = item.get("price", 0)
		var duration_min: float = float(item.get("duration_minutes", 1))
		var duration_sec: float = duration_min * 60.0

		REPAIRS[name] = {
			"prix": price,
			"duree": duration_sec
		}

	print("🔥 REPAIRS depuis Firebase: ", REPAIRS)

		
func _on_auth_ok(auth):
	print("✅ Firebase Auth OK")
	var db_interventions = Firebase.Database.get_database_reference("interventions")
	var db_ref = Firebase.Database.get_database_reference("cars")
	db_interventions.value_changed.connect(_on_interventions_update)
	db_interventions.get()
	db_ref.value_changed.connect(_on_cars_update)  # ← value_changed (pas new_data_update)
	db_ref.get()  # Fetch initial
	_on_world_auth_ok(auth)  # Redirige
	
func _on_cars_update(resource):  # ← MANQUANTE
	cars_data = resource.data if resource else {}
	print("🔥 Firebase cars updated: ", cars_data.keys())
	_update_car_list()
	_update_car_count()
	
func _on_world_auth_ok(auth: Dictionary):
	auth_token = auth.get("idToken", "")
	user_email = auth.get("email", "")
	print("🔐 Garage prêt: User %s" % user_email)
	if user_label:
		user_label.text = "Connecté en tant que : " + user_email	# Fetch cars API avec token
	fetch_cars_from_api()

func fetch_cars_from_api() -> void:
	const LARAVEL_API = "https://garage-s5-default-rtdb.firebaseio.com"
	
	if auth_token == "":
		print("⚠ Pas de token, skip API.")
		return
		
	var url = LARAVEL_API + "cars?email=" + _url_encode(user_email)
	var headers = [
		"Authorization: Bearer " + auth_token,
		"Content-Type: application/json"
	]
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func _url_encode(s: String) -> String:
	var result := s
	result = result.replace(" ", "%20")
	result = result.replace("@", "%40")
	result = result.replace(":", "%3A")
	result = result.replace("/", "%2F")
	return result

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not repair_blocked:
		var s = _get_slot_with_player()
		if s != null:
			_open_repair_menu_for_slot(s)
		else:
			print("Joueur pas près d'une voiture")
			
func print_cars_data():
	print("🚗 cars_data:"); for id in cars_data: print("  V%d: %s" % [id, cars_data[id]["repairs_left"]])
	
func _get_slot_with_player():
	print("Slot1: player_inside=%s, car=%d" % [slot1.player_inside, slot1.current_car_id])
	print("Slot2: player_inside=%s, car=%d" % [slot2.player_inside, slot2.current_car_id])
	
	if slot1.player_inside and slot1.current_car_id != -1: return slot1
	if slot2.player_inside and slot2.current_car_id != -1: return slot2
	return null

func _toggle_car_list() -> void:
	side_panel.visible = !side_panel.visible
	if side_panel.visible: _update_car_list()
	print("Liste: ", "OUVERTURE" if side_panel.visible else "FERMÉE")
	
func _update_car_count() -> void:
	# Compte SEULEMENT à réparer (badge précis)
	var total_repair = 0
	for car_id in cars_data:
		if cars_data[car_id]["repairs_left"].size() > 0:
			total_repair += 1
	btn_voitures.text = "🚗 Voitures (%d)" % total_repair

func _update_car_list() -> void:
	if car_list_repair: car_list_repair.clear()
	if car_list_waiting: car_list_waiting.clear()
	
	# À RÉPARER (cliquables)
	for car_id in cars_data:
		var reps = cars_data[car_id]["repairs_left"].size()
		if reps > 0:
			var status = "📥" if slot1.current_car_id != car_id and slot2.current_car_id != car_id else "🔧"
			var txt = "%d - %s (%d) %s" % [car_id, cars_data[car_id]["name"], reps, status]
			car_list_repair.add_item(txt)
	
	# ATTENTE (info seulement)
	for car_id in waiting_slot.waiting_car_ids:  # Assume array publique
		var name = cars_data.get(car_id, {}).get("name", "?")
		car_list_waiting.add_item("💰 %d - %s (Payer)" % [car_id, name])
	
	btn_voitures.text = "🚗 (%d)" % car_list_repair.item_count

func _on_car_list_activated_repair(index: int) -> void:  # UNIQUEMENT repair list
	_handle_car_selection(car_list_repair, index)

func _on_car_list_activated_waiting(index: int) -> void:
	print("💰 Paiement simulé V", car_list_waiting.get_item_text(index).split(" ")[1])
	waiting_slot.remove_car(int(car_list_waiting.get_item_text(index).split(" ")[1]))  # Ex: remove 1
	_update_car_list()

func _handle_car_selection(list: ItemList, index: int) -> void:
	var text = list.get_item_text(index)
	var car_id = int(text.split(" - ")[0])
	
	var free_slot = _get_free_slot()
	if not free_slot:
		print("❌ Slots pleins!"); return
	
	side_panel.visible = false
	waiting_slot.remove_car(car_id)
	free_slot.place_car(car_id)
	print("🚗 V%d → slot %s" % [car_id, free_slot.name.split("_")[1]])
func _get_free_slot():
	if slot1.current_car_id == -1 and not slot1.is_busy:
		return slot1
	if slot2.current_car_id == -1 and not slot2.is_busy:
		return slot2
	return null

func _open_repair_menu_for_slot(slot) -> void:
	current_slot = slot
	var car_id = slot.current_car_id
	if car_id == -1:
		print("❌ Slot libre")
		return

	var car_info = cars_data.get(car_id)
	if car_info == null:
		print("❌ Voiture %d inconnue dans cars_data !" % car_id)
		print("cars_data keys: ", cars_data.keys())
		return
		
	repair_list.clear()
	
	# SAFE : check repairs_left existe
	if not car_info.has("repairs_left") or car_info["repairs_left"].is_empty():
		repair_list.add_item("✅ Toutes terminées")
		repair_menu.visible = true
		return
	
	# TOUTES les réparations
	for rep_name in car_info["repairs_left"]:
		var data = REPAIRS.get(rep_name, {"prix":0, "duree":5.0})
		var txt = "%s - %d Ar - %.0fs" % [rep_name, data["prix"], data["duree"]]
		repair_list.add_item(txt)
	
	repair_menu.visible = true
	print("✅ Menu %d reps pour V%d" % [car_info["repairs_left"].size(), car_id])

func _on_repair_list_item_activated(index: int) -> void:
	if current_slot == null:
		return
	var text = repair_list.get_item_text(index)
	var rep_name = text.split(" - ")[0]
	_start_repair_on_slot(current_slot, rep_name)
	repair_menu.visible = false
	repair_blocked = true  # ← BLOCK E
	await get_tree().create_timer(0.5).timeout  # Anti-spam
	repair_blocked = false

func _on_repair_close_pressed() -> void:
	repair_menu.visible = false
	current_slot = null

func _start_repair_on_slot(slot, repair_type: String) -> void:
	if slot.is_busy:  # ← BLOCK si déjà réparation
		print("⏳ Slot occupé ! Attends fin.")
		return
	var car_id = slot.current_car_id
	var data = REPAIRS.get(repair_type, {"prix":0,"duree":10.0})
	var duration = data["duree"]

	print("🔧 Démarre %s (voiture %d, slot %d, %ds)" % [repair_type, car_id, slot.slot_id, duration])

	slot.is_busy = true
	slot.repair_type = repair_type

	var bar: ProgressBar = progress1 if slot == slot1 else progress2
	bar.value = 0
	bar.visible = true

	var tween = create_tween()
	tween.tween_property(bar, "value", 100, duration)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	add_child(timer)
	timer.start()

	timer.timeout.connect(func():
		_on_repair_finished(slot, car_id, repair_type, bar, timer)
	)

func _on_repair_finished(slot, car_id: int, repair_type: String, bar: ProgressBar, timer: Timer):
	# UNE SEULE déclaration car_info
	var car_info = cars_data[car_id]
	
	# SUPPRIME la rep (erase suffit, pas pop_front double)
	car_info["repairs_left"].erase(repair_type)
	
	print("✅ %s terminée (V%d). Restantes: %s" % [repair_type, car_id, car_info["repairs_left"]])
	
	# Slot libre
	slot.is_busy = false
	slot.repair_type = ""
	bar.value = 0
	bar.visible = false
	timer.queue_free()
	
	# Toutes finies ? → Waiting
	if car_info["repairs_left"].is_empty():
		slot.clear_slot()
		waiting_slot.add_car(car_id)
		print("🎉 V%d prête ! En attente paiement." % car_id)
	
	# Refresh direct (pas on_car_list_changed)
	_update_car_list()
	_update_car_count()
	
func _on_http_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		cars_data = json.get("cars", {})  # Merge
	if cars_data.is_empty():
		print("⚠ Aucune voiture pour cet utilisateur.")
	else:
		print("✅ API cars: ", cars_data.keys())
	_update_car_list()
