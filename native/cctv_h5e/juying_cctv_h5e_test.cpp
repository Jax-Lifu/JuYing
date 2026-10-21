#include "juying_cctv_h5e.h"

#include <algorithm>
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include "cctv_h5e_decrypt.hpp"

namespace {
using Bytes = std::vector<uint8_t>;

void Check(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

void AppendCrc(Bytes &section) {
  uint32_t crc = 0xffffffff;
  for (uint8_t value : section) {
    crc ^= static_cast<uint32_t>(value) << 24;
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x80000000) ? (crc << 1) ^ 0x04c11db7 : crc << 1;
    }
  }
  for (int shift = 24; shift >= 0; shift -= 8) {
    section.push_back(static_cast<uint8_t>(crc >> shift));
  }
}

void AddPacket(Bytes &ts, uint16_t pid, bool start, uint8_t counter,
               const Bytes &payload) {
  Check(!payload.empty() && payload.size() <= 184, "invalid test payload");
  std::array<uint8_t, 188> packet;
  packet.fill(0xff);
  packet[0] = 0x47;
  packet[1] = static_cast<uint8_t>((pid >> 8) | (start ? 0x40 : 0));
  packet[2] = static_cast<uint8_t>(pid);
  packet[3] = static_cast<uint8_t>((payload.size() == 184 ? 0x10 : 0x30) |
                                   (counter & 15));
  const size_t offset = packet.size() - payload.size();
  if (payload.size() != 184) {
    packet[4] = static_cast<uint8_t>(183 - payload.size());
    if (packet[4] != 0)
      packet[5] = 0;
  }
  std::copy(payload.begin(), payload.end(), packet.begin() + offset);
  ts.insert(ts.end(), packet.begin(), packet.end());
}

Bytes MakeTables(uint16_t video_pid, uint8_t stream_type = 0x1b,
                 bool split_pmt = false) {
  Bytes ts;
  Bytes pat{0, 0xb0, 13, 0, 1, 0xc1, 0, 0, 0, 1, 0xf0, 0};
  AppendCrc(pat);
  pat.insert(pat.begin(), 0);
  AddPacket(ts, 0, true, 0, pat);
  const uint8_t high = static_cast<uint8_t>(0xe0 | (video_pid >> 8));
  const uint8_t low = static_cast<uint8_t>(video_pid);
  Bytes pmt{2,   0xb0, 18, 0,           1,    0xc1, 0,    0, high,
            low, 0xf0, 0,  stream_type, high, low,  0xf0, 0};
  AppendCrc(pmt);
  pmt.insert(pmt.begin(), 0);
  if (split_pmt) {
    AddPacket(ts, 0x1000, true, 0, Bytes(pmt.begin(), pmt.begin() + 8));
    AddPacket(ts, 0x1000, false, 1, Bytes(pmt.begin() + 8, pmt.end()));
  } else {
    AddPacket(ts, 0x1000, true, 0, pmt);
  }
  return ts;
}

Bytes MakeSegment(uint16_t pid, const Bytes &elementary,
                  bool split_pmt = false) {
  Bytes ts = MakeTables(pid, 0x1b, split_pmt);
  Bytes pes{0, 0, 1, 0xe0, 0, 0, 0x80, 0, 0};
  pes.insert(pes.end(), elementary.begin(), elementary.end());
  uint8_t counter = 0;
  for (size_t offset = 0; offset < pes.size(); offset += 184) {
    const size_t end = std::min(offset + 184, pes.size());
    AddPacket(ts, pid, offset == 0, counter++,
              Bytes(pes.begin() + offset, pes.begin() + end));
  }
  return ts;
}

void CheckFailure(Bytes input, const char *message) {
  const Bytes original = input;
  Check(juying_h5e_decode(input.data(), static_cast<intptr_t>(input.size())) <
            0,
        message);
  Check(input == original, "failure changed caller bytes");
}

void CheckSynthetic() {
  Check(juying_h5e_alloc(0) == nullptr, "zero allocation accepted");
  Check(juying_h5e_alloc(-1) == nullptr, "negative allocation accepted");
  Check(juying_h5e_alloc(32 * 1024 * 1024 + 1) == nullptr,
        "oversized allocation accepted");
  auto *allocation = juying_h5e_alloc(188);
  Check(allocation != nullptr, "allocation failed");
  juying_h5e_free(allocation);
  juying_h5e_free(nullptr);
  Check(juying_h5e_decode(nullptr, 188) < 0, "null accepted");

  Bytes plain_nal(200, 0x55);
  plain_nal[0] = 0x65;
  Bytes plain_es{0, 0, 1};
  plain_es.insert(plain_es.end(), plain_nal.begin(), plain_nal.end());
  const Bytes plain = MakeSegment(0x123, plain_es);
  Bytes value = plain;
  Check(juying_h5e_decode(value.data(), value.size()) == 0 && value == plain,
        "non-default H264 PID/plain segment failed");
  value = MakeSegment(0x1a2, plain_es, true);
  const Bytes split = value;
  Check(juying_h5e_decode(value.data(), value.size()) == 0 && value == split,
        "split PMT reassembly failed");

  // A deterministic classic H5E slice exercises state isolation without
  // checking copyrighted media into the repository.
  Bytes encrypted_nal = plain_nal;
  for (size_t offset = 32; offset + 80 <= encrypted_nal.size(); offset += 80) {
    cctv_h5e::tea_encrypt_block(encrypted_nal.data() + offset,
                                encrypted_nal.data() + offset,
                                plain_nal.data() + 16);
  }
  Bytes encrypted_es{0, 0, 1, 0x19, 1, 1, 6, 0, 0, 1};
  encrypted_es.insert(encrypted_es.end(), encrypted_nal.begin(),
                      encrypted_nal.end());
  Bytes expected_es{0, 0, 1, 0x19, 1, 1, 6, 0, 0, 1};
  expected_es.insert(expected_es.end(), plain_nal.begin(), plain_nal.end());
  const Bytes expected = MakeSegment(0x123, expected_es);
  const Bytes encrypted = MakeSegment(0x123, encrypted_es);
  value = encrypted;
  Check(value != expected, "synthetic encryption did not change the slice");
  Check(juying_h5e_decode(value.data(), value.size()) == 0 && value == expected,
        "encrypted synthetic segment failed");
  value = plain;
  Check(juying_h5e_decode(value.data(), value.size()) == 0 && value == plain,
        "previous segment state leaked into plaintext");
  value = encrypted;
  Check(juying_h5e_decode(value.data(), value.size()) == 0 && value == expected,
        "independent repeated segment changed output");

  value = plain;
  value.pop_back();
  CheckFailure(value, "partial packet accepted");
  value = plain;
  value[0] = 0;
  CheckFailure(value, "invalid sync accepted");
  value = plain;
  value[1] |= 0x80;
  CheckFailure(value, "transport error accepted");
  value = plain;
  value[3] &= 0xcf;
  CheckFailure(value, "reserved adaptation control accepted");
  value = plain;
  value[4] = 255;
  CheckFailure(value, "adaptation overrun accepted");
  value = plain;
  value[188 - 17] = 255;
  CheckFailure(value, "PSI pointer overrun accepted");
  value = plain;
  value[187] ^= 1;
  CheckFailure(value, "invalid PSI CRC accepted");
  value = MakeTables(0x123, 0x24);
  CheckFailure(value, "unsupported HEVC accepted");
  value = MakeTables(0x123);
  CheckFailure(value, "missing PES accepted");
  value = plain;
  value[2 * 188 + 1] &= ~0x40;
  CheckFailure(value, "leading PES continuation accepted");
  value = plain;
  value[3 * 188 + 3] ^= 3;
  CheckFailure(value, "missing video packet accepted");

  // Exercise mutation-driven trust-boundary checks; failed calls must be
  // atomic even when a malformed section reaches the vendored parser.
  std::mt19937 random(0x485545);
  for (int iteration = 0; iteration < 10000; ++iteration) {
    value = encrypted;
    const size_t offset = random() % value.size();
    value[offset] ^= static_cast<uint8_t>(1 + random() % 255);
    const Bytes original = value;
    const int status = juying_h5e_decode(value.data(), value.size());
    Check(status == 0 || value == original, "mutation failure was not atomic");
  }

  // Large hostile NALs must remain bounded work after EPB removal. This
  // complete TS intentionally carries dense markers, not playable video.
  Bytes dense_es{0, 0, 1, 0x19, 1, 1, 9, 0, 0, 1, 0x65};
  for (size_t count = 0; count < 350000; ++count) {
    dense_es.insert(dense_es.end(), {0, 0, 3});
  }
  value = MakeSegment(0x123, dense_es);
  Check(juying_h5e_decode(value.data(), value.size()) == 0,
        "large marker-dense segment failed");
}

Bytes ReadFile(const char *path) {
  std::ifstream file(path, std::ios::binary);
  Check(static_cast<bool>(file), "fixture could not be opened");
  return Bytes(std::istreambuf_iterator<char>(file), {});
}
} // namespace

int main(int argc, char **argv) {
  try {
    Check((argc - 1) % 2 == 0, "usage: test [source.ts expected.ts]...");
    CheckSynthetic();
    for (int index = 1; index < argc; index += 2) {
      Bytes input = ReadFile(argv[index]);
      const Bytes expected = ReadFile(argv[index + 1]);
      Check(juying_h5e_decode(input.data(), input.size()) == 0,
            "real segment decode failed");
      Check(input == expected, "real segment differs from verified output");
      std::cout << "Verified " << argv[index] << '\n';
    }
    std::cout << "H5E native checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
