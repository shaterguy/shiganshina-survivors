# Fantasy Skills Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans; preserve the approved isolated candidate and exact patches.

**Goal:** Deliver actual chain-lightning and finite fire-zone combat through existing offers, capped progression, cross-skill evolutions and save validation.
**Architecture:** Extend the existing catalogs and bounded player_attack_instances contract. A dedicated resolver proposes and validates new attacks. Core owns hits and events.
**Tech Stack:** Godot 4.6.3, GDScript, JSON definitions.
**Spec:** Parent-approved bounded design and function ownership, 2026-10-12.

## Global Constraints
- No external writes, Git remote, device, Work, cloud threads, UI, Registry or character edits.
- Keep Lv5 and four equipment/passive slots; preserve original six weapons and two evolutions.
- At most 64 pending records, at most 8 fire pulses per cast and two overlapping fire fields.
- No schema/revision reset; chapter edits delivered separately. Native/Android remain unverified.

## Review Focus
- Same-distance chains must resolve by stable ID, exclude previously hit IDs and respect cover per hop.
- A pending base fire field must survive acquiring its evolution or later damage/range upgrades.
- Four occupied slots must report cross-skill prerequisites as blocked rather than bypassing them.
- Cold JSON restoration must preserve exact cast-time damage and future event replay.
- Capacity refusal must be atomic and observable, with a finite retry tick.

## Task 1: Base chain combat
- [x] Write actual offer→choose→chain-hit→restore tests and observe RED.
- [x] Add chain data/catalog stats and pure chain proposal, dispatch through Core.
- [x] Verify deterministic nearest links, no repeated target, bounds, cover, damage bonus and exact replay.

## Task 2: Finite fire zone and cross-skill ultimates
- [x] Write pulse timing, pending mutation, blocked prerequisites, actual evolution-choice and stronger-behavior tests; observe RED.
- [x] Extend catalogs/Growth target guidance, route pending validation/canonicalization by family, add finite pulse proposals.
- [x] Verify pause/replay, forged records, atomic capacity and actual offer progression.

## Task 3: Integration handoff
- [x] Run focused progression/Core/persistence nonregressions; coordinate full suite with parent.
- [x] Record exact base/final identity, apply-ready patches, VFX geometry contract, remaining native/Android gaps.

## Rulings and status
- Final full-suite execution remains with parent because current and historical providers require distinct identities. Focused tests are not a full pass.
- Preserved raw JSON exposed a preexisting integer-normalization mismatch in permanent_levels. A minimal canonical int copy was approved and verified through real Store replacement.
- Core/Store/Chapter integration patches remain separate to avoid overwriting parallel character and enemy work.
- Independent review and Android/native/VFX remain integration gates, not claimed complete here.
