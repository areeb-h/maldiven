extends RefCounted
## Builds the dedicated server's public status for the control panel and keeps
## its event feed.
##
## Everything here comes from Net.roster and StationRules.public_snapshot():
## the same information every phone already has. Roles, the infiltrator's name
## and the timeline only appear once the round has ended (phase RESULT). The
## panel can sit on a screen the players see, and the host may be playing too.

const FEED_LIMIT := 60
const PHASES := ["briefing", "stabilise", "extraction", "result"]

var feed: Array = []  # [{t: unix seconds, text, kind}], oldest first
var _seq := 0
var _last := {}  # previous public view, for turning changes into feed lines


## kind: info, join, leave, round, power, shuttle, pod, alert, down, spaced, good, result
func log_line(text: String, kind := "info") -> void:
	_seq += 1
	feed.append({"id": _seq, "t": Time.get_unix_time_from_system(), "text": text, "kind": kind})
	if feed.size() > FEED_LIMIT:
		feed = feed.slice(feed.size() - FEED_LIMIT)
	print("[station] ", text)


## Called whenever the roster changes: join and leave lines.
func roster_changed(roster: Dictionary, kicked: Dictionary) -> void:
	var before: Dictionary = _last.get("roster", {})
	for id in roster:
		if not before.has(id):
			log_line("%s joined" % roster[id].name, "join")
	for id in before:
		if not roster.has(id):
			if kicked.has(id):
				log_line("%s was removed by the host" % before[id], "leave")
			else:
				log_line("%s left" % before[id], "leave")
	var names := {}
	for id in roster:
		names[id] = str(roster[id].name)
	_last["roster"] = names


func round_started(crew: int) -> void:
	_last.erase("round")
	log_line("Round started with %d crew aboard" % crew, "round")


## Turns changes in the public round state into feed lines. Mirrors the alerts
## phones show (including "Someone is down" during a blackout).
func observe_round(snap: Dictionary) -> void:
	var now := _round_view(snap)
	var was: Dictionary = _last.get("round", {})
	_last["round"] = now
	if was.is_empty():
		return
	if now.phase != was.phase:
		match now.phase:
			StationRules.Phase.STABILISE:
				log_line("Briefing over: restore power, %d cells to the Reactor" % now.cells_total, "power")
			StationRules.Phase.EXTRACTION:
				log_line("Power restored: vault and armory open", "power")
			StationRules.Phase.RESULT:
				log_line(_result_line(snap), "result")
				if str(snap.get("infiltrator", "nobody")) != "nobody":
					log_line("The infiltrator was %s" % snap.infiltrator, "result")
	if now.cells > was.cells and now.phase <= StationRules.Phase.EXTRACTION:
		log_line("Power cell %d/%d online" % [now.cells, now.cells_total], "power")
	elif now.cells < was.cells and now.phase != StationRules.Phase.RESULT:
		log_line("A power cell was pulled (%d/%d)" % [now.cells, now.cells_total], "alert")
	if now.phase != StationRules.Phase.RESULT:
		if now.shuttle and not was.shuttle:
			log_line("Shuttle launch sequence started", "shuttle")
		elif was.shuttle and not now.shuttle:
			log_line("Shuttle launch aborted", "alert")
		if now.pod and not was.pod:
			log_line("Warning: cargo pod armed in Cargo", "pod")
		elif was.pod and not now.pod:
			log_line("Cargo pod disarmed", "good")
		if now.blackout and not was.blackout:
			log_line("Blackout: main lights failed", "alert")
		elif was.blackout and not now.blackout:
			log_line("Main lights back on", "good")
		if now.airlock == "warning" and was.airlock != "warning":
			log_line("Airlock cycling", "alert")
	var states: Dictionary = now.states
	var old_states: Dictionary = was.states
	for id in states:
		var state: String = states[id]
		var before: String = old_states.get(id, state)
		if state == before:
			continue
		var who: String = now.names.get(id, "Someone")
		match state:
			StationRules.DOWNED:
				log_line("Someone is down" if now.blackout else "%s is down" % who, "down")
			StationRules.DEAD:
				log_line("%s was spaced" % who, "spaced")
			StationRules.OK:
				if before == StationRules.DOWNED:
					log_line("%s is back on their feet" % who, "good")


func _round_view(snap: Dictionary) -> Dictionary:
	var cells := 0
	var total := 0
	for socket_id in StationLayout.SOCKETS:
		if StationLayout.SOCKETS[socket_id].kind == "reactor":
			total += 1
	for item_id in snap.items:
		var socket: String = snap.items[item_id].socket
		if socket != "" and StationLayout.SOCKETS.has(socket) and StationLayout.SOCKETS[socket].kind == "reactor":
			cells += 1
	var states := {}
	var names := {}
	for id in snap.players:
		states[int(id)] = str(snap.players[id].state)
		names[int(id)] = str(snap.players[id].name)
	return {"phase": int(snap.phase), "cells": cells, "cells_total": total,
		"shuttle": float(snap.shuttle_left) >= 0.0, "pod": float(snap.pod_left) >= 0.0,
		"blackout": float(snap.blackout_left) > 0.0, "airlock": str(snap.get("airlock_state", "idle")),
		"states": states, "names": names}


func _result_line(snap: Dictionary) -> String:
	var why := str(snap.get("reason", "")).trim_suffix(".")
	match str(snap.get("winner", "")):
		StationRules.CREW:
			return "Crew wins: %s" % why
		StationRules.INFILTRATOR:
			return "Infiltrator wins: %s" % why
	return "Round over: %s" % why


## The whole status document (see docs/hosting.md, "Control protocol").
## `rules` is the authoritative host rules object or null in the lobby; only its
## public snapshot is read.
func build(rules: StationRules, info: Dictionary) -> Dictionary:
	var snap: Dictionary = rules.public_snapshot() if rules != null else {}
	var state := "lobby"
	if not snap.is_empty():
		state = PHASES[clampi(int(snap.phase), 0, PHASES.size() - 1)]
	var ids: Array = Net.roster.keys()
	ids.sort()
	var players := []
	for id in ids:
		var entry: Dictionary = Net.roster[id]
		var row := {"id": id, "name": str(entry.name), "color": "#" + Color(entry.color).to_html(false),
			"ping_ms": int(round(Net.peer_rtt(id) * 1000.0)), "state": "lobby"}
		if not snap.is_empty():
			if snap.players.has(id):
				var p: Dictionary = snap.players[id]
				row.state = str(p.state)  # ok / downed / dead: public, every phone sees it
				row.holding = str(p.holding)
				row.carrying_body = int(p.body) != 0
				if row.state == StationRules.DOWNED:
					row.down_left = snapped(float(p.down_left), 0.1)
			else:
				row.state = "waiting"  # joined after the round ended; plays the next one
		players.append(row)
	var status := {
		"type": "status",
		"version": info.version,
		"protocol": Net.PROTOCOL,
		"room_name": Net.room_name,
		"state": state,
		"players": players,
		"max_players": info.max_players,
		"min_players": info.min_players,
		"port": Net.PORT,
		"discovery_port": Net.DISCOVERY_PORT,
		"addresses": Array(Net.local_addresses()),
		"uptime": snapped(info.uptime, 0.1),
		"feed": feed.slice(maxi(0, feed.size() - 30)),
		"stopping": info.stopping,
	}
	if not snap.is_empty():
		var view := _round_view(snap)
		var round_info := {
			"elapsed": snapped(float(snap.elapsed), 0.1),
			"total": StationRules.ROUND_SECONDS,
			"left": snapped(maxf(0.0, StationRules.ROUND_SECONDS - float(snap.elapsed)), 0.1),
			"briefing_left": snapped(maxf(0.0, StationRules.BRIEFING_SECONDS - float(snap.elapsed)), 0.1),
			"cells": view.cells, "cells_total": view.cells_total,
			"shuttle_left": snapped(float(snap.shuttle_left), 0.1),
			"pod_left": snapped(float(snap.pod_left), 0.1),
			"blackout_left": snapped(float(snap.blackout_left), 0.1),
			"airlock": view.airlock,
		}
		if state == "result":
			# The reveal: only now are the winner, the infiltrator and the timeline public.
			round_info.result = {"winner": str(snap.get("winner", "")), "reason": str(snap.get("reason", "")),
				"infiltrator": str(snap.get("infiltrator", "")), "timeline": snap.get("timeline", [])}
			round_info.lobby_in = info.get("lobby_in", -1.0)
		status.round = round_info
	return status
