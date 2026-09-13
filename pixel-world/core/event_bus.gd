extends Node
## Global, decoupled signal hub.
##
## Systems never hold hard references to UI (and vice versa); everything that
## crosses a layer boundary travels through here. Keeps /simulation ignorant of
## /ui, which is what makes the headless simulation mode possible.

# --- World lifecycle -------------------------------------------------------
signal world_generated(world_seed: int)
signal world_loaded(world_seed: int)
signal world_save_completed(slot: String)

# --- Entities --------------------------------------------------------------
signal creature_born(creature)
signal creature_died(creature, cause: int)
signal creature_selected(creature)
signal creature_deselected()
signal species_created(species)

# --- Simulation ------------------------------------------------------------
signal speed_changed(speed: float)
signal tick_advanced(tick: int)
signal day_passed(day: int)
signal year_passed(year: int)

# --- World events / weather ------------------------------------------------
signal world_event_started(event_id: int, label: String)
signal world_event_ended(event_id: int)
signal weather_changed(weather_id: int)

# --- User interaction ------------------------------------------------------
signal tool_selected(tool_id: int)
signal camera_focus_requested(world_pos: Vector2, zoom: float)

# --- Presentation feedback -------------------------------------------------
signal toast(text: String, color: Color)
signal screen_shake(strength: float)
signal screen_flash(color: Color, strength: float)

# --- Effects requests (world space) ---------------------------------------
## Effect kinds carried by `fx_burst`. They live here, on the boundary,
## because the simulation emits them and the effects layer renders them — and
## the simulation is not allowed to depend on the effects layer.
const FX_IGNITE: int = 0
const FX_BURN: int = 1
const FX_SPLASH: int = 2
const FX_BLOOM: int = 3
const FX_DUST: int = 4
const FX_FROST: int = 5
const FX_GUST: int = 6
const FX_METEOR: int = 7
const FX_ERUPT: int = 8
const FX_SPAWN: int = 9
const FX_LIGHTNING: int = 10
## Creature-scale feedback: emitted constantly, so the effects layer
## view-culls and budget-scales these rather than drawing them all.
const FX_HIT: int = 11
const FX_EAT: int = 12
const FX_DRINK: int = 13
const FX_BIRTH: int = 14
const FX_DEATH: int = 15

const FX_FREQUENT: PackedInt32Array = [FX_HIT, FX_EAT, FX_DRINK, FX_BIRTH, FX_DEATH]

signal fx_burst(world_pos: Vector2, kind: int, strength: float)
