#include "juying_cctv_h5e.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "cctv_h5e_decrypt.hpp"

namespace {
constexpr size_t kPacketSize = 188;
constexpr intptr_t kMaxSegmentSize = 32 * 1024 * 1024;

uint16_t PacketPid(const uint8_t *packet) {
  return static_cast<uint16_t>(((packet[1] & 0x1f) << 8) | packet[2]);
}

size_t PayloadOffset(const uint8_t *packet) {
  const auto control = (packet[3] >> 4) & 3;
  if (control == 2)
    return kPacketSize;
  return control == 1 ? 4 : 5 + packet[4];
}

bool ValidPackets(const uint8_t *data, size_t size) {
  for (size_t offset = 0; offset < size; offset += kPacketSize) {
    const uint8_t *packet = data + offset;
    const auto control = (packet[3] >> 4) & 3;
    if (packet[0] != 0x47 || (packet[1] & 0x80) != 0 ||
        (packet[3] & 0xc0) != 0 || control == 0) {
      return false;
    }
    if ((control == 2 && packet[4] != 183) ||
        (control == 3 && packet[4] > 182)) {
      return false;
    }
  }
  return true;
}

bool ValidSectionCrc(const std::vector<uint8_t> &section) {
  uint32_t crc = 0xffffffff;
  for (uint8_t byte : section) {
    crc ^= static_cast<uint32_t>(byte) << 24;
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x80000000) ? (crc << 1) ^ 0x04c11db7 : crc << 1;
    }
  }
  return crc == 0;
}

// PSI sections may cross packets. Bounded reassembly prevents a forged section
// length or pointer field from escaping the containing TS buffer.
std::vector<uint8_t> ReadSection(const uint8_t *data, size_t size, uint16_t pid,
                                 uint8_t table_id) {
  std::vector<uint8_t> section;
  size_t expected = 0;
  int previous_counter = -1;
  for (size_t offset = 0; offset < size; offset += kPacketSize) {
    const uint8_t *packet = data + offset;
    if (PacketPid(packet) != pid)
      continue;
    size_t payload = PayloadOffset(packet);
    if (payload == kPacketSize)
      continue;
    const int counter = packet[3] & 15;
    if (previous_counter >= 0 && counter != ((previous_counter + 1) & 15)) {
      section.clear();
      expected = 0;
    }
    previous_counter = counter;
    if ((packet[1] & 0x40) != 0) {
      const size_t pointer = packet[payload++];
      if (pointer > kPacketSize - payload)
        return {};
      // We only need the first current PAT/PMT section. A new start supersedes
      // an incomplete section, never appends a second table to the first.
      payload += pointer;
      section.clear();
      expected = 0;
    } else if (section.empty()) {
      continue;
    }
    while (payload < kPacketSize) {
      section.push_back(packet[payload++]);
      if (section.size() == 1 && section[0] != table_id)
        return {};
      if (section.size() == 3) {
        expected = 3 + ((section[1] & 15) << 8) + section[2];
        if ((section[1] & 0x80) == 0 || expected < 12 || expected > 1024) {
          return {};
        }
      }
      if (expected != 0 && section.size() == expected) {
        if ((section[5] & 1) == 0 || !ValidSectionCrc(section))
          return {};
        return section;
      }
    }
  }
  return {};
}

int FindVideoPid(const uint8_t *data, size_t size) {
  const auto pat = ReadSection(data, size, 0, 0);
  if (pat.empty() || (pat.size() - 12) % 4 != 0)
    return -2;
  for (size_t entry = 8; entry + 4 <= pat.size() - 4; entry += 4) {
    // Program zero describes the network table, not a playable program.
    if (pat[entry] == 0 && pat[entry + 1] == 0)
      continue;
    const uint16_t pmt_pid =
        static_cast<uint16_t>(((pat[entry + 2] & 31) << 8) | pat[entry + 3]);
    const auto pmt = ReadSection(data, size, pmt_pid, 2);
    if (pmt.size() < 16)
      return -2;
    size_t position = 12 + ((pmt[10] & 15) << 8) + pmt[11];
    const size_t end = pmt.size() - 4;
    if (position > end)
      return -2;
    int video_pid = -3;
    while (position < end) {
      if (end - position < 5)
        return -2;
      const size_t descriptor_size =
          ((pmt[position + 3] & 15) << 8) | pmt[position + 4];
      if (descriptor_size > end - position - 5)
        return -2;
      if (pmt[position] == 0x1b && video_pid < 0) {
        video_pid = ((pmt[position + 1] & 31) << 8) | pmt[position + 2];
      }
      position += 5 + descriptor_size;
    }
    if (video_pid >= 0)
      return video_pid;
  }
  return -3;
}

bool ValidVideoPes(const uint8_t *data, size_t size, uint16_t video_pid) {
  bool started = false;
  int previous_counter = -1;
  size_t declared_length = 0;
  size_t received_length = 0;
  for (size_t offset = 0; offset < size; offset += kPacketSize) {
    const uint8_t *packet = data + offset;
    if (PacketPid(packet) != video_pid)
      continue;
    const size_t payload = PayloadOffset(packet);
    if (payload == kPacketSize)
      continue;
    const int counter = packet[3] & 15;
    const bool discontinuity =
        (packet[3] & 0x20) != 0 && packet[4] > 0 && (packet[5] & 0x80) != 0;
    if (previous_counter >= 0 && counter != ((previous_counter + 1) & 15) &&
        !discontinuity) {
      return false;
    }
    previous_counter = counter;
    if ((packet[1] & 0x40) != 0) {
      if (started && declared_length != 0 &&
          received_length != declared_length + 6)
        return false;
      const size_t available = kPacketSize - payload;
      const uint8_t *pes = packet + payload;
      if (available < 9 || pes[0] != 0 || pes[1] != 0 || pes[2] != 1 ||
          (pes[3] & 0xf0) != 0xe0 || (pes[6] & 0xc0) != 0x80 ||
          pes[8] > available - 9) {
        return false;
      }
      declared_length = (pes[4] << 8) | pes[5];
      if (declared_length != 0 && declared_length < 3 + pes[8])
        return false;
      received_length = 0;
      started = true;
    } else if (!started) {
      return false;
    }
    received_length += kPacketSize - payload;
    if (declared_length != 0 && received_length > declared_length + 6)
      return false;
  }
  return started &&
         (declared_length == 0 || received_length == declared_length + 6);
}

int32_t DecodeSegment(uint8_t *data, intptr_t size, cctv_h5e::StreamMode mode) {
  if (!data || size <= 0 || size > kMaxSegmentSize || size % kPacketSize != 0) {
    return -1;
  }
  try {
    const size_t length = static_cast<size_t>(size);
    if (!ValidPackets(data, length))
      return -2;
    const int video_pid = FindVideoPid(data, length);
    if (video_pid < 0)
      return video_pid;
    if (!ValidVideoPes(data, length, static_cast<uint16_t>(video_pid)))
      return -2;
    std::vector<uint8_t> output(data, data + length);
    cctv_h5e::Session session(mode);
    const size_t nals =
        cctv_h5e::decrypt_ts_inplace(output.data(), output.size(), session,
                                     static_cast<uint16_t>(video_pid));
    if (nals == 0 || !ValidPackets(output.data(), output.size()))
      return -4;
    std::memcpy(data, output.data(), length);
    return 0;
  } catch (...) {
    return -4;
  }
}
} // namespace

uint8_t *juying_h5e_alloc(intptr_t size) {
  if (size <= 0 || size > kMaxSegmentSize)
    return nullptr;
  return static_cast<uint8_t *>(std::malloc(static_cast<size_t>(size)));
}

void juying_h5e_free(uint8_t *data) { std::free(data); }

int32_t juying_h5e_decode(uint8_t *data, intptr_t size) {
  return DecodeSegment(data, size, cctv_h5e::StreamMode::H5eVod);
}

int32_t juying_cdrm_decode(uint8_t *data, intptr_t size) {
  return DecodeSegment(data, size, cctv_h5e::StreamMode::CdrmLive);
}
