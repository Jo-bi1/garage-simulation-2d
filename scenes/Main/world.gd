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

var interaction_label: Label

@onready var firebase_auth = Firebase.Auth

signal car_list_changed

var auth_token: String = ""
var user_email: String = ""
var user_uid: String = ""   # UID du compte Godot (mécanicien), ici juste informatif

var cars_data: Dictionary = {}   # car_id -> { id, name, repairs_left: Array[Dictionary], status: String, repairs_done_count: int }
var INTERVENTIONS: Dictionary = {}  # (ancien format local si tu veux encore)
var REPAIRS: Dictionary = {}       # "amortisseurs" -> { prix, duree, label }

var current_slot = null
var repair_blocked = false

var _auth: Dictionary = {}

var refresh_timer: Timer
const REFRESH_INTERVAL: float = 10.0

# ---------------------------------------------------------
# INIT
# ---------------------------------------------------------

func _init_interventions():
	INTERVENTIONS = {
		"Pneus": {"duree": 1800.0, "prix": 120000},  # 30min
		"Système de refroidissement": {"duree": 3600.0, "prix": 250000},
		"Filtre": {"duree": 900.0, "prix": 50000},
		"Batterie": {"duree": 1080.0, "prix": 200000},
		# Ajoute tous types possibles si besoin
	}

func init_auth(auth: Dictionary) -> void:
	_auth = auth

func _ready() -> void:
	set_process_input(true)
	
	Firebase.Firestore.error.connect(_on_firestore_error)

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
	
	_setup_interaction_label()

	# Forcer le login anonyme AVANT de démarrer
	print("⏳ [DEBUG] Lancement du login anonyme Firebase...")
	await _init_firebase_and_load_data()
	
	# L'auto-refresh ne démarre QU'APRÈS le premier chargement réussi
	_setup_auto_refresh()

func _init_firebase_and_load_data() -> void:
	Firebase.Auth.login_anonymous()
	var auth_result = await Firebase.Auth.auth_request
	
	if auth_result[0] == 1:  # Succès
		print("✅ [DEBUG] Firebase Auth réussi, chargement des données...")
		await _refresh_all_cars()
	else:
		print("❌ [DEBUG] Échec de l'authentification Firebase:", auth_result)

func _on_firebase_auth_ready(auth_result: Dictionary) -> void:
	print("✅ [DEBUG] Firebase Auth prêt, chargement des données...")
	await _refresh_all_cars()

# ---------------------------------------------------------
# AUTO-REFRESH
# ---------------------------------------------------------

func _setup_interaction_label() -> void:
	interaction_label = Label.new()
	interaction_label.text = "Appuyez sur 'E' pour voir les reparations"
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.add_theme_color_override("font_color", Color.YELLOW)
	
	# Positionner au centre de l'écran un peu au dessus du bas
	# Ou juste au dessus du joueur si on le mettait dans le monde, mais ici c'est CanvasLayer
	# On va le centrer en bas de l'écran
	interaction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_label.position.y -= 100 # Remonter un peu du bas
	interaction_label.visible = false
	
	$CanvasLayer.add_child(interaction_label)

func _process(_delta: float) -> void:
	var s = _get_slot_with_player()
	if s != null and not repair_menu.visible and not s.is_busy:
		interaction_label.visible = true
	else:
		interaction_label.visible = false

func _setup_auto_refresh() -> void:
	refresh_timer = Timer.new()
	refresh_timer.wait_time = REFRESH_INTERVAL
	refresh_timer.autostart = true
	refresh_timer.one_shot = false
	refresh_timer.timeout.connect(_on_auto_refresh)
	add_child(refresh_timer)
	print("⏱ Auto-refresh timer started (%.1fs)" % REFRESH_INTERVAL)

func _on_auto_refresh() -> void:
	print("🔄 Auto-refreshing cars...")
	_refresh_all_cars()

# ---------------------------------------------------------
# AUTH & CHARGEMENT FIRESTORE
# ---------------------------------------------------------

func _on_auth_ok(auth: Dictionary) -> void:
	if auth.is_empty():
		print("ℹ Auth is empty, continuing in anonymous mode.")
		return

	print("✅ Firebase Auth OK:", auth.keys())
	
	auth_token = auth.get("idtoken", "")
	user_email = auth.get("email", "")
	user_uid   = auth.get("localid", "")

	if user_label:
		user_label.text = "Connecté en tant que : " + (user_email if user_email != "" else user_uid)

	print("🔐 User (jeu mécanicien) email:", user_email, "UID:", user_uid)

	# lance le chargement Firestore après ce frame
	call_deferred("_load_all_from_firestore")

func _load_all_from_firestore() -> void:
	print("🚀 [DEBUG] _load_all_from_firestore")
	await _load_interventions_from_firestore()
	await _refresh_all_cars()

# Charge la collection "interventions"
# On force les clés en minuscules pour éviter les soucis de casse (ex: "Amortisseurs" vs "amortisseurs")
func _load_interventions_from_firestore() -> void:
	var q := FirestoreQuery.new()
	q.from("interventions")

	var results = await Firebase.Firestore.query(q)
	# Si erreur ou null, on loggue mais on ne plante pas tout de suite
	if results == null or typeof(results) != TYPE_ARRAY:
		print("⚠ [DEBUG] Erreur chargement interventions (null ou mauvais type)")
		# On clear quand même pour repartir propre
		REPAIRS.clear()
	else:
		REPAIRS.clear()
		for doc in results:
			# On met la clé en minuscules
			var inter_id: String = doc.doc_name.to_lower()
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

	# Backup si vide
	if REPAIRS.is_empty():
		REPAIRS["amortisseurs"] = {"prix": 300000, "duree": 1800.0, "label": "Amortisseurs"}
		REPAIRS["vidange"] = {"prix": 80000, "duree": 600.0, "label": "Vidange"}
		REPAIRS["système de refroidissement"] = {"prix": 350000, "duree": 3600.0, "label": "Système de refroidissement"}

	print("🔧 Interventions Firestore chargées:", REPAIRS.keys())

# ---------------------------------------------------------
# CHARGEMENT DES VOITURES (cars) AVEC REPAIRS INLINE
# ---------------------------------------------------------

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
		var car_id: String = car_doc.doc_name

		var annee_val = car_doc.get_value("annee")
		var marque_val = car_doc.get_value("marque")
		var modele_val = car_doc.get_value("modele")
		var immat_val  = car_doc.get_value("immatriculation")
		var status_val = car_doc.get_value("status") # Statut global de la voiture "paid", "repaired", etc.
		
		# Supporte aussi les champs anglais si présents (comme dans ton exemple)
		if modele_val == null: modele_val = car_doc.get_value("model")
		if immat_val == null: immat_val = car_doc.get_value("licensePlate")

		var annee  = str(annee_val)  if annee_val  != null else ""
		var marque = str(marque_val) if marque_val != null else ""
		var modele = str(modele_val) if modele_val != null else "Voiture"
		var immat  = str(immat_val)  if immat_val  != null else ""
		var status = str(status_val) if status_val != null else ""

		print("📄 [DEBUG] car_doc id =", car_id, "annee=", annee, "marque=", marque, "modele=", modele, "immat=", immat, "status=", status)

		# Récupère les réparations sous forme de dictionnaires complets
		var parsed_repairs: Dictionary = _parse_car_repairs(car_doc)
		var repairs_left: Array = parsed_repairs["pending"]
		var repairs_done_count: int = parsed_repairs["done_count"]
		
		print("🔧 [DEBUG] repairs_left pour", car_id, "=", repairs_left.size(), " done=", repairs_done_count)

		# Construit le nom d'affichage
		var display_name = modele
		if marque != "": display_name = marque + " " + display_name
		if immat != "": display_name += " " + immat
		if annee != "": display_name += " (" + annee + ")"

		# On stocke TOUJOURS la voiture pour l'avoir dans la liste d'attente si besoin
		# sauf si elle est déjà payée (selon la logique user, si status != "paid")
		# Pour l'instant on garde tout, le filtre se fera à l'affichage
		cars_data[car_id] = {
			"id": car_id,
			"name": display_name,
			"repairs_left": repairs_left,
			"repairs_done_count": repairs_done_count,
			"status": status
		}

	print("🚗 [DEBUG] cars_data keys =", cars_data.keys())

	_update_car_list()
	_update_car_list()
	_update_car_count()

func _on_firestore_error(code, status, message):
	print("🔥 FIRESTORE ERROR: ", code, " - ", status, " - ", message)

# Analyse les réparations
func _parse_car_repairs(car_doc) -> Dictionary:
	var pending = []
	var done_count = 0
	
	var repairs_array = car_doc.get_value("repairs")
	if repairs_array == null or typeof(repairs_array) != TYPE_ARRAY:
		return {"pending": pending, "done_count": done_count}

	for i in range(repairs_array.size()):
		var repair_map = repairs_array[i]
		if typeof(repair_map) == TYPE_DICTIONARY:
			var status_val = repair_map.get("status", "")
			var type_val = repair_map.get("type", "")
			
			var status_str: String = str(status_val).to_lower()
			var type_str: String = str(type_val).to_lower()
			
			if status_str == "done":
				done_count += 1
			elif status_str == "pending" and type_str != "":
				# On stocke aussi le prix et la durée spécifiques à cette voiture si présents
				var specific_price = int(repair_map.get("price", 0))
				# Si duration est présente, on suppose que c'est des MINUTES comme dans la collection interventions
				var specific_duration_min = float(repair_map.get("duration", 0))

				pending.append({
					"type": type_str,      # minuscule pour matcher REPAIRS
					"label_orig": str(type_val), # Garde la casse originale pour l'affichage si besoin
					"index": i,            # Index vital pour la mise à jour Firestore
					"price": specific_price,
					"duration": specific_duration_min * 60.0 # Converti en secondes
				})
				
	return {"pending": pending, "done_count": done_count}


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
	if slot1 and slot1.player_inside and str(slot1.current_car_id) != "":
		return slot1
	if slot2 and slot2.player_inside and str(slot2.current_car_id) != "":
		return slot2
	return null

# ---------------------------------------------------------
# LISTES VOITURES
# ---------------------------------------------------------

func _toggle_car_list() -> void:
	side_panel.visible = !side_panel.visible
	if side_panel.visible:
		_update_car_list()

func _update_car_count():
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
		var status = info.get("status", "")
		var repairs_done = info.get("repairs_done_count", 0)
		
		# 1. LISTE DE REPARATION (si encore du boulot)
		if reps.size() > 0:
			var icon_status = "📥"

			var car_id_str: String = str(car_id)
			var slot1_id_str: String = ""
			if slot1: slot1_id_str = str(slot1.current_car_id)
			var slot2_id_str: String = ""
			if slot2: slot2_id_str = str(slot2.current_car_id)

			if slot1_id_str == car_id_str or slot2_id_str == car_id_str:
				icon_status = "🔧"

			var txt = "%s - %s (%d à faire) %s" % [car_id_str, info.get("name", "?"), reps.size(), icon_status]
			var idx = car_list_repair.add_item(txt)
			car_list_repair.set_item_metadata(idx, car_id)
		
		# 2. LISTE ATTENTE PAIEMENT (si fini mais pas payé)
		# On affiche si repairs_left vaut 0 ET status != "paid"
		# On peut aussi vérifier si la voiture est dans waiting_slot physiquement, 
		# mais si on veut une vue globale, on affiche tout ce qui est en attente.
		elif status.to_lower() != "paid":
			# On peut afficher: "Modele - 3 réparations terminées - En attente paiement"
			var txt = "📱 %s - %s (%d terminées) - Paiement App" % [str(car_id), info.get("name", "?"), repairs_done]
			var idx = car_list_waiting.add_item(txt)
			car_list_waiting.set_item_metadata(idx, car_id)


	btn_voitures.text = "🚗 (%d)" % car_list_repair.item_count
	car_list_changed.emit()

func _on_car_list_activated_repair(index: int) -> void:
	_handle_car_selection(car_list_repair, index)

func _on_car_list_activated_waiting(index: int) -> void:
	# PAS DE PAIEMENT INGAME
	# Juste un feedback visuel ou console
	var car_id = car_list_waiting.get_item_metadata(index)
	print("Paiement désactivé pour", car_id, ". Utilisez l'application mobile.")
	
	# Optionnel: Afficher une popup "Veuillez payer sur l'application mobile"


func _handle_car_selection(list: ItemList, index: int) -> void:
	var text = list.get_item_text(index)
	var car_id = list.get_item_metadata(index) # car_id est String via metadata

	# VÉRIFICATION : La voiture est-elle déjà dans un slot ?
	if (slot1 and slot1.current_car_id == car_id) or (slot2 and slot2.current_car_id == car_id):
		print("❌ Cette voiture est déjà dans un garage !")
		# Optionnel : Faire clignoter le slot ou feedback visuel
		return

	var free_slot = _get_free_slot()
	if not free_slot:
		print("❌ Slots pleins !")
		return

	side_panel.visible = false
	waiting_slot.remove_car(car_id)
	free_slot.place_car(car_id)  # car_id est String

func _get_free_slot():
	if slot1 and str(slot1.current_car_id) == "" and not slot1.is_busy:
		return slot1
	if slot2 and str(slot2.current_car_id) == "" and not slot2.is_busy:
		return slot2
	return null

# ---------------------------------------------------------
# MENU DE RÉPARATION (Corrigé)
# ---------------------------------------------------------

func _open_repair_menu_for_slot(slot) -> void:
	current_slot = slot
	var car_id = slot.current_car_id
	if car_id == "": return

	# Si le slot est déjà occupé par une réparation en cours, on n'ouvre pas le menu
	if slot.is_busy:
		print("⚠ Une réparation est déjà en cours sur ce véhicule.")
		return

	var car_info = cars_data.get(car_id)
	if car_info == null: return

	repair_list.clear()

	var repairs_left: Array = car_info.get("repairs_left", [])
	if repairs_left.is_empty():
		repair_list.add_item("✅ Toutes terminées")
		repair_menu.visible = true
		return

	# repairs_left est maintenant une Array de Dictionnaires
	for rep_data in repairs_left:
		var type_key = rep_data["type"] # minuscule
		
		# 1. Chercher les infos globales (interventions collection)
		# Fallback par défaut
		var global_info = REPAIRS.get(type_key, {
			"prix": 0, 
			"duree": 5.0, 
			"label": rep_data.get("label_orig", type_key)
		})
		
		# 2. Surcharger avec les infos spécifiques de la voiture si > 0
		var final_price = global_info.prix
		if rep_data["price"] > 0:
			final_price = rep_data["price"]
			
		var final_duration = global_info.duree
		# La durée dans rep_data est DÉJÀ en secondes (convertie dans _get_pending...)
		if rep_data["duration"] > 0:
			final_duration = rep_data["duration"]
		
		var txt = "%s - %d Ar" % [global_info.label, final_price]
		var idx = repair_list.add_item(txt)
		
		# On stocke TOUT le dictionnaire rep_data dans les métadonnées pour le récupérer au clic
		repair_list.set_item_metadata(idx, rep_data)

	repair_menu.visible = true


func _on_repair_list_item_activated(index: int) -> void:
	if current_slot == null: return
	var text = repair_list.get_item_text(index)
	if text.begins_with("✅"): return

	# On récupère les métadonnées stockées (le dictionnaire complet)
	var rep_data = repair_list.get_item_metadata(index)
	if typeof(rep_data) != TYPE_DICTIONARY: return

	_start_repair_on_slot(current_slot, rep_data)
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

func _start_repair_on_slot(slot, rep_data: Dictionary) -> void:
	if slot.is_busy: return
	var car_id: String = slot.current_car_id
	if car_id == "": return

	var repair_type = rep_data["type"]
	# var original_index = rep_data["index"] # On a besoin de l'index pour Firestore
	
	# On recalcule la durée comme dans _open_repair_menu ou on la repasse
	# On va faire simple : on regarde dans REPAIRS pour la durée d'animation
	var global_info = REPAIRS.get(repair_type, {"duree": 5.0})
	var duration = global_info.duree
	
	# Si on a une durée spécifique valide (déjà convertie en secondes), on l'utilise
	if rep_data["duration"] > 0:
		duration = rep_data["duration"]

	slot.is_busy = true
	slot.repair_type = repair_type

	var bar: ProgressBar = progress1 if slot == slot1 else progress2
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.visible = true

	print("⏱ Démarrage réparation ", repair_type, " duration ", duration)

	var tween := create_tween()
	tween.tween_property(bar, "value", 100.0, duration)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	add_child(timer)
	timer.start()

	timer.timeout.connect(func():
		_on_repair_finished(slot, car_id, rep_data, bar, timer)
	)

func _on_repair_finished(slot, car_id: String, rep_data: Dictionary, bar: ProgressBar, timer: Timer) -> void:
	var car_info: Dictionary = cars_data.get(car_id, {})
	var repairs_left: Array = car_info.get("repairs_left", [])

	# On retire cet élément précis de la liste locale
	repairs_left.erase(rep_data)
	car_info["repairs_left"] = repairs_left
	
	# On augmente le compteur de réparations terminées (pour affichage)
	var done = car_info.get("repairs_done_count", 0)
	car_info["repairs_done_count"] = done + 1
	
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

	# Mise à jour Firestore avec le BON index
	await _update_repair_status_in_firestore(car_id, rep_data["index"])


# Fonction de mise à jour Firestore utilisant l'index
func _update_repair_status_in_firestore(car_id: String, rep_index: int) -> void:
	print("🔄 [DEBUG] Update Firestore START - car_id:", car_id, " repair index:", rep_index)
	var collection = Firebase.Firestore.collection("cars")
	print("🔄 [DEBUG] Collection retrieved")
	
	var car_doc = await collection.get_doc(car_id)
	print("🔄 [DEBUG] Document retrieved:", car_doc != null)
	
	if car_doc:
		var repairs = car_doc.get_value("repairs")
		print("🔄 [DEBUG] Repairs array:", repairs != null, "size:", repairs.size() if repairs != null else 0)
		
		if repairs != null and rep_index < repairs.size():
			print("🔄 [DEBUG] Index valid, updating repair at index:", rep_index)
			# On met à jour l'état
			var rep = repairs[rep_index]
			print("🔄 [DEBUG] Current repair status:", rep.get("status") if typeof(rep) == TYPE_DICTIONARY else "not dict")
			
			if typeof(rep) == TYPE_DICTIONARY:
				rep["status"] = "done"
				rep["progress"] = 100
				repairs[rep_index] = rep
				print("🔄 [DEBUG] Repair updated to 'done', sending to Firestore...")
				
				# Mise à jour du champ dans l'objet Document
				car_doc.add_or_update_field("repairs", repairs)
				
				# Envoi de la modification à Firestore
				var result = await collection.update(car_doc)
				print("✅ [DEBUG] Firestore update result:", result)
				print("✅ Firestore mis à jour !")
		else:
			print("⚠ [DEBUG] Invalid index or repairs array is null")
	else:
		print("⚠ [DEBUG] car_doc is null, document not found")
