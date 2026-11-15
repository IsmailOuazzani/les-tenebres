class_name PlayerClass

enum Kit { SOLO, SCOUT, MENEUR, MEDIC }
enum Ability { REVEAL, SPEED_BOOST, HEAL, BARRIER, CROISSANT_SHOT }

const DEFAULT_KIT := Kit.MENEUR
const LAN_KITS := [Kit.SCOUT, Kit.MENEUR, Kit.MEDIC]


static func display_name(kit: int) -> String:
	match kit:
		Kit.SCOUT: return "Scout"
		Kit.MENEUR: return "Meneur"
		Kit.MEDIC: return "Medic"
	return "Solo"


static func description(kit: int) -> String:
	match kit:
		Kit.SCOUT: return "Recruit, reveal police, and double jump. Heavy-knockback baguette."
		Kit.MENEUR: return "Send the mob and boost its speed. Swing or fire a croissant."
		Kit.MEDIC: return "Heal teammates and summon a barrier. Shove cops with a protest sign."
	return ""


static func abilities(kit: int) -> Array[int]:
	match kit:
		Kit.SCOUT: return [Ability.REVEAL]
		Kit.MENEUR: return [Ability.SPEED_BOOST, Ability.CROISSANT_SHOT]
		Kit.MEDIC: return [Ability.HEAL, Ability.BARRIER]
	return []


static func ability_label(ability: int) -> String:
	match ability:
		Ability.REVEAL: return "Reveal"
		Ability.SPEED_BOOST: return "Boost"
		Ability.HEAL: return "Heal"
		Ability.BARRIER: return "Barrier"
		Ability.CROISSANT_SHOT: return "Fire"
	return ""


static func ability_slot(ability: int) -> int:
	return 1 if ability == Ability.CROISSANT_SHOT else 0


static func ability_is_left_click(ability: int) -> bool:
	return ability == Ability.REVEAL or ability == Ability.HEAL
