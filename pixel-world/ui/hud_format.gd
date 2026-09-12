class_name HudFormat
extends RefCounted
## Small shared formatting helpers for the interface.

static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

static func duration(days: float) -> String:
	var years := int(days / float(GameConfig.DAYS_PER_YEAR))
	var d := days - float(years * GameConfig.DAYS_PER_YEAR)
	return "%dy %.1fd" % [years, d]
