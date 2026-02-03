extends Panel

var active_car = null

func _ready():
	hide() # Caché au départ
	Events.player_near_car.connect(_on_player_near_car)
	Events.player_left_car.connect(_on_player_left_car)
	
	# Connecter les 8 boutons de votre VBoxContainer
	for button in $VBoxContainer.get_children():
		button.pressed.connect(_on_repair_button_pressed.bind(button.name))

func _on_player_near_car(car):
	active_car = car
	show() # On affiche le menu quand le joueur s'approche

func _on_player_left_car():
	active_car = null
	hide() # On cache le menu quand il s'éloigne

func _on_repair_button_pressed(repair_name):
	if active_car != null and not active_car.is_repairing:
		# On lance la réparation sur la voiture
		# On récupère la durée depuis un dictionnaire ou l'API
		var duration = 5.0 # Exemple : 5 secondes
		active_car.start_repair(duration)
		hide() # Optionnel : cacher le menu pendant que ça répare
