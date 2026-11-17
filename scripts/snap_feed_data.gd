extends RefCounted
class_name SnapFeedData

## Each post is [handle, text]. A third post in a prop exchange is saved
## for the next pre-wave countdown.
const PROFILES := {
	"lea.bzh44": {"emoji": "🫣", "color": Color(0.45, 0.75, 1.0)},
	"kevindu93": {"emoji": "🥖", "color": Color(1.0, 0.85, 0.3)},
	"manon2000": {"emoji": "👀", "color": Color(1.0, 0.5, 0.75)},
	"sofiane_tlse": {"emoji": "🫡", "color": Color(0.55, 1.0, 0.55)},
}

const PROP_THREADS := {
	&"shop_window": [
		[
			["lea.bzh44", "la vitrine vient de lâcher"],
			["kevindu93", "ah c'était ça le bruit. j'ai cru que c'était mon tel"],
			["lea.bzh44", "j'ai retrouvé le prix du grille-pain sur ma manche"],
		],
		[
			["manon2000", "la vitrine a pété j'ai sursauté"],
			["kevindu93", "moi aussi et j'avais déjà les yeux dessus"],
		],
	],
	&"garbage_truck": [
		[
			["manon2000", "y a une roue du camion-benne qui se barre"],
			["kevindu93", "elle est en avance sur le reste de la collecte"],
		],
		[
			["lea.bzh44", "le camion-benne vient de perdre sa portière"],
			["sofiane_tlse", "le chauffeur l'avait fermée en plus"],
		],
	],
	&"barricade": [
		[
			["sofiane_tlse", "la barrière a cédé"],
			["manon2000", "et moi qui me demandais où était l'ouverture"],
		],
		[
			["manon2000", "on vient de faire sauter la barrière"],
			["kevindu93", "j'aurais pu passer à côté. je le vois maintenant"],
		],
	],
	&"car": [
		[
			["lea.bzh44", "la voiture vient de perdre son pare-chocs"],
			["kevindu93", "ça compte comme un accrochage sans l'autre voiture ?"],
		],
		[
			["manon2000", "la bagnole se démonte devant moi"],
			["sofiane_tlse", "y avait encore le A à l'arrière"],
		],
	],
	&"traffic_light": [
		[
			["lea.bzh44", "on a cassé le feu"],
			["kevindu93", "bon mon auto-école avait pas prévu ça"],
		],
		[
			["sofiane_tlse", "le feu du carrefour vient de tomber"],
			["manon2000", "j'ai quand même regardé des deux côtés"],
		],
	],
}

const MEGACOP_THREADS := [
	[
		["manon2000", "attendez vous voyez la taille de celui-là"],
		["kevindu93", "oui il a coupé le soleil deux secondes"],
	],
	[
		["sofiane_tlse", "le grand là c'est aussi un flic ?"],
		["lea.bzh44", "oui j'ai dû lever la tête pour vérifier"],
	],
]

const RECRUIT_THREADS := [
	[
		["lea.bzh44", "y en a %d qui viennent de nous rejoindre d'un coup"],
		["sofiane_tlse", "ok je comprends pourquoi je te vois plus"],
	],
	[
		["manon2000", "j'ai cligné des yeux y en a %d de plus"],
		["kevindu93", "ah c'est pour ça que tout le monde me marche dessus"],
	],
]
