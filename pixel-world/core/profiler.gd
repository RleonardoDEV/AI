class_name Profiler
extends RefCounted
## Rolling-average timing buckets for the debug overlay.

const WINDOW: int = 30

var _samples: Dictionary = {}
var _starts: Dictionary = {}

func begin(key: String) -> void:
	_starts[key] = Time.get_ticks_usec()

func end(key: String) -> void:
	if not _starts.has(key):
		return
	var dt := float(Time.get_ticks_usec() - int(_starts[key])) / 1000.0
	var arr: PackedFloat32Array = _samples.get(key, PackedFloat32Array())
	arr.append(dt)
	if arr.size() > WINDOW:
		arr = arr.slice(arr.size() - WINDOW)
	_samples[key] = arr

## Average duration in milliseconds.
func avg(key: String) -> float:
	if not _samples.has(key):
		return 0.0
	var arr: PackedFloat32Array = _samples[key]
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v
	return s / float(arr.size())
