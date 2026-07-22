#+private
package presentation

import rl "vendor:raylib"

// Sourced art, embedded in the binary the same way the font is (ui.odin): ADR-0009
// commits to a self-contained game.exe, which a sidecar .png breaks. Each asset is
// generated through the PixelLab MCP, conformed to the style guide, and authored at
// native resolution to be POINT-scaled to the window.

// The Chart Table's sourced background — the #284 carve-out the style guide reserves
// (docs/ui/style-guide.md, "What this guide does not cover"). 400x272 native.
//
// This is the bright *daytime* scene — the register of the reference the maintainer
// asked for (docs/ui/references/style/island-tropical.jpg): blue sky, turquoise water,
// midday sun. A bright ground sits *above* the title's luminance, so the guide's "world
// never outshines the chrome" rule cannot hold globally for it; legibility is bought
// locally by a scrim behind the title instead (draw_menu_title_scrim, chart_table.odin).
// A ramp-conformed dusk variant that *does* satisfy the rule globally is kept beside it
// as menu-island-night.png; swap the #load path to use it (and drop the title scrim).
MENU_ISLAND_PNG :: #load("../assets/art/menu-island-day.png")

// The parchment treasure-map page (spec 0001 §2/§9): the warm aged sheet the Chart is
// inked onto, with its rough torn deckled edge (Sand→Cliff→Rock) baked into the same
// texture. The page and its rim are one object — a torn sheet of paper on the table — so a
// blit fills the centred MAP_AREA and the transparent surround shows the darkened Build
// behind it.
PARCHMENT_PAGE_PNG :: #load("../assets/art/parchment-page.png")

// The sailing ship (spec 0001 §5/§9): a PixelLab 8-direction pixel-art sprite — deliberately
// the one raster on the otherwise-procedural live layer, a little vessel *on* the map rather
// than a mark drawn *in* it. Warm sepia hull + cream sail, no amber, so it reads on the
// parchment. The eight baked headings (N, NE, E, SE, S, SW, W, NW) are laid out left-to-right
// in a single horizontal strip, each frame a square the sheet's own height, so a heading
// indexes a column (view.odin draw_ship_sprite).
SHIP_SPRITE_PNG :: #load("../assets/art/ship-sprite.png")

// The uploaded atlases. GPU resources like the font, so they are loaded after InitWindow
// and freed by art_unload.
menu_island_tex: rl.Texture2D
parchment_page_tex: rl.Texture2D
ship_sprite_tex: rl.Texture2D

// art_texture uploads one embedded PNG. POINT filtering is the same rule the font atlas
// needs: raylib defaults to bilinear, which softens pixel art on upload and undoes
// authoring at native resolution.
art_texture :: proc(png: []u8) -> rl.Texture2D {
	img := rl.LoadImageFromMemory(".png", raw_data(png), i32(len(png)))
	defer rl.UnloadImage(img)
	tex := rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(tex, .POINT)
	return tex
}

// art_load uploads every embedded asset. Must run after InitWindow.
art_load :: proc() {
	menu_island_tex = art_texture(MENU_ISLAND_PNG)
	parchment_page_tex = art_texture(PARCHMENT_PAGE_PNG)
	ship_sprite_tex = art_texture(SHIP_SPRITE_PNG)
}

art_unload :: proc() {
	rl.UnloadTexture(menu_island_tex)
	rl.UnloadTexture(parchment_page_tex)
	rl.UnloadTexture(ship_sprite_tex)
}
