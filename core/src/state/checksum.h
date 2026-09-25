// State snapshots and the tick checksum (conventions.md §9): floats as their 32 raw bits, integers little
// endian, booleans one byte; FNV-1a 64 over the tick index then every boat's snapshot bytes in index order.
#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace wm {

class Fnv1a64 {
 public:
  static constexpr std::uint64_t kOffset = 0xCBF29CE484222325ull;
  static constexpr std::uint64_t kPrime = 0x00000100000001B3ull;

  void update(std::span<const std::uint8_t> bytes);
  void update_u32(std::uint32_t v);  // little endian
  std::uint64_t value() const { return h_; }

 private:
  std::uint64_t h_ = kOffset;
};

std::uint64_t fnv1a64(std::span<const std::uint8_t> bytes);

// Serialises state in the order a spec lists it.
class SnapshotWriter {
 public:
  void put_u8(std::uint8_t v) { bytes_.push_back(v); }
  void put_i8(std::int8_t v) { bytes_.push_back(static_cast<std::uint8_t>(v)); }
  void put_bool(bool v) { bytes_.push_back(v ? 1 : 0); }
  void put_u16(std::uint16_t v);
  void put_u32(std::uint32_t v);
  void put_i32(std::int32_t v) { put_u32(static_cast<std::uint32_t>(v)); }
  void put_u64(std::uint64_t v);
  void put_f32(float v);  // raw bits, so -0 and NaN payloads are kept

  const std::vector<std::uint8_t>& bytes() const { return bytes_; }
  void clear() { bytes_.clear(); }

 private:
  std::vector<std::uint8_t> bytes_;
};

// Reads what SnapshotWriter wrote. Reading past the end sets failed() and returns zeros.
class SnapshotReader {
 public:
  explicit SnapshotReader(std::span<const std::uint8_t> bytes) : bytes_(bytes) {}

  std::uint8_t get_u8();
  std::int8_t get_i8() { return static_cast<std::int8_t>(get_u8()); }
  bool get_bool() { return get_u8() != 0; }
  std::uint16_t get_u16();
  std::uint32_t get_u32();
  std::int32_t get_i32() { return static_cast<std::int32_t>(get_u32()); }
  std::uint64_t get_u64();
  float get_f32();

  bool failed() const { return failed_; }
  bool at_end() const { return pos_ == bytes_.size(); }

 private:
  std::span<const std::uint8_t> bytes_;
  std::size_t pos_ = 0;
  bool failed_ = false;
};

// Tick checksum: FNV-1a 64 over the tick index (uint32 LE) then each boat's snapshot bytes in index order.
std::uint64_t tick_checksum(std::uint32_t tick, std::span<const std::vector<std::uint8_t>> boat_snapshots);

}  // namespace wm
