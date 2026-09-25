// Writes the environment vector file the test suite checks (tests/vectors/env_vectors.txt): wind at a grid of
// points and times (FNV-1a 64 of the bit patterns), sea heights and slopes, and wind-shadow losses of the fixed
// scenarios in tests/env_scenarios.h. Regenerate only on purpose, and check the result on a second architecture
// before committing it:
//   build/tests/windmark_gen_env_vectors > tests/vectors/env_vectors.txt
#include <cstdio>

#include "env_scenarios.h"

int main() {
  std::printf("# windmark env vectors: wind (hash of a 50 x 50 grid), sea, shadow; binary32 bit patterns, hex\n");
  for (const std::string& line : wm_env::env_vector_lines()) std::printf("%s\n", line.c_str());
  return 0;
}
