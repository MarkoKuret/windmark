#include "course/course.h"

#include <span>

#include "data/json.h"
#include "data/table_reader.h"
#include "state/sha256.h"

namespace wm {

std::string_view mark_type_name(MarkType t) {
  switch (t) {
    case MarkType::buoy: return "buoy";
    case MarkType::committee_boat: return "committee_boat";
    case MarkType::mark_boat: return "mark_boat";
    case MarkType::virtual_point: return "virtual";
  }
  return "?";
}

std::string_view side_name(Side s) { return s == Side::port ? "port" : "starboard"; }

std::string_view prep_flag_name(PrepFlag f) {
  switch (f) {
    case PrepFlag::P: return "P";
    case PrepFlag::I: return "I";
    case PrepFlag::Z: return "Z";
    case PrepFlag::U: return "U";
    case PrepFlag::black: return "black";
  }
  return "?";
}

std::int32_t CourseData::find_mark(std::string_view mark_id) const {
  for (std::size_t i = 0; i < marks.size(); ++i) {
    if (marks[i].id == mark_id) return static_cast<std::int32_t>(i);
  }
  return -1;
}

namespace {

using data::member;
using data::read_float;
using json::Value;

constexpr float kRadiusMin = 0.8f;  // courses.md §2, collisions.md §3.5

bool has_em_dash(std::string_view s) { return s.find("\xE2\x80\x94") != std::string_view::npos; }

bool ends_with(std::string_view s, std::string_view suffix) {
  return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool convex_ccw_around_origin(const std::vector<Vec2>& p) {
  const std::size_t n = p.size();
  if (n < 6 || n > 32) return false;
  for (std::size_t i = 0; i < n; ++i) {
    const Vec2 a = p[i], b = p[(i + 1) % n], c = p[(i + 2) % n];
    const double ax = static_cast<double>(a.x), ay = static_cast<double>(a.y);
    const double bx = static_cast<double>(b.x), by = static_cast<double>(b.y);
    const double e1x = bx - ax, e1y = by - ay;
    const double e2x = static_cast<double>(c.x) - bx, e2y = static_cast<double>(c.y) - by;
    if (!(e1x * e2y - e1y * e2x > 0.0)) return false;              // strictly convex, counter-clockwise
    if (!(e1x * (0.0 - ay) - e1y * (0.0 - ax) > 0.0)) return false;  // origin inside
  }
  return true;
}

class CourseReader {
 public:
  CourseReader(ErrorSink& sink, CourseData& out) : sink_(sink), out_(out) {}

  bool read(const Value& root) {
    if (!data::check_schema(root, "windmark.course", 1, sink_)) return false;
    return header(root) && marks(root) && lines(root) && sequence(root) && area(root) && race(root) &&
           display(root) && expand();
  }

 private:
  ErrorSink& sink_;
  CourseData& out_;

  bool fail(const std::string& path, std::string_view why) { return sink_.fail(path, why); }

  bool id_field(const Value& obj, const std::string& path, std::string& out) {
    if (!data::read_string(obj, path, "id", out, sink_)) return false;
    if (!data::is_valid_id(out)) return fail(path_key(path, "id"), "ids are lowercase [a-z0-9_]");
    return true;
  }

  bool world_point(const Value& v, const std::string& path, Vec2& out) {
    if (!data::expect_object(v, path, sink_)) return false;
    return read_float(v, path, "x", out.x, sink_) && read_float(v, path, "y", out.y, sink_);
  }

  // `known` = number of marks resolved before this position (no forward references, courses.md §3.2).
  bool resolve_from(const std::string& from, std::size_t known, CoursePos& p, const std::string& path) {
    for (std::size_t i = 0; i < known; ++i) {
      if (out_.marks[i].id == from) {
        p.base_a = static_cast<std::int32_t>(i);
        return true;
      }
    }
    if (ends_with(from, "_mid")) {
      const std::string ab = from.substr(0, from.size() - 4);
      for (std::size_t cut = 1; cut + 1 < ab.size(); ++cut) {
        if (ab[cut] != '_') continue;
        const std::string a = ab.substr(0, cut), b = ab.substr(cut + 1);
        std::int32_t ia = -1, ib = -1;
        for (std::size_t i = 0; i < known; ++i) {
          if (out_.marks[i].id == a) ia = static_cast<std::int32_t>(i);
          if (out_.marks[i].id == b) ib = static_cast<std::int32_t>(i);
        }
        if (ia >= 0 && ib >= 0) {
          p.base_a = ia;
          p.base_b = ib;
          return true;
        }
      }
    }
    return fail(path_key(path, "from"), "\"" + from + "\" is not a mark or midpoint defined earlier in the file");
  }

  bool position(const Value& v, const std::string& path, std::size_t known, CoursePos& p) {
    if (!data::expect_object(v, path, sink_)) return false;
    if (v.find("x") != nullptr || v.find("y") != nullptr) {
      p.offset = false;
      return world_point(v, path, p.world);
    }
    if (out_.frame != CourseFrame::wind) return fail(path, "a world-frame course gives positions as {x, y}");
    p.offset = true;
    if (!read_float(v, path, "bearing", p.bearing, sink_)) return false;
    if (!read_float(v, path, "dist", p.dist, sink_)) return false;
    if (!(p.dist >= 0.0f)) return fail(path_key(path, "dist"), "must be >= 0");
    if (const Value* f = v.find("from")) {
      if (!f->is_string()) return fail(path_key(path, "from"), "expected a string");
      p.from = f->text;
      if (!resolve_from(p.from, known, p, path)) return false;
    }
    if (const Value* fx = v.find("fixed")) {
      if (!fx->is_bool()) return fail(path_key(path, "fixed"), "expected a boolean");
      p.fixed = fx->boolean;
    }
    return true;
  }

  bool header(const Value& root) {
    if (!id_field(root, "$", out_.id)) return false;
    if (!data::read_string(root, "$", "name", out_.name, sink_)) return false;
    if (has_em_dash(out_.name)) return fail("$.name", "player-facing text has no em dashes");
    if (!data::read_string(root, "$", "venue", out_.venue, sink_)) return false;
    if (!data::is_valid_id(out_.venue)) return fail("$.venue", "ids are lowercase [a-z0-9_]");
    if (const Value* c = root.find("classes")) {
      if (!c->is_array()) return fail("$.classes", "expected an array of class ids");
      for (std::size_t i = 0; i < c->items.size(); ++i) {
        const Value& s = c->items[i];
        if (!s.is_string() || !data::is_valid_id(s.text)) return fail(path_index("$.classes", i), "expected a class id");
        out_.classes.push_back(s.text);
      }
    }
    std::string frame;
    if (!data::read_string(root, "$", "frame", frame, sink_)) return false;
    if (frame == "world") out_.frame = CourseFrame::world;
    else if (frame == "wind") out_.frame = CourseFrame::wind;
    else return fail("$.frame", "expected \"world\" or \"wind\"");
    if (out_.frame == CourseFrame::wind) {
      const Value* r = member(root, "$", "reference", true, sink_);
      if (r == nullptr || !world_point(*r, "$.reference", out_.reference)) return false;
    } else if (const Value* r = root.find("reference")) {
      if (!world_point(*r, "$.reference", out_.reference)) return false;
    }
    return true;
  }

  bool marks(const Value& root) {
    const Value* mv = member(root, "$", "marks", true, sink_);
    if (mv == nullptr) return false;
    if (!mv->is_array() || mv->items.empty()) return fail("$.marks", "expected a non-empty array");
    for (std::size_t i = 0; i < mv->items.size(); ++i) {
      const Value& m = mv->items[i];
      const std::string p = path_index("$.marks", i);
      if (!data::expect_object(m, p, sink_)) return false;
      CourseMark mk;
      if (!id_field(m, p, mk.id)) return false;
      if (ends_with(mk.id, "_mid")) return fail(path_key(p, "id"), "ids ending in _mid are reserved for midpoints");
      for (const CourseMark& o : out_.marks) {
        if (o.id == mk.id) return fail(path_key(p, "id"), "duplicate mark id \"" + mk.id + "\"");
      }
      std::string type;
      if (!data::read_string(m, p, "type", type, sink_)) return false;
      if (type == "buoy") mk.type = MarkType::buoy;
      else if (type == "committee_boat") mk.type = MarkType::committee_boat;
      else if (type == "mark_boat") mk.type = MarkType::mark_boat;
      else if (type == "virtual") mk.type = MarkType::virtual_point;
      else return fail(path_key(p, "type"), "expected buoy, committee_boat, mark_boat or virtual");

      if (mk.type == MarkType::buoy) {
        mk.style = "inflatable";
        if (const Value* s = m.find("style")) {
          if (!s->is_string()) return fail(path_key(p, "style"), "expected a string");
          mk.style = s->text;
        }
        if (mk.style == "inflatable" || mk.style == "tetra") mk.radius = 0.8f;
        else if (mk.style == "large") mk.radius = 1.5f;
        else return fail(path_key(p, "style"), "expected inflatable, large or tetra");
      }
      if (mk.type == MarkType::committee_boat) {
        mk.length = 14.0f;
        mk.beam = 4.5f;
      } else if (mk.type == MarkType::mark_boat) {
        mk.length = 7.0f;
        mk.beam = 2.5f;
      }
      if (m.find("radius") != nullptr) {
        if (!read_float(m, p, "radius", mk.radius, sink_)) return false;
        if (!(mk.radius >= kRadiusMin)) return fail(path_key(p, "radius"), "radius below the 0.8 m minimum");
      }
      const bool is_boat = mk.type == MarkType::committee_boat || mk.type == MarkType::mark_boat;
      if (is_boat) {
        if (m.find("length") != nullptr) {
          if (!read_float(m, p, "length", mk.length, sink_)) return false;
          if (!(mk.length >= 2.0f * kRadiusMin)) return fail(path_key(p, "length"), "must be >= 1.6 m");
        }
        if (m.find("beam") != nullptr) {
          if (!read_float(m, p, "beam", mk.beam, sink_)) return false;
          if (!(mk.beam >= 2.0f * kRadiusMin) || mk.beam > mk.length) {
            return fail(path_key(p, "beam"), "must be >= 1.6 m and not above the length");
          }
        }
        if (const Value* ov = m.find("outline")) {
          const std::string op = path_key(p, "outline");
          if (!data::read_points(*ov, op, mk.outline, sink_)) return false;
          if (!convex_ccw_around_origin(mk.outline)) {
            return fail(op, "expected 6 to 32 vertices, strictly convex, counter-clockwise, around the origin");
          }
        }
        if (const Value* h = m.find("heading")) {
          if (!h->is_null()) {
            if (!read_float(m, p, "heading", mk.heading, sink_)) return false;
            if (mk.heading < 0.0f || mk.heading > TWO_PI) return fail(path_key(p, "heading"), "expected [0, 2π]");
            mk.head_to_wind = false;
          }
        }
      }
      const Value* at = member(m, p, "at", true, sink_);
      if (at == nullptr || !position(*at, path_key(p, "at"), i, mk.at)) return false;
      out_.marks.push_back(std::move(mk));
    }
    return true;
  }

  bool mark_ref(const Value& v, const std::string& path, std::int32_t& out) {
    if (!v.is_string()) return fail(path, "expected a mark id");
    out = out_.find_mark(v.text);
    if (out < 0) return fail(path, "unknown mark \"" + v.text + "\"");
    return true;
  }

  bool ends(const Value& obj, const std::string& path, std::int32_t e[2]) {
    const Value* ev = member(obj, path, "ends", true, sink_);
    if (ev == nullptr) return false;
    const std::string p = path_key(path, "ends");
    if (!ev->is_array() || ev->items.size() != 2) return fail(p, "expected two mark ids");
    if (!mark_ref(ev->items[0], path_index(p, 0), e[0]) || !mark_ref(ev->items[1], path_index(p, 1), e[1])) {
      return false;
    }
    if (e[0] == e[1]) return fail(p, "a line needs two different marks");
    return true;
  }

  bool lines(const Value& root) {
    const Value* s = member(root, "$", "start", true, sink_);
    if (s == nullptr || !data::expect_object(*s, "$.start", sink_)) return false;
    if (!ends(*s, "$.start", out_.start_ends)) return false;
    if (s->find("bias") != nullptr) {
      if (out_.frame != CourseFrame::wind) return fail("$.start.bias", "bias is for wind-frame courses only");
      if (!read_float(*s, "$.start", "bias", out_.start_bias, sink_)) return false;
      if (out_.start_bias < -HALF_PI || out_.start_bias > HALF_PI) return fail("$.start.bias", "expected [-π/2, π/2]");
    }
    const Value* f = member(root, "$", "finish", true, sink_);
    if (f == nullptr) return false;
    if (f->is_string()) {
      if (f->text != "start") return fail("$.finish", "expected \"start\" or an object with \"ends\"");
      out_.finish_is_start = true;
      out_.finish_ends[0] = out_.start_ends[0];
      out_.finish_ends[1] = out_.start_ends[1];
      return true;
    }
    if (!data::expect_object(*f, "$.finish", sink_)) return false;
    return ends(*f, "$.finish", out_.finish_ends);
  }

  bool side(const Value& v, const std::string& path, Side& out) {
    if (!v.is_string()) return fail(path, "expected \"port\" or \"starboard\"");
    if (v.text == "port") out = Side::port;
    else if (v.text == "starboard") out = Side::starboard;
    else return fail(path, "expected \"port\" or \"starboard\"");
    return true;
  }

  bool item(const Value& v, const std::string& path, int depth, std::int32_t source, SequenceItem& it) {
    it.source_index = source;
    if (v.is_string()) {
      if (v.text != "lap") return fail(path, "expected \"lap\" or an object");
      it.kind = SequenceItem::Kind::lap;
      return true;
    }
    if (!data::expect_object(v, path, sink_)) return false;
    if (const Value* m = v.find("mark")) {
      it.kind = SequenceItem::Kind::mark;
      if (!mark_ref(*m, path_key(path, "mark"), it.marks[0])) return false;
      if (out_.marks[static_cast<std::size_t>(it.marks[0])].type == MarkType::virtual_point) {
        return fail(path_key(path, "mark"), "a virtual point cannot be rounded");
      }
      const Value* r = member(v, path, "round", true, sink_);
      return r != nullptr && side(*r, path_key(path, "round"), it.sides[0]);
    }
    if (const Value* g = v.find("gate")) {
      it.kind = SequenceItem::Kind::gate;
      const std::string gp = path_key(path, "gate");
      if (!g->is_array() || g->items.size() != 2) return fail(gp, "expected two buoy ids");
      for (std::size_t k = 0; k < 2; ++k) {
        if (!mark_ref(g->items[k], path_index(gp, k), it.marks[k])) return false;
        if (out_.marks[static_cast<std::size_t>(it.marks[k])].type != MarkType::buoy) {
          return fail(path_index(gp, k), "gate marks are buoys");
        }
      }
      if (it.marks[0] == it.marks[1]) return fail(gp, "a gate needs two different buoys");
      if (const Value* r = v.find("round")) {
        const std::string rp = path_key(path, "round");
        if (!r->is_array() || r->items.size() != 2) return fail(rp, "expected two sides");
        if (!side(r->items[0], path_index(rp, 0), it.sides[0]) || !side(r->items[1], path_index(rp, 1), it.sides[1])) {
          return false;
        }
        it.has_sides = true;
      }
      if (const Value* gm = v.find("gate_mode")) {
        if (!gm->is_string()) return fail(path_key(path, "gate_mode"), "expected \"round\" or \"cross\"");
        if (gm->text == "round") it.gate_mode = GateMode::round;
        else if (gm->text == "cross") it.gate_mode = GateMode::cross;
        else return fail(path_key(path, "gate_mode"), "expected \"round\" or \"cross\"");
      }
      return true;
    }
    if (v.find("repeat") != nullptr) {
      it.kind = SequenceItem::Kind::repeat;
      if (depth >= 3) return fail(path, "repeat blocks nest one level at most");
      std::int64_t n = 0;
      if (!data::read_int(v, path, "repeat", n, sink_)) return false;
      if (n < 1 || n > 100) return fail(path_key(path, "repeat"), "expected 1 to 100");
      it.repeat = static_cast<std::int32_t>(n);
      const Value* st = member(v, path, "steps", true, sink_);
      if (st == nullptr) return false;
      const std::string sp = path_key(path, "steps");
      if (!st->is_array()) return fail(sp, "expected an array");
      for (std::size_t k = 0; k < st->items.size(); ++k) {
        SequenceItem child;
        if (!item(st->items[k], path_index(sp, k), depth + 1, source, child)) return false;
        it.steps.push_back(std::move(child));
      }
      return true;
    }
    return fail(path, "expected a mark, a gate, a repeat block or \"lap\"");
  }

  bool sequence(const Value& root) {
    const Value* sv = member(root, "$", "sequence", true, sink_);
    if (sv == nullptr) return false;
    if (!sv->is_array()) return fail("$.sequence", "expected an array");
    for (std::size_t i = 0; i < sv->items.size(); ++i) {
      SequenceItem it;
      if (!item(sv->items[i], path_index("$.sequence", i), 1, static_cast<std::int32_t>(i), it)) return false;
      out_.sequence.push_back(std::move(it));
    }
    return true;
  }

  bool polygon(const Value& v, const std::string& path, std::vector<CoursePos>& out) {
    if (!v.is_array() || v.items.size() < 3) return fail(path, "expected at least 3 points");
    for (std::size_t i = 0; i < v.items.size(); ++i) {
      CoursePos p;
      if (!position(v.items[i], path_index(path, i), out_.marks.size(), p)) return false;
      out.push_back(p);
    }
    return true;
  }

  bool area(const Value& root) {
    const Value* av = root.find("area");
    if (av == nullptr) return true;
    if (!data::expect_object(*av, "$.area", sink_)) return false;
    if (const Value* b = av->find("boundary")) {
      if (!polygon(*b, "$.area.boundary", out_.boundary)) return false;
      out_.has_boundary = true;
    }
    if (const Value* ex = av->find("exclusions")) {
      if (!ex->is_array()) return fail("$.area.exclusions", "expected an array");
      for (std::size_t i = 0; i < ex->items.size(); ++i) {
        const std::string p = path_index("$.area.exclusions", i);
        if (!data::expect_object(ex->items[i], p, sink_)) return false;
        CourseExclusion e;
        if (!id_field(ex->items[i], p, e.id)) return false;
        const Value* pv = member(ex->items[i], p, "polygon", true, sink_);
        if (pv == nullptr || !polygon(*pv, path_key(p, "polygon"), e.polygon)) return false;
        out_.exclusions.push_back(std::move(e));
      }
    }
    if (const Value* sp = av->find("spawn")) {
      if (!data::expect_object(*sp, "$.area.spawn", sink_)) return false;
      const Value* pv = member(*sp, "$.area.spawn", "polygon", true, sink_);
      if (pv == nullptr || !polygon(*pv, "$.area.spawn.polygon", out_.spawn)) return false;
      out_.has_spawn = true;
    }
    return true;
  }

  bool race(const Value& root) {
    const Value* rv = root.find("race");
    if (rv == nullptr) return true;
    const std::string p = "$.race";
    if (!data::expect_object(*rv, p, sink_)) return false;
    CourseRaceDefaults& r = out_.race;
    if (const Value* t = rv->find("type")) {
      if (!t->is_string() || (t->text != "fleet" && t->text != "match")) {
        return fail(path_key(p, "type"), "expected \"fleet\" or \"match\"");
      }
      r.has_type = true;
      r.type = t->text == "fleet" ? RaceType::fleet : RaceType::match;
    }
    if (const Value* s = rv->find("sequence")) {
      if (!s->is_string()) return fail(path_key(p, "sequence"), "expected a string");
      r.has_sequence = true;
      if (s->text == "5-4-1-0") r.sequence = SequenceKind::s5410;
      else if (s->text == "3-2-1-0") r.sequence = SequenceKind::s3210;
      else if (s->text == "match") r.sequence = SequenceKind::match;
      else return fail(path_key(p, "sequence"), "expected \"5-4-1-0\", \"3-2-1-0\" or \"match\"");
    }
    if (const Value* f = rv->find("prep_flag")) {
      if (!f->is_string()) return fail(path_key(p, "prep_flag"), "expected a string");
      r.has_prep_flag = true;
      if (f->text == "P") r.prep_flag = PrepFlag::P;
      else if (f->text == "I") r.prep_flag = PrepFlag::I;
      else if (f->text == "Z") r.prep_flag = PrepFlag::Z;
      else if (f->text == "U") r.prep_flag = PrepFlag::U;
      else if (f->text == "black") r.prep_flag = PrepFlag::black;
      else return fail(path_key(p, "prep_flag"), "expected P, I, Z, U or black");
    }
    if (rv->find("time_limit") != nullptr) {
      if (!read_float(*rv, p, "time_limit", r.time_limit, sink_)) return false;
      if (!(r.time_limit >= 0.0f)) return fail(path_key(p, "time_limit"), "must be >= 0");
    }
    if (rv->find("target_duration") != nullptr) {
      if (!read_float(*rv, p, "target_duration", r.target_duration, sink_)) return false;
      if (!(r.target_duration >= 0.0f)) return fail(path_key(p, "target_duration"), "must be >= 0");
    }
    if (rv->find("zone_lengths") != nullptr) {
      if (!read_float(*rv, p, "zone_lengths", r.zone_lengths, sink_)) return false;
      if (!(r.zone_lengths >= 1.0f && r.zone_lengths <= 6.0f)) return fail(path_key(p, "zone_lengths"), "expected 1 to 6");
    }
    return true;
  }

  bool display(const Value& root) {
    const Value* dv = root.find("display");
    if (dv == nullptr) return true;
    if (!data::expect_object(*dv, "$.display", sink_)) return false;
    if (const Value* n = dv->find("names")) {
      if (!n->is_object()) return fail("$.display.names", "expected an object");
      for (const auto& [lang, text] : n->members) {
        if (!text.is_string()) return fail(path_key("$.display.names", lang), "expected a string");
        if (has_em_dash(text.text)) return fail(path_key("$.display.names", lang), "player-facing text has no em dashes");
      }
    }
    if (const Value* l = dv->find("labels")) {
      if (!l->is_object()) return fail("$.display.labels", "expected an object");
      for (const auto& [id, text] : l->members) {
        const std::string p = path_key("$.display.labels", id);
        if (out_.find_mark(id) < 0) return fail(p, "unknown mark \"" + id + "\"");
        if (!text.is_string()) return fail(p, "expected a string");
        if (has_em_dash(text.text)) return fail(p, "player-facing text has no em dashes");
        out_.labels.push_back({id, text.text});
      }
    }
    return true;
  }

  // courses.md §4.4 expansion with lap numbers.
  struct Flat {
    const SequenceItem* it;
    std::int32_t lap;
  };

  void flatten(const std::vector<SequenceItem>& items, bool markers, bool top, std::int32_t& lap_marker,
               std::int32_t& iterations, std::vector<Flat>& out) {
    for (const SequenceItem& it : items) {
      switch (it.kind) {
        case SequenceItem::Kind::lap:
          ++lap_marker;
          break;
        case SequenceItem::Kind::repeat:
          for (std::int32_t r = 0; r < it.repeat; ++r) {
            if (top && !markers) ++iterations;
            flatten(it.steps, markers, false, lap_marker, iterations, out);
          }
          break;
        default:
          out.push_back({&it, markers ? lap_marker : (iterations > 1 ? iterations : 1)});
          break;
      }
    }
  }

  static bool any_marker(const std::vector<SequenceItem>& items) {
    for (const SequenceItem& it : items) {
      if (it.kind == SequenceItem::Kind::lap) return true;
      if (it.kind == SequenceItem::Kind::repeat && any_marker(it.steps)) return true;
    }
    return false;
  }

  bool expand() {
    const bool markers = any_marker(out_.sequence);
    std::int32_t lap_marker = 1, iterations = 0;
    std::vector<Flat> flat;
    flatten(out_.sequence, markers, true, lap_marker, iterations, flat);
    if (flat.empty()) return fail("$.sequence", "the sequence expands to no step");
    std::vector<CourseStep>& st = out_.expanded;
    CourseStep s0;
    s0.kind = StepKind::start;
    s0.marks[0] = out_.start_ends[0];
    s0.marks[1] = out_.start_ends[1];
    s0.lap = 1;
    s0.leg_in_lap = 0;
    st.push_back(s0);
    std::int32_t prev_lap = 1, leg = 0;
    for (const Flat& f : flat) {
      CourseStep s;
      s.kind = f.it->kind == SequenceItem::Kind::gate ? StepKind::gate : StepKind::mark;
      s.marks[0] = f.it->marks[0];
      s.marks[1] = f.it->marks[1];
      s.sides[0] = f.it->sides[0];
      s.sides[1] = f.it->sides[1];
      s.gate_mode = f.it->gate_mode;
      s.sides_given = f.it->has_sides;
      s.source_index = f.it->source_index;
      s.lap = f.lap < prev_lap ? prev_lap : f.lap;
      leg = s.lap == prev_lap ? leg + 1 : 1;
      prev_lap = s.lap;
      s.leg_in_lap = leg;
      st.push_back(s);
    }
    CourseStep fin;
    fin.kind = StepKind::finish;
    fin.marks[0] = out_.finish_ends[0];
    fin.marks[1] = out_.finish_ends[1];
    fin.lap = prev_lap;
    fin.leg_in_lap = leg + 1;
    st.push_back(fin);
    return true;
  }
};

}  // namespace

bool parse_course(std::string_view text, std::string_view file, CourseData& out, LoadError& err) {
  out = CourseData{};
  err = LoadError{};
  ErrorSink sink(err, file);
  const json::ParseResult pr = json::parse(text);
  if (!pr.ok) return sink.fail("", "JSON: " + pr.error);
  CourseReader reader(sink, out);
  if (!reader.read(pr.value)) {
    out = CourseData{};
    return false;
  }
  const auto* bytes = reinterpret_cast<const std::uint8_t*>(text.data());
  out.file_sha256 = to_hex(sha256(std::span<const std::uint8_t>(bytes, text.size())));
  return true;
}

bool load_course(const std::string& file, CourseData& out, LoadError& err) {
  out = CourseData{};
  std::string text;
  if (!data::read_file(file, text, err)) return false;
  return parse_course(text, file, out, err);
}

}  // namespace wm
