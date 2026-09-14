## Physics layer bits and team constants. Single source of truth for collision setup.
class_name Layers
extends RefCounted

enum Team { PLAYER, ENEMY, NEUTRAL }

const WORLD := 1 << 0  # walls, static geometry
const PLAYER := 1 << 1  # player body
const ENEMY := 1 << 2  # enemy bodies
const PLAYER_HURTBOX := 1 << 3
const ENEMY_HURTBOX := 1 << 4
const PLAYER_HITBOX := 1 << 5
const ENEMY_HITBOX := 1 << 6
const PROJECTILE := 1 << 7
const PICKUP := 1 << 8
const INTERACTABLE := 1 << 9
const TRAP := 1 << 10
const PIT := 1 << 11
const PROP := 1 << 12  # destructible/solid props

const TILE := 16


static func hurtbox_layer_for(team: Team) -> int:
	return PLAYER_HURTBOX if team == Team.PLAYER else ENEMY_HURTBOX


static func hitbox_mask_for(team: Team) -> int:
	# A hitbox hits the *other* team's hurtboxes and props.
	return (ENEMY_HURTBOX if team == Team.PLAYER else PLAYER_HURTBOX) | PROP
