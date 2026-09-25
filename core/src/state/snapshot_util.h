// Encodings shared by the race, rules and world snapshots (conventions.md §9): vec2 as two floats, list<T> as a
// uint32 count then the items, enums as one byte. Readers check counts against the bytes left and enums against
// their last value, and mark the reader failed on a bad value.
#pragma once

#include <cstdint>
#include <vector>

#include "math/wm_math.h"
#include "state/checksum.h"

namespace wm::snap {

inline void put_vec2(SnapshotWriter& w, Vec2 v) {
  w.put_f32(v.x);
  w.put_f32(v.y);
}

inline Vec2 get_vec2(SnapshotReader& r) {
  const float x = r.get_f32();
  const float y = r.get_f32();
  return {x, y};
}

template <class E>
void put_enum(SnapshotWriter& w, E e) {
  w.put_u8(static_cast<std::uint8_t>(e));
}

// `last` is the enum's highest value.
template <class E>
E get_enum(SnapshotReader& r, E last) {
  const std::uint8_t v = r.get_u8();
  if (v > static_cast<std::uint8_t>(last)) {
    r.fail();
    return E{};
  }
  return static_cast<E>(v);
}

inline void put_count(SnapshotWriter& w, std::size_t n) { w.put_u32(static_cast<std::uint32_t>(n)); }

// A list count; each item takes at least `min_item_bytes`, so a count the bytes left cannot hold fails.
inline std::uint32_t get_count(SnapshotReader& r, std::size_t min_item_bytes = 1) {
  const std::uint32_t n = r.get_u32();
  if (r.failed() || static_cast<std::uint64_t>(n) * min_item_bytes > r.remaining()) {
    r.fail();
    return 0;
  }
  return n;
}

inline void put_vec2s(SnapshotWriter& w, const std::vector<Vec2>& v) {
  put_count(w, v.size());
  for (const Vec2 p : v) put_vec2(w, p);
}

inline void get_vec2s(SnapshotReader& r, std::vector<Vec2>& v) {
  const std::uint32_t n = get_count(r, 8);
  v.resize(n);
  for (Vec2& p : v) p = get_vec2(r);
}

inline void put_f32s(SnapshotWriter& w, const std::vector<float>& v) {
  put_count(w, v.size());
  for (const float x : v) w.put_f32(x);
}

inline void get_f32s(SnapshotReader& r, std::vector<float>& v) {
  const std::uint32_t n = get_count(r, 4);
  v.resize(n);
  for (float& x : v) x = r.get_f32();
}

inline void put_u8s(SnapshotWriter& w, const std::vector<std::uint8_t>& v) {
  put_count(w, v.size());
  for (const std::uint8_t x : v) w.put_u8(x);
}

inline void get_u8s(SnapshotReader& r, std::vector<std::uint8_t>& v) {
  const std::uint32_t n = get_count(r, 1);
  v.resize(n);
  for (std::uint8_t& x : v) x = r.get_u8();
}

inline void put_u32s(SnapshotWriter& w, const std::vector<std::uint32_t>& v) {
  put_count(w, v.size());
  for (const std::uint32_t x : v) w.put_u32(x);
}

inline void get_u32s(SnapshotReader& r, std::vector<std::uint32_t>& v) {
  const std::uint32_t n = get_count(r, 4);
  v.resize(n);
  for (std::uint32_t& x : v) x = r.get_u32();
}

inline void put_i32s(SnapshotWriter& w, const std::vector<std::int32_t>& v) {
  put_count(w, v.size());
  for (const std::int32_t x : v) w.put_i32(x);
}

inline void get_i32s(SnapshotReader& r, std::vector<std::int32_t>& v) {
  const std::uint32_t n = get_count(r, 4);
  v.resize(n);
  for (std::int32_t& x : v) x = r.get_i32();
}

inline void put_i64(SnapshotWriter& w, std::int64_t v) { w.put_u64(static_cast<std::uint64_t>(v)); }
inline std::int64_t get_i64(SnapshotReader& r) { return static_cast<std::int64_t>(r.get_u64()); }

}  // namespace wm::snap
