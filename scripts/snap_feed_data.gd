extends RefCounted
class_name SnapFeedData

## Static content pools for scripts/snap_feed.gd -- no AI generation, just
## randomized combinations of canned French-riot-groupchat text, per
## agents/snap-feed-notes.md. Kept in its own file so snap_feed.gd stays
## about feed mechanics, not copywriting.

const USERNAMES: Array[String] = [
	"kevindu93", "titouan_75", "ratatouille92", "jordan.rsa", "sofiane_tlse",
	"lea.bzh44", "yanis_du9", "manon2000", "doudou_94", "nolhan.oss",
	"inesse_paname", "bryan_le_fou", "kenzaa.75", "mathys_banlieue",
	"chloe_xv", "rayan931", "lucas.caillou", "sarah_mdr95", "theo_zbeul",
	"lina.chui", "karimdu13", "enzo_frero", "yasmine.tl", "nathan2k6",
	"dylan_93200", "mehdi.zbeul", "camille_bg", "soufiane77", "jade_paname",
	"hugo_relou", "amine.tqt", "zinedine.ocb", "lisa_du62", "malik95",
]

const AVATAR_EMOJIS: Array[String] = [
	"😎", "🤡", "👽", "🔥", "💀", "🥖", "🐸", "🤠", "👻", "🫠",
	"😤", "🫡", "🤌", "😭", "🗿", "🦖", "🥵", "😈", "🤯", "🫣",
]

const AVATAR_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.45), Color(0.45, 0.75, 1.0), Color(0.55, 1.0, 0.55),
	Color(1.0, 0.85, 0.3), Color(0.85, 0.5, 1.0), Color(1.0, 0.6, 0.2),
	Color(0.4, 0.95, 0.85), Color(1.0, 0.5, 0.75), Color(0.7, 0.9, 0.3),
]

## Reacting to the general vibe of a riot in progress -- not tied to any
## one real event, just plausible chatter.
const CHATTER: Array[String] = [
	"YA LES CONDÉS À GAUCHE MDRRR",
	"CHUI EN TRAIN DE TOUT CASSER REGARDEZ 🔥",
	"LE MEGAPHONE IL EST OP FR",
	"ON LES EXPLOSE LES CRS 😭😭",
	"VENEZ VITE Y'A DE L'ACTION DEVANT LA MAIRIE",
	"LA POLICE ELLE COMPREND RIEN MDR",
	"J'AI RECRUTÉ 10 PERSONNES EN 2MIN CHUI UN BOSS",
	"CA PART EN VRILLE ICI FRRR",
	"REGARDE CE QUI SE PASSE EN DIRECT 📸",
	"LE GRABUGE IL MONTE A FOND LA",
	"ILS ONT PEUR DE NOUS MDRRRR",
	"TOUT LE MONDE DEHORS C'EST LE MOMENT",
	"ON EST COMBIEN LA 300 400 ???",
	"J'ENTENDS LES SIRENES DE PARTOUT",
	"RESTEZ GROUPÉS LES GARS",
	"QUELQU'UN A UN DRAPEAU EN TROP",
]

const NONSENSE: Array[String] = [
	"qui a pris mon sandwich",
	"ON EST OU LA ???",
	"jpp je suis fatigué",
	"qui veut un kebab après ça",
	"y'a quelqu'un qui a vu mon frère",
	"sérieux c'est chaud ici",
	"je crois que j'ai perdu ma clope",
	"c'est qui lui 💀",
	"j'arrive pas à croire que je rate ça pour un contrôle",
	"ma mère va me tuer si je rentre tard",
	"quelqu'un connait un bon plan pour ce soir",
	"franchement journée de fou",
	"j'ai mal aux pieds direct",
	"pourquoi il fait aussi froid",
	"elle est où Léa jsp",
	"mdrrrr regardez ce mec",
	"j'ai raté mon bus à cause de ça",
	"quelqu'un a du chargeur",
	"AAAAH JE GLISSE",
	"c'est le bordel total ici 💀💀",
	"on se capte où après",
	"j'ai faim grave",
	"c'est normal que mon tel chauffe autant",
	"MDR regarde son pantalon",
	"qui a une trottinette à prêter",
]

## Ambient "stat flavor" lines, formatted with live GameState values --
## picked by the periodic ticker's 20% gameplay-event roll even when no
## real event just fired, so the feed still feels alive during quiet
## stretches. See snap_feed.gd._push_gameplay_flavor(). Split by which
## value (if any) they interpolate, since GDScript's %-format has no named
## placeholders to disambiguate "%d" meaning grabuge vs. crowd count.
const GAMEPLAY_FLAVOR_GRABUGE_TEMPLATES: Array[String] = [
	"📈 GRABUGE À %d%% ET CA MONTE",
]

const GAMEPLAY_FLAVOR_CROWD_TEMPLATES: Array[String] = [
	"👥 %d MANIFESTANTS DANS LA RUE MAINTENANT",
]

const GAMEPLAY_FLAVOR_PLAIN_TEMPLATES: Array[String] = [
	"🔥 L'AMBIANCE EST CHAUDE CE SOIR",
	"📢 ON ENTEND LE MEGAPHONE JUSQU'ICI",
	"🚨 ALERTE GENERALE DANS LE QUARTIER",
]

const RECRUIT_TEMPLATES: Array[String] = [
	"👻 +1 MANIFESTANT RECRUTÉ ! (%d au total)",
	"🙌 UN NOUVEAU VENU REJOINT LA FOULE (%d)",
	"🎉 LA FOULE GROSSIT ENCORE (%d)",
]

## Used when several recruits land in the same batch window (see
## snap_feed.gd._flush_recruit_batch) -- first %d is how many joined just
## now, second %d is the new running total.
const RECRUIT_BATCH_TEMPLATES: Array[String] = [
	"👻 +%d MANIFESTANTS RECRUTÉS D'UN COUP ! (%d au total)",
	"🙌 TOUTE UNE BANDE REJOINT LA FOULE (+%d, %d au total)",
	"🎉 LA FOULE EXPLOSE : +%d NOUVEAUX (%d au total)",
]

const DESTRUCTION_TEMPLATES: Array[String] = [
	"🔥 +%d GRABUGE ! Un truc vient de cramer",
	"💥 CASSE EN COURS, CA PART EN FEU (+%d)",
	"🚗 VOITURE RETOURNÉE ! +%d GRABUGE",
	"🪑 MOBILIER URBAIN DÉTRUIT (+%d)",
]

const POLICE_DEFEAT_TEMPLATES: Array[String] = [
	"🚓 UN CRS AU TAPIS ! +%d GRABUGE",
	"👮 FLIC NEUTRALISÉ, UN DE MOINS ! (+%d)",
	"🛡️ LA FOULE VIENT DE METTRE UN CONDÉ KO (+%d GRABUGE)",
]


static func random_username(rng: RandomNumberGenerator) -> String:
	return USERNAMES[rng.randi_range(0, USERNAMES.size() - 1)]


static func random_avatar_emoji(rng: RandomNumberGenerator) -> String:
	return AVATAR_EMOJIS[rng.randi_range(0, AVATAR_EMOJIS.size() - 1)]


static func random_avatar_color(rng: RandomNumberGenerator) -> Color:
	return AVATAR_COLORS[rng.randi_range(0, AVATAR_COLORS.size() - 1)]


static func random_chatter(rng: RandomNumberGenerator) -> String:
	return CHATTER[rng.randi_range(0, CHATTER.size() - 1)]


static func random_nonsense(rng: RandomNumberGenerator) -> String:
	return NONSENSE[rng.randi_range(0, NONSENSE.size() - 1)]


static func random_gameplay_flavor(rng: RandomNumberGenerator, grabuge: float, crowd_count: int) -> String:
	match rng.randi_range(0, 2):
		0:
			var template: String = GAMEPLAY_FLAVOR_GRABUGE_TEMPLATES[rng.randi_range(0, GAMEPLAY_FLAVOR_GRABUGE_TEMPLATES.size() - 1)]
			return template % int(round(grabuge))
		1:
			var template: String = GAMEPLAY_FLAVOR_CROWD_TEMPLATES[rng.randi_range(0, GAMEPLAY_FLAVOR_CROWD_TEMPLATES.size() - 1)]
			return template % crowd_count
		_:
			return GAMEPLAY_FLAVOR_PLAIN_TEMPLATES[rng.randi_range(0, GAMEPLAY_FLAVOR_PLAIN_TEMPLATES.size() - 1)]


static func random_recruit_message(rng: RandomNumberGenerator, crowd_count: int) -> String:
	var template: String = RECRUIT_TEMPLATES[rng.randi_range(0, RECRUIT_TEMPLATES.size() - 1)]
	return template % crowd_count


static func random_recruit_batch_message(rng: RandomNumberGenerator, gained: int, crowd_count: int) -> String:
	var template: String = RECRUIT_BATCH_TEMPLATES[rng.randi_range(0, RECRUIT_BATCH_TEMPLATES.size() - 1)]
	return template % [gained, crowd_count]


static func random_destruction_message(rng: RandomNumberGenerator, grabuge_gain: int) -> String:
	var template: String = DESTRUCTION_TEMPLATES[rng.randi_range(0, DESTRUCTION_TEMPLATES.size() - 1)]
	return template % grabuge_gain


static func random_police_defeat_message(rng: RandomNumberGenerator, grabuge_gain: int) -> String:
	var template: String = POLICE_DEFEAT_TEMPLATES[rng.randi_range(0, POLICE_DEFEAT_TEMPLATES.size() - 1)]
	return template % grabuge_gain
