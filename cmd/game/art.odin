package main

import rl "vendor:raylib"

// Sourced art, embedded in the binary the same way the font is (ui.odin): ADR-0009
// commits to a self-contained game.exe, which a sidecar .png breaks. This is the
// Chart Table's sourced background — the #284 carve-out the style guide reserves
// (docs/ui/style-guide.md, "What this guide does not cover"): the screen's ground was
// drawn from the ramp (#294) as a placeholder "only in ambition", and #284 anticipated
// a sourced image as an improvement in *depiction*.
//
// It was generated through the PixelLab MCP from a tropical-island prompt, then
// conformed (trial watermark painted out). 400x272 at native resolution, POINT-scaled
// to the window.
//
// This is the bright *daytime* scene — the register of the reference the maintainer
// asked for (docs/ui/references/style/island-tropical.jpg): blue sky, turquoise water,
// midday sun. A bright ground sits *above* the title's luminance, so the guide's "world
// never outshines the chrome" rule cannot hold globally for it; legibility is bought
// locally by a scrim behind the title instead (draw_menu_title_scrim, chart_table.odin).
// A ramp-conformed dusk variant that *does* satisfy the rule globally is kept beside it
// as menu-island-night.png; swap the #load path to use it (and drop the title scrim).
MENU_ISLAND_PNG :: #load("../../assets/art/menu-island-day.png")

// menu_island_tex is the uploaded atlas. Like the font it is a GPU resource, so it is
// loaded after InitWindow and freed by menu_art_unload.
menu_island_tex: rl.Texture2D

// menu_art_load uploads the embedded PNG. POINT filtering is the same rule the font
// atlas needs: raylib defaults to bilinear, which softens pixel art on upload and undoes
// generating at native resolution. Must run after InitWindow.
menu_art_load :: proc() {
	img := rl.LoadImageFromMemory(".png", raw_data(MENU_ISLAND_PNG), i32(len(MENU_ISLAND_PNG)))
	defer rl.UnloadImage(img)
	menu_island_tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(menu_island_tex, .POINT)
}

menu_art_unload :: proc() {
	rl.UnloadTexture(menu_island_tex)
}

// The parchment treasure-map page (spec 0001 §2/§9): the warm aged sheet the Chart is
// inked onto, with its rough torn deckled edge (Sand→Cliff→Rock) baked into the same
// texture. The page and its rim are one object — a torn sheet of paper on the table — so a
// blit fills the centred MAP_AREA and the transparent surround shows the darkened Build
// behind it. Same embed pipeline as the menu island: PixelLab-sourced, conformed to the
// parchment roster (§8), POINT-scaled at native resolution.
PARCHMENT_PAGE_PNG :: #load("../../assets/art/parchment-page.png")

// parchment_page_tex is the uploaded page. A GPU resource like the menu island, so it is
// loaded after InitWindow and freed by parchment_art_unload.
parchment_page_tex: rl.Texture2D

// parchment_art_load uploads the embedded page. POINT filtering for the same reason the
// menu island and font need it: raylib's default bilinear softens pixel art on upload and
// undoes generating at native resolution. Must run after InitWindow.
parchment_art_load :: proc() {
	img := rl.LoadImageFromMemory(".png", raw_data(PARCHMENT_PAGE_PNG), i32(len(PARCHMENT_PAGE_PNG)))
	defer rl.UnloadImage(img)
	parchment_page_tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(parchment_page_tex, .POINT)
}

parchment_art_unload :: proc() {
	rl.UnloadTexture(parchment_page_tex)
}
