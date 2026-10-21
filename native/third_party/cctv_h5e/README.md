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
`native/cctv_h5e` outside the imported implementation.

This source handles H.264 H5E MPEG-TS segments. It does not implement UDRM,
Widevine, HEVC or a general license client. No official CCTV DLL is bundled.
