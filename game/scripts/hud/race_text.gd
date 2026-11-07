class_name RaceText
extends RefCounted
## Player-facing race texts of hud.md: the rule texts of §12.3, flags and signals (§9.1), start consequences
## (§9.2), rules awareness (§11) and score codes. No em dashes in any of them.

## rules.md §11.3 rule codes (WM_RULE_*), in the C API's order
enum Rule { NONE, R10, R11, R12, R13, R14, R15, R16_1, R16_2, R17, R18_2, R18_3, R18_4, R19, R20, R21_1, R21_2,
	R31, LATE, C_PREP, C_ENTRY, SI_BOUNDARY }
## race.md §0 race types (WM_RACE_*)
const RACE_MATCH := 1
## race.md §3.3 prep flags (WM_FLAG_*)
enum Flag { P, I, Z, U, BLACK }
## race.md §3.1 (WM_RACE_*)
enum RaceState { CREATED, FREE_SAILING, SEQUENCE, RACING, CLOSING, CLOSED, ABANDONED }
## race.md §3.2 (WM_SEQUENCE_*)
enum Sequence { S5410, S3210, MATCH }
## race.md §11 (WM_EV_*)
enum Ev { SIGNAL, BOAT_OCS, BOAT_RETURNED, STARTED, ROUNDED, FINISH_BLOCKED, FINISHED, GHOSTED, RETIRED, JOINED,
	LEFT, WINDOW_WARNING, RACE_CLOSING, RACE_CLOSED, ABANDONED }
## race.md §6.3 why a boat became a ghost (WM_GHOST_*)
enum Ghost { NONE, FINISHED, RETIRED, DSQ, UFD, BFD, DNF, DNS, LEFT }
## race.md §11 signal kinds (WM_SIGNAL_*)
enum SignalKind { WARNING, PREP_UP, PREP_DOWN, START, GENERAL_RECALL, X_UP, X_DOWN }
## rules.md §11.3 (WM_REV_*)
enum Rev { RULE_WARNING, INCIDENT, PENALTY, PENALTY_SERVED, PENALTY_CANCELLED, PENALTY_LATE, MARK_TOUCH,
	PROTESTABLE, PROTESTED, DISQUALIFIED }
## rules.md §9.3 why the last started penalty turn was reset (WM_TURN_RESET_*)
enum TurnReset { NONE, PAUSED, REVERSED, ZONE, ROUNDED }
## hud.md §12.1 the panel's reset text by reason
const TURN_RESET_TEXT := ["", "Turn reset: paused", "Turn reset: turned back", "Turn reset: inside the zone",
	"Turn reset: mark rounded"]
## rules.md §11.1 keep-clear and room states (WM_KC_*)
enum Kc { CLEAR, WARNING, BREACH }
## courses.md steps (WM_STEP_*), marks (WM_MARK_*), sides (WM_SIDE_*)
enum Step { START, MARK, GATE, FINISH }
enum Side { PORT, STARBOARD }
## race.md §9 score codes (WM_SCORE_*)
const SCORE := ["", "ZFP", "DNC", "DNS", "OCS", "UFD", "BFD", "DNF", "RET", "DSQ"]

## hud.md §12.3 by code name
const RULE_TEXT := {
	"10": "Port tack keeps clear of starboard",
	"11": "Windward boat keeps clear",
	"12": "Boat clear astern keeps clear",
	"13": "Tacking boat keeps clear",
	"14": "Avoid contact",
	"15": "Give room after gaining right of way",
	"16.1": "Changing course: give room to keep clear",
	"16.2": "Don't bear away onto a ducking port boat",
	"17": "Don't sail above your proper course",
	"18.2": "Give mark-room",
	"18.3": "Tacked in the zone: keep clear",
	"18.4": "Gybe at the mark, don't sail wide",
	"19": "Give room at the obstruction",
	"20": "Room to tack at an obstruction",
	"21.1": "Returning starter keeps clear",
	"21.2": "Boat taking a penalty keeps clear",
	"31": "Touched a mark",
	"44.2-late": "Penalty not taken within 2 minutes",
	"C-prep": "Not outside the line at the preparatory signal",
	"C-entry": "Did not enter through the line in time",
	"SI-boundary": "Outside the race area",
	"29.1": "Over early (P flag)",
	"30.1": "Over early (I flag)",
	"30.2": "Over early (Z flag)",
	"30.3": "Over early (U flag)",
	"30.4": "Over early (black flag)",
}
## code names in Rule order (wm_rule_code_name)
const RULE_CODES := ["", "10", "11", "12", "13", "14", "15", "16.1", "16.2", "17", "18.2", "18.3", "18.4", "19",
	"20", "21.1", "21.2", "31", "44.2-late", "C-prep", "C-entry", "SI-boundary"]
## hud.md §9.1 signal banner, the prep flag's meaning
const PREP_MEANING := [
	"P flag: be behind the line at the start",
	"I flag: over in the last minute means round an end",
	"Z flag: in the triangle in the last minute is a scoring penalty",
	"U flag: in the triangle in the last minute is a disqualification",
	"Black flag: in the triangle in the last minute is a disqualification",
]
## hud.md §9.2 consequence of being over in the last minute, per prep flag
const OVER_CONSEQUENCE := [
	"P flag: be back behind the line at the gun",
	"I flag: round an end",
	"Z flag: scoring penalty",
	"U flag: disqualification",
	"Black flag: disqualification",
]


static func code(rule: int) -> String:
	return RULE_CODES[rule] if rule >= 0 and rule < RULE_CODES.size() else ""


## hud.md §12.3 short text of a rule (by Rule value or code name)
static func rule_text(rule: Variant) -> String:
	var c: String = code(int(rule)) if (rule is int or rule is float) else str(rule)
	return RULE_TEXT.get(c, "Rule %s" % c)


## hud.md §9.1 banner for a signal (flag: the prep flag shown)
static func signal_banner(kind: int, flag: int) -> String:
	match kind:
		SignalKind.WARNING:
			return "Warning signal: class flag up"
		SignalKind.PREP_UP:
			return "Preparatory signal, " + PREP_MEANING[clampi(flag, 0, 4)]
		SignalKind.PREP_DOWN:
			return "One minute"
		SignalKind.START:
			return "Start"
		SignalKind.GENERAL_RECALL:
			return "General recall: the start is sailed again"
		SignalKind.X_UP:
			return "Individual recall: X flag"
		SignalKind.X_DOWN:
			return "X flag down"
	return ""


## hud.md §9.2 OCS instruction after the gun
static func ocs_instruction(ocs_i: bool) -> String:
	return "OCS: return around an end" if ocs_i else "OCS: return behind the line"


## hud.md §11 right of way in plain words (for the holder, while the other boat is in Warning)
static func right_of_way_call(rule: int) -> String:
	match rule:
		Rule.R10:
			return "Starboard!"
		Rule.R11:
			return "Leeward!"
		Rule.R12:
			return "Clear ahead: right of way"
		Rule.R13:
			return "She is tacking: right of way"
	return "Right of way"


static func score(code_value: int) -> String:
	return SCORE[code_value] if code_value >= 0 and code_value < SCORE.size() else ""


## 1st, 2nd, 3rd, 4th ...
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]
