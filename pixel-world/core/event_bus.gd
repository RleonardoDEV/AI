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
## kind: see EffectsManager.FX
signal fx_burst(world_pos: Vector2, kind: int, strength: float)
