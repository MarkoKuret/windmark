// Venue physics file `windmark.venue/1` (data_format.md §6): wind field, current, sea exposure, land and
// obstacles of a sailing area. Loaded and fully validated at once into the environment structs the wind and sea
// already read; the core never runs with partly valid data.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "course/geometry.h"
#include "data/load_error.h"
#include "math/wm_math.h"
#include "sea/sea.h"
#include "wind/wind.h"

namespace wm {

// data_format.md §6.5: land, counter-clockwise, interior = land, simple.
struct VenueLand {
  std::string id;
  std::vector<Vec2> points;  // world ENU, m
  PolygonIndex index;        // built at load (venues.md §4.1): land queries visit only the edges near them
};

// data_format.md §6.5: a convex counter-clockwise polygon or a circle.
struct VenueObstacle {
  std::string id;
  bool is_circle = false;
  std::vector<Vec2> polygon;  // when !is_circle
  Vec2 c{0.0f, 0.0f};         // when is_circle
  float r = 0.0f;
};

// data_format.md §6.7: the venue's typical weather, SI units, with the defaults of the table and, for the keys of
// `random` the file leaves out, the widened local values (filled at load).
struct VenueConditions {
  float speed_min = 7.20f, speed_max = 7.20f;  // m/s
  float from = 0.0f;                           // rad
  float from_spread = 0.0f;                    // rad
  ShiftPreset shift_preset = ShiftPreset::shifty;
  bool has_shift_amplitude = false, has_hold_max = false, has_hold_min = false;
  float shift_amplitude = 0.0f;  // rad
  float hold_max_s = 0.0f, hold_min_s = 0.0f;
  float trend_rate = 0.0f;   // rad/s
  float trend_max = 0.35f;   // rad
  bool has_oscillation = false;
  float osc_amplitude = 0.0f, osc_time_scale = 17.0f;
  PuffPreset puff_preset = PuffPreset::standard;
  PuffParams puffs;            // the preset with the file's overrides applied
  bool puffs_enabled = true;
  float current_speed = 0.0f, current_to = 0.0f;
  bool has_tide = false;
  float tide_scale = 0.0f;
  std::uint32_t tide_period_s = 44712;
  float sea_scale = 1.0f;
  std::vector<WaveTrain> swells;
  // random (race.md §2.1)
  float r_speed_min = 0.0f, r_speed_max = 0.0f;
  float r_from_spread = 0.0f;
  std::vector<ShiftPreset> r_shift;
  std::vector<PuffPreset> r_puffs;
  float r_tide_min = 0.5f, r_tide_max = 1.2f;
  float r_swell_min = 0.5f, r_swell_max = 1.5f;

  // The local shift settings: the preset, replaced by any explicit values (race.md §2.1).
  void local_shift(WindSettings& w) const;
};

struct VenueData {
  // §6.1 header
  std::string id, name;
  std::int64_t version = 0;
  bool has_origin = false;
  float origin_lat = 0.0f, origin_lon = 0.0f;  // display only
  float bounds[4] = {0.0f, 0.0f, 0.0f, 0.0f};  // xmin, ymin, xmax, ymax
  float fetch = 10000.0f;                      // m
  float exposure_default = 1.0f;

  // §6.2 to §6.4, each optional.
  bool has_wind_field = false;
  VenueWindField wind_field;
  bool has_current_field = false;
  VenueCurrentField current_field;
  bool has_exposure = false;
  VenueExposure exposure;

  // §6.3 ref_speed (optional in older files, §6.9)
  bool has_ref_speed = false;
  float ref_speed = 0.0f;  // m/s

  // §6.7 (optional, §6.9: a venue without it offers the custom weather mode only)
  bool has_conditions = false;
  VenueConditions conditions;

  // §6.5, in file order.
  std::vector<VenueLand> land;
  std::vector<VenueObstacle> obstacles;

  std::string file_sha256;  // lowercase hex of the file bytes (announced online, data_format.md §7)

  const VenueWindField* wind_field_ptr() const { return has_wind_field ? &wind_field : nullptr; }
  const VenueCurrentField* current_field_ptr() const { return has_current_field ? &current_field : nullptr; }
  const VenueExposure* exposure_ptr() const { return has_exposure ? &exposure : nullptr; }
};

// Parses and validates. `file` names the source in errors. On failure `out` is left empty.
bool parse_venue(std::string_view text, std::string_view file, VenueData& out, LoadError& err);
bool load_venue(const std::string& file, VenueData& out, LoadError& err);

// Points the race's settings at the venue: the wind field and the current field (wind.md §1, §7, §8), the
// exposure grid and its default (sea.md §2, §6). The settings keep pointers into `v`, so `v` must outlive every
// WindField and SeaField built from them and must not be moved meanwhile. Fields the venue lacks are cleared.
void apply_venue(const VenueData& v, WindSettings& wind, SeaSettings& sea);

}  // namespace wm
