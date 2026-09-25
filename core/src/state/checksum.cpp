#include "state/checksum.h"

#include <cstring>

namespace wm {

void Fnv1a64::update(std::span<const std::uint8_t> bytes) {
  for (std::uint8_t b : bytes) {
    h_ ^= b;
    h_ *= kPrime;
  }
}

void Fnv1a64::update_u32(std::uint32_t v) {
  const std::uint8_t b[4] = {static_cast<std::uint8_t>(v), static_cast<std::uint8_t>(v >> 8),
                             static_cast<std::uint8_t>(v >> 16), static_cast<std::uint8_t>(v >> 24)};
  update(b);
}

std::uint64_t fnv1a64(std::span<const std::uint8_t> bytes) {
  Fnv1a64 h;
  h.update(bytes);
  return h.value();
}

void SnapshotWriter::put_u16(std::uint16_t v) {
  bytes_.push_back(static_cast<std::uint8_t>(v));
  bytes_.push_back(static_cast<std::uint8_t>(v >> 8));
}

void SnapshotWriter::put_u32(std::uint32_t v) {
  for (int i = 0; i < 4; ++i) bytes_.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
}

void SnapshotWriter::put_u64(std::uint64_t v) {
  for (int i = 0; i < 8; ++i) bytes_.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
}

void SnapshotWriter::put_f32(float v) {
  std::uint32_t u;
  std::memcpy(&u, &v, sizeof u);
  put_u32(u);
}

std::uint8_t SnapshotReader::get_u8() {
  if (pos_ >= bytes_.size()) {
    failed_ = true;
    return 0;
  }
  return bytes_[pos_++];
}

std::uint16_t SnapshotReader::get_u16() {
  const std::uint16_t lo = get_u8();
  const std::uint16_t hi = get_u8();
  return static_cast<std::uint16_t>(lo | (hi << 8));
}

std::uint32_t SnapshotReader::get_u32() {
  std::uint32_t v = 0;
  for (int i = 0; i < 4; ++i) v |= static_cast<std::uint32_t>(get_u8()) << (8 * i);
  return v;
}

std::uint64_t SnapshotReader::get_u64() {
  std::uint64_t v = 0;
  for (int i = 0; i < 8; ++i) v |= static_cast<std::uint64_t>(get_u8()) << (8 * i);
  return v;
}

float SnapshotReader::get_f32() {
  const std::uint32_t u = get_u32();
  float f;
  std::memcpy(&f, &u, sizeof f);
  return f;
}

std::uint64_t tick_checksum(std::uint32_t tick, std::span<const std::vector<std::uint8_t>> boat_snapshots) {
  Fnv1a64 h;
  h.update_u32(tick);
  for (const std::vector<std::uint8_t>& s : boat_snapshots) h.update(s);
  return h.value();
}

}  // namespace wm
