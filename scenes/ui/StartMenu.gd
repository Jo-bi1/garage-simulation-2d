extends Control

func _on_BoutonJouer_pressed():
	get_tree().change_scene_to_file("res://scenes/Main/World.tscn")

func _on_BoutonQuitter_pressed():
	get_tree().quit()

func _on_BoutonOption_pressed():
	print("Options clicked")
