---
status: pending
blocked-by: 
date: 2026-10-20
---

# 0004 — Publish, add CI on the shared graph, and have AemiSDR depend on it by revision

Abysm is local only: no remote, no CI, no license file (the owner's choice). AemiSDR's `systemStyle` and corner-radius
fixes depend on it, so until it is pushed those commits cannot be merged.

## What lands

A repository, a `LICENSE`, CI calling `swift-quality.yml@<sha>` with a macOS leg and an iOS simulator leg on the floor
and the newest runtime (the canary), and AemiSDR pinning it by revision.
