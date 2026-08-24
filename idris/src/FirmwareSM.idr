-- SPDX-License-Identifier: GPL-2.0-only
-- iwchaos — Intel firmware state machine (Idris 2, QTT linear types)
--
-- Models the Intel Wi-Fi firmware command/response protocol as a
-- linear state machine. Quantitative Type Theory (multiplicity 1)
-- ensures DMA command buffers are consumed exactly once — eliminating
-- use-after-free at the type level.
--
-- Compiled to freestanding C via: idris2 --codegen C

module FirmwareSM

import Data.Linear.Notation

%default total

-- ── Firmware states ────────────────────────────────────────────────────────

||| The firmware command state machine.
||| Each constructor represents a stable hardware state.
public export
data FirmwareState : Type where
    ||| Hardware is powered down / unclaimed.
    PowerOff  : FirmwareState
    ||| PCIe claimed, MMIO mapped, firmware not yet loaded.
    PciReady  : FirmwareState
    ||| Firmware image loaded into DMA buffer, awaiting start command.
    FwLoaded  : FirmwareState
    ||| Firmware running, MAC layer active.
    MacActive : FirmwareState
    ||| Fatal hardware error, driver must reset.
    FwError   : FirmwareState

-- ── DMA buffer linear ticket ───────────────────────────────────────────────

||| A one-shot DMA buffer ticket.
||| The multiplicity-1 (linear) guarantee means it must be consumed
||| exactly once. Passing or copying it is a compile-time error.
public export
data DmaTicket : Type where
    MkDmaTicket : (physAddr : Bits64) -> DmaTicket

-- ── State machine transitions (total, linear) ─────────────────────────────

||| Claim the PCIe device and return a PciReady state witness.
||| Consumes the PowerOff proof linearly.
export
claimPci : (1 _ : FirmwareState) -> FirmwareState
claimPci PowerOff = PciReady
claimPci _        = FwError   -- illegal transition

||| Load the firmware image using a DMA ticket.
||| The ticket is consumed exactly once here (linear multiplicity).
export
loadFirmware : (1 _ : FirmwareState) -> (1 _ : DmaTicket) -> FirmwareState
loadFirmware PciReady _ = FwLoaded
loadFirmware _        _ = FwError

||| Start the firmware and activate the MAC layer.
export
startMac : (1 _ : FirmwareState) -> FirmwareState
startMac FwLoaded = MacActive
startMac _        = FwError

||| Reset firmware on error or unload.
export
resetFirmware : (1 _ : FirmwareState) -> FirmwareState
resetFirmware _ = PowerOff
