class_name HudValues
extends RefCounted
## The values behind the minimal HUD (hud.md §2, §3.1, §4 polar speed, §5): the core's values of the tick, shown
## without display smoothing (hud.md §1). A placeholder for the core's HudValues record: same definitions, computed
## here from SimSource until the binding provides it.

const DT := SimSource.DT
const TOL_DEFAULT := deg_to_rad(2.0)
const TOL_STEP := deg_to_rad(0.1)
const TOL_MAX := deg_to_rad(30.0)
const POLAR_MIN := 0.3 * HudFormat.KNOT  # m/s: no polar target below this polar speed

enum Colour { NONE, GREEN, YELLOW, RED }


## one trim gauge (hud.md §5)
class Gauge:
	var sail := -1
	var name := ""
	var eps := 0.0
	var e := 0.0  # normalised error, [-2, 2]
	var needle := 0.0  # e, 0 with auto trim
	var colour := Colour.NONE
	var telltale := ""
	var auto := false
	var greyed := false


var bsp := 0.0  # m/s (v_filt)
var sog := 0.0  # m/s
var cog := 0.0
var hdg := 0.0
var heel := 0.0  # signed phi
var h := 0.0
var h_cmd := 0.0
var tws := 0.0
var twa := 0.0  # signed: the core's twa, heading against the true wind direction
var twd := 0.0
var aws := 0.0
var awa := 0.0  # signed
var polar_speed := NAN  # m/s, V_pol at the present TWA; NAN below 0.3 kn (head to wind)
var sheet_cmd := 0.0
var auto_trim := true
var let_fly := false
## front sail up ("" = main only), the sail being hoisted and its progress
var sail_up := ""
var sail_hoisting := ""
var hoist_progress := 0.0
var gauges: Array[Gauge] = []
## h_cmd, sheet_cmd, auto_trim and let_fly come from the local controls (set_commands), not from the sim's
## controls record
var commands_local := false

var _tol_cache := {}


## The player's own commands of this frame (PlayerControls): helm command, sheet, auto-trim, let fly.
## Returns true when one of them changed.
func set_commands(c: PlayerControls) -> bool:
	var h_new := clampf(c.h_cmd, -1.0, 1.0)
	var sheet_new := clampf(c.sheet_cmd, 0.0, 1.0)
	commands_local = true
	var changed := h_new != h_cmd or sheet_new != sheet_cmd or c.auto_trim != auto_trim or c.let_fly != let_fly
	h_cmd = h_new
	sheet_cmd = sheet_new
	auto_trim = c.auto_trim
	let_fly = c.let_fly
	return changed


## Once per tick, after the step.
func tick(sim: SimSource, boat: int) -> void:
	var s := sim.state(boat)
	var o := sim.outputs(boat)
	var c := sim.controls(boat)
	var sv := sim.sails(boat)
	var info := sim.class_info(boat)
	bsp = s.v_filt
	sog = Vector2(s.sog_filt_x, s.sog_filt_y).length()
	cog = o.cog
	hdg = s.psi
	heel = s.phi
	h = s.h
	if not commands_local:
		h_cmd = c.h_cmd
		sheet_cmd = c.sheet_cmd
		auto_trim = c.auto_trim
		let_fly = c.let_fly
	tws = s.tws
	twa = s.twa
	twd = s.twd_from
	aws = s.aws
	awa = s.awa
	polar_speed = o.polar_speed if o.polar_speed >= POLAR_MIN else NAN
	sail_up = info.sails[sv.front].name if sv.front >= 0 else ""
	sail_hoisting = ""
	hoist_progress = 0.0
	var run := sv.running()
	if run != null and run.sail != sv.front and (run.phase == SimSource.Phase.PREPARE_HOIST \
			or run.phase == SimSource.Phase.HOISTING):
		sail_hoisting = info.sails[run.sail].name
		hoist_progress = sv.sails[run.sail].progress
	_gauges(sim, boat, s, sv, info, auto_trim)


func _gauges(sim: SimSource, boat: int, s: SimSource.BoatState, sv: SimSource.SailsView,
		info: SimSource.ClassInfo, auto: bool) -> void:
	var want: Array[int] = [info.main_sail]
	if sv.front >= 0:
		want.append(sv.front)
	var keep: Array[Gauge] = []
	for i in want:
		var g: Gauge = null
		for old in gauges:
			if old.sail == i:
				g = old
		if g == null:
			g = Gauge.new()
			g.sail = i
			g.name = info.sails[i].name
		keep.append(g)
	gauges = keep
	var tol := trim_tolerance(sim, boat, s.tws, absf(s.awa))
	for g in gauges:
		var so: SimSource.SailOutput = sv.out[g.sail]
		var ph: int = sv.sails[g.sail].phase
		g.greyed = ph != SimSource.Phase.UP and ph != SimSource.Phase.DOWN
		g.auto = auto
		g.eps = so.trim_error
		g.e = clampf(g.eps / tol.x if g.eps >= 0.0 else g.eps / tol.y, -2.0, 2.0)
		if auto:
			g.needle = 0.0
			g.colour = Colour.NONE
		else:
			g.needle = g.e
			var ae := absf(g.e)
			g.colour = Colour.GREEN if ae <= 0.5 else (Colour.YELLOW if ae <= 1.0 else Colour.RED)
		if g.e > 1.0 or so.luff_shiver > 0.5:
			g.telltale = "Luffing: sheet in"
		elif g.e < -1.0:
			g.telltale = "Stalled: ease"
		elif so.backed:
			g.telltale = "Aback"
		else:
			g.telltale = "Flowing"


## hud.md §5: the trim errors (+, -) at which the config's trim_speed falls to 0.98, stepping 0.1 deg out to
## 30 deg, cached per 0.5 m/s of TWS and 1 deg of AWA; +-2 deg without a table. Returns (tol+, |tol-|).
func trim_tolerance(sim: SimSource, boat: int, tws_now: float, awa_abs: float) -> Vector2:
	var tq := roundf(tws_now / 0.5) * 0.5
	var aq := deg_to_rad(roundf(rad_to_deg(awa_abs)))
	var front := sim.sails(boat).front
	var key := "%d:%.1f:%.0f" % [front, tq, rad_to_deg(aq)]
	if _tol_cache.has(key):
		return _tol_cache[key]
	var res := Vector2(TOL_DEFAULT, TOL_DEFAULT)
	if not is_nan(sim.trim_speed_at(boat, tq, aq, 0.0)):
		res = Vector2(_find(sim, boat, tq, aq, 1.0), _find(sim, boat, tq, aq, -1.0))
	_tol_cache[key] = res
	return res


func _find(sim: SimSource, boat: int, tq: float, aq: float, sgn_: float) -> float:
	var e := TOL_STEP
	while e <= TOL_MAX + 1e-9:
		if sim.trim_speed_at(boat, tq, aq, sgn_ * e) <= 0.98:
			return e
		e += TOL_STEP
	return TOL_MAX
