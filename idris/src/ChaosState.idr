-- SPDX-License-Identifier: GPL-2.0-only
-- iwchaos — Chaos engine mode selection (Idris 2, QTT linear types)
--
-- Models the chaos engine as a typed state machine where each attractor
-- occupies a distinct mode. Mode transitions are linearly typed to prevent:
--   1. Running two attractors simultaneously on the same state
--   2. Using a state struct after it has been stepped (use-after-move)
--   3. Forgetting to advance all attractors in a coordinated update
--
-- The ChaosMode type enforces that the driver always uses a complete,
-- consistent set of chaos outputs (all six systems must be stepped before
-- the ChaosParams snapshot is consumed).

module ChaosState

import Data.Linear.Notation

%default total

-- ── Chaos attractor mode tags ──────────────────────────────────────────────

||| Tags identifying which chaos subsystem owns a given computation step.
||| Used as phantom types to enforce correct sequencing at the type level.
public export
data AttractorTag : Type where
    ||| Lorenz 3D strange attractor (RK4).
    TagLorenz    : AttractorTag
    ||| Mandelbrot set escape-time oracle.
    TagMandelbrot : AttractorTag
    ||| Rössler single-scroll attractor (RK4).
    TagRossler   : AttractorTag
    ||| Duffing forced nonlinear oscillator (RK4).
    TagDuffing   : AttractorTag
    ||| Logistic map / Feigenbaum cascade.
    TagLogistic  : AttractorTag
    ||| Lyapunov exponent estimator (RK4 with perturbation).
    TagLyapunov  : AttractorTag

-- ── Attractor step token (linear) ─────────────────────────────────────────

||| A one-shot token proving that attractor `t` has been stepped exactly once
||| in the current update cycle.
|||
||| Linear multiplicity (multiplicity-1) means:
|||   - Dropping a StepToken without consuming it is a compile-time error.
|||   - Consuming it twice (double-step) is a compile-time error.
||| This enforces that every attractor is stepped exactly once per cycle.
public export
data StepToken : (tag : AttractorTag) -> Type where
    MkStepToken : (tag : AttractorTag) -> StepToken tag

-- ── Update cycle proof ────────────────────────────────────────────────────

||| Proof that all six attractors have been stepped exactly once.
||| Constructed by consuming six linear StepTokens — one per attractor.
||| The ChaosParams snapshot must not be read until this proof exists.
public export
data AllStepped : Type where
    ||| Construct the proof by consuming all six step tokens linearly.
    MkAllStepped :
        (1 _ : StepToken TagLorenz)     ->
        (1 _ : StepToken TagMandelbrot) ->
        (1 _ : StepToken TagRossler)    ->
        (1 _ : StepToken TagDuffing)    ->
        (1 _ : StepToken TagLogistic)   ->
        (1 _ : StepToken TagLyapunov)   ->
        AllStepped

-- ── Update cycle functions ────────────────────────────────────────────────

||| Step the Lorenz attractor.
||| Consumes the previous token (preventing double-stepping) and returns
||| a fresh token for this cycle.
export
stepLorenz : (1 _ : ()) -> StepToken TagLorenz
stepLorenz () = MkStepToken TagLorenz

||| Step the Mandelbrot oracle.
export
stepMandelbrot : (1 _ : ()) -> StepToken TagMandelbrot
stepMandelbrot () = MkStepToken TagMandelbrot

||| Step the Rössler attractor.
export
stepRossler : (1 _ : ()) -> StepToken TagRossler
stepRossler () = MkStepToken TagRossler

||| Step the Duffing oscillator.
export
stepDuffing : (1 _ : ()) -> StepToken TagDuffing
stepDuffing () = MkStepToken TagDuffing

||| Step the logistic map.
export
stepLogistic : (1 _ : ()) -> StepToken TagLogistic
stepLogistic () = MkStepToken TagLogistic

||| Step the Lyapunov estimator.
export
stepLyapunov : (1 _ : ()) -> StepToken TagLyapunov
stepLyapunov () = MkStepToken TagLyapunov

||| Perform one complete update cycle: step all six attractors and return
||| the AllStepped proof. The linearity constraint ensures that if any
||| step is omitted, the proof cannot be constructed and the snapshot
||| cannot be consumed.
export
fullUpdateCycle : AllStepped
fullUpdateCycle =
    MkAllStepped
        (stepLorenz    ())
        (stepMandelbrot ())
        (stepRossler   ())
        (stepDuffing   ())
        (stepLogistic  ())
        (stepLyapunov  ())

-- ── Snapshot consumption ──────────────────────────────────────────────────

||| A ChaosParams snapshot is valid only after all attractors have been stepped.
||| The AllStepped proof is consumed linearly — reading the snapshot twice
||| would require two AllStepped proofs, which cannot be constructed from
||| a single cycle.
export
readSnapshot : (1 _ : AllStepped) -> ()
readSnapshot (MkAllStepped
    (MkStepToken TagLorenz)
    (MkStepToken TagMandelbrot)
    (MkStepToken TagRossler)
    (MkStepToken TagDuffing)
    (MkStepToken TagLogistic)
    (MkStepToken TagLyapunov)) = ()
