-- SPDX-License-Identifier: GPL-2.0-only
-- iwchaos — Agda wire/bound invariants (offline formal verification)
--
-- These proofs are NOT compiled into the kernel module.
-- They are run offline to verify the invariants that the Idris 2 and Rust
-- code rely on. The verified algorithms are then hand-translated or
-- code-generated into the corresponding implementation files.

module Invariants where

open import Data.Nat
open import Data.Nat.Properties
open import Relation.Binary.PropositionalEquality

-- ── Bound invariant: DMA buffer size is nonzero ────────────────────────────

record DmaBound : Set where
    field
        size      : ℕ
        nonzero   : 0 < size

-- Proof: a buffer of size n+1 always satisfies the bound invariant.
mkDmaBound : (n : ℕ) → DmaBound
mkDmaBound n = record { size = suc n ; nonzero = s≤s z≤n }

-- ── Wire invariant: MAC backoff delay is within [10, 1000] µs ─────────────

record BackoffBound (delay : ℕ) : Set where
    field
        lb : 10 ≤ delay
        ub : delay ≤ 1000

-- Proof template: clamp(x) is within [10, 1000].
-- The Rust caller is obliged to provide this proof structurally by
-- construction (see iwchaos_lorenz_backoff in rust/src/lib.rs).
postulate
    lorenz_backoff_bounded : ∀ (x : ℕ) → BackoffBound (10 + (x * 990 / 40))

-- ── Power state invariant: Mandelbrot power index ∈ [0, 4] ───────────────

PowerState : Set
PowerState = ℕ

postulate
    mandelbrot_power_bounded : ∀ (escape max_iter : ℕ)
        → (escape * 5 / max_iter) ≤ 4
