// wind.md §10.1, sea.md §8.1, wind_shadow.md §4: the environment reproduces the stored vector file bit for bit
// (wind over a 50 x 50 grid at 100 times per scenario as a hash, sea heights and slopes up to 8 km and 4 h,
// shadow losses).
#include <fstream>
#include <string>
#include <vector>

#include "doctest.h"
#include "env_scenarios.h"

TEST_CASE("env vector file: wind, sea and shadow bit for bit") {
  std::ifstream in(WINDMARK_ENV_VECTORS_FILE);
  REQUIRE_MESSAGE(in.good(), "missing " << WINDMARK_ENV_VECTORS_FILE);
  std::vector<std::string> stored;
  for (std::string line; std::getline(in, line);)
    if (!line.empty() && line[0] != '#') stored.push_back(line);
  const std::vector<std::string> now = wm_env::env_vector_lines();
  REQUIRE(stored.size() == now.size());
  int failed = 0;
  for (std::size_t i = 0; i < now.size(); ++i)
    if (stored[i] != now[i]) {
      if (failed < 10) MESSAGE("mismatch:\n  stored " << stored[i] << "\n  now    " << now[i]);
      ++failed;
    }
  MESSAGE(now.size() << " env vectors checked");
  CHECK(failed == 0);
}

TEST_CASE("env vectors are the same on a second evaluation") {
  CHECK(wm_env::env_vector_lines() == wm_env::env_vector_lines());
}
