# ADR-0032: A stage is the ship screen reframed, and the entry travels there

## Status

Accepted — **extends ADR-0024** (the voyage UI spine). The Build surface was already "the one refit surface, reused by Offer and Shop stages with a shelf added"; this settles what *reused* means at the pixel level, and adds the move between the two framings. Landed for Offer and Shop ([#476](https://github.com/ssalter21/fantasy-ship-game/issues/476)); Fight and Trade/Reward have not followed yet.

## Context

Issue [#476](https://github.com/ssalter21/fantasy-ship-game/issues/476), out of the prototype in [#475](https://github.com/ssalter21/fantasy-ship-game/issues/475), under the voyage-UI effort.

ADR-0024 says the Build surface is the whole of refit and that the stages reuse it. In practice they did not: Home drew the real galleon as a three-quarter cutaway, and an Offer or Shop drew a flat 2D hull sketch beside a vertical shelf of steel cards. Sailing into a Port cut from one visual language to a different one, and the "same surface" claim was true only of the code that answered which slot a click was over.

The obvious repair — draw the galleon on the stage too — has a framing problem. She is composed for a three-quarter camera that fills the frame; a stage needs half the frame for its stock.

## Decision

**A stage draws the same galleon, from the same painters, under a different camera.** Sky, sea, hull, rooms, ornament, rig, waterline and the berth highlights are one set of procedures with one input: a `Ship_Framing`.

**The framing is chosen by the caller, and the draw and the hit-test are handed the same one.** They each built their own before, which was harmless while there was one framing and a latent bug the moment there were two — a berth painted through one camera and picked through another.

**The stage framing is orthographic, not a side-on perspective camera.** This is the point of the framing rather than a detail of it. Orthographic is the only projection with no convergence anywhere, so every bulkhead is a true rectangle however far off frame centre she sits. A side-on perspective camera is square only near the middle of the frame, and — worse — convergence down her length flattens the berths into a wall of planking, where what makes a room read as a room is being able to see into it as a squared-off compartment.

**She is panned, never turned.** The eye and its target slide together along the camera's right axis. Moving both leaves the view direction untouched, so a broadside stays a broadside however far she slides to port of centre.

**An orthographic framing must have a horizontal view axis, and it is asserted.** Under an orthographic projection a water plane oblique to the view axis has no horizon at all: parallel rays each meet the plane exactly once, so a plane even slightly off edge-on projects over the entire frame and the whole screen is sea. With the axis horizontal the plane is exactly edge-on, world y maps linearly to screen y, and the sea's edge is the row y = 0 lands on.

**Entering a stage travels to its framing rather than cutting to it**, over ~0.9s on smootherstep — zero first *and* second derivative at both ends, because a camera that leaves or arrives with acceleration reads as a jolt on a move this short. The stock is held back to the last stretch and slides in from the edge: paper travelling while the ship is still swinging gives the eye two things moving in different directions at once. The travel plays once per **stop**, not once per screen entry — a Shop re-presents its shelf after every buy.

**The move blends the projection matrices.** The two ends do not share a projection, and lerping the eye then switching at the end pops: canvas snaps from visible to gone and every bulkhead straightens in one frame. A perspective matrix divides by −z and an orthographic one does not, so blending the two component-wise gives a valid projective transform whose convergence falls off smoothly. Both ends stay exact.

**A view therefore carries its projection as a matrix**, and everything that puts a world point on this screen goes through it — the room openings, the picking, the wake, the foam. raylib builds the same matrix inside `BeginMode3D` and again inside `GetWorldToScreenEx` and hands back neither, which is no use to a framing that has to blend two of them.

**Water that belongs to the hull is projected off her own waterline, not off the backdrop's horizon.** From an eye sitting on the water plane the two are the same line, which is why one number served for as long as there was one framing. Part-way through the move the eye is off the plane, y = 0 spreads into a band fifteen pixels deep along her length, and foam pinned to a single painted row floats a dozen pixels clear of her planking. Her waterline is a straight line in world space and a projective transform takes straight lines to straight lines, so interpolating stem to stern is exact.

**Broadside, her canvas is handed and her yards are braced round.** A square yard spans athwartships and a sail bellies fore-and-aft, so from dead abeam the yard points straight at the eye and both project to a spot beside the mast — which is why an orthographic sheer draught of a square-rigger shows bare masts. Furling alone does not answer it: a handed sail on a square yard is a bundle seen end-on. Bracing is what turns the yard and its bundle broadside-on, and the two go together because they are one act — a ship comes alongside by handing her canvas and bracing her yards to clear what she is coming in beside. ADR-0020 already makes mast configuration a cosmetic read-out rather than an input, so there is nothing here for a depiction to contradict.

**Shared chrome keeps its furniture and follows the ground under it.** Every tone in the encounter frame was picked for a body drawn on `COLOUR_DEEP`. A stage whose body is the ship screen's own sky and sea is the brightest surface in the game: there the vignette reads as glass over her, and the tinted header and steel stat line read as almost nothing. The style guide answers both — the framing signal is the torn parchment edge and *not* a dark vignette, and a heading placed over the sea takes cream — so a stage says `over_water` and every piece of furniture is still drawn, in the same place, in the tones its ground calls for.

**The shelf is opaque parchment in one aligned column**: one left edge, one width, one rhythm, cast shadows, prices scanning down a straight line, and a full-width leave control closing the block on the same two edges it opened on. **Unaffordable dims by tone, never by alpha** — translucency costs a panel its own ground, and an alpha-dimmed card let a hull-down island read through it as a stain.

## Consequences

- **A stage's body has no free bottom-right corner.** The hovered-berth description card is thrown clear of the hull into open water, and on a stage the column stands exactly there — so the stages draw the ship without it. The berth still lights under the cursor.
- **The flat cross-section is draw-only.** With the stages on the hull, the only caller left is the Fight, whose two ships are looked at rather than refitted. Its picker (`cutaway_slot_at`) is deleted; giving it one back is a change to make when something needs to pick against it.
- **The category hue is off one screen.** A stage over water names itself in cream rather than in its `stage_tint`, so the node-to-header colour echo ADR-0024 wanted survives in the word and on the map marker, not in the header's ink.
- **The moored framing is unchanged, and provably so.** Every screen that draws her from the shipped eye is byte-identical through the framing lift, the carried projection, the handed canvas at 0, and the waterline change — the shot manifest is what says so, and it named only the two Shop screens.
- **Two more stages are still in the old language.** Fight is a different framing problem (two ships), and Trade and Reward draw no ship at all. The wider direction — every stage screen as the ship screen reframed — only truly lands once those follow.

See GitHub issue [#476](https://github.com/ssalter21/fantasy-ship-game/issues/476) for the ticket, [#475](https://github.com/ssalter21/fantasy-ship-game/issues/475) for the prototype the framing constants were tuned in, ADR-0024 for the spine this extends, and ADR-0020 for the mast read-out the sails call rests on.
