#pragma once

#include <stdint.h>

#if defined(_WIN32)
#if defined(JUYING_H5E_BUILD)
#define JUYING_H5E_API __declspec(dllexport)
#else
#define JUYING_H5E_API __declspec(dllimport)
#endif
#else
#define JUYING_H5E_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Allocations stay in this DLL's CRT. Invalid sizes and allocation failures
// return NULL; the largest accepted complete TS segment is 32 MiB.
JUYING_H5E_API uint8_t *juying_h5e_alloc(intptr_t size);
JUYING_H5E_API void juying_h5e_free(uint8_t *data);

// Decode one complete H.264 MPEG-TS segment, locating its PID through PAT/PMT.
// Each call starts a fresh session so seek and episode changes share no state.
// Success (0) replaces exactly size bytes. Failure leaves the input unchanged:
// -1 invalid argument, -2 malformed TS, -3 unsupported stream, -4 decode
// failure. The caller must supply a writable allocation containing at least
// size bytes. No C++ exception crosses this ABI.
JUYING_H5E_API int32_t juying_h5e_decode(uint8_t *data, intptr_t size);

#ifdef __cplusplus
}
#endif
