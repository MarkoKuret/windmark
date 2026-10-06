// Venue physics file loader (data_format.md §6): the shipped example venue, its use by the wind and the sea, and
// the refusals of every validation rule.
#include <cmath>
#include <string>
#include <vector>

#include "data/venue.h"
#include "doctest.h"
#include "wind/grid.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;

// A small valid venue; the refusal cases replace one piece of it.
struct Parts {
  std::string header = R"("schema": "windmark.venue/1", "id": "t", "name": "T", "version": 1,
                          "bounds": [-100, -100, 100, 100])";
  std::string grid = R"({"x0": -100, "y0": -100, "dx": 100, "dy": 100, "nx": 3, "ny": 3})";
  std::string f_mid = "0.8";
  std::string d_mid = "0.1";
  std::string sectors_extra;  // appended to the sector list
  std::string current = R"(, "current_field": {"grid": {"x0": 0, "y0": 0, "dx": 10, "dy": 10, "nx": 2, "ny": 2},
                              "vx": [0.1, 0.2, 0.3, 0.4], "vy": [0, 0, 0, 0]})";
  std::string exposure = R"(, "exposure": {"grid": {"x0": 0, "y0": 0, "dx": 10, "dy": 10, "nx": 2, "ny": 2},
                               "e": [0, 0.5, 1, 1]})";
  std::string land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 0], [10, 10], [0, 10]]}])";
  std::string obstacles = R"(, "obstacles": [{"id": "pier", "polygon": [[20, 0], [22, 0], [22, 8], [20, 8]]},
                                              {"id": "rock", "circle": {"c": [30, 30], "r": 2}}])";

  std::string text() const {
    std::string sector = R"({"f": [1, 1, 1, 1, )" + f_mid + R"(, 1, 1, 1, 1], "d": [0, 0, 0, 0, )" + d_mid +
                         R"(, 0, 0, 0, 0]})";
    std::string sectors = sector;
    for (int k = 1; k < 8; ++k) sectors += ", " + sector;
    sectors += sectors_extra;
    return "{" + header + R"(, "wind_field": {"grid": )" + grid + R"(, "sectors": [)" + sectors + "]}" + current +
           exposure + land + obstacles + "}";
  }
};

void refuse(const std::string& name, const std::string& text, const std::string& path) {
  CAPTURE(name);
  wm::VenueData v;
  wm::LoadError err;
  CHECK(!wm::parse_venue(text, "t.venue.json", v, err));
  CHECK(err.file == "t.venue.json");
  CHECK(!err.reason.empty());
  CHECK_MESSAGE(err.path.rfind(path, 0) == 0, err.message());
  // Nothing partly loaded.
  CHECK(v.id.empty());
  CHECK(!v.has_wind_field);
  CHECK(v.land.empty());
  CHECK(v.obstacles.empty());
}

}  // namespace

TEST_CASE("venue: the test venue loads") {
  const Parts p;
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_venue(p.text(), "t", v, err), err.message());
  CHECK(v.id == "t");
  CHECK(v.fetch == 10000.0f);  // default
  CHECK(v.exposure_default == 1.0f);
  CHECK(!v.has_origin);
  REQUIRE(v.has_wind_field);
  CHECK(v.wind_field.grid.nx == 3);
  CHECK(v.wind_field.f[5][4] == 0.8f);
  CHECK(v.wind_field.d[7][4] == 0.1f);
  REQUIRE(v.has_current_field);
  CHECK(v.current_field.vx[3] == 0.4f);
  REQUIRE(v.has_exposure);
  CHECK(v.exposure.e[1] == 0.5f);
  REQUIRE(v.land.size() == 1);
  CHECK(v.land[0].points.size() == 4);
  REQUIRE(v.obstacles.size() == 2);
  CHECK(!v.obstacles[0].is_circle);
  CHECK(v.obstacles[1].is_circle);
  CHECK(v.obstacles[1].r == 2.0f);
  CHECK(v.obstacles[1].c.x == 30.0f);
  CHECK(v.file_sha256.size() == 64);
}

TEST_CASE("venue: header only is open water") {
  const std::string text = R"({"schema": "windmark.venue/1", "id": "open", "name": "Open", "version": 2,
                               "bounds": [-8000, -8000, 8000, 8000], "fetch": 30000, "exposure_default": 0.9,
                               "origin": {"lat": -33.9, "lon": 151.2}, "future_key": {"x": 1}})";
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_venue(text, "open", v, err), err.message());
  CHECK(!v.has_wind_field);
  CHECK(!v.has_current_field);
  CHECK(!v.has_exposure);
  CHECK(v.fetch == 30000.0f);
  CHECK(v.has_origin);
  CHECK(v.origin_lat == -33.9f);
  wm::WindSettings ws;
  wm::SeaSettings ss;
  wm::apply_venue(v, ws, ss);
  CHECK(ws.venue_wind_field == nullptr);
  CHECK(ws.venue_current_field == nullptr);
  CHECK(ss.exposure == nullptr);
  CHECK(ss.exposure_default == 0.9f);
}

TEST_CASE("venue: the example venue drives the wind, current and sea") {
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/practice_waters.venue.json", v, err), err.message());
  CHECK(v.id == "practice_waters");
  REQUIRE(v.has_wind_field);
  REQUIRE(v.has_current_field);
  REQUIRE(v.has_exposure);
  CHECK(v.land.size() == 1);
  CHECK(v.obstacles.size() == 2);

  wm::WindSettings ws;
  wm::apply_shift_preset(ws, wm::ShiftPreset::steady);
  ws.puffs_enabled = false;
  ws.base_from = 0.0f;  // from the north: the island (north of the course) shelters the water south of it
  ws.tide_scale = 1.0f;
  wm::SeaSettings ss;
  ss.wind_sea = {0.4f, 2.7f, 0.0f};
  wm::apply_venue(v, ws, ss);
  REQUIRE(wm::check_wind_settings(ws) == nullptr);
  REQUIRE(wm::check_sea_settings(ss) == nullptr);
  CHECK(ws.venue_wind_field == &v.wind_field);
  CHECK(ss.exposure == &v.exposure);

  const wm::WindField w(1, ws);
  const wm::WindTick tick = w.at(0);
  const float lee = w.wind_clean(tick, 0.0f, 1500.0f).speed;   // just south of the island
  const float open = w.wind_clean(tick, 0.0f, -1500.0f).speed;  // far side of the course
  MESSAGE("lee " << lee << " m/s, open " << open << " m/s");
  CHECK(lee < 0.9f * ws.base_speed);
  CHECK(open > 0.95f * ws.base_speed);
  // Outside the grid the field is (1, 0).
  CHECK(w.wind_clean(tick, 5000.0f, 0.0f).speed == ws.base_speed);

  const wm::Vec2 c = w.current(0.0f, 0.0f, 0);  // tide(0) = 1
  CHECK(c.x > 0.1f);

  const wm::SeaField sea(1, ss);
  CHECK(sea.exposure(0.0f, 2400.0f) < 0.1f);    // on the island
  CHECK(sea.exposure(0.0f, -2000.0f) > 0.9f);   // open water
  CHECK(sea.exposure(9000.0f, 0.0f) == 1.0f);   // outside the grid: exposure_default
}

TEST_CASE("venue: refusals") {
  auto with = [](auto edit) {
    Parts p;
    edit(p);
    return p.text();
  };
  refuse("not JSON", "{", "");
  refuse("schema major", R"({"schema": "windmark.venue/2", "id": "t", "name": "T", "version": 1,
                             "bounds": [-1, -1, 1, 1]})",
         "$.schema");
  refuse("bad id", with([](Parts& p) { p.header.replace(p.header.find("\"t\""), 3, "\"T x\""); }), "$.id");
  refuse("version 0", with([](Parts& p) { p.header.replace(p.header.find("1,"), 1, "0"); }), "$.version");
  refuse("bounds missing", R"({"schema": "windmark.venue/1", "id": "t", "name": "T", "version": 1})", "$.bounds");
  refuse("bounds beyond 8 km", with([](Parts& p) { p.header.replace(p.header.find("100]"), 3, "9000"); }),
         "$.bounds[3]");
  refuse("bounds inverted", with([](Parts& p) { p.header.replace(p.header.find("[-100"), 5, "[200"); }),
         "$.bounds");
  refuse("fetch 0", with([](Parts& p) { p.header += R"(, "fetch": 0)"; }), "$.fetch");
  refuse("exposure_default > 1", with([](Parts& p) { p.header += R"(, "exposure_default": 1.5)"; }),
         "$.exposure_default");
  refuse("latitude", with([](Parts& p) { p.header += R"(, "origin": {"lat": 95, "lon": 0})"; }), "$.origin.lat");

  refuse("grid 1 node wide", with([](Parts& p) { p.grid.replace(p.grid.find("\"nx\": 3"), 7, "\"nx\": 1"); }),
         "$.wind_field.grid.nx");
  refuse("grid too big", with([](Parts& p) { p.grid.replace(p.grid.find("\"ny\": 3"), 7, "\"ny\": 2000"); }),
         "$.wind_field.grid.ny");
  refuse("grid spacing 0", with([](Parts& p) { p.grid.replace(p.grid.find("\"dx\": 100"), 9, "\"dx\": 0"); }),
         "$.wind_field.grid.dx");
  refuse("grid nx not an integer",
         with([](Parts& p) { p.grid.replace(p.grid.find("\"nx\": 3"), 7, "\"nx\": 3.5"); }), "$.wind_field.grid.nx");
  refuse("value count", with([](Parts& p) { p.grid.replace(p.grid.find("\"ny\": 3"), 7, "\"ny\": 4"); }),
         "$.wind_field.sectors[0].f");
  refuse("nine sectors", with([](Parts& p) { p.sectors_extra = R"(, {"f": [], "d": []})"; }),
         "$.wind_field.sectors");
  refuse("negative speed factor", with([](Parts& p) { p.f_mid = "-0.1"; }), "$.wind_field.sectors[0].f[4]");
  refuse("offset beyond pi", with([](Parts& p) { p.d_mid = "3.5"; }), "$.wind_field.sectors[0].d[4]");
  refuse("value not a number", with([](Parts& p) { p.f_mid = "null"; }), "$.wind_field.sectors[0].f[4]");
  {
    // A border node that is not (1, 0).
    Parts p;
    std::string t = p.text();
    t.replace(t.find(R"("f": [1, 1)"), 10, R"("f": [1, 0.9)");
    refuse("border f", t, "$.wind_field.sectors[0].f[1]");
    Parts q;
    std::string u = q.text();
    u.replace(u.find(R"("d": [0,)"), 8, R"("d": [0.01,)");
    refuse("border d", u, "$.wind_field.sectors[0].d[0]");
  }

  refuse("current count", with([](Parts& p) { p.current.replace(p.current.find("0.4]"), 4, "0.4, 0.5]"); }),
         "$.current_field.vx");
  refuse("current vy missing", with([](Parts& p) { p.current.replace(p.current.find("\"vy\""), 4, "\"vz\""); }),
         "$.current_field.vy");
  refuse("exposure above 1", with([](Parts& p) { p.exposure.replace(p.exposure.find("0.5"), 3, "1.5"); }),
         "$.exposure.e[1]");

  refuse("land clockwise", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [0, 10], [10, 10], [10, 0]]}])";
         }),
         "$.land[0].points");
  refuse("land self-intersecting", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 10], [10, 0], [0, 10]]}])";
         }),
         "$.land[0].points");
  refuse("land two points", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 10]]}])";
         }),
         "$.land[0].points");
  refuse("land repeated point", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 0], [10, 0], [10, 10]]}])";
         }),
         "$.land[0].points");
  refuse("land folds back", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 0], [5, 0], [5, 10]]}])";
         }),
         "$.land[0].points");
  refuse("land duplicate id", with([](Parts& p) {
           p.land = R"(, "land": [{"id": "isle", "points": [[0, 0], [10, 0], [10, 10]]},
                                  {"id": "isle", "points": [[20, 0], [30, 0], [30, 10]]}])";
         }),
         "$.land[1].id");
  refuse("obstacle not convex", with([](Parts& p) {
           p.obstacles = R"(, "obstacles": [{"id": "pier", "polygon": [[0, 0], [10, 0], [5, 2], [10, 10], [0, 10]]}])";
         }),
         "$.obstacles[0].polygon");
  refuse("obstacle clockwise", with([](Parts& p) {
           p.obstacles = R"(, "obstacles": [{"id": "pier", "polygon": [[0, 0], [0, 10], [10, 10], [10, 0]]}])";
         }),
         "$.obstacles[0].polygon");
  refuse("obstacle both shapes", with([](Parts& p) {
           p.obstacles = R"(, "obstacles": [{"id": "x", "polygon": [[0, 0], [1, 0], [1, 1]],
                                             "circle": {"c": [0, 0], "r": 1}}])";
         }),
         "$.obstacles[0]");
  refuse("obstacle no shape", with([](Parts& p) { p.obstacles = R"(, "obstacles": [{"id": "x"}])"; }),
         "$.obstacles[0]");
  refuse("circle radius 0", with([](Parts& p) {
           p.obstacles = R"(, "obstacles": [{"id": "rock", "circle": {"c": [0, 0], "r": 0}}])";
         }),
         "$.obstacles[0].circle.r");
  refuse("circle centre", with([](Parts& p) {
           p.obstacles = R"(, "obstacles": [{"id": "rock", "circle": {"c": [0], "r": 1}}])";
         }),
         "$.obstacles[0].circle.c");
}

TEST_CASE("venue: missing file") {
  wm::VenueData v;
  wm::LoadError err;
  CHECK(!wm::load_venue(kData + "/venues/no_such.venue.json", v, err));
  CHECK(!err.reason.empty());
}
