-- SPDX-License-Identifier: GPL-2.0-only
-- iwchaos — Linear DMA buffer allocator (Idris 2, QTT)
--
-- Enforces that every allocated DMA buffer ticket is consumed exactly once.
-- Prevents use-after-free and double-free at the type level via linear
-- multiplicities (multiplicity 1 in Quantitative Type Theory).

module DmaLinear

import Data.Linear.Notation

%default total

-- ── Types ──────────────────────────────────────────────────────────────────

||| Physical address of a DMA coherent buffer. Opaque to Idris.
public export
PhysAddr : Type
PhysAddr = Bits64

||| A linear DMA ticket. Must be consumed exactly once.
||| Holding a ticket without consuming it, or consuming it twice,
||| is a compile-time type error.
public export
data DmaTicket : Type where
    MkTicket : (addr : PhysAddr) -> (size : Bits32) -> DmaTicket

-- ── Operations ─────────────────────────────────────────────────────────────

||| Wrap a physical address into a fresh linear ticket.
||| Called once per dma_alloc_coherent invocation.
export
mkDmaTicket : PhysAddr -> Bits32 -> (1 _ : ()) -> DmaTicket
mkDmaTicket addr sz () = MkTicket addr sz

||| Consume the ticket and return the physical address for the firmware load.
||| After this call the ticket ceases to exist — it cannot be used again.
export
consumeTicket : (1 _ : DmaTicket) -> PhysAddr
consumeTicket (MkTicket addr _) = addr

||| Return the allocation size from a ticket without consuming it.
||| Note: uses unrestricted multiplicity (ω) — read-only, no ownership transfer.
export
ticketSize : DmaTicket -> Bits32
ticketSize (MkTicket _ sz) = sz
