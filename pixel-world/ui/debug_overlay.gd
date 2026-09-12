extends PanelContainer
## Performance overlay: frame rate, entity counts, simulation scheduling and
## the split between simulation and render time.

var sim: Simulation
var main: Node
var _label: Label
var _t: float = 0.0
var _fps: float = 60.0

func setup(simulation: Simulation, main_node: Node) -> void:
	sim = simulation
	main = main_node
	add_theme_stylebox_override("panel", UITheme.panel(8, Color(0.02, 0.03, 0.05, 0.82)))
	_label = UITheme.label("", 9, Color(0.62, 0.95, 0.72))
	add_child(_label)

func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_fps = lerpf(_fps, 1.0 / maxf(0.0001, delta), 0.1)
	_t += delta
	if _t < 0.2:
		return
	_t = 0.0
	var p := sim.profiler
	var ent: int = main.entity_view.drawn_count if main != null else 0
	var flo: int = main.flora_view.drawn_count if main != null else 0
	_label.text = ("FPS %5.1f  (frame %.1f ms)\n"
		+ "entities %d / %d   drawn %d   flora %d/%d\n"
		+ "tick %s   ticks/frame %d   stride %d   budget %d\n"
		+ "sim  creatures %.2f  grid %.2f  world %.2f\n"
		+ "     growth %.2f  flora %.2f  weather %.2f\n"
		+ "process %.2f ms   particles %d+%d   fires %d   wet %d\n"
		+ "draw calls %d   objects %d   vram %.1f MB") % [
		_fps, main.frame_ms() if main != null else 0.0,
		sim.population(), GameConfig.MAX_CREATURES, ent, flo, sim.flora.count,
		HudFormat.commas(sim.tick), sim.last_ticks(), sim.stride, sim.update_budget(),
		p.avg("creatures"), p.avg("grid"), p.avg("world"),
		p.avg("growth"), p.avg("flora"), p.avg("weather"),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		main.effects.pool.count if main != null else 0,
		main.effects.glow_pool.count if main != null else 0,
		sim.world.burning_cells.size(), sim.world.wet_cells.size(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0]
