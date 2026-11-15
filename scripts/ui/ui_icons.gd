class_name UiIcons
extends RefCounted
## Drift Station's bespoke icon set: chunky, friendly sci-fi glyphs that echo the
## premium-toy art (glossy suits with LED visors, canister cells, the caged core).
## Every glyph is hand-written SVG on a 48-unit grid and is rasterised at runtime
## (ThorVG via Image.load_svg_from_string), so nothing depends on import settings
## and it works the same on Android.
##
## STYLES
##   "duo"    (default) two-tone white: a primary layer plus a secondary layer at
##            reduced opacity, with knock-out gaps, inner shapes and glints for
##            depth. Tint it with any colour (draw colour / modulate).
##   "color"  curated full colour for hero spots (result, role reveal, lobby):
##            shared paints with top-left lit gradients and soft glows. Only the
##            alpha of the draw colour applies.
##
## STYLE RULES (keep new glyphs consistent)
##   Grid 48 units, live area 4..44, protrusions (antenna, ticks) to 2..46.
##   Line weight 4.5-6 units (round caps and joins), detail lines 2.2-3.4.
##   Corner radius: 6-7 on large bodies, 2.5-3.5 on parts, 1.5 on tiny parts.
##   Gaps (knock-outs) 2-3 units so they survive at 24 px; finer details carry
##   the `d` flag and disappear in the small (<= 36 px) optical variant.
##   Light comes from the top left: glints sit top left, extrusions and dark
##   facets fall to the bottom right (+2.4, +2.4).
##   Secondary layer opacity 0.42 (0.55 when small). Every glyph gets a soft dark
##   halo (black, so it survives tinting) for contrast on bright scenes.
##
## TOKENS (inside an SVG element: `<rect ... {p shell r2 d}/>`)
##   role  p / s / g / u = fill as primary / secondary / glint / under-layer
##         (under-layers are drawn beneath everything and never cut);
##         x = colour-mode only; k = knock out everything drawn before it.
##         Upper-case (P S G U X K) = the same, but as a stroke.
##   paint any PAINTS key (used by the colour style).
##   wN    stroke width; rN round the corners of a fill with an N-unit stroke.
##   d     detail: dropped in the small variant;  m: small variant only.
##   `<g transform='...'>` wrappers (not nested) are flattened onto children.
##
## Draw in a CanvasItem with texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
##   UiIcons.draw(self, "cell", center, 32.0, UiStyle.AMBER)
##   UiIcons.draw(self, "core", center, 96.0, Color.WHITE, 0.0, "color")
##   UiIcons.badge(self, "crown", center, 88.0, UiStyle.AMBER)
## draw() picks the optical variant from the on-screen pixel size, rasterises
## small and medium icons at their exact pixel size and snaps them to the pixel
## grid; rotated or very large icons use mipmapped textures.

const RASTER := 128  # px of texture() / texture_styled() by default
const GRID := 48
const SECONDARY := 0.42
const SECONDARY_SMALL := 0.55
const GLINT := 0.92
const SMALL_PX := 36  # at or below this many screen pixels, use the small variant
const EXACT_MAX := 160  # draw(): rasterise at exact pixel size up to this
const HALO_ALPHA := 0.62
const CACHE_LIMIT := 768
const STYLES := ["duo", "color"]
const SHAPES := ["hex", "square"]

## Shared colour-mode paints. lin: top-left lit gradient (light, dark).
## rad: spherical (centre, mid, edge). flat: one colour (+ opacity o).
## glow: soft radial falloff of one colour.
const PAINTS := {
	"shell": {"lin": ["#ffffff", "#c2ccd9"]},
	"steel": {"lin": ["#eef3f9", "#8592a7"]},
	"graphite": {"lin": ["#56637b", "#1a2131"]},
	"visor": {"lin": ["#2b3c5e", "#060a13"]},
	"led": {"flat": "#f2fdff"},
	"crew": {"lin": ["#93c1ff", "#2b5bd0"]},
	"crew_dk": {"lin": ["#2f56b8", "#152f70"]},
	"red": {"lin": ["#ff8f99", "#cf1b36"]},
	"red_dk": {"lin": ["#b01d34", "#5a0a17"]},
	"slit": {"lin": ["#fff0f1", "#ff4458"]},
	"amber": {"lin": ["#fff3a3", "#ffaf1c"]},
	"amber_dk": {"lin": ["#d98912", "#7f4805"]},
	"orange": {"lin": ["#ffb56e", "#e2500d"]},
	"cyan": {"lin": ["#c8f9ff", "#17abe0"]},
	"cyan_dk": {"lin": ["#1688bb", "#0a3f60"]},
	"orb": {"rad": ["#ffffff", "#8cf3ff", "#0a9bd4"]},
	"teal": {"lin": ["#b6fff6", "#10b3a0"]},
	"teal_dk": {"lin": ["#0f8d7f", "#064c44"]},
	"gold": {"lin": ["#fff5ab", "#ee9d1b"]},
	"gold_dk": {"lin": ["#c47a0d", "#6f3e04"]},
	"violet": {"lin": ["#f3eeff", "#9c86ff"]},
	"violet_dk": {"lin": ["#7a62e0", "#3b2a8c"]},
	"hazard": {"flat": "#ffd23f"},
	"gloss": {"flat": "#ffffff", "o": 0.62},
	"shade": {"flat": "#03060c", "o": 0.3},
	"glow_cyan": {"glow": "#5fe6ff"},
	"glow_amber": {"glow": "#ffc23d"},
	"glow_red": {"glow": "#ff3b50"},
	"glow_teal": {"glow": "#3df5dd"},
	"glow_gold": {"glow": "#ffd34d"},
	"glow_violet": {"glow": "#b49cff"},
}

## Friendly names that point at a glyph (not part of names()).
const ALIASES := {
	"crew": "face", "infiltrator": "mask", "power": "bolt", "use": "hand", "grab": "hand",
	"shoot": "crosshair", "sabotage": "blackout", "timer": "clock", "host": "crown",
	"lobby": "users", "lan": "wifi", "win": "trophy", "exit": "leave", "settings": "gear",
}

# --- Shared geometry -------------------------------------------------------------
## The crew helmet (front): dome shell, wide visor bezel, glass.
const HELMET := "M24 5C34.5 5 42 12.5 42 23V30C42 37.7 36.2 43 29 43H19C11.8 43 6 37.7 6 30V23C6 12.5 13.5 5 24 5Z"
const VISOR_CUT := "M15 14H33C36.9 14 39 16.6 39 20.5V27C39 32.5 35 36.5 29.5 36.5H18.5C13 36.5 9 32.5 9 27V20.5C9 16.6 11.1 14 15 14Z"
const VISOR := "M15.6 16.6H32.4C35 16.6 36.4 18.2 36.4 20.8V27C36.4 31.1 33.5 34 29.4 34H18.6C14.5 34 11.6 31.1 11.6 27V20.8C11.6 18.2 13 16.6 15.6 16.6Z"
## The infiltrator's visor: an angry V brow.
const BROW_CUT := "M9 20.5C9 18.4 11 17 13 17.8L24 22L35 17.8C37 17 39 18.4 39 20.5V27C39 32.5 35 36.5 29.5 36.5H18.5C13 36.5 9 32.5 9 27Z"
const BROW := "M11.6 22.4C11.6 21.2 12.8 20.4 13.9 20.8L24 24.7L34.1 20.8C35.2 20.4 36.4 21.2 36.4 22.4V27C36.4 31.1 33.5 34 29.4 34H18.6C14.5 34 11.6 31.1 11.6 27Z"
## Bust (user / users): small helmet over rounded shoulders.
const BUST_HEAD := "M24 3C31.2 3 36 8.2 36 15V18C36 23.5 31.8 27.5 26.5 27.5H21.5C16.2 27.5 12 23.5 12 18V15C12 8.2 16.8 3 24 3Z"
const BUST_VISOR_CUT := "M19 10H29C31.5 10 33 11.7 33 14.3V17.5C33 20.6 30.6 23 27.5 23H20.5C17.4 23 15 20.6 15 17.5V14.3C15 11.7 16.5 10 19 10Z"
const BUST_VISOR := "M19.4 12H28.6C30.2 12 31 13 31 14.8V17.5C31 19.6 29.6 21 27.5 21H20.5C18.4 21 17 19.6 17 17.5V14.8C17 13 17.8 12 19.4 12Z"
const BUST_BODY := "M6.5 44C6.5 36 13.6 31 24 31C34.4 31 41.5 36 41.5 44V44.5C41.5 45.3 40.8 46 40 46H8C7.2 46 6.5 45.3 6.5 44.5Z"
const BOLT := "M26.5 2.5L8.5 26H21.5L18.5 43L37.5 18.5H24.5Z"
const PLAY := "M15.5 8.3C15.5 6.6 17.4 5.6 18.8 6.6L39.7 21.6C40.9 22.4 40.9 24.2 39.7 25L18.8 40C17.4 41 15.5 40 15.5 38.3Z"
const MENU_BAR := "M11.5 8H40.5C41.6 8 42.3 9.1 41.9 10.1L40 14.4C39.6 15.4 38.7 16 37.6 16H8.5C7.4 16 6.7 14.9 7.1 13.9L9 9.6C9.4 8.6 10.4 8 11.5 8Z"
const HAZARD := "M6 0L-42 48M13 0L-35 48M20 0L-28 48M27 0L-21 48M34 0L-14 48M41 0L-7 48M48 0L0 48M55 0L7 48M62 0L14 48M69 0L21 48M76 0L28 48M83 0L35 48M90 0L42 48"
## Glove (palm view, three fingers and a thumb).
const GLOVE := ("<path d='M19.5 18.5H30C33.6 18.5 36.5 21.4 36.5 25V31.5C36.5 36.2 32.7 40 28 40H21C16.3 40 12.5 36.2 12.5 31.5V25.5C12.5 21.6 15.6 18.5 19.5 18.5Z' {p shell}/>"
	+ "<ellipse cx='25' cy='31' rx='6' ry='4.4' {k d}/><ellipse cx='25' cy='31' rx='6' ry='4.4' {s graphite d}/>"
	+ "<path d='M16 21.5V10.5' {P shell w7}/>"
	+ "<path d='M24 20V7' {K w10.6}/><path d='M24 20V7' {P shell w7}/>"
	+ "<path d='M32 21.5V10.5' {K w10.6}/><path d='M32 21.5V10.5' {P shell w7}/>"
	+ "<path d='M14.5 32L7.5 23.5' {K w10.6}/><path d='M14.5 32L7.5 23.5' {P shell w7}/>"
	+ "<rect x='14.5' y='41' width='20' height='5.5' rx='2.5' {k w3}/><rect x='14.5' y='41' width='20' height='5.5' rx='2.5' {p crew}/>")

## name -> SVG body (elements with tokens). Order = names() order.
const GLYPHS := {
	# --- People and roles --------------------------------------------------------
	## A crew helmet: glossy dome, LED pill eyes on a dark visor, antenna, ear pucks.
	"face": ("<rect x='2.5' y='20' width='6' height='13' rx='3' {s graphite}/><rect x='39.5' y='20' width='6' height='13' rx='3' {s graphite}/>"
		+ "<path d='M32.6 9L36 4.4' {P graphite w2.6 d}/><path d='M32.6 9L35.6 4.9' {P graphite w3.6 m}/><circle cx='36.4' cy='4.1' r='2.5' {p cyan}/>"
		+ "<path d='%s' {p crew}/><path d='M11.6 17C13.4 11.9 17.6 8.8 23 8.4' {X gloss w2.2 d}/>" % HELMET
		+ "<path d='%s' {k}/><path d='%s' {x graphite}/><path d='%s' {s visor}/>" % [VISOR_CUT, VISOR_CUT, VISOR]
		+ "<ellipse cx='24' cy='25.2' rx='11' ry='8' {x glow_cyan}/>"
		+ "<rect x='16.4' y='20.2' width='5.2' height='10' rx='2.6' {p led}/><rect x='26.4' y='20.2' width='5.2' height='10' rx='2.6' {p led}/>"
		+ "<path d='M14.1 26C14.1 22.6 14.6 20.6 16 19.4' {G gloss w1.6 d}/>"),
	## The infiltrator: the same helmet with swept fins and an angry red slit visor.
	"mask": ("<path d='M10 27.5L3.4 15C2.9 14 4 12.9 5 13.6L14 20.5Z' {p red_dk}/><path d='M38 27.5L44.6 15C45.1 14 44 12.9 43 13.6L34 20.5Z' {p red_dk}/>"
		+ "<path d='%s' {p red}/><path d='M11.6 17C13.4 11.9 17.6 8.8 23 8.4' {X gloss w2.2 d}/>" % HELMET
		+ "<path d='%s' {k}/><path d='%s' {x graphite}/><path d='%s' {s visor}/>" % [BROW_CUT, BROW_CUT, BROW]
		+ "<ellipse cx='24' cy='27' rx='12' ry='6.5' {x glow_red}/>"
		+ "<rect x='13.4' y='25.4' width='9' height='3.8' rx='1.9' transform='rotate(21 17.9 27.3)' {p slit}/><rect x='25.6' y='25.4' width='9' height='3.8' rx='1.9' transform='rotate(-21 30.1 27.3)' {p slit}/>"),
	## Crew insignia: a shield with rank chevrons.
	"shield": ("<path d='M22.6 3.9C23.5 3.6 24.5 3.6 25.4 3.9L39.4 8.5C40.9 9 42 10.4 42 12V22C42 32.2 35.2 39.8 25.4 44.4C24.5 44.8 23.5 44.8 22.6 44.4C12.8 39.8 6 32.2 6 22V12C6 10.4 7.1 9 8.6 8.5Z' {p crew}/>"
		+ "<path d='M24 9L37.5 13.4V22C37.5 29.8 32.6 35.8 24 40C15.4 35.8 10.5 29.8 10.5 22V13.4Z' {k}/><path d='M24 9L37.5 13.4V22C37.5 29.8 32.6 35.8 24 40C15.4 35.8 10.5 29.8 10.5 22V13.4Z' {s crew_dk}/>"
		+ "<path d='M15.5 22.5L24 16.5L32.5 22.5' {P led w4.6}/><path d='M15.5 31L24 25L32.5 31' {P led w4.6}/>"
		+ "<path d='M13 17.5V14.6L18.5 12.8' {G gloss w1.6 d}/>"),
	## Downed: a tipped-over helmet with X eyes and a dizzy orbit.
	"downed": ("<g transform='rotate(-14 24 30) translate(5.3 11) scale(.78)'><path d='%s' {p steel}/><path d='%s' {k}/><path d='%s' {x graphite}/><path d='%s' {s visor}/>" % [HELMET, VISOR_CUT, VISOR_CUT, VISOR]
		+ "<path d='M16 21.4L22 27.4M22 21.4L16 27.4M26 21.4L32 27.4M32 21.4L26 27.4' {P amber w3.6}/></g>"
		+ "<path d='M9 4.2Q9.8 8.6 14.2 9.4Q9.8 10.2 9 14.6Q8.2 10.2 3.8 9.4Q8.2 8.6 9 4.2Z' {p amber}/>"
		+ "<path d='M22.5 1.6Q23 4.3 25.7 4.8Q23 5.3 22.5 8Q22 5.3 19.3 4.8Q22 4.3 22.5 1.6Z' {p amber d}/>"
		+ "<path d='M39 3.4Q39.7 7.3 43.6 8Q39.7 8.7 39 12.6Q38.3 8.7 34.4 8Q38.3 7.3 39 3.4Z' {p amber}/>"),
	## Ghost: a helmet dome with hollow ring eyes trailing into a wispy tail.
	"ghost": ("<path d='M6.5 35.5C3.6 37.4 3.4 41 6.6 42.4' {S violet w2.6 d}/><path d='M42 30.5C44.6 32 45 35 43 36.6' {S violet w2.6 d}/>"
		+ "<path d='M24 4C33.4 4 41 11 41 20.5V27C41 32.4 38.6 36.4 35 39.4C32.8 41.2 32.8 43.6 35.8 44.8C30.6 46.4 26 45 24.2 42C22.2 44.2 18.4 45 15 43.6C17.4 42.4 17.8 40.6 16.2 39C11 35.4 7 31.6 7 26V20.5C7 11 14.6 4 24 4Z' {p violet}/>"
		+ "<path d='M24.8 33.5C23.9 36.6 23.6 39.4 24.2 42' {K w2.2 d}/>"
		+ "<path d='M15.5 12.5H32.5C36.1 12.5 38 15 38 18.6V22.5C38 27.2 34.6 30.5 30 30.5H18C13.4 30.5 10 27.2 10 22.5V18.6C10 15 11.9 12.5 15.5 12.5Z' {k}/>"
		+ "<path d='M15.5 12.5H32.5C36.1 12.5 38 15 38 18.6V22.5C38 27.2 34.6 30.5 30 30.5H18C13.4 30.5 10 27.2 10 22.5V18.6C10 15 11.9 12.5 15.5 12.5Z' {x violet_dk}/>"
		+ "<path d='M16 15H32C34.4 15 35.5 16.4 35.5 19V22.5C35.5 25.8 33.2 28 30 28H18C14.8 28 12.5 25.8 12.5 22.5V19C12.5 16.4 13.6 15 16 15Z' {s visor}/>"
		+ "<circle cx='18.8' cy='21.5' r='3.1' {P led w2.5}/><circle cx='29.2' cy='21.5' r='3.1' {P led w2.5}/>"),
	## One player: a crew bust.
	"user": ("<path d='%s' {p crew}/><path d='%s' {k}/><path d='%s' {x graphite}/><path d='%s' {s visor}/>" % [BUST_HEAD, BUST_VISOR_CUT, BUST_VISOR_CUT, BUST_VISOR]
		+ "<rect x='19.6' y='13.6' width='3' height='5.6' rx='1.5' {p led d}/><rect x='25.4' y='13.6' width='3' height='5.6' rx='1.5' {p led d}/>"
		+ "<path d='%s' {p crew}/><rect x='21' y='36' width='6' height='4' rx='1.5' {x cyan d}/>" % BUST_BODY),
	## The lobby: three crew busts, one in front.
	"users": ("<g transform='translate(-1.9 12.4) scale(.6)'><path d='%s' {s crew_dk}/><path d='%s' {s crew_dk}/></g>" % [BUST_HEAD, BUST_BODY]
		+ "<g transform='translate(21.1 12.4) scale(.6)'><path d='%s' {s crew_dk}/><path d='%s' {s crew_dk}/></g>" % [BUST_HEAD, BUST_BODY]
		+ "<g transform='translate(7.2 13.8) scale(.7)'><path d='%s' {k w6}/><path d='%s' {k w6}/></g>" % [BUST_HEAD, BUST_BODY]
		+ "<g transform='translate(7.2 13.8) scale(.7)'><path d='%s' {p crew}/><path d='%s' {k}/><path d='%s' {x graphite}/><path d='%s' {s visor}/>" % [BUST_HEAD, BUST_VISOR_CUT, BUST_VISOR_CUT, BUST_VISOR]
		+ "<rect x='19.6' y='13.6' width='3' height='5.6' rx='1.5' {p led d}/><rect x='25.4' y='13.6' width='3' height='5.6' rx='1.5' {p led d}/><path d='%s' {p crew}/></g>" % BUST_BODY),
	## Host: a chunky crown with gems.
	"crown": ("<path d='M6 17.5L15.5 25.5L24 11.5L32.5 25.5L42 17.5L38.8 34H9.2Z' {p gold r3}/>"
		+ "<circle cx='5.6' cy='15.2' r='3.3' {p gold}/><circle cx='24' cy='8.8' r='3.5' {p gold}/><circle cx='42.4' cy='15.2' r='3.3' {p gold}/>"
		+ "<path d='M24 22.5L27.3 27L24 31.5L20.7 27Z' {k r1.2}/><path d='M24 22.5L27.3 27L24 31.5L20.7 27Z' {s cyan r1.2}/>"
		+ "<rect x='8.5' y='37.5' width='31' height='7' rx='2.5' {p gold}/>"
		+ "<circle cx='16' cy='41' r='1.9' {k d}/><circle cx='24' cy='41' r='1.9' {k d}/><circle cx='32' cy='41' r='1.9' {k d}/>"
		+ "<circle cx='16' cy='41' r='1.9' {x teal d}/><circle cx='24' cy='41' r='1.9' {x red d}/><circle cx='32' cy='41' r='1.9' {x teal d}/>"),
	# --- Verbs ---------------------------------------------------------------------
	## Use / grab: an EVA glove.
	"hand": GLOVE,
	## Shove: the glove pushing right into an impact burst.
	"shove": ("<g transform='translate(19 24) scale(.8) rotate(90) translate(-24 -24)'>%s</g>" % GLOVE
		+ "<path d='M39.8 14.5L44 10.8M41.2 24H46M39.8 33.5L44 37.2' {P amber w3.6}/>"),
	## Throw: a power cell flying along a dotted arc.
	"throw": ("<circle cx='6' cy='43' r='1.8' {s cyan d}/><circle cx='8.6' cy='36.4' r='2.2' {s cyan d}/><circle cx='12.6' cy='30.4' r='2.6' {p cyan d}/>"
		+ "<circle cx='7.5' cy='40.5' r='2.8' {s cyan m}/><circle cx='13' cy='31.5' r='3.2' {p cyan m}/>"
		+ "<g transform='translate(30.5 18) rotate(32) scale(1.12)'><rect x='-7' y='-9' width='14' height='20' rx='3.5' {k w5}/><rect x='-4' y='-13' width='8' height='4.4' rx='1.5' {k w5}/>"
		+ "<rect x='-4' y='-13' width='8' height='4.4' rx='1.5' {p orange}/><rect x='-7' y='-9' width='14' height='20' rx='3.5' {p shell}/>"
		+ "<rect x='-3' y='-4.5' width='6' height='11.5' rx='2' {k}/><rect x='-3' y='-4.5' width='6' height='11.5' rx='2' {s graphite}/><rect x='-1.8' y='0.5' width='3.6' height='5' rx='1' {p amber d}/></g>"),
	## Shoot: a chunky reticle with a lens.
	"crosshair": ("<circle cx='24' cy='24' r='12.5' {s graphite}/><circle cx='24' cy='24' r='16' {P orange w4}/>"
		+ "<path d='M24 2.5V13M24 35V45.5M2.5 24H13M35 24H45.5' {P orange w4.6}/><circle cx='24' cy='24' r='3.3' {p red}/>"),
	## Jump: rising chevrons over a launch pad.
	"jump": ("<path d='M13 31.5L24 21L35 31.5' {S cyan w5.4}/><path d='M13 21L24 10.5L35 21' {P cyan w5.4}/>"
		+ "<rect x='9' y='38.5' width='30' height='5.5' rx='2.75' {p steel}/><rect x='14' y='38.5' width='20' height='2' rx='1' {x cyan d}/>"),
	## Drop: an arrow down onto the floor and its landing shadow.
	"drop": ("<ellipse cx='24' cy='36.5' rx='10' ry='2.8' {s shade}/><path d='M24 4.5V25M14.5 17L24 26.5L33.5 17' {P cyan w5.4}/>"
		+ "<path d='M6.5 42.5H41.5' {P steel w4}/>"),
	## Blackout (sabotage): a dead bulb, slashed, with a spark.
	"blackout": ("<path d='M22 4C30.3 4 36.5 10.4 36.5 18.3C36.5 23.2 34.1 27 30.8 29.6C29.6 30.6 29 31.6 29 33V34.5H15V33C15 31.6 14.4 30.6 13.2 29.6C9.9 27 7.5 23.2 7.5 18.3C7.5 10.4 13.7 4 22 4Z' {p amber}/>"
		+ "<path d='M14 11.5C15.4 9.4 17.4 8.2 19.6 7.8' {X gloss w2 d}/><path d='M17 19.5L19.5 23.5L22 19.5L24.5 23.5L27 19.5' {K w2.2 d}/>"
		+ "<rect x='15.5' y='36' width='13' height='3.2' rx='1.6' {p graphite}/><rect x='17' y='40.5' width='10' height='3.5' rx='1.75' {p graphite}/>"
		+ "<path d='M6 5L41 41' {K w9}/><path d='M6 5L41 41' {P red w4.4}/>"
		+ "<path d='M39.5 3.5Q40.4 8.1 45 9Q40.4 9.9 39.5 14.5Q38.6 9.9 34 9Q38.6 8.1 39.5 3.5Z' {p amber}/>"),
	# --- Items and places --------------------------------------------------------------
	## Power cell: brass terminal, orange cap, hazard collar, energy window, handles.
	"cell": ("<rect x='7.5' y='21' width='3.5' height='14' rx='1.75' {s graphite}/><rect x='37' y='21' width='3.5' height='14' rx='1.75' {s graphite}/>"
		+ "<rect x='20.5' y='2.5' width='7' height='3.5' rx='1.2' {p gold}/><rect x='15' y='5' width='18' height='6.5' rx='2.5' {p orange}/>"
		+ "<rect x='11' y='13' width='26' height='32' rx='6' {p shell}/><rect x='11' y='13.5' width='26' height='4.5' {x hazard d}/>"
		+ "<path d='M14.5 18.5L18.5 13M20 18.5L24 13M25.5 18.5L29.5 13M31 18.5L35 13' {K w1.8 d}/>"
		+ "<rect x='17' y='20.5' width='14' height='20' rx='3.5' {k}/><rect x='17' y='20.5' width='14' height='20' rx='3.5' {s graphite}/>"
		+ "<rect x='17' y='20.5' width='14' height='20' rx='3.5' {x glow_amber}/>"
		+ "<rect x='19.5' y='33.5' width='9' height='4.2' rx='1.4' {p amber d}/><rect x='19.5' y='28' width='9' height='4.2' rx='1.4' {p amber d}/><rect x='19.5' y='22.5' width='9' height='4.2' rx='1.4' {s amber d}/>"
		+ "<rect x='19.5' y='26' width='9' height='11.7' rx='1.8' {p amber m}/>"),
	## The core: a glowing orb in a ribbed cage on a cradle.
	"core": ("<rect x='20' y='1.8' width='8' height='4.2' rx='1.5' {p steel}/>"
		+ "<circle cx='24' cy='21' r='13' {s glow_cyan}/><circle cx='24' cy='21' r='10' {s orb}/><circle cx='22.4' cy='19.4' r='7.6' {p orb}/>"
		+ "<path d='M19.6 14.6C20.6 13.8 21.8 13.3 23 13.2' {K w1.8 d}/>"
		+ "<path d='M9.2 23A15 4.4 0 0 0 38.8 23' {K w6.6}/><path d='M9.2 23A15 4.4 0 0 0 38.8 23' {P steel w2.8}/>"
		+ "<circle cx='24' cy='21' r='15.2' {P steel w3}/>"
		+ "<path d='M24 3.4V7.6M24 34.4V38.6' {P steel w4.4 d}/>"
		+ "<path d='M14.5 45H33.5C34.6 45 35.3 43.9 34.9 42.9L32.5 37.6H15.5L13.1 42.9C12.7 43.9 13.4 45 14.5 45Z' {p graphite}/><rect x='16' y='37.6' width='16' height='2' {x cyan d}/>"),
	## Ammo: three energy rounds.
	"ammo": ("<path d='M7.5 19C7.5 13.5 9.5 10 11.5 7.5C13.5 10 15.5 13.5 15.5 19Z' {p cyan}/><rect x='7.5' y='21' width='8' height='21' rx='2' {p orange}/>"
		+ "<path d='M20 16C20 10.5 22 7 24 4.5C26 7 28 10.5 28 16Z' {p cyan}/><rect x='20' y='18' width='8' height='24' rx='2' {p orange}/>"
		+ "<path d='M32.5 19C32.5 13.5 34.5 10 36.5 7.5C38.5 10 40.5 13.5 40.5 19Z' {p cyan}/><rect x='32.5' y='21' width='8' height='21' rx='2' {p orange}/>"
		+ "<path d='M7.5 37.5H15.5M20 37.5H28M32.5 37.5H40.5' {K w1.8 d}/><rect x='4' y='42' width='40' height='3' rx='1.5' {s graphite}/>"),
	## The only gun: chunky toy blaster facing right.
	"gun": ("<path d='M11 11.5V9.5C11 8.4 11.9 7.5 13 7.5H27C28.1 7.5 29 8.4 29 9.5V11.5Z' {s orange}/>"
		+ "<rect x='27' y='27.5' width='10.5' height='5' rx='2.5' {s graphite}/><path d='M23.5 26V30.5C23.5 31.6 24.4 32.5 25.5 32.5' {P graphite w2.6}/>"
		+ "<path d='M12.5 25H23L20 41.5C19.7 43.2 18.2 44.5 16.5 44.5H12.6C10.3 44.5 8.6 42.4 9.1 40.2Z' {p graphite}/>"
		+ "<path d='M14.6 29H20.4L18.6 39.4C18.5 40.2 17.8 40.8 17 40.8H14.3C13.2 40.8 12.4 39.8 12.6 38.7Z' {k d}/><path d='M14.6 29H20.4L18.6 39.4C18.5 40.2 17.8 40.8 17 40.8H14.3C13.2 40.8 12.4 39.8 12.6 38.7Z' {s graphite d}/>"
		+ "<path d='M10 11.5H33.5C35.7 11.5 37.5 13.3 37.5 15.5V22.5C37.5 24.7 35.7 26.5 33.5 26.5H10C7.2 26.5 5 24.3 5 21.5V16.5C5 13.7 7.2 11.5 10 11.5Z' {p shell}/>"
		+ "<circle cx='15.5' cy='19' r='2.1' {k}/><circle cx='21' cy='19' r='2.1' {k}/><circle cx='26.5' cy='19' r='2.1' {k}/>"
		+ "<circle cx='15.5' cy='19' r='2.1' {s teal}/><circle cx='21' cy='19' r='2.1' {s teal}/><circle cx='26.5' cy='19' r='2.1' {s teal}/>"
		+ "<path d='M31.5 15.5V22.5M34.2 15.5V22.5' {K w1.6 d}/>"
		+ "<rect x='39.5' y='14.5' width='4.5' height='9' rx='1.8' {p cyan}/>"),
	## Crew escape: the shuttle in side view, nose right.
	"shuttle": ("<path d='M4.5 20H2.5C1.7 20 1 20.7 1 21.5V27.5C1 28.3 1.7 29 2.5 29H4.5Z' {s graphite}/><ellipse cx='1.5' cy='24.5' rx='3' ry='5' {x glow_cyan d}/>"
		+ "<path d='M14 33L11.5 40M33 33L35.5 40' {S graphite w2.6}/><path d='M8.5 40.5H14.5M32.5 40.5H38.5' {P graphite w2.6}/>"
		+ "<path d='M5.5 17.5L3.6 9.6C3.3 8.4 4.2 7.2 5.5 7.2H7.6C8.5 7.2 9.3 7.7 9.7 8.5L14.5 17.5Z' {p teal}/>"
		+ "<path d='M8.5 16H28C36.5 16 43 19.6 45.6 24.5C43 29.4 36.5 33 28 33H8.5C6 33 4 31 4 28.5V20.5C4 18 6 16 8.5 16Z' {p shell}/>"
		+ "<path d='M33.5 19.2C37.6 19.6 40.6 21 42.6 23H33.5Z' {k r1}/><path d='M33.5 19.2C37.6 19.6 40.6 21 42.6 23H33.5Z' {s cyan r1}/>"
		+ "<rect x='19' y='15' width='4' height='19' {k}/><rect x='19' y='15.5' width='4' height='17' {s teal}/>"
		+ "<circle cx='26.5' cy='26' r='2.3' {k}/><circle cx='32' cy='26' r='2.3' {k}/><circle cx='37.5' cy='26' r='2.3' {k d}/>"
		+ "<circle cx='26.5' cy='26' r='2.3' {s amber}/><circle cx='32' cy='26' r='2.3' {s amber}/><circle cx='37.5' cy='26' r='2.3' {s amber d}/>"
),
	## Infiltrator escape: the cargo pod in its frame on a hazard pad.
	"pod": ("<rect x='3.5' y='40.5' width='41' height='5' rx='2' {u graphite d}/>"
		+ "<path d='M6.5 42V10C6.5 8 8 6.5 10 6.5H38C40 6.5 41.5 8 41.5 10V42' {S graphite w3.4}/>"
		+ "<path d='M13 40V23C13 16 17.9 10.5 24 10.5C30.1 10.5 35 16 35 23V40Z' {p shell}/>"
		+ "<circle cx='24' cy='16' r='2.2' {k d}/><circle cx='24' cy='16' r='2.2' {x cyan d}/>"
		+ "<rect x='18' y='21.5' width='12' height='15' rx='2.5' {k}/><rect x='18' y='21.5' width='12' height='15' rx='2.5' {x orange}/><rect x='18' y='21.5' width='12' height='15' rx='2.5' {s orange}/>"
		+ "<rect x='25.8' y='27.5' width='2' height='4.5' rx='1' {p graphite d}/>"
		+ "<rect x='3.5' y='40.5' width='41' height='5' rx='2' {p hazard}/>"
		+ "<path d='M9 45.5L12 40.5M15 45.5L18 40.5M21 45.5L24 40.5M27 45.5L30 40.5M33 45.5L36 40.5M39 45.5L42 40.5' {K w2.4 d}/>"),
	## Airlock: a round hatch with a hazard-striped ring and split doors.
	"airlock": ("<circle cx='24' cy='24' r='18.5' {U graphite w6 d}/><circle cx='24' cy='24' r='18.5' {P hazard w6}/>"
		+ "<path d='%s' {K w3.4 d}/>" % HAZARD
		+ "<circle cx='24' cy='24' r='12' {p steel}/><path d='M15.5 32.5L32.5 15.5' {K w2.8}/>"
		+ "<circle cx='24' cy='24' r='5.4' {k}/><circle cx='24' cy='24' r='3.2' {p red}/>"),
	## Medbay: a bed with a medical cross.
	"medbay": ("<rect x='4' y='18' width='5' height='26' rx='2' {p steel}/><rect x='12' y='23.5' width='9' height='4.5' rx='2.25' {s shell}/>"
		+ "<rect x='10.5' y='28.5' width='33.5' height='7.5' rx='2.5' {p shell}/><rect x='10.5' y='37' width='33.5' height='2.5' rx='1.25' {s graphite}/>"
		+ "<rect x='39.5' y='37' width='4' height='7' rx='1.5' {p steel}/>"
		+ "<path d='M28.5 4.5H34.5V10.5H40.5V16.5H34.5V22.5H28.5V16.5H22.5V10.5H28.5Z' {p teal r2}/>"),
	## Vault (Command): a heavy door with a spoked wheel.
	"vault": ("<rect x='1.5' y='12' width='4' height='7' rx='1.5' {s graphite}/><rect x='1.5' y='29' width='4' height='7' rx='1.5' {s graphite}/>"
		+ "<rect x='4' y='4' width='40' height='40' rx='7' {p steel}/>"
		+ "<circle cx='6.4' cy='6.4' r='1.2' {k d}/><circle cx='41.6' cy='6.4' r='1.2' {k d}/><circle cx='6.4' cy='41.6' r='1.2' {k d}/><circle cx='41.6' cy='41.6' r='1.2' {k d}/>"
		+ "<rect x='8.5' y='8.5' width='31' height='31' rx='4' {k}/><rect x='8.5' y='8.5' width='31' height='31' rx='4' {s graphite}/>"
		+ "<circle cx='24' cy='24' r='8.5' {P cyan w3.4}/><path d='M24 11V15.5M24 32.5V37M11 24H15.5M32.5 24H37' {P cyan w3.4}/><circle cx='24' cy='24' r='3' {p cyan}/>"),
	## Armory (Security): a chamfered blast door with a reticle stencil.
	"armory": ("<path d='M15.5 3.5H32.5L41.5 12.5V40.5C41.5 42.7 39.7 44.5 37.5 44.5H10.5C8.3 44.5 6.5 42.7 6.5 40.5V12.5Z' {p steel r2}/>"
		+ "<path d='M17.2 7.5H30.8L37.5 14.2V38.5C37.5 39.6 36.6 40.5 35.5 40.5H12.5C11.4 40.5 10.5 39.6 10.5 38.5V14.2Z' {k}/>"
		+ "<path d='M17.2 7.5H30.8L37.5 14.2V38.5C37.5 39.6 36.6 40.5 35.5 40.5H12.5C11.4 40.5 10.5 39.6 10.5 38.5V14.2Z' {s graphite}/>"
		+ "<circle cx='24' cy='21.5' r='6.5' {P orange w3}/><path d='M24 11.5V15.5M24 27.5V31.5M14 21.5H18M30 21.5H34' {P orange w3}/><circle cx='24' cy='21.5' r='1.8' {p orange}/>"
		+ "<path d='M16.5 35H31.5' {P steel w2.6 d}/>"),
	## Locked.
	"lock": ("<path d='M15.5 21V15C15.5 10.3 19.3 6.5 24 6.5C28.7 6.5 32.5 10.3 32.5 15V21' {P steel w5}/>"
		+ "<rect x='9' y='20' width='30' height='25' rx='6' {p amber}/><path d='M13 25H35' {K w1.6 d}/>"
		+ "<circle cx='24' cy='31' r='3.4' {k}/><path d='M22.3 32H25.7L26.6 39H21.4Z' {k r1}/>"),
	## Unlocked: the shackle swung open.
	"unlock": ("<path d='M27 20.5V14C27 9.3 30.8 5.5 35.5 5.5C40.2 5.5 44 9.3 44 14V17' {P steel w5}/>"
		+ "<rect x='5' y='20' width='30' height='25' rx='6' {p teal}/><path d='M9 25H31' {K w1.6 d}/>"
		+ "<circle cx='20' cy='31' r='3.4' {k}/><path d='M18.3 32H21.7L22.6 39H17.4Z' {k r1}/>"),
	## Reactor: three cell sockets around a glowing hub.
	"reactor": ("<circle cx='24' cy='27.5' r='19.5' {S graphite w2.6}/>"
		+ "<rect x='19.5' y='5.5' width='9' height='14' rx='3' {k w5}/><rect x='19.5' y='5.5' width='9' height='14' rx='3' {k w5}/>"
		+ "<g transform='rotate(120 24 27.5)'><rect x='19.5' y='5.5' width='9' height='14' rx='3' {k w5}/></g><g transform='rotate(240 24 27.5)'><rect x='19.5' y='5.5' width='9' height='14' rx='3' {k w5}/></g>"
		+ "<rect x='19.5' y='5.5' width='9' height='14' rx='3' {p shell}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {k d}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {s amber d}/>"
		+ "<g transform='rotate(120 24 27.5)'><rect x='19.5' y='5.5' width='9' height='14' rx='3' {p shell}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {k d}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {s amber d}/></g>"
		+ "<g transform='rotate(240 24 27.5)'><rect x='19.5' y='5.5' width='9' height='14' rx='3' {p shell}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {k d}/><rect x='22' y='8.5' width='4' height='7.5' rx='1.5' {s amber d}/></g>"
		+ "<circle cx='24' cy='27.5' r='9' {x glow_cyan}/><circle cx='24' cy='27.5' r='6.6' {P cyan w3}/><circle cx='24' cy='27.5' r='2.6' {p cyan}/>"),
	# --- Status and UI -------------------------------------------------------------------
	## Power: a bolt with a toy extrusion.
	"bolt": ("<path transform='translate(2.4 2.4)' d='%s' {s amber_dk r3}/><path d='%s' {p amber r3}/>" % [BOLT, BOLT]
		+ "<path d='M24.5 7.5L13.6 21.6' {X gloss w1.8 d}/>"),
	"warning": ("<path d='M20.4 8.1C22 5.3 26 5.3 27.6 8.1L44.2 37.1C45.8 39.9 43.8 43.5 40.6 43.5H7.4C4.2 43.5 2.2 39.9 3.8 37.1Z' {p amber}/>"
		+ "<path d='M24 15L38 39H10Z' {k r2}/><path d='M24 15L38 39H10Z' {s graphite r2}/>"
		+ "<path d='M21.8 19.8H26.2L25.4 30.2H22.6Z' {p amber r2.2}/><circle cx='24' cy='34.6' r='2.4' {p amber}/>"),
	"info": ("<circle cx='24' cy='24' r='20.5' {p cyan}/><path d='M10.4 17.5C12.6 11.6 18 7.6 24.2 7.6' {X gloss w2.4 d}/>"
		+ "<circle cx='24' cy='14.6' r='3.3' {k}/><rect x='21' y='20.5' width='6' height='15' rx='3' {k}/>"
		+ "<circle cx='24' cy='14.6' r='3.3' {x led}/><rect x='21' y='20.5' width='6' height='15' rx='3' {x led}/>"),
	## Abort / nobody wins: a prohibition sign.
	"abort": ("<circle cx='24' cy='24' r='15.6' {s red_dk}/><path d='M13.4 13.4L34.6 34.6' {K w10}/>"
		+ "<circle cx='24' cy='24' r='18' {P red w5}/><path d='M13.4 13.4L34.6 34.6' {P red w5}/>"),
	## Timer: a stopwatch with an elapsed wedge.
	"clock": ("<rect x='19.5' y='2.5' width='9' height='4.5' rx='1.8' {p steel}/><rect x='22.2' y='6' width='3.6' height='4' {p steel}/>"
		+ "<rect x='35.1' y='10.9' width='6' height='4' rx='1.6' transform='rotate(45 38.1 12.9)' {p steel}/>"
		+ "<circle cx='24' cy='27' r='17.5' {p steel}/><circle cx='24' cy='27' r='13.8' {k}/><circle cx='24' cy='27' r='13.8' {s graphite}/>"
		+ "<path d='M24 27V17A10 10 0 0 1 32.66 32Z' {p amber}/><circle cx='24' cy='27' r='2.6' {p amber}/>"),
	"copy": ("<rect x='5' y='4' width='24' height='28' rx='5' {s steel}/><rect x='17' y='14' width='26' height='30' rx='5' {k w6}/>"
		+ "<rect x='17' y='14' width='26' height='30' rx='5' {p shell}/><path d='M22.5 23.5H37.5M22.5 29.5H37.5M22.5 35.5H31.5' {K w2.6 d}/>"),
	## LAN: a station beacon broadcasting.
	"wifi": ("<path d='M24 22L30.5 42H17.5Z' {s graphite r2}/><rect x='14' y='41' width='20' height='4' rx='2' {p graphite}/>"
		+ "<circle cx='24' cy='19' r='7' {x glow_cyan d}/><circle cx='24' cy='19' r='4.2' {p cyan}/>"
		+ "<path d='M17.5 24.5A8.5 8.5 0 0 1 17.5 13.5M30.5 13.5A8.5 8.5 0 0 1 30.5 24.5' {P cyan w4}/>"
		+ "<path d='M12.1 29A15.5 15.5 0 0 1 12.1 9M35.9 9A15.5 15.5 0 0 1 35.9 29' {P cyan w4}/>"),
	"play": "<path transform='translate(1.4 1.4)' d='%s' {s cyan_dk}/><path transform='translate(-1 -1)' d='%s' {p cyan}/>" % [PLAY, PLAY],
	"pause": ("<rect x='13.4' y='9.4' width='9' height='31' rx='3' {s cyan_dk}/><rect x='28.4' y='9.4' width='9' height='31' rx='3' {s cyan_dk}/>"
		+ "<rect x='11' y='7' width='9' height='31' rx='3' {p cyan}/><rect x='26' y='7' width='9' height='31' rx='3' {p cyan}/>"),
	## Menu: three slanted bars, like the game's buttons.
	"menu": ("<path transform='translate(1.4 1.4)' d='%s' {s cyan_dk}/><path transform='translate(1.4 13.4)' d='%s' {s cyan_dk}/><path transform='translate(1.4 25.4)' d='%s' {s cyan_dk}/>" % [MENU_BAR, MENU_BAR, MENU_BAR]
		+ "<path transform='translate(-1 -1)' d='%s' {p cyan}/><path transform='translate(-1 11)' d='%s' {p cyan}/><path transform='translate(-1 23)' d='%s' {p cyan}/>" % [MENU_BAR, MENU_BAR, MENU_BAR]),
	## Leave: out through a hatch.
	"leave": ("<path d='M27 13.5V10C27 7.8 25.2 6 23 6H11.5C9.3 6 7.5 7.8 7.5 10V38C7.5 40.2 9.3 42 11.5 42H23C25.2 42 27 40.2 27 38V34.5' {P steel w4.5}/>"
		+ "<path d='M10 8.5L21 11.5V36.5L10 39.5Z' {s orange r1.5}/>"
		+ "<path d='M18.5 24H40M33 16.5L40.5 24L33 31.5' {K w10}/><path d='M18.5 24H40M33 16.5L40.5 24L33 31.5' {P cyan w5}/>"),
	"close": "<path transform='translate(1.4 1.4)' d='M13 13L35 35M35 13L13 35' {S red_dk w6}/><path transform='translate(-1 -1)' d='M13 13L35 35M35 13L13 35' {P red w6}/>",
	"check": "<path transform='translate(1.4 1.4)' d='M9.5 25L19.5 35L39 14' {S teal_dk w6}/><path transform='translate(-1 -1)' d='M9.5 25L19.5 35L39 14' {P teal w6}/>",
	"chevron": "<path transform='translate(1.4 1.4)' d='M18.5 8.5L33.5 24L18.5 39.5' {S cyan_dk w6}/><path transform='translate(-1 -1)' d='M18.5 8.5L33.5 24L18.5 39.5' {P cyan w6}/>",
	"flag": ("<ellipse cx='11' cy='43.5' rx='6' ry='2' {s graphite}/><path d='M11 5.5V43' {P steel w4}/>"
		+ "<path d='M26.5 7.8C31.5 10.6 36.5 10.6 42 7.8V26.8C36.5 29.6 31.5 29.6 26.5 26.8Z' {s cyan_dk r1.5}/>"
		+ "<path d='M11 7.5C16.5 4.8 21.5 5 26.5 7.8V26.8C21.5 24 16.5 23.8 11 26.5Z' {p cyan r1.5}/>"),
	"signal": ("<rect x='7.9' y='34.4' width='7' height='9' rx='2.5' {s cyan_dk}/><rect x='17.4' y='26.4' width='7' height='17' rx='2.5' {s cyan_dk}/>"
		+ "<rect x='26.9' y='17.4' width='7' height='26' rx='2.5' {s cyan_dk}/><rect x='36.4' y='7.4' width='7' height='36' rx='2.5' {s cyan_dk}/>"
		+ "<rect x='5.5' y='32' width='7' height='9' rx='2.5' {p cyan}/><rect x='15' y='24' width='7' height='17' rx='2.5' {p cyan}/>"
		+ "<rect x='24.5' y='15' width='7' height='26' rx='2.5' {p cyan}/><rect x='34' y='5' width='7' height='36' rx='2.5' {p cyan}/>"),
	## Off-screen marker: a faceted dart pointing right (+x), lit from above.
	"dart": ("<path d='M44.5 24L12.6 24L5.1 38.1C4 40.3 6.3 42.6 8.5 41.5Z' {s cyan_dk r1.5}/>"
		+ "<path d='M44.5 24L8.5 6.5C6.3 5.4 4 7.7 5.1 9.9L12.6 24Z' {p cyan r1.5}/>"),
	"gear": ("<circle cx='24' cy='24' r='15.5' {p steel}/>"
		+ "<rect x='20.5' y='3' width='7' height='9' rx='1.8' {p steel}/><rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(45 24 24)' {p steel}/>"
		+ "<rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(90 24 24)' {p steel}/><rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(135 24 24)' {p steel}/>"
		+ "<rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(180 24 24)' {p steel}/><rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(225 24 24)' {p steel}/>"
		+ "<rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(270 24 24)' {p steel}/><rect x='20.5' y='3' width='7' height='9' rx='1.8' transform='rotate(315 24 24)' {p steel}/>"
		+ "<circle cx='24' cy='24' r='9.5' {k}/><circle cx='24' cy='24' r='9.5' {s graphite}/><circle cx='24' cy='24' r='4.6' {p cyan}/>"),
	## Achievement star: five points, each with a lit and a shaded facet.
	"star": ("<path d='M24 25L18.71 17.72L24 4Z M24 25L29.29 17.72L43.97 18.51Z M24 25L32.56 27.78L36.34 41.99Z M24 25L24 34L11.66 41.99Z M24 25L15.44 27.78L4.03 18.51Z' {p gold}/>"
		+ "<path d='M24 25L24 4L29.29 17.72Z M24 25L43.97 18.51L32.56 27.78Z M24 25L36.34 41.99L24 34Z M24 25L11.66 41.99L15.44 27.78Z M24 25L4.03 18.51L18.71 17.72Z' {s gold_dk}/>"),
	"trophy": ("<path d='M12.5 9H8.5C6.6 9 5.5 10.2 5.5 12C5.5 17 8.5 20.5 13.2 21.5M35.5 9H39.5C41.4 9 42.5 10.2 42.5 12C42.5 17 39.5 20.5 34.8 21.5' {P gold w3.6}/>"
		+ "<path d='M12.5 5H35.5V17.5C35.5 24.4 30.4 30 24 30C17.6 30 12.5 24.4 12.5 17.5Z' {p gold r2}/><path d='M12.5 9.5H35.5' {K w1.6 d}/>"
		+ "<path d='M24 10L25.7 14.15L30.18 14.49L26.76 17.4L27.82 21.76L24 19.4L20.18 21.76L21.24 17.4L17.82 14.49L22.3 14.15Z' {k d}/>"
		+ "<path d='M24 10L25.7 14.15L30.18 14.49L26.76 17.4L27.82 21.76L24 19.4L20.18 21.76L21.24 17.4L17.82 14.49L22.3 14.15Z' {s gold_dk d}/>"
		+ "<rect x='21' y='29.5' width='6' height='7.5' {p gold_dk}/><path d='M15 37H33C34.1 37 35 37.9 35 39V43.5H13V39C13 37.9 13.9 37 15 37Z' {p graphite r1.5}/>"
		+ "<rect x='19' y='39.5' width='10' height='2' rx='1' {x gold d}/>"),
}

static var _cache := {}
static var _re_elem := RegEx.create_from_string("<(\\w+)\\s([^<>]*?)\\{([^}]*)\\}([^<>]*?)/>")
static var _re_group := RegEx.create_from_string("(?s)<g transform='([^']*)'>(.*?)</g>")
static var _re_child := RegEx.create_from_string("<(\\w+)\\s([^<>]*?)/>")


# --- Public API ----------------------------------------------------------------------

static func has(name: String) -> bool:
	return GLYPHS.has(name) or ALIASES.has(name)


## Canonical glyph names (aliases excluded), in catalogue order.
static func names() -> PackedStringArray:
	return PackedStringArray(GLYPHS.keys())


## A complete SVG document for a glyph. `style` is "duo" or "color"; `small`
## selects the optical variant for <= 36 px; `ink` is the duo colour.
static func svg(name: String, px := RASTER, style := "duo", small := false, ink := "#ffffff") -> String:
	var parts := _compose(_body(name), style, small, ink, "", 0.0)
	return _doc(px, parts.defs, parts.body)


## White duo icon texture with mipmaps (cached). Tint with modulate.
static func texture(name: String) -> Texture2D:
	return texture_styled(name)


## Icon texture in a style, with mipmaps (cached). `px` <= 36 gives the small
## optical variant. "color" textures should be drawn with a white modulate.
static func texture_styled(name: String, style := "duo", px := RASTER) -> Texture2D:
	return _texture(_resolve(name), style, maxi(8, px), px <= SMALL_PX, true, true)


## Draw an icon centred on a point. `angle` rotates around the centre. In the
## "color" style only the alpha of `color` is used.
static func draw(canvas: CanvasItem, name: String, center: Vector2, size: float, color: Color, angle := 0.0, style := "duo") -> void:
	if color.a <= 0.003 or size <= 0.5:
		return
	var glyph := _resolve(name)
	var colour_mode := style == "color"
	# Dark ink (e.g. on a filled chip) skips the halo, which would only blur it.
	var halo := colour_mode or color.get_luminance() > 0.3
	var modulate := Color(1, 1, 1, color.a) if colour_mode else color
	_blit(canvas, func(px: int, small: bool, mips: bool) -> Texture2D: return _texture(glyph, style, px, small, halo, mips),
		center, size, modulate, angle)


## A badge: the icon on a glass backplate (hex or rounded square) with an inner
## bevel and a rim in `accent`. For touch buttons, achievements and hero spots.
static func badge(canvas: CanvasItem, name: String, center: Vector2, size: float, accent: Color, style := "color", shape := "hex", alpha := 1.0) -> void:
	if alpha <= 0.003 or size <= 0.5:
		return
	var glyph := _resolve(name)
	_blit(canvas, func(px: int, small: bool, mips: bool) -> Texture2D: return _badge_texture(glyph, accent, shape, style, px, small, mips),
		center, size, Color(1, 1, 1, alpha), 0.0)


## Badge texture with mipmaps (cached), e.g. for a TextureRect or Button icon.
static func badge_texture(name: String, accent: Color, shape := "hex", style := "color", px := RASTER) -> Texture2D:
	return _badge_texture(_resolve(name), accent, shape, style, maxi(8, px), px <= SMALL_PX, true)


## SVG document of a badge.
static func badge_svg(name: String, accent: Color, shape := "hex", style := "color", px := RASTER, small := false) -> String:
	var plate := _plate_path(shape)
	var a := "#" + accent.to_html(false)
	var lit := "#" + accent.lerp(Color.WHITE, 0.45).to_html(false)
	var top := "#" + Color("101a2c").lerp(accent, 0.16).to_html(false)
	var ink := "#" + accent.lerp(Color.WHITE, 0.3).to_html(false)
	var scale := 0.6 if shape == "hex" else 0.64
	var offset := 24.0 - 24.0 * scale
	var icon := _compose(_body(name), style, small, ink, "i", 0.0)
	var defs: String = ("<linearGradient id='bp' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='%s'/><stop offset='1' stop-color='#050912'/></linearGradient>" % top
		+ "<linearGradient id='bb' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#fff' stop-opacity='.4'/><stop offset='.45' stop-color='#fff' stop-opacity='0'/><stop offset='1' stop-color='#000' stop-opacity='.45'/></linearGradient>"
		+ "<linearGradient id='br' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='%s'/><stop offset='1' stop-color='%s'/></linearGradient>" % [lit, a]
		+ "<radialGradient id='bg' cx='.5' cy='.5' r='.5'><stop offset='0' stop-color='%s' stop-opacity='.4'/><stop offset='1' stop-color='%s' stop-opacity='0'/></radialGradient>" % [a, a]
		+ icon.defs)
	var body: String = ("<path d='%s' transform='translate(0 1.6)' fill='#000' fill-opacity='.45'/>" % plate
		+ "<path d='%s' fill='url(#bp)'/>" % plate
		+ "<circle cx='24' cy='24' r='17' fill='url(#bg)'/>"
		+ "<path d='%s' transform='translate(24 24) scale(.86) translate(-24 -24)' fill='none' stroke='url(#bb)' stroke-width='1.8'/>" % plate
		+ "<path d='%s' fill='none' stroke='url(#br)' stroke-width='2.4'/>" % plate
		+ "<g transform='translate(%.2f %.2f) scale(%.3f)'>%s</g>" % [offset, offset, scale, icon.body])
	return _doc(px, defs, body)


# --- Composition ---------------------------------------------------------------------

static func _resolve(name: String) -> String:
	var glyph: String = ALIASES.get(name, name)
	return glyph if GLYPHS.has(glyph) else "info"


static func _body(name: String) -> String:
	return GLYPHS[_resolve(name)]


static func _doc(px: int, defs: String, body: String) -> String:
	return ("<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 48 48'><defs>%s</defs>" % [px, px, defs]
		+ "<g stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % body)


## Moves `<g transform>` wrappers onto their children so every token element is
## top level (knock-outs wrap everything drawn before them).
static func _flatten(body: String) -> String:
	var out := body
	var m := _re_group.search(out)
	while m != null:
		var xf := m.get_string(1)
		var inner := m.get_string(2)
		var rebuilt := ""
		var pos := 0
		for c in _re_child.search_all(inner):
			rebuilt += inner.substr(pos, c.get_start() - pos)
			var attrs := c.get_string(2)
			if attrs.contains("transform='"):
				attrs = attrs.replace("transform='", "transform='%s " % xf)
			else:
				attrs = "transform='%s' %s" % [xf, attrs]
			rebuilt += "<%s %s/>" % [c.get_string(1), attrs]
			pos = c.get_end()
		rebuilt += inner.substr(pos)
		out = out.substr(0, m.get_start()) + rebuilt + out.substr(m.get_end())
		m = _re_group.search(out)
	return out


## Expands tokens for one style. Returns {defs, body, shadow}; `shadow` is the
## silhouette (black, spread by `spread` units) used for the halo.
static func _compose(body: String, style: String, small: bool, ink: String, prefix: String, spread: float) -> Dictionary:
	var src := _flatten(body)
	var colour := style == "color"
	var sec := SECONDARY_SMALL if small else SECONDARY
	var defs := {}
	var out := ""
	var under := ""
	var shadow := ""
	var cuts := 0
	var pos := 0
	for m in _re_elem.search_all(src):
		out += src.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var tag := m.get_string(1)
		var attrs := (m.get_string(2) + " " + m.get_string(4)).strip_edges()
		var words := m.get_string(3).split(" ", false)
		var role: String = words[0]
		var kind := role.to_lower()
		var stroke_role := role != kind
		var paint := ""
		var width := 0.0
		var rounding := 0.0
		var detail := false
		var mini := false
		for i in range(1, words.size()):
			var word: String = words[i]
			if word == "d":
				detail = true
			elif word == "m":
				mini = true
			elif word.begins_with("w") and word.substr(1).is_valid_float():
				width = float(word.substr(1))
			elif word.begins_with("r") and word.substr(1).is_valid_float():
				rounding = float(word.substr(1))
			else:
				paint = word
		if (detail and small) or (mini and not small):
			continue
		if kind == "k":
			cuts += 1
			var id := "%sk%d" % [prefix, cuts]
			var cut := "fill='none' stroke='#000' stroke-width='%s'" % width if stroke_role else "fill='#000'"
			if not stroke_role and (width > 0.0 or rounding > 0.0):
				cut += " stroke='#000' stroke-width='%s'" % maxf(width, rounding)
			defs[id] = ("<mask id='%s' maskUnits='userSpaceOnUse' x='-8' y='-8' width='64' height='64'>" % id
				+ "<rect x='-8' y='-8' width='64' height='64' fill='#fff'/><%s %s %s/></mask>" % [tag, attrs, cut])
			out = "<g mask='url(#%s)'>%s</g>" % [id, out]
			continue
		if kind == "x" and not colour:
			continue
		if kind != "x" and kind != "g" and spread > 0.0:
			var grow := (width if stroke_role else rounding) + spread * 2.0
			shadow += "<%s %s fill='%s' stroke='#000' stroke-width='%s'/>" % [tag, attrs, "none" if stroke_role else "#000", grow]
		var ref := ink
		var opacity := 1.0
		if colour:
			if paint == "":
				paint = {"p": "shell", "s": "graphite", "g": "gloss", "u": "graphite", "x": "shade"}.get(kind, "shell")
			var p := _paint(paint, stroke_role, prefix, defs)
			ref = p[0]
			opacity = p[1]
		else:
			opacity = {"s": sec, "u": sec, "g": GLINT}.get(kind, 1.0)
		var look := ""
		if stroke_role:
			look = "fill='none' stroke='%s' stroke-width='%s'" % [ref, width]
		else:
			look = "fill='%s'" % ref
			if rounding > 0.0:
				look += " stroke='%s' stroke-width='%s'" % [ref, rounding]
		var element := "<%s %s %s/>" % [tag, attrs, look]
		if opacity < 0.999:
			element = "<g opacity='%.3f'>%s</g>" % [opacity, element]
		if kind == "u":
			under += element
		else:
			out += element
	out += src.substr(pos)
	var defs_text := ""
	for id in defs:
		defs_text += defs[id]
	return {"defs": defs_text, "body": under + out, "shadow": shadow}


## Colour-mode paint -> [fill/stroke value, opacity]; adds gradient defs.
static func _paint(name: String, for_stroke: bool, prefix: String, defs: Dictionary) -> Array:
	if name.begins_with("#"):
		return [name, 1.0]
	var spec: Dictionary = PAINTS.get(name, PAINTS.shell)
	if spec.has("flat"):
		return [spec.flat, float(spec.get("o", 1.0))]
	var id := "%sp_%s%s" % [prefix, name, "_u" if for_stroke else ""]
	if not defs.has(id):
		if spec.has("lin"):
			var units := "gradientUnits='userSpaceOnUse' x1='18' y1='4' x2='30' y2='44'" if for_stroke else "x1='.3' y1='0' x2='.7' y2='1'"
			defs[id] = "<linearGradient id='%s' %s><stop offset='0' stop-color='%s'/><stop offset='1' stop-color='%s'/></linearGradient>" % [id, units, spec.lin[0], spec.lin[1]]
		elif spec.has("rad"):
			defs[id] = ("<radialGradient id='%s' cx='.38' cy='.34' r='.72'><stop offset='0' stop-color='%s'/>" % [id, spec.rad[0]]
				+ "<stop offset='.45' stop-color='%s'/><stop offset='1' stop-color='%s'/></radialGradient>" % [spec.rad[1], spec.rad[2]])
		else:
			var c: String = spec.glow
			defs[id] = ("<radialGradient id='%s' cx='.5' cy='.5' r='.5'><stop offset='0' stop-color='%s' stop-opacity='.85'/>" % [id, c]
				+ "<stop offset='.5' stop-color='%s' stop-opacity='.35'/><stop offset='1' stop-color='%s' stop-opacity='0'/></radialGradient>" % [c, c])
	return ["url(#%s)" % id, 1.0]


## Rounded hexagon (pointy top) or rounded square on the 48 grid.
static func _plate_path(shape: String) -> String:
	if shape != "hex":
		return "M15 3H33C39.1 3 45 8.9 45 15V33C45 39.1 39.1 45 33 45H15C8.9 45 3 39.1 3 33V15C3 8.9 8.9 3 15 3Z"
	var pts: Array[Vector2] = []
	for i in range(6):
		var a := deg_to_rad(-90.0 + 60.0 * i)
		pts.append(Vector2(24, 24) + Vector2(cos(a), sin(a)) * 22.5)
	var d := ""
	for i in range(6):
		var v := pts[i]
		var a := v + (pts[(i + 5) % 6] - v).normalized() * 5.0
		var b := v + (pts[(i + 1) % 6] - v).normalized() * 5.0
		d += "%s%.2f %.2fQ%.2f %.2f %.2f %.2f" % ["M" if i == 0 else "L", a.x, a.y, v.x, v.y, b.x, b.y]
	return d + "Z"


# --- Rasterising and drawing ---------------------------------------------------------------

static func _image(svg_text: String, shadow: String, px: int, spread_px: float) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg_text, 1.0) != OK or img.is_empty():
		return Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	if shadow == "":
		return img
	# Soft dark halo: the silhouette spread a little, rendered at half size and
	# scaled up so it blurs, then the icon on top. Black survives tinting.
	var half := maxi(8, int(round(px * 0.5)))
	var halo := Image.new()
	var doc := "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 48 48'><g opacity='%.2f' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % [half, half, HALO_ALPHA, shadow]
	if halo.load_svg_from_string(doc, 1.0) != OK or halo.is_empty():
		return img
	halo.convert(Image.FORMAT_RGBA8)
	halo.resize(px, px, Image.INTERPOLATE_BILINEAR)
	halo.blend_rect(img, Rect2i(0, 0, px, px), Vector2i.ZERO)
	return halo


static func _spread(px: int) -> float:
	# Halo spread in grid units: 2.2 units at 128 px, at least ~1.3 px when small.
	return maxf(2.2, 1.3 * GRID / float(px))


static func _texture(glyph: String, style: String, px: int, small: bool, halo: bool, mips: bool) -> Texture2D:
	var key := "%s|%s|%d|%d|%d|%d" % [glyph, style, px, int(small), int(halo), int(mips)]
	if _cache.has(key):
		return _cache[key]
	var ink := "#ffffff"
	var parts := _compose(GLYPHS[glyph], style, small, ink, "", _spread(px) if halo else 0.0)
	var img := _image(_doc(px, parts.defs, parts.body), parts.shadow if halo else "", px, 0.0)
	return _store(key, img, mips)


static func _badge_texture(glyph: String, accent: Color, shape: String, style: String, px: int, small: bool, mips: bool) -> Texture2D:
	var key := "badge|%s|%s|%s|%s|%d|%d|%d" % [glyph, accent.to_html(), shape, style, px, int(small), int(mips)]
	if _cache.has(key):
		return _cache[key]
	return _store(key, _image(badge_svg(glyph, accent, shape, style, px, small), "", px, 0.0), mips)


static func _store(key: String, img: Image, mips: bool) -> Texture2D:
	if mips:
		img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = tex
	return tex


## Exact pixel size for crisp small and medium icons; coarser steps above.
static func _bucket(px: float) -> int:
	if px <= 64.0:
		return maxi(8, int(round(px)))
	return int(round(px / 4.0)) * 4


## Draws a texture from `make(px, small, mips)`: pixel-exact and snapped when
## axis aligned and not huge, otherwise mipmapped and transformed.
static func _blit(canvas: CanvasItem, make: Callable, center: Vector2, size: float, modulate: Color, angle: float) -> void:
	var screen := canvas.get_screen_transform()
	var scale := screen.get_scale()
	var px := size * absf(scale.x)
	var aligned := angle == 0.0 and absf(screen.get_rotation()) < 0.0001 and absf(screen.get_skew()) < 0.0001 \
		and scale.x > 0.0 and is_equal_approx(scale.x, scale.y)
	if aligned and px <= EXACT_MAX:
		var bucket := _bucket(px)
		var tex: Texture2D = make.call(bucket, bucket <= SMALL_PX, false)
		var mid := screen * center
		var corner := (mid - Vector2(bucket, bucket) * 0.5).round()
		var local := screen.affine_inverse() * corner
		var side := bucket / scale.x
		canvas.draw_texture_rect(tex, Rect2(local, Vector2(side, side)), false, modulate)
		return
	var raster := 32
	while raster < px and raster < 512:
		raster *= 2
	var mipped: Texture2D = make.call(raster, px <= SMALL_PX, true)
	var rect := Rect2(-Vector2(size, size) * 0.5, Vector2(size, size))
	if angle == 0.0:
		canvas.draw_texture_rect(mipped, Rect2(center + rect.position, rect.size), false, modulate)
		return
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_texture_rect(mipped, rect, false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
