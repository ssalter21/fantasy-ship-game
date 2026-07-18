package main

import rl "vendor:raylib"

// Sourced art, embedded in the binary the same way the font is (ui.odin): ADR-0009
// commits to a self-contained game.exe, which a sidecar .png breaks. This is the
// Chart Table's sourced background — the #284 carve-out the style guide reserves
// (docs/ui/style-guide.md, "What this guide does not cover"): the screen's ground was
// drawn from the ramp (#294) as a placeholder "only in ambition", and #284 anticipated
// a sourced image as an improvement in *depiction*.
//
// It was generated through the PixelLab MCP from a dusk-tropical-island prompt steered
// onto the ramp, then conformed: measured at peak luminance 142 (below the title's
// ~211, so it cannot outshine the chrome — the guide's hard rule), carrying zero warm
// pixels (so it spends none of the amber the button reserves), and with the trial
// watermark painted out. 400x272 at native resolution, POINT-scaled to the window.
MENU_ISLAND_PNG :: #load("../../assets/art/menu-island.png")

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
