class_name SimContext
extends RefCounted
## Everything a system or a creature brain needs, passed by reference so no
## global lookups happen in the hot path.

var world: WorldData
var entities              # EntityManager
var registry: SpeciesRegistry
var climate: Climate
var weather               # WeatherSystem
var stats                 # SimStats
var rng: RandomNumberGenerator
var tick: int = 0
var dt: float = GameConfig.TICK_DT
## Creature update stride in ticks (scales with simulation speed).
var stride: int = 2
## Rectangle currently visible, in cell coordinates (for level-of-detail).
var view_rect: Rect2 = Rect2(0, 0, 256, 256)
