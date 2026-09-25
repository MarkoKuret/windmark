// conventions.md §9 snapshots and checksum; SHA-256 for data identity.
#include <cmath>
#include <string>
#include <string_view>
#include <vector>

#include "doctest.h"
#include "state/checksum.h"
#include "state/sha256.h"

namespace {

std::vector<std::uint8_t> bytes_of(std::string_view s) { return {s.begin(), s.end()}; }

}  // namespace

TEST_CASE("FNV-1a 64 reference values") {
  CHECK(wm::fnv1a64(bytes_of("")) == 0xCBF29CE484222325ull);
  CHECK(wm::fnv1a64(bytes_of("a")) == 0xAF63DC4C8601EC8Cull);
  CHECK(wm::fnv1a64(bytes_of("foobar")) == 0x85944171F73967E8ull);
}

TEST_CASE("snapshot writer: little endian, floats as raw bits, round trip") {
  wm::SnapshotWriter w;
  w.put_u32(0x01020304u);
  w.put_f32(1.0f);
  w.put_f32(-0.0f);
  w.put_bool(true);
  w.put_i8(-2);
  w.put_u16(0xBEEF);
  w.put_u64(0x1122334455667788ull);
  const std::vector<std::uint8_t> expect{0x04, 0x03, 0x02, 0x01, 0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x00, 0x80,
                                         0x01, 0xFE, 0xEF, 0xBE, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11};
  CHECK(w.bytes() == expect);

  wm::SnapshotReader r(w.bytes());
  CHECK(r.get_u32() == 0x01020304u);
  CHECK(r.get_f32() == 1.0f);
  const float nz = r.get_f32();
  CHECK((nz == 0.0f && std::signbit(nz)));
  CHECK(r.get_bool());
  CHECK(r.get_i8() == -2);
  CHECK(r.get_u16() == 0xBEEF);
  CHECK(r.get_u64() == 0x1122334455667788ull);
  CHECK(r.at_end());
  CHECK(!r.failed());
  r.get_u8();
  CHECK(r.failed());
}

TEST_CASE("tick checksum: tick index first, then boats in index order") {
  const std::vector<std::vector<std::uint8_t>> boats{{1, 2, 3}, {4, 5}};
  std::vector<std::uint8_t> all{7, 0, 0, 0, 1, 2, 3, 4, 5};
  CHECK(wm::tick_checksum(7, boats) == wm::fnv1a64(all));
  const std::vector<std::vector<std::uint8_t>> swapped{{4, 5}, {1, 2, 3}};
  CHECK(wm::tick_checksum(7, swapped) != wm::tick_checksum(7, boats));
  CHECK(wm::tick_checksum(8, boats) != wm::tick_checksum(7, boats));
}

TEST_CASE("SHA-256 reference values") {
  CHECK(wm::to_hex(wm::sha256(bytes_of(""))) ==
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(wm::to_hex(wm::sha256(bytes_of("abc"))) ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  CHECK(wm::to_hex(wm::sha256(bytes_of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))) ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  const std::vector<std::uint8_t> million(1000000, 'a');
  CHECK(wm::to_hex(wm::sha256(million)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  // Lengths around the padding boundary.
  CHECK(wm::to_hex(wm::sha256(std::vector<std::uint8_t>(55, 'a'))) ==
        "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318");
  CHECK(wm::to_hex(wm::sha256(std::vector<std::uint8_t>(64, 'a'))) ==
        "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
}
