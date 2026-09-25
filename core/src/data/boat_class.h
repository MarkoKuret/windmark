// Boat-class file `windmark.boatclass/1` (data_format.md §3), as far as the core needs it. The core sails from
// the performance file alone; it reads the class file only to check that a performance file was generated from
// it (same id, version, file hash and sail inventory, data_format.md §7).
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "data/load_error.h"
#include "data/perf.h"

namespace wm {

struct BoatClassSail {
  std::string id;
  SailType type = SailType::main;
  float area = 0.0f;  // m²
};

struct BoatClassInfo {
  std::string id;
  std::string name;
  std::int64_t version = 0;
  std::string sha256;  // lowercase hex of the file bytes
  std::vector<BoatClassSail> sails;  // in file order, exactly one main
  std::int32_t start_front_sail = -1;  // index into sails, -1 = none
};

bool parse_boat_class(std::string_view text, std::string_view file, BoatClassInfo& out, LoadError& err);
bool load_boat_class(const std::string& file, BoatClassInfo& out, LoadError& err);

// True when `perf` was generated from this class file: class id, version and sha256 match, and the sails are
// the same ids with the same types. Otherwise false with the reason in `err`.
bool perf_matches_class(const PerfData& perf, const BoatClassInfo& cls, LoadError& err);

}  // namespace wm
