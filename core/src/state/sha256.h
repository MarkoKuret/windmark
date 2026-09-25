// SHA-256 (FIPS 180-4) for data identity: the perf file records the hash of its class file, and online the
// server announces the hash of each perf file (data_format.md §4.1, §7).
#pragma once

#include <array>
#include <cstdint>
#include <span>
#include <string>

namespace wm {

using Sha256Digest = std::array<std::uint8_t, 32>;

Sha256Digest sha256(std::span<const std::uint8_t> bytes);
std::string to_hex(const Sha256Digest& d);  // lowercase, 64 characters

}  // namespace wm
