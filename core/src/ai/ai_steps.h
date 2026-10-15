// The decision steps of the AI skippers shared between ai_start.cpp, ai_course.cpp and ai_rules.cpp (ai.md §4–§10).
#pragma once

#include <cstdint>

#include "ai/ai_internal.h"

namespace wm::ai_detail {

using AB = AiSkippers::Boat;
using AC = AiSkippers::Ctx;

// One AI boat as seen in one decision.
struct Me {
  const wm::Boat& b;
  const BoatState& s;
  const RaceBoat& rb;
  const BoatRules& br;
  const EnvAtBoat& env;
  Vec2 c;
  float L, B;
  float tws, twd;   // TWS_f, TWD_f
  float twa;        // wrap_pi(TWD_f − ψ)
  float tack;       // sgn(twa)
  float theta_up, theta_dn, v_up, v_dn;  // polar at TWS_f, speeds scaled by the performance scale
  float scale;
  Vec2 cur;
};
Me me_of(AC& x, AB& a);

// Decision entry (every 0.1 s): ai_course.cpp.
void ai_decide(AC& x, AB& a);

// Polar speed at |twa| with the boat's performance scale.
float polar_speed(const AB& a, const Me& m, float twa_abs);
inline float heading_for(float twd, float twa) { return wrap_2pi(twd - twa); }
// A heading corrected for the current so the course over ground points along `bearing` (ai.md §4.2).
float cog_heading(const Me& m, float bearing, float speed);
// The direction over the ground of heading psi at the speed the boat will make on it, with the current here.
Vec2 cog_dir(const AB& a, const Me& m, float psi);
// The same at the speed the boat will make on that course (her own, at least 0.8 of the polar speed).
float cog_heading_for(const AB& a, const Me& m, float bearing);

// Manoeuvres (§10). `forced`: layline, rules or obstruction triggers (no cooldown or speed check).
bool manoeuvre_checks(AC& x, AB& a, const Me& m, bool forced);
void start_tack(AC& x, AB& a, const Me& m, AiTactic why);
void start_gybe(AC& x, AB& a, const Me& m, AiTactic why);
// Tack if the checks pass (with the entry speed build of §10 when slow); returns true when it started or is
// pending.
bool request_tack(AC& x, AB& a, const Me& m, AiTactic why, bool forced);
bool request_gybe(AC& x, AB& a, const Me& m, AiTactic why, bool forced);

// §6.1: a heading from here runs at the mark being rounded on the wrong side (the circle of the decision's rounding
// plan): it passes the mark closer than ρ + 0.5·L on the wrong side, within ρ + 3·L.
bool into_rounding_mark(const AB& a, const Me& m, float psi);

// Beat or run towards R on the laylines (§4.3, §4.4). `mlay` in hull lengths; `triggers` enables the tactical
// triggers (corridor, shift, pressure, bad air, cover).
void beat_run(AC& x, AB& a, const Me& m, Vec2 R, bool beat, float mlay, bool triggers);
// Sail to a point: beat on laylines when it is upwind, else straight (current corrected).
void sail_to_point(AC& x, AB& a, const Me& m, Vec2 p);

// §7.6 penalty turns: true while a turn owns the helm (ai_course.cpp).
bool penalty_turns(AC& x, AB& a, const Me& m, Leg leg);

// Start (§5): ai_start.cpp.
void free_sailing(AC& x, AB& a, const Me& m);
// §5.2 the fleet's start spots, all AIs together (every decision tick, before the boats decide).
void assign_spots(AC& x);
void prestart(AC& x, AB& a, const Me& m);
void after_gun(AC& x, AB& a, const Me& m);
void hover(AC& x, AB& a, const Me& m, Vec2 S, bool may_loop);
// Race time to reach `spot` from the present state along ψ_app (§5.5).
float time_to_spot(const AB& a, const Me& m, Vec2 spot, float psi_app);
float time_to_spot_go(const AB& a, const Me& m, Vec2 spot);

// Rules (§7): ai_rules.cpp.
// §7.3: false if the manoeuvre onto `psi_new` would leave a boat within 5 L without escape or tacks into the path
// of a boat on the other tack within 3 L.
bool tack_safe(AC& x, AB& a, const Me& m, float psi_new, bool gybe);
// §7.2, §7.4: keeping clear, holding course, rule 17 and the emergency; applied after the plan of the decision.
// `obj_turn`: this decision's heading was turned to pass a course object (§6.4), which holding course never undoes.
void rules_overlay(AC& x, AB& a, const Me& m, Vec2 aim, bool obj_turn = false);
// True when a right-of-way constraint (§7.4 hold course) forbids starting a manoeuvre now.
bool holding_course(AC& x, AB& a, const Me& m);
// Course objects (marks, committee and mark boats) ahead on the planned heading: steer to pass them clear, on the
// side they are on (`skip_mark`: the mark being rounded, which the rounding circle keeps clear). True when it turned
// the heading for one.
bool avoid_objects(AC& x, AB& a, const Me& m, std::int32_t skip_mark);
// §6.5 pinned on an object: the escape, when it runs (ai_course.cpp).
void pinned_escape(AC& x, AB& a, const Me& m);
// §4.6 land, obstacles and the race area: true (and the escape set) when the boat must turn away.
bool land_check(AC& x, AB& a, const Me& m);

// Anticipated wind deficit at a point from the tick's shadow snapshot (§8 anticipation).
float predicted_deficit(AC& x, const AB& a, Vec2 p);

}  // namespace wm::ai_detail
