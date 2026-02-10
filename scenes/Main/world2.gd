extends Node2D

@onready var player        = $Player
@onready var slot1         = $Slot_1
@onready var slot2         = $Slot_2
@onready var waiting_slot  = $WaitingSlot

@onready var side_panel       = $CanvasLayer/SidePanel
@onready var car_list_repair  = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListToRepair
@onready var car_list_waiting = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListWaiting

@onready var repair_menu   = $CanvasLayer/RepairMenu
@onready var repair_list   = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairList
@onready var repair_close  = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairCloseButton
@onready var user_label    = $CanvasLayer/UserLabel

@onready var progress1     = $CanvasLayer/ProgressSlot1
@onready var progress2     = $CanvasLayer/ProgressSlot2
@onready var btn_voitures  = $CanvasLayer/BoutonVoiture

@onready var firebase_auth = Firebase.Auth

signal car_list_changed

var auth_token: String = ""
var user_email: String = ""
var user_uid: String = ""   # UID du compte Godot (mécanicien), ici juste informatif
var db_cars_ref: FirebaseDatabaseReference
var db_repairs_ref: FirebaseDatabaseReference
var cars_data: Dictionary = {}  # car_id -> {name, repairs_left: Array[type]}
var INTERVENTIONS: Dictionary = {}  # "Pneus" -> {duree:1800, prix:150000}
var current_slot = null
var repair_blocked = false
var REPAIRS: Dictionary = {}     # "batterie" -> { prix, duree, label }
#var cars_listener = null
#var repairs_listener = null
var _auth: Dictionary = {}
var db_ref_cars: FirebaseDatabaseReference

func _init_interventions():
	INTERVENTIONS = {
		"Pneus": {"duree": 1800.0, "prix": 120000},  # 30min
		"Système de refroidissement": {"duree": 3600.0, "prix": 250000},
		"Filtre": {"duree": 900.0, "prix": 50000},
		"Batterie": {"duree": 1080.0, "prix": 200000},
		# Ajoute tous types possibles
	}
	
func init_auth(auth: Dictionary) -> void:
	_auth = auth

func _ready() -> void:
	set_process_input(true)

	repair_menu.visible = false
	side_panel.visible = false

	if repair_list:
		repair_list.item_activated.connect(_on_repair_list_item_activated)
	if repair_close:
		repair_close.pressed.connect(_on_repair_close_pressed)
	if car_list_repair:
		car_list_repair.item_activated.connect(_on_car_list_activated_repair)
	if car_list_waiting:
		car_list_waiting.item_activated.connect(_on_car_list_activated_waiting)
	if btn_voitures:
		btn_voitures.pressed.connect(_toggle_car_list)

	progress1.value = 0
	progress2.value = 0
	progress1.visible = false
	progress2.visible = false

	_update_car_list()
	_update_car_count()

	if _auth.size() > 0:
		print("🚀 [DEBUG] World reçoit auth via init_auth")
		_on_auth_ok(_auth)
	else:
		print("⚠ [DEBUG] World n’a pas reçu d’auth")

#func _exit_tree() -> void:
	#if cars_listener:
		#cars_listener.disconnect()
	#if repairs_listener:
		#repairs_listener.disconnect()


# ---------------------------------------------------------
# AUTH & CHARGEMENT FIRESTORE
# ---------------------------------------------------------

func _on_auth_ok(auth: Dictionary) -> void:
	print("✅ Firebase Auth OK:", auth.keys())
	print("🚀 [DEBUG] _on_auth_ok appelé")
	print("🔐 auth keys:", auth.keys())
	auth_token = auth.get("idtoken", "")
	user_email = auth.get("email", "")
	user_uid   = auth.get("localid", "")

	if user_label:
		user_label.text = "Connecté en tant que : " + (user_email if user_email != "" else user_uid)

	print("🔐 User (jeu mécanicien) email:", user_email, "UID:", user_uid)

	# lance le chargement Firestore après ce frame
	call_deferred("_load_all_from_firestore")
	call_deferred("_test_repairs_simple")  # AJOUT TEMPORAIRE
	
func _test_repairs_simple() -> void:
	print("🧪 [TEST] Lecture simple de repairs")
	var q := FirestoreQuery.new()
	q.from("repairs")  # orthographe exacte de la collection

	var results = await Firebase.Firestore.query(q)
	print("🧪 [TEST] repairs results =", results)

	if results == null:
		print("🧪 [TEST] -> results == null (pb règles ou chemin)")
		return

	if typeof(results) != TYPE_ARRAY:
		print("🧪 [TEST] -> type =", typeof(results))
		return

	print("🧪 [TEST] nb repairs =", results.size())
	for rep_doc in results:
		print("🧪 [TEST] rep_doc.name =", rep_doc.doc_name, "carId =", rep_doc.get_value("carId"), "status =", rep_doc.get_value("status"))


func _load_all_from_firestore() -> void:
	print("🚀 [DEBUG] _load_all_from_firestore")
	await _load_interventions_from_firestore()
	await _refresh_all_cars()

	# Pour l’instant, PAS de listener on_snapshot
	# Quand tu voudras rafraîchir après une modif, tu pourras rappeler _refresh_all_cars() manuellement,
	# par exemple sur un bouton "Rafraîchir" ou un Timer.


#func _on_firestore_changed() -> void:
	## Re-sync complet
	#call_deferred("_refresh_all_cars")

func _load_interventions_from_firestore() -> void:
	var q := FirestoreQuery.new()
	q.from("interventions")

	var results = await Firebase.Firestore.query(q)  # PAS typé Array
	if results == null:
		print("⚠ [DEBUG] interventions results == null")
		return
	if typeof(results) != TYPE_ARRAY:
		print("⚠ [DEBUG] interventions results n’est pas un Array, type =", typeof(results))
		return

	REPAIRS.clear()

	for doc in results:
		var inter_id: String = doc.doc_name  # ID du doc, ex: "batterie"
		var name_val = doc.get_value("name")
		var price_val = doc.get_value("price")
		var dur_val = doc.get_value("duration_minutes")

		var name: String = str(name_val) if name_val != null else inter_id
		var price: int = int(price_val) if price_val != null else 0
		var duration_min: float = float(dur_val) if dur_val != null else 1.0
		var duration_sec: float = duration_min * 60.0

		REPAIRS[inter_id] = {
			"prix": price,
			"duree": duration_sec,
			"label": name
		}

	print("🔧 Interventions Firestore:", REPAIRS.keys())


func _refresh_all_cars() -> void:
	print("🚀 [DEBUG] _refresh_all_cars() lancé")
	var cars_query := FirestoreQuery.new()
	cars_query.from("cars")

	print("🔥 [DEBUG] Query cars (toutes les voitures)")
	var cars_results = await Firebase.Firestore.query(cars_query)
	if cars_results == null:
		print("⚠ [DEBUG] cars_results == null")
		return
	if typeof(cars_results) != TYPE_ARRAY:
		print("⚠ [DEBUG] cars_results n’est pas un Array, type =", typeof(cars_results))
		return

	print("🔥 [DEBUG] cars_results size =", cars_results.size())

	cars_data.clear()

	for car_doc in cars_results:
		var car_id: String = car_doc.doc_name  # ← DÉFINI ICI d'abord

		var annee_val = car_doc.get_value("annee")
		var marque_val = car_doc.get_value("marque")
		var modele_val = car_doc.get_value("modele")
		var immat_val  = car_doc.get_value("immatriculation")

		var annee  = str(annee_val)  if annee_val  != null else ""
		var marque = str(marque_val) if marque_val != null else ""
		var modele = str(modele_val) if modele_val != null else ""
		var immat  = str(immat_val)  if immat_val  != null else ""

		print("📄 [DEBUG] car_doc id =", car_id, "annee=", annee, "marque=", marque, "modele=", modele, "immat=", immat)

		# Récupère les repairs pour CETTE voiture
		var repairs_left = await _get_pending_repairs_for_car(car_id)
		print("🔧 [DEBUG] repairs_left pour", car_id, "=", repairs_left)

		# ← CORRECTION : TOUJOURS ajouter la voiture
		if repairs_left.is_empty():
			repairs_left = ["maintenance"]  # Ou [] si tu préfères sans icône

		var display_name = "%s %s %s (%s)" % [marque, modele, immat, annee]

		cars_data[car_id] = {
			"id": car_id,
			"name": display_name,
			"repairs_left": repairs_left
		}

	print("🚗 [DEBUG] cars_data keys =", cars_data.keys())

	_update_car_list()
	_update_car_count()


func _get_pending_repairs_for_car(car_id: String):
	var pending: Array[String] = []

	var q := FirestoreQuery.new()
	q.from("repairs")

	print("🔥 [DEBUG] Query repairs (toutes) pour carId =", car_id)
	var results = await Firebase.Firestore.query(q)
	if results == null or typeof(results) != TYPE_ARRAY:
		return pending

	print("🔥 [DEBUG] repairs results size (global) =", results.size())

	# IMPORTANT : car_id_ref = string de l'id voiture Firestore
	var car_id_ref: String = str(car_id)

	for rep_doc in results:
		var car_id_val = rep_doc.get_value("carId")
		var status_val = rep_doc.get_value("status")
		var inter_id_val = rep_doc.get_value("interventionId")

		var car_id_str: String = str(car_id_val)
		var status_str: String = str(status_val)
		var inter_id_str: String = str(inter_id_val)

		print("📄 [DEBUG] repair doc name =", rep_doc.doc_name,
			"carId =", car_id_str, "status =", status_str, "interventionId =", inter_id_str)

		# Tout est string → plus d'erreur 'int' == 'String'
		if car_id_str == car_id_ref and status_str == "pending" and inter_id_str != "":
			pending.append(inter_id_str)

	return pending

# ---------------------------------------------------------
# INPUTS / INTERACTIONS
# ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not repair_blocked:
		var s = _get_slot_with_player()
		if s != null:
			_open_repair_menu_for_slot(s)
		else:
			print("Joueur pas près d'une voiture")


func _get_slot_with_player():
	if slot1 and slot1.player_inside and slot1.current_car_id != "":
		return slot1
	if slot2 and slot2.player_inside and slot2.current_car_id != "":
		return slot2
	return null
# ---------------------------------------------------------
# LISTES VOITURES
# ---------------------------------------------------------

func _toggle_car_list() -> void:
	side_panel.visible = !side_panel.visible
	if side_panel.visible:
		_update_car_list()


func _update_car_count() -> void:
	var total_repair = 0
	for car_id in cars_data:
		var info: Dictionary = cars_data[car_id]
		if info.get("repairs_left", []).size() > 0:
			total_repair += 1
	btn_voitures.text = "🚗 Voitures (%d)" % total_repair


func _update_car_list() -> void:
	if car_list_repair:
		car_list_repair.clear()
	if car_list_waiting:
		car_list_waiting.clear()

	for car_id in cars_data:
		var info: Dictionary = cars_data[car_id]
		var reps: Array = info.get("repairs_left", [])
		if reps.size() > 0:
			var status = "📥"

			var car_id_str: String = str(car_id)

			var slot1_id_str: String = ""
			if slot1:
				slot1_id_str = str(slot1.current_car_id)

			var slot2_id_str: String = ""
			if slot2:
				slot2_id_str = str(slot2.current_car_id)

			if slot1_id_str == car_id_str or slot2_id_str == car_id_str:
				status = "🔧"

			var txt = "%s - %s (%d) %s" % [car_id_str, info.get("name", "?"), reps.size(), status]
			car_list_repair.add_item(txt)

	for car_id in waiting_slot.waiting_car_ids:
		var info = cars_data.get(car_id, {})
		var name = info.get("name", "?")
		car_list_waiting.add_item("💰 %s - %s (Payer)" % [str(car_id), name])

	btn_voitures.text = "🚗 (%d)" % car_list_repair.item_count
	car_list_changed.emit()


func _on_car_list_activated_repair(index: int) -> void:
	_handle_car_selection(car_list_repair, index)


func _on_car_list_activated_waiting(index: int) -> void:
	var text = car_list_waiting.get_item_text(index)  # "💰 carId - name (Payer)"
	var parts = text.split(" ")
	if parts.size() > 1:
		var car_id = parts[1]
		waiting_slot.remove_car(car_id)
		_update_car_list()


func _handle_car_selection(list: ItemList, index: int) -> void:
	var text = list.get_item_text(index)
	var car_id = text.split(" - ")[0]  # String

	var free_slot = _get_free_slot()
	if not free_slot:
		print("❌ Slots pleins !")
		return

	side_panel.visible = false
	waiting_slot.remove_car(car_id)
	free_slot.place_car(car_id)  # car_id est String


func _get_free_slot():
	if slot1 and slot1.current_car_id == "" and not slot1.is_busy:
		return slot1
	if slot2 and slot2.current_car_id == "" and not slot2.is_busy:
		return slot2
	return null


# ---------------------------------------------------------
# MENU DE RÉPARATION
# ---------------------------------------------------------

func _open_repair_menu_for_slot(slot) -> void:
	current_slot = slot
	var car_id = slot.current_car_id
	if car_id == "":
		return

	var car_info = cars_data.get(car_id)
	if car_info == null:
		return

	repair_list.clear()

	var repairs_left: Array = car_info.get("repairs_left", [])
	if repairs_left.is_empty():
		repair_list.add_item("✅ Toutes terminées")
		repair_menu.visible = true
		return

	for rep_id in repairs_left:
		var data = REPAIRS.get(rep_id, {"prix": 0, "duree": 5.0, "label": rep_id})
		var txt = "%s - %d Ar - %.0fs" % [data["label"], data["prix"], data["duree"]]
		repair_list.add_item(txt)

	repair_menu.visible = true


func _on_repair_list_item_activated(index: int) -> void:
	if current_slot == null:
		return

	var text = repair_list.get_item_text(index)
	if text.begins_with("✅"):
		return

	var car_id = current_slot.current_car_id
	var car_info = cars_data.get(car_id, {})
	var repairs_left: Array = car_info.get("repairs_left", [])

	if index < 0 or index >= repairs_left.size():
		return

	var rep_id: String = repairs_left[index]

	_start_repair_on_slot(current_slot, rep_id)
	repair_menu.visible = false
	repair_blocked = true
	await get_tree().create_timer(0.5).timeout
	repair_blocked = false


func _on_repair_close_pressed() -> void:
	repair_menu.visible = false
	current_slot = null


# ---------------------------------------------------------
# LOGIQUE RÉPARATION
# ---------------------------------------------------------

func _start_repair_on_slot(slot, repair_type: String) -> void:
	if slot.is_busy:
		print("⚠ Slot déjà occupé")
		return

	var car_id: String = slot.current_car_id
	if car_id == "":
		print("⚠ Pas de voiture dans ce slot")
		return

	var data = REPAIRS.get(repair_type, {"prix": 0, "duree": 10.0, "label": repair_type})
	var duration: float = float(data["duree"])

	slot.is_busy = true
	slot.repair_type = repair_type

	var bar: ProgressBar = progress1 if slot == slot1 else progress2
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.visible = true

	print("⏱ Démarrage réparation", repair_type, "sur", car_id, "durée", duration, "s")

	var tween := create_tween()
	tween.tween_property(bar, "value", 100.0, duration)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	add_child(timer)
	timer.start()

	timer.timeout.connect(func():
		_on_repair_finished(slot, car_id, repair_type, bar, timer)
	)

func _on_repair_finished(slot, car_id: String, repair_type: String, bar: ProgressBar, timer: Timer) -> void:
	var car_info: Dictionary = cars_data.get(car_id, {})
	var repairs_left: Array = car_info.get("repairs_left", [])

	repairs_left.erase(repair_type)
	car_info["repairs_left"] = repairs_left
	cars_data[car_id] = car_info

	slot.is_busy = false
	slot.repair_type = ""
	bar.value = 0
	bar.visible = false
	timer.queue_free()

	if repairs_left.is_empty():
		slot.clear_slot()
		waiting_slot.add_car(car_id)

	_update_car_list()
	_update_car_count()

#extends Node2D
#
#@onready var player        = $Player
#@onready var slot1         = $Slot_1
#@onready var slot2         = $Slot_2
#@onready var waiting_slot  = $WaitingSlot
#
#@onready var side_panel       = $CanvasLayer/SidePanel
#@onready var car_list_repair  = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListToRepair
#@onready var car_list_waiting = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListWaiting
#
#@onready var repair_menu   = $CanvasLayer/RepairMenu
#@onready var repair_list   = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairList
#@onready var repair_close  = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairCloseButton
#@onready var user_label    = $CanvasLayer/UserLabel
#
#@onready var progress1     = $CanvasLayer/ProgressSlot1
#@onready var progress2     = $CanvasLayer/ProgressSlot2
#@onready var btn_voitures  = $CanvasLayer/BoutonVoiture
#
#signal car_list_changed
#
#var cars_data: Dictionary = {}
#var INTERVENTIONS: Dictionary = {}
#
#var current_slot = null
#var repair_blocked = false
#var _auth: Dictionary = {}
#var db_ref_cars: FirebaseDatabaseReference
#var auth_data: Dictionary
#var auth_ready := false
#
#func init_auth(auth: Dictionary) -> void:
	#auth_data = auth
	#auth_ready = true
	#_start_world()
#
#func _start_world():
	#print("🚀 World lancé pour :", auth_data.get("email",""))
#
#
## ---------------------------------------------------------
## INTERVENTIONS
## ---------------------------------------------------------
#
#func _init_interventions():
	#INTERVENTIONS = {
		#"Pneus": {"duree": 1800.0, "prix": 120000},
		#"Système de refroidissement": {"duree": 3600.0, "prix": 250000},
		#"Filtre": {"duree": 900.0, "prix": 50000},
		#"Batterie": {"duree": 1080.0, "prix": 200000}
	#}
#
#
## ---------------------------------------------------------
## READY
## ---------------------------------------------------------
#
#func _ready() -> void:
	#set_process_input(true)
	#_init_interventions()
#
	#repair_menu.visible = false
	#side_panel.visible = false
#
	#if repair_list:
		#repair_list.item_activated.connect(_on_repair_list_item_activated)
	#if repair_close:
		#repair_close.pressed.connect(_on_repair_close_pressed)
	#if btn_voitures:
		#btn_voitures.pressed.connect(_toggle_car_list)
#
	#progress1.visible = false
	#progress2.visible = false
#
#
## ---------------------------------------------------------
## AUTH
## ---------------------------------------------------------
#
#func _on_auth_ok(auth: Dictionary) -> void:
	#_auth = auth
#
	#Firebase.Database.database_url = "https://garage-s5-default-rtdb.firebaseio.com/"
	#call_deferred("_load_realtime_repairs")
#
#
## ---------------------------------------------------------
## REALTIME DB MOBILE
## ---------------------------------------------------------
#
#func _load_realtime_repairs() -> void:	
	#db_ref_cars = Firebase.Database.get_database_reference("cars", {})
#
	#db_ref_cars.new_data_update.connect(_on_mobile_repairs_update)
#
	#await db_ref_cars.get("")
#
	#print("📱 RealtimeDB connecté")
#
#
#func _on_repair_close_pressed() -> void:
	#repair_menu.visible = false
	#current_slot = null
#
#func _update_car_list() -> void:
#
	#if car_list_repair:
		#car_list_repair.clear()
#
	#for car_id in cars_data:
#
		#var info = cars_data[car_id]
		#var reps = info.get("repairs_left",[])
#
		#var txt = "%s - %s (%d)" % [
			#car_id,
			#info.get("name","?"),
			#reps.size()
		#]
#
		#car_list_repair.add_item(txt)
#
	#car_list_changed.emit()
#
#func _toggle_car_list() -> void:
	#side_panel.visible = !side_panel.visible
#
#func _update_car_count() -> void:
#
	#var total = 0
#
	#for car_id in cars_data:
		#if cars_data[car_id]["repairs_left"].size() > 0:
			#total += 1
#
	#btn_voitures.text = "🚗 (%d)" % total
#
#
#func _on_mobile_repairs_update(resource:) -> void:
	#print("🔄 Mobile update reçu")
	#_parse_mobile_cars(resource.data)
	#_update_car_list()
	#_update_car_count()
#
#
#func _parse_mobile_cars(cars_dict: Dictionary) -> void:
	#cars_data.clear()
#
	#for car_id in cars_dict.keys():
#
		#var car: Dictionary = cars_dict[car_id]
		#var pending_repairs: Array[String] = []
#
		#if car.has("repairs") and car["repairs"] is Array:
#
			#for rep in car["repairs"]:
#
				#if rep.get("status","") == "pending":
					#pending_repairs.append(rep.get("type",""))
#
		#if pending_repairs.size() > 0:
#
			#cars_data[car_id] = {
				#"name": "%s (%s)" % [
					#car.get("model","?"),
					#car.get("licensePlate","?")
				#],
				#"repairs_left": pending_repairs
			#}
#
	#print("🚗 Cars loaded:", cars_data.keys())
#
#
#
## ---------------------------------------------------------
## INPUT
## ---------------------------------------------------------
#
#func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("ui_accept") and not repair_blocked:
		#var s = _get_slot_with_player()
		#if s != null:
			#_open_repair_menu_for_slot(s)
#
#
#func _get_slot_with_player():
	#if slot1 and slot1.player_inside and slot1.current_car_id != "":
		#return slot1
	#if slot2 and slot2.player_inside and slot2.current_car_id != "":
		#return slot2
	#return null
#
#
## ---------------------------------------------------------
## MENU REPAIR
## ---------------------------------------------------------
#
#func _open_repair_menu_for_slot(slot) -> void:
	#current_slot = slot
	#var car_id = slot.current_car_id
	#var car_info = cars_data.get(car_id)
#
	#if car_info == null:
		#return
#
	#repair_list.clear()
#
	#var repairs_left: Array = car_info.get("repairs_left", [])
	#for rep_type in repairs_left:
		#var interv = INTERVENTIONS.get(rep_type, {"duree":300.0,"prix":50000})
		#var txt = "%s - %d Ar (%.0fmin)" % [rep_type, interv.prix, interv.duree/60]
		#repair_list.add_item(txt)
#
	#repair_menu.visible = true
#
#
#func _on_repair_list_item_activated(index: int) -> void:
	#if current_slot == null:
		#return
#
	#var car_id = current_slot.current_car_id
	#var car_info = cars_data.get(car_id, {})
	#var repairs_left: Array = car_info.get("repairs_left", [])
#
	#var rep_type: String = repairs_left[index]
	#var interv = INTERVENTIONS[rep_type]
#
	#_start_repair_on_slot(current_slot, rep_type, interv.duree)
#
	#repair_menu.visible = false
	#repair_blocked = true
	#await get_tree().create_timer(0.5).timeout
	#repair_blocked = false
#
#
## ---------------------------------------------------------
## REPAIR LOGIC
## ---------------------------------------------------------
#
#func _start_repair_on_slot(slot, rep_type: String, duration: float) -> void:
	#slot.is_busy = true
#
	#var bar: ProgressBar = progress1 if slot == slot1 else progress2
	#bar.value = 0
	#bar.visible = true
#
	#var tween := create_tween()
	#tween.tween_property(bar,"value",100.0,duration)
#
	#var timer := Timer.new()
	#timer.one_shot = true
	#timer.wait_time = duration
	#add_child(timer)
	#timer.start()
#
	#timer.timeout.connect(func():
		#_on_repair_finished(slot, slot.current_car_id, rep_type, bar, timer)
	#)
#
#
#func _on_repair_finished(slot, car_id: String, rep_type: String, bar: ProgressBar, timer: Timer) -> void:
#
	#var car_info: Dictionary = cars_data.get(car_id, {})
	#var repairs_left: Array = car_info.get("repairs_left", [])
#
	#repairs_left.erase(rep_type)
	#car_info["repairs_left"] = repairs_left
	#cars_data[car_id] = car_info
#
	#slot.is_busy = false
	#bar.visible = false
	#timer.queue_free()
#
	#await _mark_mobile_repair_done(car_id, rep_type)
#
	#_update_car_list()
	#_update_car_count()
#
#
## ---------------------------------------------------------
## MOBILE UPDATE DONE
## ---------------------------------------------------------
#
#func _mark_mobile_repair_done(car_id: String, rep_type: String) -> void:
#
	#var ref_cars = Firebase.Database.get_database_reference(
		#"cars/%s/repairs" % car_id, {}
	#)
#
	#var snapshot = await ref_cars.get({})
#
	#if snapshot.data and snapshot.data is Array:
#
		#for i in range(snapshot.data.size()):
#
			#var rep = snapshot.data[i]
#
			#if rep.get("type","") == rep_type:
#
				#var ref_rep = Firebase.Database.get_database_reference(
					#"cars/%s/repairs/%s" % [car_id,i], {}
				#)
#
				#await ref_rep.update({
					#"status":"done",
					#"progress":100,
					#"finishedAt":Time.get_unix_time_from_system()
				#})
#
				#print("📤 Repair done synced:", car_id, rep_type)
				#return


#extends Node2D
#
#@onready var player        = $Player
#@onready var slot1         = $Slot_1
#@onready var slot2         = $Slot_2
#@onready var waiting_slot  = $WaitingSlot
#
#@onready var side_panel       = $CanvasLayer/SidePanel
#@onready var car_list_repair  = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListToRepair
#@onready var car_list_waiting = $CanvasLayer/SidePanel/Panel/VBoxContainer/CarListWaiting
#
#@onready var repair_menu   = $CanvasLayer/RepairMenu
#@onready var repair_list   = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairList
#@onready var repair_close  = $CanvasLayer/RepairMenu/Panel/VBoxContainer/RepairCloseButton
#@onready var user_label    = $CanvasLayer/UserLabel
#
#@onready var progress1     = $CanvasLayer/ProgressSlot1
#@onready var progress2     = $CanvasLayer/ProgressSlot2
#@onready var btn_voitures  = $CanvasLayer/BoutonVoiture
#
#@onready var firebase_auth = Firebase.Auth
#
#signal car_list_changed
#
#var auth_token: String = ""
#var user_email: String = ""
#var user_uid: String = ""   # UID du compte Godot (mécanicien), ici juste informatif
#var db_cars_ref: FirebaseDatabaseReference
#var db_repairs_ref: FirebaseDatabaseReference
#var cars_data: Dictionary = {}  # car_id -> {name, repairs_left: Array[type]}
#var INTERVENTIONS: Dictionary = {}  # "Pneus" -> {duree:1800, prix:150000}
#var current_slot = null
#var repair_blocked = false
#var REPAIRS: Dictionary = {}     # "batterie" -> { prix, duree, label }
##var cars_listener = null
##var repairs_listener = null
#var _auth: Dictionary = {}
#var db_ref_cars: FirebaseDatabaseReference
#
#func _init_interventions():
	#INTERVENTIONS = {
		#"Pneus": {"duree": 1800.0, "prix": 120000},  # 30min
		#"Système de refroidissement": {"duree": 3600.0, "prix": 250000},
		#"Filtre": {"duree": 900.0, "prix": 50000},
		#"Batterie": {"duree": 1080.0, "prix": 200000},
		## Ajoute tous types possibles
	#}
	#
#func init_auth(auth: Dictionary) -> void:
	#_auth = auth
#
#func _ready() -> void:
	#set_process_input(true)
#
	#repair_menu.visible = false
	#side_panel.visible = false
#
	#if repair_list:
		#repair_list.item_activated.connect(_on_repair_list_item_activated)
	#if repair_close:
		#repair_close.pressed.connect(_on_repair_close_pressed)
	#if car_list_repair:
		#car_list_repair.item_activated.connect(_on_car_list_activated_repair)
	#if car_list_waiting:
		#car_list_waiting.item_activated.connect(_on_car_list_activated_waiting)
	#if btn_voitures:
		#btn_voitures.pressed.connect(_toggle_car_list)
#
	#progress1.value = 0
	#progress2.value = 0
	#progress1.visible = false
	#progress2.visible = false
#
	#_update_car_list()
	#_update_car_count()
#
	#if _auth.size() > 0:
		#print("🚀 [DEBUG] World reçoit auth via init_auth")
		#_on_auth_ok(_auth)
	#else:
		#print("⚠ [DEBUG] World n’a pas reçu d’auth")
#
##func _exit_tree() -> void:
	##if cars_listener:
		##cars_listener.disconnect()
	##if repairs_listener:
		##repairs_listener.disconnect()
#
#
## ---------------------------------------------------------
## AUTH & CHARGEMENT FIRESTORE
## ---------------------------------------------------------
#
#func _on_auth_ok(auth: Dictionary) -> void:
	#print("✅ Firebase Auth OK:", auth.keys())
	#print("🚀 [DEBUG] _on_auth_ok appelé")
	#print("🔐 auth keys:", auth.keys())
	#auth_token = auth.get("idtoken", "")
	#user_email = auth.get("email", "")
	#user_uid   = auth.get("localid", "")
#
	#if user_label:
		#user_label.text = "Connecté en tant que : " + (user_email if user_email != "" else user_uid)
#
	#print("🔐 User (jeu mécanicien) email:", user_email, "UID:", user_uid)
#
	## lance le chargement Firestore après ce frame
	#call_deferred("_load_all_from_firestore")
	#call_deferred("_test_repairs_simple")  # AJOUT TEMPORAIRE
	#
#func _test_repairs_simple() -> void:
	#print("🧪 [TEST] Lecture simple de repairs")
	#var q := FirestoreQuery.new()
	#q.from("repairs")  # orthographe exacte de la collection
#
	#var results = await Firebase.Firestore.query(q)
	#print("🧪 [TEST] repairs results =", results)
#
	#if results == null:
		#print("🧪 [TEST] -> results == null (pb règles ou chemin)")
		#return
#
	#if typeof(results) != TYPE_ARRAY:
		#print("🧪 [TEST] -> type =", typeof(results))
		#return
#
	#print("🧪 [TEST] nb repairs =", results.size())
	#for rep_doc in results:
		#print("🧪 [TEST] rep_doc.name =", rep_doc.doc_name, "carId =", rep_doc.get_value("carId"), "status =", rep_doc.get_value("status"))
#
#
#func _load_all_from_firestore() -> void:
	#print("🚀 [DEBUG] _load_all_from_firestore")
	#await _load_interventions_from_firestore()
	#await _refresh_all_cars()
#
	## Pour l’instant, PAS de listener on_snapshot
	## Quand tu voudras rafraîchir après une modif, tu pourras rappeler _refresh_all_cars() manuellement,
	## par exemple sur un bouton "Rafraîchir" ou un Timer.
#
#
##func _on_firestore_changed() -> void:
	### Re-sync complet
	##call_deferred("_refresh_all_cars")
#
#func _load_interventions_from_firestore() -> void:
	#var q := FirestoreQuery.new()
	#q.from("interventions")
#
	#var results = await Firebase.Firestore.query(q)  # PAS typé Array
	#if results == null:
		#print("⚠ [DEBUG] interventions results == null")
		#return
	#if typeof(results) != TYPE_ARRAY:
		#print("⚠ [DEBUG] interventions results n’est pas un Array, type =", typeof(results))
		#return
#
	#REPAIRS.clear()
#
	#for doc in results:
		#var inter_id: String = doc.doc_name  # ID du doc, ex: "batterie"
		#var name_val = doc.get_value("name")
		#var price_val = doc.get_value("price")
		#var dur_val = doc.get_value("duration_minutes")
#
		#var name: String = str(name_val) if name_val != null else inter_id
		#var price: int = int(price_val) if price_val != null else 0
		#var duration_min: float = float(dur_val) if dur_val != null else 1.0
		#var duration_sec: float = duration_min * 60.0
#
		#REPAIRS[inter_id] = {
			#"prix": price,
			#"duree": duration_sec,
			#"label": name
		#}
#
	#print("🔧 Interventions Firestore:", REPAIRS.keys())
#
#
#func _refresh_all_cars() -> void:
	#print("🚀 [DEBUG] _refresh_all_cars() lancé")
	#var cars_query := FirestoreQuery.new()
	#cars_query.from("cars")
#
	#print("🔥 [DEBUG] Query cars (toutes les voitures)")
	#var cars_results = await Firebase.Firestore.query(cars_query)
	#if cars_results == null:
		#print("⚠ [DEBUG] cars_results == null")
		#return
	#if typeof(cars_results) != TYPE_ARRAY:
		#print("⚠ [DEBUG] cars_results n’est pas un Array, type =", typeof(cars_results))
		#return
#
	#print("🔥 [DEBUG] cars_results size =", cars_results.size())
#
	#cars_data.clear()
#
	#for car_doc in cars_results:
		#var car_id: String = car_doc.doc_name  # ← DÉFINI ICI d'abord
#
		#var annee_val = car_doc.get_value("annee")
		#var marque_val = car_doc.get_value("marque")
		#var modele_val = car_doc.get_value("modele")
		#var immat_val  = car_doc.get_value("immatriculation")
#
		#var annee  = str(annee_val)  if annee_val  != null else ""
		#var marque = str(marque_val) if marque_val != null else ""
		#var modele = str(modele_val) if modele_val != null else ""
		#var immat  = str(immat_val)  if immat_val  != null else ""
#
		#print("📄 [DEBUG] car_doc id =", car_id, "annee=", annee, "marque=", marque, "modele=", modele, "immat=", immat)
#
		## Récupère les repairs pour CETTE voiture
		#var repairs_left = await _get_pending_repairs_for_car(car_id)
		#print("🔧 [DEBUG] repairs_left pour", car_id, "=", repairs_left)
#
		## ← CORRECTION : TOUJOURS ajouter la voiture
		#if repairs_left.is_empty():
			#repairs_left = ["maintenance"]  # Ou [] si tu préfères sans icône
#
		#var display_name = "%s %s %s (%s)" % [marque, modele, immat, annee]
#
		#cars_data[car_id] = {
			#"id": car_id,
			#"name": display_name,
			#"repairs_left": repairs_left
		#}
#
	#print("🚗 [DEBUG] cars_data keys =", cars_data.keys())
#
	#_update_car_list()
	#_update_car_count()
#
#
#func _get_pending_repairs_for_car(car_id: String):
	#var pending: Array[String] = []
#
	#var q := FirestoreQuery.new()
	#q.from("repairs")
#
	#print("🔥 [DEBUG] Query repairs (toutes) pour carId =", car_id)
	#var results = await Firebase.Firestore.query(q)
	#if results == null or typeof(results) != TYPE_ARRAY:
		#return pending
#
	#print("🔥 [DEBUG] repairs results size (global) =", results.size())
#
	## IMPORTANT : car_id_ref = string de l'id voiture Firestore
	#var car_id_ref: String = str(car_id)
#
	#for rep_doc in results:
		#var car_id_val = rep_doc.get_value("carId")
		#var status_val = rep_doc.get_value("status")
		#var inter_id_val = rep_doc.get_value("interventionId")
#
		#var car_id_str: String = str(car_id_val)
		#var status_str: String = str(status_val)
		#var inter_id_str: String = str(inter_id_val)
#
		#print("📄 [DEBUG] repair doc name =", rep_doc.doc_name,
			#"carId =", car_id_str, "status =", status_str, "interventionId =", inter_id_str)
#
		## Tout est string → plus d'erreur 'int' == 'String'
		#if car_id_str == car_id_ref and status_str == "pending" and inter_id_str != "":
			#pending.append(inter_id_str)
#
	#return pending
#
## ---------------------------------------------------------
## INPUTS / INTERACTIONS
## ---------------------------------------------------------
#
#func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("ui_accept") and not repair_blocked:
		#var s = _get_slot_with_player()
		#if s != null:
			#_open_repair_menu_for_slot(s)
		#else:
			#print("Joueur pas près d'une voiture")
#
#
#func _get_slot_with_player():
	#if slot1 and slot1.player_inside and slot1.current_car_id != "":
		#return slot1
	#if slot2 and slot2.player_inside and slot2.current_car_id != "":
		#return slot2
	#return null
## ---------------------------------------------------------
## LISTES VOITURES
## ---------------------------------------------------------
#
#func _toggle_car_list() -> void:
	#side_panel.visible = !side_panel.visible
	#if side_panel.visible:
		#_update_car_list()
#
#
#func _update_car_count() -> void:
	#var total_repair = 0
	#for car_id in cars_data:
		#var info: Dictionary = cars_data[car_id]
		#if info.get("repairs_left", []).size() > 0:
			#total_repair += 1
	#btn_voitures.text = "🚗 Voitures (%d)" % total_repair
#
#
#func _update_car_list() -> void:
	#if car_list_repair:
		#car_list_repair.clear()
	#if car_list_waiting:
		#car_list_waiting.clear()
#
	#for car_id in cars_data:
		#var info: Dictionary = cars_data[car_id]
		#var reps: Array = info.get("repairs_left", [])
		#if reps.size() > 0:
			#var status = "📥"
#
			#var car_id_str: String = str(car_id)
#
			#var slot1_id_str: String = ""
			#if slot1:
				#slot1_id_str = str(slot1.current_car_id)
#
			#var slot2_id_str: String = ""
			#if slot2:
				#slot2_id_str = str(slot2.current_car_id)
#
			#if slot1_id_str == car_id_str or slot2_id_str == car_id_str:
				#status = "🔧"
#
			#var txt = "%s - %s (%d) %s" % [car_id_str, info.get("name", "?"), reps.size(), status]
			#car_list_repair.add_item(txt)
#
	#for car_id in waiting_slot.waiting_car_ids:
		#var info = cars_data.get(car_id, {})
		#var name = info.get("name", "?")
		#car_list_waiting.add_item("💰 %s - %s (Payer)" % [str(car_id), name])
#
	#btn_voitures.text = "🚗 (%d)" % car_list_repair.item_count
	#car_list_changed.emit()
#
#
#func _on_car_list_activated_repair(index: int) -> void:
	#_handle_car_selection(car_list_repair, index)
#
#
#func _on_car_list_activated_waiting(index: int) -> void:
	#var text = car_list_waiting.get_item_text(index)  # "💰 carId - name (Payer)"
	#var parts = text.split(" ")
	#if parts.size() > 1:
		#var car_id = parts[1]
		#waiting_slot.remove_car(car_id)
		#_update_car_list()
#
#
#func _handle_car_selection(list: ItemList, index: int) -> void:
	#var text = list.get_item_text(index)
	#var car_id = text.split(" - ")[0]  # String
#
	#var free_slot = _get_free_slot()
	#if not free_slot:
		#print("❌ Slots pleins !")
		#return
#
	#side_panel.visible = false
	#waiting_slot.remove_car(car_id)
	#free_slot.place_car(car_id)  # car_id est String
#
#
#func _get_free_slot():
	#if slot1 and slot1.current_car_id == "" and not slot1.is_busy:
		#return slot1
	#if slot2 and slot2.current_car_id == "" and not slot2.is_busy:
		#return slot2
	#return null
#
#
## ---------------------------------------------------------
## MENU DE RÉPARATION
## ---------------------------------------------------------
#
#func _open_repair_menu_for_slot(slot) -> void:
	#current_slot = slot
	#var car_id = slot.current_car_id
	#if car_id == "":
		#return
#
	#var car_info = cars_data.get(car_id)
	#if car_info == null:
		#return
#
	#repair_list.clear()
#
	#var repairs_left: Array = car_info.get("repairs_left", [])
	#if repairs_left.is_empty():
		#repair_list.add_item("✅ Toutes terminées")
		#repair_menu.visible = true
		#return
#
	#for rep_id in repairs_left:
		#var data = REPAIRS.get(rep_id, {"prix": 0, "duree": 5.0, "label": rep_id})
		#var txt = "%s - %d Ar - %.0fs" % [data["label"], data["prix"], data["duree"]]
		#repair_list.add_item(txt)
#
	#repair_menu.visible = true
#
#
#func _on_repair_list_item_activated(index: int) -> void:
	#if current_slot == null:
		#return
#
	#var text = repair_list.get_item_text(index)
	#if text.begins_with("✅"):
		#return
#
	#var car_id = current_slot.current_car_id
	#var car_info = cars_data.get(car_id, {})
	#var repairs_left: Array = car_info.get("repairs_left", [])
#
	#if index < 0 or index >= repairs_left.size():
		#return
#
	#var rep_id: String = repairs_left[index]
#
	#_start_repair_on_slot(current_slot, rep_id)
	#repair_menu.visible = false
	#repair_blocked = true
	#await get_tree().create_timer(0.5).timeout
	#repair_blocked = false
#
#
#func _on_repair_close_pressed() -> void:
	#repair_menu.visible = false
	#current_slot = null
#
#
## ---------------------------------------------------------
## LOGIQUE RÉPARATION
## ---------------------------------------------------------
#
#func _start_repair_on_slot(slot, repair_type: String) -> void:
	#if slot.is_busy:
		#print("⚠ Slot déjà occupé")
		#return
#
	#var car_id: String = slot.current_car_id
	#if car_id == "":
		#print("⚠ Pas de voiture dans ce slot")
		#return
#
	#var data = REPAIRS.get(repair_type, {"prix": 0, "duree": 10.0, "label": repair_type})
	#var duration: float = float(data["duree"])
#
	#slot.is_busy = true
	#slot.repair_type = repair_type
#
	#var bar: ProgressBar = progress1 if slot == slot1 else progress2
	#bar.min_value = 0
	#bar.max_value = 100
	#bar.value = 0
	#bar.visible = true
#
	#print("⏱ Démarrage réparation", repair_type, "sur", car_id, "durée", duration, "s")
#
	#var tween := create_tween()
	#tween.tween_property(bar, "value", 100.0, duration)
#
	#var timer := Timer.new()
	#timer.one_shot = true
	#timer.wait_time = duration
	#add_child(timer)
	#timer.start()
#
	#timer.timeout.connect(func():
		#_on_repair_finished(slot, car_id, repair_type, bar, timer)
	#)
#
#func _on_repair_finished(slot, car_id: String, repair_type: String, bar: ProgressBar, timer: Timer) -> void:
	#var car_info: Dictionary = cars_data.get(car_id, {})
	#var repairs_left: Array = car_info.get("repairs_left", [])
#
	#repairs_left.erase(repair_type)
	#car_info["repairs_left"] = repairs_left
	#cars_data[car_id] = car_info
#
	#slot.is_busy = false
	#slot.repair_type = ""
	#bar.value = 0
	#bar.visible = false
	#timer.queue_free()
#
	#if repairs_left.is_empty():
		#slot.clear_slot()
		#waiting_slot.add_car(car_id)
#
	#_update_car_list()
	#_update_car_count()
