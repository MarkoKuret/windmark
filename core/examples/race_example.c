/* A headless race through the C API only (include/windmark.h): the example venue and its windward-leeward
 * course, four boats of the shipped classes steered by a small scripted skipper in the step-2 controller, from
 * the spawn to the results. The race runs twice with the same seed and must give the same checksum; then one
 * boat sails freely in a world without a race.
 *
 *   windmark_race_example [data_dir] [courses_dir]
 *
 * Exit code 0 when the race closed with every boat scored, both runs agree, and the free-sailing boat moved.
 * The skipper is example code, not the computer skipper of ai.md; its own arithmetic is plain C floats. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "windmark.h"

#define N_BOATS 4
#define PI_F 3.14159274f
#define DEG_F 0.0174532924f

static float wrap_pi(float a) {
  while (a >= PI_F) a -= 2.0f * PI_F;
  while (a < -PI_F) a += 2.0f * PI_F;
  return a;
}
static float wrap_2pi(float a) {
  while (a >= 2.0f * PI_F) a -= 2.0f * PI_F;
  while (a < 0.0f) a += 2.0f * PI_F;
  return a;
}
static float compass(float vx, float vy) { return wrap_2pi(atan2f(vx, vy)); }
static float clampf(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }

typedef struct skipper {
  int tack;             /* +1 starboard, -1 port, for beating */
  int turning;          /* doing a penalty turn */
  int ret_stage;        /* returning around an end: 0 out, 1 back below */
  float turn_dir;
  float turn_started;
  float slow_time, unstick_until;
} skipper;

typedef struct pilot {
  skipper b[N_BOATS];
} pilot;

static void helm_to(wm_world* w, int i, const wm_boat_state* s, float want, float limit) {
  const float e = wrap_pi(want - s->psi);
  const float h = clampf(2.5f * e, -limit, limit);
  wm_world_set_helm(w, i, s->v < 0.0f ? -h : h);
}

/* Toward a target, beating on the laylines when it is upwind. */
static void sail_to(wm_world* w, int i, skipper* k, const wm_boat_state* s, float tx, float ty, float twd,
                    float tws) {
  const wm_perf* perf = wm_world_boat_perf(w, i);
  float up_twa = 0.7f;
  wm_perf_polar_vmg(perf, tws > 0.5f ? tws : 4.0f, NULL, &up_twa, NULL, NULL);
  const float th = up_twa + 3.0f * DEG_F;
  const float beta = compass(tx - s->pos_x, ty - s->pos_y);
  const float twa_t = wrap_pi(twd - beta);
  const float cur_twa = wrap_pi(twd - s->psi);
  if (fabsf(twa_t) < th) {
    if (fabsf(cur_twa) < 0.5f * PI_F) k->tack = cur_twa >= 0.0f ? 1 : -1;
    if (k->tack == 1 && twa_t <= -(th - 6.0f * DEG_F)) k->tack = -1;
    if (k->tack == -1 && twa_t >= th - 6.0f * DEG_F) k->tack = 1;
    helm_to(w, i, s, wrap_2pi(twd - (float)k->tack * th), 0.7f);
    return;
  }
  float want = beta;
  if (fabsf(twa_t) > 170.0f * DEG_F) want = wrap_2pi(twd - (twa_t >= 0.0f ? 1.0f : -1.0f) * 170.0f * DEG_F);
  helm_to(w, i, s, want, 0.6f);
}

static void steer(wm_world* w, pilot* p, int i, float t) {
  skipper* k = &p->b[i];
  wm_boat_state s;
  wm_boat_env env;
  wm_race_boat rb;
  wm_boat_rules br;
  wm_world_boat_state(w, i, &s);
  wm_world_boat_env(w, i, &env);
  wm_world_race_boat(w, i, &rb);
  wm_world_boat_rules(w, i, &br);
  const float twd = env.wind_from_clean, tws = env.wind_speed_clean;

  wm_step start;
  wm_mark a, b;
  wm_world_course_step(w, 0, &start);
  wm_world_course_mark(w, start.marks[0], &a);
  wm_world_course_mark(w, start.marks[1], &b);
  const float mx = 0.5f * (a.x + b.x), my = 0.5f * (a.y + b.y);
  const float ul = sqrtf((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
  const float ux = (b.x - a.x) / ul, uy = (b.y - a.y) / ul;
  const float upx = -uy, upy = ux; /* toward the course side */

  if (rb.ghost || rb.finished) {
    helm_to(w, i, &s, compass(upx, upy), 0.6f);
    return;
  }
  /* In irons or pinned for 6 s: bear away onto a reach for 8 s. */
  k->slow_time = s.v < 0.4f ? k->slow_time + 0.05f : 0.0f;
  if (k->slow_time > 6.0f && !k->turning) {
    k->unstick_until = t + 8.0f;
    k->slow_time = 0.0f;
  }
  if (t < k->unstick_until) {
    const float twa = wrap_pi(twd - s.psi);
    helm_to(w, i, &s, wrap_2pi(twd - (twa >= 0.0f ? 1.0f : -1.0f) * 120.0f * DEG_F), 0.8f);
    return;
  }
  /* Penalty turns (rules.md §9.3), not while returning to start: a steady turn with way on, given up after 50 s. */
  if (br.pending > 0 && !(t >= 0.0f && !rb.started && (rb.ocs || rb.ocs_i || rb.returning))) {
    if (!k->turning && s.v > 1.2f) {
      const float twa0 = wrap_pi(twd - s.psi);
      const float toward = twa0 >= 0.0f ? 1.0f : -1.0f;
      k->turning = 1;
      k->turn_started = t;
      k->turn_dir = fabsf(twa0) < 100.0f * DEG_F ? toward : -toward;
    }
    if (k->turning && t - k->turn_started < 50.0f) {
      wm_world_set_helm(w, i, 0.6f * k->turn_dir);
      return;
    }
  }
  k->turning = 0;

  const float slot = 18.0f * (float)(i % 5 - 2);
  const float sx = mx + ux * slot, sy = my + uy * slot;
  if (!rb.started && !rb.ocs_scored) {
    if (t >= 0.0f && (rb.ocs || rb.ocs_i || rb.returning)) {
      /* Over early: under the I flag back around the nearer end (race.md §4.3), else straight back. */
      if (rb.ocs_i) {
        const int a_near = hypotf(s.pos_x - a.x, s.pos_y - a.y) < hypotf(s.pos_x - b.x, s.pos_y - b.y);
        const float ox = a_near ? -ux : ux, oy = a_near ? -uy : uy;
        const float ex = (a_near ? a.x : b.x) + ox * 25.0f, ey = (a_near ? a.y : b.y) + oy * 25.0f;
        if (k->ret_stage == 0 && hypotf(s.pos_x - (ex + upx * 10.0f), s.pos_y - (ey + upy * 10.0f)) < 12.0f)
          k->ret_stage = 1;
        if (k->ret_stage == 0) sail_to(w, i, k, &s, ex + upx * 10.0f, ey + upy * 10.0f, twd, tws);
        else sail_to(w, i, k, &s, ex - upx * 20.0f, ey - upy * 20.0f, twd, tws);
      } else {
        sail_to(w, i, k, &s, s.pos_x - upx * 30.0f, s.pos_y - upy * 30.0f, twd, tws);
      }
      return;
    }
    if (t >= 0.0f) {
      sail_to(w, i, k, &s, sx + upx * 40.0f, sy + upy * 40.0f, twd, tws);
      return;
    }
    if (t < -60.0f) {
      /* Reach back and forth below the line. */
      const float bx = sx - upx * 60.0f, by = sy - upy * 60.0f;
      if (hypotf(s.pos_x - bx, s.pos_y - by) > 60.0f) {
        sail_to(w, i, k, &s, bx, by, twd, tws);
      } else {
        const int west = ((long)floorf((t + 10000.0f) / 15.0f)) % 2 == 0;
        helm_to(w, i, &s, wrap_2pi(twd + (west ? -90.0f : 90.0f) * DEG_F), 0.6f);
      }
      return;
    }
    /* Timed approach: go when the distance to the line takes the time left, to cross just after the gun. */
    const float d = (s.pos_x - mx) * upx + (s.pos_y - my) * upy; /* < 0 below the line */
    const float v = s.v > 1.0f ? s.v : 1.0f;
    if (-d / v >= -t - 1.0f) {
      sail_to(w, i, k, &s, sx + upx * 20.0f, sy + upy * 20.0f, twd, tws);
    } else if (d > -30.0f) {
      helm_to(w, i, &s, wrap_2pi(twd - 30.0f * DEG_F), 0.4f);
    } else {
      sail_to(w, i, k, &s, sx - upx * 25.0f, sy - upy * 25.0f, twd, tws);
    }
    return;
  }

  wm_step st;
  wm_world_course_step(w, rb.next, &st);
  if (st.kind == WM_STEP_FINISH) {
    wm_mark fa, fb;
    wm_world_course_mark(w, st.marks[0], &fa);
    wm_world_course_mark(w, st.marks[1], &fb);
    const float fl = hypotf(fb.x - fa.x, fb.y - fa.y);
    const float fux = (fb.x - fa.x) / fl, fuy = (fb.y - fa.y) / fl;
    sail_to(w, i, k, &s, 0.5f * (fa.x + fb.x) + fuy * 40.0f, 0.5f * (fa.y + fb.y) - fux * 40.0f, twd, tws);
    return;
  }
  const int m = st.kind == WM_STEP_GATE && st.sides[1] == WM_SIDE_PORT ? 1 : 0;
  wm_mark mk;
  wm_world_course_mark(w, st.marks[m], &mk);
  const float sgn = st.sides[m] == WM_SIDE_PORT ? 1.0f : -1.0f;
  const float r = 14.0f;
  const float dist = hypotf(mk.x - s.pos_x, mk.y - s.pos_y);
  if (dist < 45.0f) {
    /* Orbit the mark in the rounding direction, aiming 50 degrees ahead on the circle. */
    const float ang = atan2f(s.pos_y - mk.y, s.pos_x - mk.x) + sgn * 50.0f * DEG_F;
    sail_to(w, i, k, &s, mk.x + r * cosf(ang), mk.y + r * sinf(ang), twd, tws);
  } else {
    const float dx = (mk.x - s.pos_x) / dist, dy = (mk.y - s.pos_y) / dist;
    sail_to(w, i, k, &s, mk.x + dy * sgn * r, mk.y - dx * sgn * r, twd, tws);
  }
}

static void controller(wm_world* w, void* user) {
  pilot* p = (pilot*)user;
  wm_race_info ri;
  if (wm_world_race(w, &ri) != WM_OK) return;
  for (int i = 0; i < wm_world_boat_count(w); ++i) steer(w, p, i, ri.race_time);
}

static const char* signal_name(int s) {
  static const char* n[] = {"warning", "prep up", "prep down", "start", "general recall", "X up", "X down"};
  return s >= 0 && s <= 6 ? n[s] : "?";
}

typedef struct outcome {
  int ok;
  uint64_t checksum;
  uint32_t ticks;
  int results;
} outcome;

static int check(wm_status s, const char* what) {
  if (s != WM_OK) fprintf(stderr, "%s: %s\n", what, wm_last_error());
  return s == WM_OK;
}

static outcome run_race(const char* data, const char* courses, int verbose) {
  outcome o = {0, 0, 0, 0};
  char path[1024];
  wm_perf* perf[2] = {NULL, NULL};
  wm_venue* venue = NULL;
  wm_course* course = NULL;
  wm_world* w = NULL;
  snprintf(path, sizeof path, "%s/perf/wm7.perf.json", data);
  if (!check(wm_perf_load(path, &perf[0]), "wm7")) goto done;
  snprintf(path, sizeof path, "%s/perf/wm12.perf.json", data);
  if (!check(wm_perf_load(path, &perf[1]), "wm12")) goto done;
  snprintf(path, sizeof path, "%s/venues/example_bay.venue.json", data);
  if (!check(wm_venue_load(path, &venue), "venue")) goto done;
  snprintf(path, sizeof path, "%s/example_bay/example_wl.course.json", courses);
  if (!check(wm_course_load(path, &course), "course")) goto done;

  wm_world_settings ws;
  wm_world_settings_init(&ws);
  ws.race_seed = 20260925;
  ws.wind_speed = 11.0f * 0.514444470f;
  ws.wind_from = 0.2f;
  ws.shift_preset = WM_SHIFT_STABLE;
  ws.free_sailing_s = 10.0f;
  if (!check(wm_world_create(&ws, venue, &w), "world")) goto done;
  /* The world keeps what it was given: the caller's handles can go now. */
  wm_venue_free(venue);
  venue = NULL;
  if (verbose) {
    wm_land land;
    wm_obstacle ob;
    float x0 = 0.0f, y0 = 0.0f;
    for (int32_t i = 0; i < wm_world_land_count(w); ++i) {
      if (!check(wm_world_land(w, i, &land), "land") || !check(wm_world_land_point(w, i, 0, &x0, &y0), "land point"))
        goto done;
      printf("land %s: %d points from (%.1f, %.1f)\n", land.id, land.point_count, (double)x0, (double)y0);
    }
    for (int32_t i = 0; i < wm_world_obstacle_count(w); ++i) {
      if (!check(wm_world_obstacle(w, i, &ob), "obstacle")) goto done;
      printf("obstacle %s: %s\n", ob.id, ob.kind == WM_OBSTACLE_CIRCLE ? "circle" : "polygon");
    }
  }
  for (int i = 0; i < N_BOATS; ++i) {
    wm_boat_entry e;
    wm_boat_entry_init(&e, perf[i == N_BOATS - 1 ? 1 : 0]);
    int32_t idx = -1;
    if (!check(wm_world_add_boat(w, &e, &idx), "add boat")) goto done;
  }
  if (!check(wm_world_create_race(w, course), "create race")) goto done;

  wm_course_info ci;
  wm_world_course(w, &ci);
  if (verbose) printf("course %s: %d marks, %d steps, axis %.3f rad, scale %.2f\n", ci.id, ci.mark_count,
                      ci.step_count, (double)ci.twd_c, (double)ci.k);

  pilot p;
  memset(&p, 0, sizeof p);
  for (int i = 0; i < N_BOATS; ++i) {
    p.b[i].tack = 1;
    p.b[i].unstick_until = -1e9f;
  }
  wm_world_set_controller(w, controller, &p);

  wm_race_info ri;
  wm_world_race(w, &ri);
  const int64_t gun = ri.n_gun;
  for (int k = 0; k < 80000; ++k) {
    o.checksum = wm_world_step(w);
    for (int e = 0; verbose && e < wm_world_race_event_count(w); ++e) {
      wm_race_event ev;
      wm_world_race_event(w, e, &ev);
      if (ev.kind == WM_EV_SIGNAL) printf("t %7.1f  signal %s\n", (double)((int64_t)ev.tick - gun) * 0.05, signal_name(ev.signal));
      if (ev.kind == WM_EV_STARTED) printf("t %7.1f  boat %d started\n", (double)((int64_t)ev.tick - gun) * 0.05, ev.boat);
      if (ev.kind == WM_EV_ROUNDED) printf("t %7.1f  boat %d rounded step %d\n", (double)((int64_t)ev.tick - gun) * 0.05, ev.boat, ev.step);
      if (ev.kind == WM_EV_FINISHED) printf("t %7.1f  boat %d finished, place %d\n", (double)((int64_t)ev.tick - gun) * 0.05, ev.boat, ev.place);
    }
    for (int e = 0; verbose && e < wm_world_rules_event_count(w); ++e) {
      wm_rules_event ev;
      wm_world_rules_event(w, e, &ev);
      if (ev.kind == WM_REV_PENALTY || ev.kind == WM_REV_PENALTY_SERVED)
        printf("t %7.1f  boat %d %s rule %s\n", (double)((int64_t)ev.tick - gun) * 0.05, ev.boat,
               ev.kind == WM_REV_PENALTY ? "penalty" : "served", wm_rule_code_name(ev.rule));
    }
    wm_world_race(w, &ri);
    if (ri.state == WM_RACE_CLOSED) break;
  }
  o.ticks = wm_world_tick(w);
  if (o.checksum != wm_world_checksum(w)) fprintf(stderr, "checksum reader differs from the step's\n");
  wm_world_race(w, &ri);
  o.results = wm_world_result_count(w);
  if (verbose) {
    printf("race %s after %u ticks (%.1f s), checksum %016llx\n", ri.state == WM_RACE_CLOSED ? "closed" : "open",
           o.ticks, (double)o.ticks * 0.05, (unsigned long long)o.checksum);
    for (int r = 0; r < o.results; ++r) {
      wm_result res;
      wm_world_result(w, r, &res);
      printf("  boat %d  place %d  %s  points %.1f  time %.2f s\n", res.boat, res.place,
             wm_score_code_name(res.code), (double)res.points, (double)res.t_finish_us * 1e-6);
    }
  }
  o.ok = ri.state == WM_RACE_CLOSED && o.results == N_BOATS;
  for (int r = 0; r < o.results; ++r) {
    wm_result res;
    wm_world_result(w, r, &res);
    if (res.place <= 0 && res.code == WM_SCORE_NONE) o.ok = 0;
  }
  /* Splits (race.md §8.4): a finisher has one per step, in order, the last at her finish time; the start
   * status of the rules hull (race.md §3.3) is readable after the race. */
  for (int i = 0; i < N_BOATS; ++i) {
    wm_race_boat rb;
    wm_course_info ci;
    wm_start_status ss;
    wm_world_race_boat(w, i, &rb);
    wm_world_course(w, &ci);
    if (wm_world_race_start_status(w, i, &ss) != WM_OK || (ss.pre_start && ss.course_side)) {
      fprintf(stderr, "start status of boat %d\n", i);
      o.ok = 0;
    }
    if (!rb.finished) continue;
    float prev = -1.0f, t = 0.0f;
    for (int k = 0; k < ci.step_count; ++k) {
      if (wm_world_race_split(w, i, k, &t) != WM_OK || t < prev) {
        fprintf(stderr, "split %d of boat %d\n", k, i);
        o.ok = 0;
      }
      prev = t;
    }
    if (fabsf(t - (float)((double)rb.t_finish_us * 1e-6)) > 1e-3f) {
      fprintf(stderr, "finish split of boat %d: %f vs %f\n", i, (double)t, (double)rb.t_finish_us * 1e-6);
      o.ok = 0;
    }
  }
done:
  wm_world_free(w);
  wm_course_free(course);
  wm_venue_free(venue);
  wm_perf_free(perf[0]);
  wm_perf_free(perf[1]);
  return o;
}

/* One boat in a world without a race: open water, steady wind, helm on a close reach for a minute. */
static int free_sail(const char* data) {
  char path[1024];
  wm_perf* perf = NULL;
  wm_world* w = NULL;
  int ok = 0;
  snprintf(path, sizeof path, "%s/perf/wm7.perf.json", data);
  if (!check(wm_perf_load(path, &perf), "wm7")) return 0;
  wm_world_settings ws;
  wm_world_settings_init(&ws);
  ws.wind_speed = 12.0f * 0.514444470f;
  ws.shift_preset = WM_SHIFT_STEADY;
  ws.puffs = 0;
  if (check(wm_world_create(&ws, NULL, &w), "world")) {
    wm_boat_entry e;
    wm_boat_entry_init(&e, perf);
    int32_t b = -1;
    if (check(wm_world_add_boat(w, &e, &b), "add") && check(wm_world_place_boat(w, b, 0.0f, 0.0f, 1.2f), "place")) {
      wm_input_frame f = {0.0f, 0.5f, WM_SAIL_REQ_NONE, WM_INPUT_AUTO_TRIM};
      for (int k = 0; k < 1200; ++k) {
        wm_world_apply_input(w, b, &f, NULL);
        wm_world_step(w);
      }
      wm_boat_state s;
      wm_world_boat_state(w, b, &s);
      wm_render_pose rp;
      wm_world_render_pose(w, b, 0.5f, &rp);
      const float d = hypotf(s.pos_x, s.pos_y);
      printf("free sailing: 60 s on heading %.2f rad, %.1f m sailed, speed %.2f m/s, twa %.2f rad, has race %d\n",
             (double)s.psi, (double)d, (double)s.v, (double)s.twa, wm_world_has_race(w));
      ok = d > 100.0f && s.v > 2.0f && !wm_world_has_race(w) &&
           wm_world_create_race(w, NULL) == WM_ERR_ARG;
      /* The render pose lies between the last two states. */
      wm_boat_state s1;
      wm_world_step(w);
      wm_world_boat_state(w, b, &s1);
      wm_world_render_pose(w, b, 0.0f, &rp);
      ok = ok && rp.pos_x == s.pos_x && rp.pos_y == s.pos_y;
      wm_world_render_pose(w, b, 1.0f, &rp);
      ok = ok && rp.pos_x == s1.pos_x && rp.pos_y == s1.pos_y && rp.psi == s1.psi;
      /* A sail request is answered at once and takes effect in the next step. */
      wm_class_info ci;
      wm_perf_info(perf, &ci);
      int32_t kite = -1;
      for (int32_t i = 0; i < ci.sail_count; ++i) {
        wm_sail_info si;
        wm_perf_sail(perf, i, &si);
        if (si.type == WM_SAIL_SPINNAKER_SYM || si.type == WM_SAIL_SPINNAKER_ASYM) kite = i;
      }
      int32_t r1 = -2, r2 = -2;
      wm_input_frame hoist = {0.0f, 0.5f, (uint8_t)(kite + 1), WM_INPUT_AUTO_TRIM};
      uint8_t wire[6];
      wm_input_frame back;
      wm_input_encode(&hoist, wire);
      wm_input_decode(wire, &back);
      ok = ok && back.sail_req == hoist.sail_req && back.flags == hoist.flags && back.h_cmd == 0.0f &&
           fabsf(back.sheet_cmd - 0.5f) < 1e-4f;
      wm_world_apply_input(w, b, &back, &r1);
      wm_world_hoist(w, b, ci.main_sail, &r2);  /* the main is never hoisted */
      wm_world_step(w);
      wm_sails sv;
      wm_world_sails(w, b, &sv);
      ok = ok && r1 == WM_REQUEST_ACCEPTED && r2 == WM_REQUEST_REJECTED && sv.queue_len > 0;
      float ts = 0.0f;
      const wm_status tst = wm_world_trim_speed_at(w, b, s1.tws, fabsf(s1.awa), 0.1f, &ts);
      wm_wind_state wst;
      wm_world_wind_state(w, wm_world_time_ms(w), &wst);
      printf("free sailing: sail change %s, queue %d steps; trim_speed(eps 0.1) %s %.3f; wind %.2f m/s from %.2f\n",
             r1 == WM_REQUEST_ACCEPTED ? "accepted" : "rejected", sv.queue_len,
             tst == WM_OK ? "=" : "absent", (double)ts, (double)wst.base_speed, (double)wst.global_from);
      ok = ok && (tst == WM_OK || tst == WM_ERR_ABSENT);
      /* The same table by name, and one that does not exist. */
      float ts2 = 0.0f, x = 0.0f;
      int32_t rank = 0;
      wm_sails now;
      wm_world_sails(w, b, &now);
      const wm_status t2 = wm_perf_table(perf, now.front, "trim_speed", s1.tws, fabsf(s1.awa), 0.1f, &ts2, &rank);
      ok = ok && t2 == tst && (tst != WM_OK || (ts2 == ts && rank == 3)) &&
           wm_perf_table(perf, -1, "no_such_table", 0.0f, 0.0f, 0.0f, &x, NULL) == WM_ERR_ARG;
    }
  }
  wm_world_free(w);
  wm_perf_free(perf);
  return ok;
}

int main(int argc, char** argv) {
  const char* data = argc > 1 ? argv[1] : "data";
  const char* courses = argc > 2 ? argv[2] : "game/data/courses";
  if (wm_api_version() != WM_API_VERSION) {
    fprintf(stderr, "library API version %d, header %d\n", wm_api_version(), WM_API_VERSION);
    return 1;
  }
  const outcome a = run_race(data, courses, 1);
  const outcome b = run_race(data, courses, 0);
  const int same = a.checksum == b.checksum && a.ticks == b.ticks;
  printf("second run: %s\n", same ? "same ticks and checksum" : "DIFFERENT");
  const int fs = free_sail(data);
  const int ok = a.ok && b.ok && same && fs;
  printf("%s\n", ok ? "OK" : "FAILED");
  return ok ? 0 : 1;
}
