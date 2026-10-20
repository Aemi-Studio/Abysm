---
status: in-progress
blocked-by: 
date: 2026-10-20
---

# 0004 — Publish, add CI on the shared graph, and have AemiSDR depend on it by revision

Abysm is published at [g-cqd/Abysm](https://github.com/g-cqd/Abysm) under MIT, as requested by the owner.
AemiSDR must use that canonical URL and a reviewed revision; no local-path dependency may ship.

CI is configured but not yet green. Its first run exposed lint violations, an unavailable ARM-only floor runtime,
and a missing-linker failure when Xcode selected the Swift.org toolchain. The violations and runtime request are
corrected; adding Xcode's tool directory to PATH still needs remote verification.

## What lands

A repository, a `LICENSE`, CI calling `swift-quality.yml@<sha>` with a macOS leg and an iOS simulator leg on the floor
and the newest runtime (the canary), and AemiSDR pinning it by revision.
