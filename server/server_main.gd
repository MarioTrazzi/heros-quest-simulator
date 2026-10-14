extends Node
## Servidor dedicado (headless):
##   godot --headless --path . -- --server
## PORT (padrão 8765) e HQ_DATA_DIR (padrão user://server) vêm do ambiente.


func _ready() -> void:
	var port := int(OS.get_environment("PORT")) if OS.has_environment("PORT") else Protocol.DEFAULT_PORT
	var data_dir := OS.get_environment("HQ_DATA_DIR") if OS.has_environment("HQ_DATA_DIR") \
		else ProjectSettings.globalize_path("user://server")
	var server := HqServer.new()
	add_child(server)
	if server.start(port, data_dir) != OK:
		push_error("HeroQuest: não consegui abrir a porta %d" % port)
		get_tree().quit(1)
