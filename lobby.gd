extends Control

@onready var Game = preload("res://game.tscn")
const URL = "https://matchmaking-4tjd.onrender.com"#dont raid xD free and easy to use
@export var game_name:String = "Lobby_test"
@export var version: String = "1.0"


@export var PID:Label
@export var feedback:Label
@export var start:Button
@export var Ready:Button
@export var Host:Button
@export var Update: Timer #server delete lobby every 30s if don't say what u online 
@export var Join:Button
@export var Refresh:Button
@export var server_wakeup:Timer # cold start server need time ~1m to wake up 
@export var Exit:Button
@export var name_edit:LineEdit # Nickname player and lobby
@export var pas_edit:LineEdit # password
@export var player_tab:VBoxContainer # list of players 
@export var player_tab_dummy:Label #example of a player
@export var lobby_tab:VBoxContainer # list of lobby
@export var lobby_tab_dummy:Label #example of a lobby

@onready var http := HTTPRequest.new()

var peer = NodeTunnelPeer.new()
var host_name: String
var Player_name: String
var players = {}
var lobby_selected = ""

func _ready() -> void:
	add_child(http)
	multiplayer.multiplayer_peer = peer
	peer.connect_to_relay("relay.nodetunnel.io", 9998)
	print("Connecting to NodeTunnel...")
	
	await peer.relay_connected
	PID.text = "ID: "+peer.online_id


func _on_host_pressed() -> void:
	if !peer.online_id: 
		feedback.text = "Please wait connection to server"
		return
	peer.host()
	
	await peer.hosting
	Update.start()
	pas_edit.editable = false
	Refresh.visible = false
	player_tab.visible = true
	lobby_tab.visible  = false 
	Host.visible = false 
	Join.visible = false
	start.visible = true
	name_edit.visible = false
	Exit.visible=true
	feedback.text = "Lobby created"
	# create a nickname
	if name_edit.text=="": 
		Player_name = peer.online_id
		host_name = Player_name
		add_player(peer.online_id)
	else: 
		Player_name = name_edit.text
		host_name = Player_name
		add_player(name_edit.text)
	create_lobby(peer.online_id, host_name, pas_edit.text)
	players.get_or_add(Player_name,Player_name)



func _on_join_pressed() -> void:
	if lobby_selected == "": 
		feedback.text = "Lobby not selected"
		return 
	else:
		var body = JSON.stringify({
		"name": lobby_selected,
		"password": pas_edit.text
		})
		var headers = ["Content-Type: application/json"]
		http.request(URL+"/check-password",
		headers, HTTPClient.METHOD_POST, body)
		http.request_completed.connect(_on_check_password_response) 

func _on_check_password_response(_result, _code, _headers, body):
	var response = JSON.parse_string(body.get_string_from_utf8())
	if response == null:
		feedback.text = "Error JSON"
		return
	if response.has("error"):
		feedback.text = "Error:" + response["error"]
		return
	if response["valid"]:
		feedback.text = "Access granted!"
		
		var host_id = response["host_id"]
		peer.join(host_id)
		
		await peer.joined
		
		feedback.text = "Join successful"
		Refresh.visible = false
		player_tab.visible = true
		lobby_tab.visible = false
		Ready.visible = true
		name_edit.visible = false
		Host.visible =false 
		Join.visible = false
		Exit.visible=true
		# create a nickname
		if name_edit.text=="": 
			Player_name = peer.online_id
			player_join.rpc(peer.online_id)
		else: 
			Player_name = name_edit.text
			player_join.rpc(name_edit.text)
		players.get_or_add(Player_name,Player_name)
	
	else:
		feedback.text = "Incorrect password."

func add_player(pid):
	for player in player_tab.get_children():
		if player is Label and player.visible and player.text == pid:
			return
	var label = player_tab_dummy.duplicate()
	label.visible = true
	label.text = pid
	if pid==host_name: label.get_child(0).text = "Host"
	player_tab.add_child(label)

func _on_start_pressed() -> void:
	http.cancel_request()
	var body = JSON.stringify({"host_id": peer.online_id})
	var headers = ["Content-Type: application/json"]
	http.request(URL+"/delete",
	headers, HTTPClient.METHOD_POST, body)
	start_game.rpc()

@rpc("authority","call_local","reliable")
func start_game():
	G.multiplayer_peer = multiplayer.multiplayer_peer
	get_tree().change_scene_to_file.call_deferred(Game.resource_path)

@rpc ("any_peer","call_remote","reliable")
func player_join(P_name):
	feedback.text = str(P_name) + " Join the server"
	resend_name.rpc(Player_name)
	add_player(P_name)
	if multiplayer.is_server(): set_host_name.rpc(Player_name)



@rpc ("any_peer","call_remote","reliable")
func resend_name(P_Name):
	for player in players:
		if players.find_key(P_Name):
			return
	players.get_or_add(P_Name,P_Name)
	players.get_or_add(Player_name,Player_name)
	add_player(P_Name)
	add_player(Player_name)



@rpc ("authority","call_remote","reliable")
func set_host_name(P_Name):
	host_name = P_Name
	for player in player_tab.get_children():
		if player is Label:
			if player.text == P_Name:
				player.get_child(0).text = "Host"

var player_ready = false
func _on_ready_pressed() -> void:
	player_ready = !player_ready
	ready_change.rpc(player_ready,Player_name)


@rpc ("any_peer","call_local")
func ready_change(r,called):
	for player in player_tab.get_children():
		if player is Label:
			if player.text == called:
				player.get_child(0).text = "Yes" if r else "No"

func _on_exit_pressed() -> void:
	leave.rpc(Player_name)#send another what player leave
	if multiplayer.is_server():
		feedback.text = "Lobby " + host_name + " close"
		http.cancel_request()
		var body = JSON.stringify({"host_id": peer.online_id})
		var headers = ["Content-Type: application/json"]
		http.request(URL+"/delete",
		headers, HTTPClient.METHOD_POST, body)
	else: feedback.text = "Leave from " + host_name + " lobby"
	for player in player_tab.get_children(): # clear player_tab
		if player is Label and player.visible and player.text != "Players":
			player.queue_free()
	lobby_main()

@rpc ("any_peer","call_remote")
func leave(Nickname):
	if host_name == Nickname: #Host leave, lobby close
		for player in player_tab.get_children():
			if player is Label and player.visible and player.text != "Players":
				feedback.text = Nickname + " Close the lobby"
				player.queue_free()
		lobby_main()
	else: #Client leave, clear from player_tab
		for player in player_tab.get_children():
			if player.visible and player.text == Nickname:
				feedback.text = Nickname + " Leave from lobby"
				player.queue_free()


func lobby_main():
	start.visible = false
	Exit.visible=false
	Ready.visible=false
	Host.visible =true 
	Join.visible = true
	name_edit.visible = true
	player_tab.visible = false
	lobby_tab.visible = true
	Refresh.visible = true
	Update.stop()
	players.clear()
	host_name = ""
	pas_edit.editable = true
	peer.leave_room()
	



func create_lobby(id, LobbyName, password):
	var url = URL+"/create"
	var body = JSON.stringify({
		"host_id": id,
		"name": ("Lobby "+LobbyName),
		"password": password,
		"game_name": game_name,
		"version": version
		})

	var headers = ["Content-Type: application/json"]
	
	http.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_refresh_pressed() -> void:
	server_wakeup.start()
	list_rooms()

func list_rooms():
	http.cancel_request()
	http.request(URL+"/rooms")
	http.request_completed.connect(_on_list_rooms_response)

var lobbies = {}
func _on_list_rooms_response(_result, code, _headers, body):
	if code != 200: 
		print("Error:", code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	print(data)
	server_wakeup.stop()
	

	for oldlobby in lobby_tab.get_children(): 
		if oldlobby is Label and oldlobby.visible and oldlobby.get_child(0).text != "ID": 
			var copyresult = false 
			for lobby in lobbies: 
				if lobby["name"] == oldlobby.text: 
					copyresult = true 
					if copyresult: 
						oldlobby.queue_free()

	if data.has(game_name) and data[game_name].has(version):
		lobbies = data[game_name][version]
		for lobby in lobbies:
			add_lobby(lobby["name"])

func add_lobby(LobbyName):
	for lobby in lobby_tab.get_children():
		if lobby is Label and lobby.get_child(0).text == LobbyName:
			return 
	var label = lobby_tab_dummy.duplicate()
	label.text = LobbyName
	label.get_child(0).text = "..."
	label.visible = true
	lobby_tab.add_child(label)


func _on_host_timeout() -> void:
	var body = JSON.stringify({"id": peer.online_id})
	var headers = ["Content-Type: application/json"]
	http.request(URL+"/update", headers, HTTPClient.METHOD_POST, body)
	print("update")
	Update.start()


func _on_server_wakeup_timeout() -> void:
	feedback.text = "Server waking up, please wait"


func _on_secret_pressed() -> void:
	pas_edit.secret = !pas_edit.secret
