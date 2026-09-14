## Enemy double that supports Hostile Takeover's `convert(team, seconds)` contract.
class_name DummyConvertibleEnemy
extends DummyEnemy

var converted_team: int = -1
var converted_seconds: float = 0.0


func convert(new_team: Layers.Team, seconds: float) -> void:
	converted_team = new_team
	converted_seconds = seconds
	team = new_team
