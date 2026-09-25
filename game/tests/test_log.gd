class_name TestLog
extends RefCounted
## Minimal check counter for the headless UI tests.

var checks := 0
var failures := 0
var section := ""


func begin(name: String) -> void:
	section = name
	print("- " + name)


func ok(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL [%s] %s" % [section, what])
	return cond


func near(a: float, b: float, tol: float, what: String) -> bool:
	return ok(absf(a - b) <= tol, "%s: %.6f vs %.6f (tol %.6f)" % [what, a, b, tol])


func near_v(a: Vector3, b: Vector3, tol: float, what: String) -> bool:
	return ok(a.distance_to(b) <= tol, "%s: %s vs %s (tol %.4f)" % [what, a, b, tol])


func finish(tree: SceneTree, name: String) -> void:
	print("%s: %d checks, %d failures" % [name, checks, failures])
	tree.quit(1 if failures > 0 else 0)
