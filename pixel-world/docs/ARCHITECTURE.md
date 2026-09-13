# PIXEL WORLD — architecture

This document explains how the pieces fit together and, more usefully, *why*
each one is shaped the way it is. Sizes and timings quoted here were measured
with `tools/bench.tscn` and the in-game debug overlay.

---

## 1. Layers

```
                      ┌──────────────┐
                      │   EventBus   │  global signal hub (autoload)
                      └──────┬───────┘
      ┌──────────────────────┼──────────────────────┐
      │                      │                      │
┌─────▼──────┐        ┌──────▼───────┐       ┌──────▼──────┐
│ simulation │        │  rendering   │       │     ui      │
│            │        │              │       │             │
│ Simulation │───────▶│ Terrain      │       │ HUD         │
│ SimContext │  read  │ Entities     │       │ Tools       │
│ SimStats   │  only  │ Flora        │       │ Minimap     │
└─────┬──────┘        │ Sky / Camera │       │ Inspector   │
      │               └──────────────┘       │ Statistics  │
      │                                      │ Evo tree    │
┌─────▼──────────────────────────────┐       │ Debug       │
│ entities   ai   genetics   world   │       └─────────────┘
│ biomes     procedural              │
└────────────────────────────────────┘
```

The rule is one-directional: `simulation/` and everything below it never
reference `rendering/` or `ui/`. Anything that has to cross a boundary goes
through `EventBus`. This is not architectural decoration — it is what makes
`tools/headless_sim.tscn` and the test suite possible, since the entire
simulation runs with no renderer, no window and no UI nodes in the tree.

`scenes/main.gd` is the only place the layers are wired together. The scene
file itself is a single node; the whole tree is built in code so the wiring
is readable in one pass and nothing depends on editor state.

---

## 2. World state: structure of arrays

`WorldData` holds the world as parallel packed arrays, one entry per cell:

| Array | Type | Purpose |
|---|---|---|
| `terrain` | `PackedByteArray` | current material (14 types) |
| `biome` | `PackedByteArray` | classification (14 biomes) |
| `elevation`, `moisture` | `PackedFloat32Array` | generated fields |
| `base_temp`, `temperature` | `PackedFloat32Array` | climate baseline, live field |
| `veg`, `fire`, `water`, `snow` | `PackedFloat32Array` | live ecology |
| `shade`, `variation`, `shore` | `PackedByteArray` | baked presentation data |

At 256×256 that is ~2.3 MB total. Why arrays rather than cell objects or a
TileMap:

- 65k cells iterate cache-friendly; the growth sweep touches ~2,700 cells a
  frame and costs ~2 ms in GDScript.
- The renderer bakes straight from these arrays into an `Image` without
  touching the scene tree.
- Saving is a block copy, not a graph walk.

Three lists make the sparse systems cheap: `burning_cells` and `wet_cells`
(so fire and water cost nothing when the world is calm) and `dirty_cells`
(cells whose albedo changed and need re-baking). `dirty_cells` is capped at a
quarter of the grid — past that it is cheaper to re-bake everything, and the
cap also keeps the queue bounded in headless runs where nothing flushes it.

A fourth list, `modified`, records cells whose *terrain or elevation* differs
from what the generator would produce. That list is the save file.

### Bulk edits

`set_terrain` normally refreshes the shoreline band around the changed cell.
For a single edit that is right; for a meteor crater it was catastrophic —
~800 cells × 25 neighbours × a 32-lookup shore computation, which showed up
as a visible hitch. Area tools now wrap their work in
`begin_bulk_edit()` / `end_bulk_edit()`, which defers the shoreline pass to
one regional recomputation.

---

## 3. Generation

`WorldGen.generate(world, seed)` is deterministic and takes ~600 ms for
256×256.

```
warped fractal relief + ridged mountains
        │
        ├── bake hillshade from the RAW relief   ← relief is what the eye reads
        │
   archetype falloff (continent / archipelago / lakeland / pangaea)
        │
   histogram remap to exact band coverage
        │
   rivers (steepest descent on the SMOOTH relief, with momentum)
        │
   distance field to water ──▶ moisture
        │
   latitude + lapse rate + noise ──▶ temperature
        │
   biome classification ──▶ terrain materials
        │
   volcanism, shoreline band, vegetation, flora scatter
```

Two steps deserve explanation because both were bugs first:

**The histogram remap.** Raw noise, even normalised, puts a wildly different
fraction of the map above any fixed threshold from seed to seed. The first
implementation produced worlds that were 89% land and mostly grey rock. The
fix builds a 512-bin CDF, converts each cell's elevation to its *rank*, and
then maps rank through an explicit piecewise curve: 45% of the water column
is abyss, 43% open water, 12% shallows; 4% of the land is coast, 84% the
habitable band, 12% highland. Water coverage per archetype is then exact.

**Rivers path on the relief, not the remapped field.** The remap creates
plateaus, and a steepest-descent walk over plateaus terminates immediately —
the first version produced isolated blue dots instead of rivers. Pathing on
the smooth pre-remap relief, with a small momentum bias and a small random
jitter, produces winding rivers that reach the sea. (The momentum bias also
has to be small: at 0.02 it overwhelmed the local gradient and every river
came out a dead-straight diagonal line.)

Hillshade is baked from the raw relief for the same reason: the remap
flattens the field for classification, but the gradient is what gives the map
its sense of depth.

---

## 4. Scheduling: how 100× costs the same as 1×

`Simulation.advance(real_delta, view)` runs once per rendered frame.

```
sim_dt = speed × real_delta              accumulate simulated time
ticks  = sim_dt / TICK_DT                how many fixed ticks that is
if ticks > MAX_TICKS_PER_FRAME:          ← time compression
    dt_per_tick = accumulated / MAX      fold the excess into a bigger dt
    ticks = MAX
stride = ceil(population × ticks / budget)   ← adaptive striding
for each tick:
    creatures where (tick + id) % (stride × lod) == 0 update with dt × step
world systems: fire (≤4 substeps), water (≤2), growth/flora (1 chunk), weather
```

Three mechanisms, each solving a different problem:

**Time compression** bounds the number of ticks per frame. Without it, 100×
needs 33 ticks a frame and the frame rate falls apart.

**Adaptive striding** bounds the number of creature updates per frame.
Creatures update in slices with a proportionally larger `dt`; the budget
itself is tuned each frame against measured frame time (shrink below ~52 FPS,
grow above ~75). The consequence is the important part: the same build holds
its frame rate on a phone and runs at higher resolution on a desktop, because
what degrades under load is simulation granularity, not smoothness.

The stride cap must be generous. It was originally 16, which meant the budget
could not actually be met at 100× — the frame rate collapsed instead of the
update resolution. It is now 64.

**Chunked sweeps** bound the whole-grid systems. Growth, thermal relaxation
and flora each process `1/SLICES` of their domain per frame with `dt × SLICES`,
so a cell is visited once per sweep and advances by the right amount on
average. Cost per frame is constant regardless of speed.

Perception is scheduled in *updates*, not seconds: at 100× a single update
covers seconds of world time, so a time-based cooldown fires every update and
searching dominates the frame. Creatures scan neighbours every 3rd update and
search for resources every 6th.

---

## 5. The creature hot path

One creature update costs ~25 µs on a desktop core, and everything about its
shape follows from that number.

```
needs          age, hunger, thirst, energy, damage, healing, breeding drive
               ~40 float ops, one inlined cell index
scavenging     only when carnivorous, hungry, and carrion exists (compact list)
perception     every 3rd update: capped grid query + ≤24 candidates
searching      every 6th update: 6 directional probes × 2–3 ranges
scoring        11 behaviours, inline comparisons, no allocation
acting         state body + flocking + steering + hard terrain constraint
```

Measured savings from the optimisation pass (`tools/bench.tscn`):

| Function | Before | After | Change |
|---|---|---|---|
| `Perception.scan` | 31.0 µs | 17.1 µs | capped candidates, hoisted members |
| `Perception.find_water` | 31.9 µs | 12.4 µs | inlined index + drinkability |
| `Perception.find_forage` | 15.9 µs | 8.2 µs | inlined index, no trig |

The specific culprits are worth naming because they are easy to repeat:

- **Allocating in the scoring block.** The first version built an
  `Array` of `[state, score]` pairs every update. That allocation cost more
  than the rest of the decision put together.
- **`Vector2.rotated()` per probe.** Replaced with a rotating probe subset
  keyed off the creature id: every animal still searches differently, but no
  sin/cos runs in the loop.
- **`Vector2.angle()` for facing.** Replaced with an octant comparison —
  three branches instead of an `atan2`.
- **`world.idx_at()`** in probe loops. Positions are already clamped inside
  the world by movement, so bounds work is redundant: `int(y) * w + int(x)`.
- **Uncapped spatial queries.** Creatures flock, so one bucket neighbourhood
  can legitimately hold hundreds of animals. An uncapped query makes
  perception O(population) per creature — a real O(n²) trap that only appears
  once the population is large enough to matter.

---

## 6. Emergence, and the balance bugs that hid it

Behaviour is scored, not scripted. Each of the eleven behaviours gets a
utility from needs and context; the current behaviour gets a small bonus so
animals commit to a course of action.

Getting interesting behaviour out of that was mostly a matter of removing
things that silently prevented it. Each of these was found by running the
headless census and asking why a number was wrong:

| Symptom | Cause | Fix |
|---|---|---|
| 73 drownings in 14 simulated days | Water avoidance was a steering *preference*; fleeing herds ran into the sea | Impassable terrain is a hard movement constraint, with axis-separated sliding so animals run *along* a coast |
| 106 deaths of thirst beside the ocean | Only water cells were drinkable, and deep water was now impassable | The baked shoreline band is drinkable — animals drink from the bank |
| Populations starving while breeding | Full reproductive drive scored above hunger and thirst | Courtship utility is scaled by satiety |
| Every carnivore lineage extinct | Density stress counted *all* neighbours, and predators live inside prey herds — so they could never breed | Density stress counts conspecifics only |
| Carnivores permanently below breeding energy | Movement cost was quadratic in speed; one chase bankrupted a fast predator | Linear movement cost, bigger meals, resting recovery |
| Predators wiping out their own prey, then starving | Hunt utility stayed high when fed | Fed predators do not hunt |
| One species crowding out all others | Nothing opposed an r-strategist that won first | A species past ~42% of the biosphere breeds against rising resistance |

Speciation is emergent too. `SpeciesRegistry.classify` compares each newborn
against its parent species' centroid and founds a new species past a
weighted-distance threshold, recording the ancestor. Two guards keep the tree
meaningful: a parent needs at least three members before it can split (so a
single freak mutant cannot fragment a lineage), and macro mutations — six
times the normal sigma, 2.5% of the time — are what actually push a lineage
over the line instead of leaving it to drift forever.

---

## 7. Rendering

| Layer | Node | Cost |
|---|---|---|
| Ocean backdrop | `Sprite2D` + shader | 1 draw call |
| Terrain | `Sprite2D` + shader | 1 draw call |
| Flora | `Node2D` custom draw | ~2 batches |
| Creatures | `Node2D` custom draw | ~3 batches |
| Particles | 2 × `Node2D` (opaque + additive) | 2 batches |
| Sky | `CanvasLayer`, 2 full-screen quads | 2 draw calls |

**The terrain is one sprite**, one texel per cell, with the entire ambient
look in a single fragment shader: depth-aware animated water, moving
shoreline foam, wind ripples over vegetation, lava and fire emission, cloud
shadows, rain wetness, snow sparkle, heat shimmer. A second RGBA texture
carries the per-cell data the shader needs (R fire, G shoreline proximity,
B vegetation, A material class, quantised so nearest sampling preserves it).
Both textures are re-baked only for dirty cells and uploaded at most once a
frame.

**Sprites are implicit shapes.** `PixelArt` samples a shape function in a
rotated local frame to produce 8 directions × 2 animation frames per species.
Nothing rotates at runtime, so the art stays pixel-perfect, and body
proportions are free to follow the genome. Greys are chosen so `modulate` by
the DNA colour yields a shaded, outlined creature — the rim is near-black
(0.10) specifically so a silhouette survives against similarly-coloured
ground.

**Draw passes are grouped by texture.** Godot batches consecutive draws that
share a texture, so drawing shadow → body → detail per creature turned every
animal into three draw calls. Grouping into three passes over the visible set
took a typical frame from ~1400 draw calls to ~350.

**Everything is lit by one grade.** `Climate` produces an ambient colour from
the time of day; the terrain shader multiplies by it, and flora and creature
layers take it as `modulate`. Emissive terms (fire, lava, glints) are added
*after* the grade and scaled up at night, so a fire at 3 a.m. glows instead
of going grey.

---

## 8. Persistence

```
save = seed
     + delta      (cells whose terrain/elevation was permanently changed)
     + veg, snow, water   (quantised to 1 byte per cell, gzip-friendly)
     + creatures  (parallel arrays: pos, vel, genome, vitals, memory)
     + species registry, climate, weather, statistics, flora
```

Loading regenerates the world from the seed and replays the delta.
Temperature, hillshade and the shoreline band are recomputed rather than
stored. The file is tens of kilobytes for a 65k-cell world with 500 animals,
and because the baseline comes from the same deterministic generator, a load
cannot drift from what generation would produce.

---

## 9. Scaling up

The current world is 256×256 with up to 520 creatures — sized for a phone.
The parts that would need attention for a much larger world, in order:

1. **Terrain texture uploads.** One 256×256 RGBA upload is 256 KB and
   negligible; a 1024×1024 world is 4 MB a frame. The fix is chunked terrain
   sprites (say 64×64 cells each) so only dirty chunks upload. The renderer
   is already driven by a dirty-cell list, so this is a change to
   `TerrainRenderer` alone.
2. **Chunk sweep divisors.** `GrowthSystem.SLICES` and `FloraSystem.SLICES`
   are fixed; they would scale with cell count to keep per-frame cost flat.
3. **Creature budget.** Already adaptive, so a bigger world simply runs at a
   coarser stride. The floor (`CREATURE_UPDATES_MIN`) is where perceived
   liveliness eventually suffers.
4. **Spatial grid cell size.** Tuned for the current density
   (`GameConfig.GRID_CELL = 8`); a much larger or denser world wants it
   re-tuned against `local_density` measurements.

Nothing in the simulation assumes a particular world size — `WorldData` takes
its dimensions as constructor arguments and every system reads `world.w` /
`world.h`.
