class_name TestKit
extends RefCounted
## Minimal assertion kit for the headless test runner. Records failures
## instead of aborting, so one broken expectation does not hide the rest.

var checks: int = 0
var failures: Array[String] = []
var current: String = ""

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current, message])
	return condition

func eq(actual, expected, message: String) -> bool:
	return check(actual == expected,
			"%s (got %s, expected %s)" % [message, str(actual), str(expected)])

func approx(actual: float, expected: float, eps: float, message: String) -> bool:
	return check(absf(actual - expected) <= eps,
			"%s (got %.4f, expected %.4f +/- %.4f)" % [message, actual, expected, eps])

func between(value: float, lo: float, hi: float, message: String) -> bool:
	return check(value >= lo and value <= hi,
			"%s (got %.4f, expected within [%.4f, %.4f])" % [message, value, lo, hi])

func at_least(value: float, lo: float, message: String) -> bool:
	return check(value >= lo, "%s (got %.4f, expected >= %.4f)" % [message, value, lo])

func at_most(value: float, hi: float, message: String) -> bool:
	return check(value <= hi, "%s (got %.4f, expected <= %.4f)" % [message, value, hi])

func not_null(value, message: String) -> bool:
	return check(value != null, message)
