# CCTV H5E native source

Vendored from [letr007/CCTVVideoDownloader](https://github.com/letr007/CCTVVideoDownloader)
at commit `8f9edcb3374aea0532f6fe08fe78eb6d9f676e28`, original paths
`src/core/src/crypto/cctv_h5e_decrypt.{hpp,cpp}`.

Copyright (C) 2025 Letr. Upstream's GPL version 3 notice is preserved in
`LICENSE`; the complete GPL version 3 text is in `COPYING`.

Original SHA256 before local changes:

- `cctv_h5e_decrypt.hpp`: `38b282e0826b159ab526b0d5bc2b0c37875294d93eb93a1dc244306aeaff1251`
- `cctv_h5e_decrypt.cpp`: `e29ec4635c440192ca07066d8f42e07e019c9645fb9707ee46853bcdece2eafe`

Local changes (2026-10-16): bound the residual PES copy when a previous span
has exhausted the rebuilt PES, preventing unsigned subtraction underflow;
compact remaining emulation-prevention bytes in linear time instead of moving
the complete tail for every removed byte; apply clang-format to the imported
C++ files. The public JuYing ABI, TS input
validation, PAT/PMT PID discovery and independent segment sessions live in
the parent `src/main/cpp` directory outside the imported implementation.

Android port (2026-10-27): reused JuYing's Flutter native decoder from commit
`331aa2972d2d4f4ec0b9c4f888632f0d36105310`, with a JNI adapter and Media3
DataSource. The imported decryption implementation remains unchanged by this
port; the Android transport bounds complete segments to 8 MiB.

Live CDRM adaptation (2026-10-27): added an explicit session mode for live
H.264 slice NALs larger than 128 bytes. It shares the classic RBSP/EPB grid
but permits a final complete 8-byte TEA cell without a full 80-byte stride.
The VOD type-25 gate and full-stride rule are unchanged. Rebuilt bounded PES
headers now record the shortened payload length; the JuYing wrapper rejects
declared PES lengths that do not match the complete input. Live uses the new
`juying_cdrm_decode` / JNI `decodeLive` entry points and shares all TS/PAT/PMT
validation with VOD. No official player JavaScript or WASM is included.
The classic behavior investigation also consulted upstream revision
`0d580c782c46c5265475b9f5674f3d8b490913b6`; the vendored base above is unchanged.

This source handles H.264 H5E MPEG-TS segments. It does not implement UDRM,
Widevine, HEVC or a general license client. No official CCTV DLL is bundled.
