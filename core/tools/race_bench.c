/* The core's tick cost over a whole race through the C API (include/windmark.h): the example venue and its
 * windward-leeward course, a fleet of AI skippers (or, with `noai`, entries that nobody steers: the boats, wind,
 * rules and race without the skippers), every wm_world_step timed and summed by race phase.
 *
 *   windmark_race_bench <data_dir> <courses_dir> <fleet> [level 0..3] [noai] [seed]
 *
 * Prints one line per phase: ticks, mean, 99th percentile and maximum µs per tick, then a hash of the world
 * checksum every 100 ticks (taken outside the timing) to show a change kept the race bit for bit. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "windmark.h"

enum { PH_FREE, PH_SEQ, PH_START, PH_RACE, PH_FINISH, PH_N };
static const char* PH_NAME[PH_N] = {"free sailing", "sequence", "gun to +60 s", "racing", "first finish to close"};

#define MAX_T 80000

static double now_us(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec * 1e-3;
}

static int cmp(const void* a, const void* b) {
  const float x = *(const float*)a, y = *(const float*)b;
  return x < y ? -1 : (x > y);
}

static int check(wm_status s, const char* what) {
  if (s != WM_OK) fprintf(stderr, "%s: %s\n", what, wm_last_error());
  return s == WM_OK;
}

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: %s data_dir courses_dir fleet [level] [noai] [seed]\n", argv[0]);
    return 2;
  }
  const int fleet = atoi(argv[3]);
  const int level = argc > 4 ? atoi(argv[4]) : WM_AI_INTERMEDIATE;
  const int noai = argc > 5 && strcmp(argv[5], "noai") == 0;
  const uint32_t seed = argc > 6 ? (uint32_t)atoi(argv[6]) : 7u;
  char path[1024];
  wm_perf* perf = NULL;
  wm_venue* venue = NULL;
  wm_course* course = NULL;
  snprintf(path, sizeof path, "%s/perf/wm7.perf.json", argv[1]);
  if (!check(wm_perf_load(path, &perf), "wm7")) return 1;
  snprintf(path, sizeof path, "%s/venues/example_bay.venue.json", argv[1]);
  if (!check(wm_venue_load(path, &venue), "venue")) return 1;
  snprintf(path, sizeof path, "%s/example_bay/example_wl.course.json", argv[2]);
  if (!check(wm_course_load(path, &course), "course")) return 1;

  wm_world_settings ws;
  wm_world_settings_init(&ws);
  ws.race_seed = seed;
  ws.wind_speed = 12.0f * 0.514444470f;
  wm_world* w = NULL;
  if (!check(wm_world_create(&ws, venue, &w), "world")) return 1;
  for (int i = 0; i < fleet; ++i) {
    int32_t idx = -1;
    if (noai) {
      wm_boat_entry e;
      wm_boat_entry_init(&e, perf);
      if (!check(wm_world_add_boat(w, &e, &idx), "boat")) return 1;
    } else if (!check(wm_world_add_ai_boat(w, perf, level, 0, &idx), "AI boat")) {
      return 1;
    }
  }
  if (!check(wm_world_create_race(w, course), "race")) return 1;

  static float t_us[PH_N][MAX_T];
  int n[PH_N] = {0};
  double sum[PH_N] = {0};
  int first_finish = 0;
  wm_race_info ri;
  double total = 0.0;
  int ticks = 0;
  uint64_t trail = 1469598103934665603ull;
  for (int k = 0; k < MAX_T; ++k) {
    wm_world_race(w, &ri);
    if (ri.state == WM_RACE_CLOSED || ri.state == WM_RACE_ABANDONED) break;
    if (noai && ri.race_time > 600.0f) break; /* nobody steers: ten minutes of racing is enough */
    int ph = PH_FREE;
    if (ri.state == WM_RACE_SEQUENCE) ph = PH_SEQ;
    if (ri.state >= WM_RACE_RACING) ph = ri.race_time < 60.0f ? PH_START : PH_RACE;
    if (first_finish || ri.state == WM_RACE_CLOSING) ph = PH_FINISH;
    const double a = now_us();
    wm_world_step(w);
    const double d = now_us() - a;
    total += d;
    ++ticks;
    t_us[ph][n[ph]++] = (float)d;
    if (ticks % 100 == 0) trail = (trail ^ wm_world_checksum(w)) * 1099511628211ull;
    sum[ph] += d;
    if (!first_finish && ri.state >= WM_RACE_RACING) {
      for (int b = 0; b < wm_world_boat_count(w); ++b) {
        wm_race_boat rb;
        wm_world_race_boat(w, b, &rb);
        if (rb.finished) first_finish = 1;
      }
    }
  }
  printf("fleet %d %s level %d seed %u: %d ticks (%.0f s of race time), %.1f ms in all, %.1f µs per tick\n", fleet,
         noai ? "no AI" : "AI", level, seed, ticks, ticks * 0.05, total * 1e-3, total / (ticks > 0 ? ticks : 1));
  for (int p = 0; p < PH_N; ++p) {
    if (n[p] == 0) continue;
    qsort(t_us[p], (size_t)n[p], sizeof(float), cmp);
    printf("  %-22s %6d ticks  mean %8.1f µs  p99 %8.1f µs  max %8.1f µs\n", PH_NAME[p], n[p], sum[p] / n[p],
           t_us[p][(int)(0.99 * (n[p] - 1))], t_us[p][n[p] - 1]);
  }
  printf("  checksum trail %016llx, final %016llx\n", (unsigned long long)trail,
         (unsigned long long)wm_world_checksum(w));
  wm_world_free(w);
  wm_course_free(course);
  wm_venue_free(venue);
  wm_perf_free(perf);
  return 0;
}
