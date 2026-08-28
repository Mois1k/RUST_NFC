# nfc-in-rust

A bare-metal PN532 NFC driver over I2C, written in `no_std` Rust with **no HAL crate** and
**no `cortex-m-rt`** — just a hand-written runtime (linker script, vector table, reset
handler) and, eventually, the vendor PAC (`mcx-pac`) for typed register access.

**Target hardware:** NXP FRDM-MCXN236 — Cortex-M33, ARMv8-M Mainline with FPU,
`thumbv8m.main-none-eabihf`.

> **Status: early work in progress.** This is not a working driver. Right now the project
> builds an ELF whose vector table points at a reset handler that spins in an infinite loop.
> It does not blink an LED, configure a clock, or touch an I2C bus yet. See
> [Current status](#current-status).

---

## Purpose & motivation

This is a dissertation project. The goal is **zero black boxes**: implement and understand
every layer between power-on and a working NFC read, without leaning on abstraction crates
that hide what the hardware is actually doing.

Concretely that means:

- **No HAL** (`embedded-hal` impls, `mcxn-hal`, etc.). Peripherals are driven by writing
  their registers directly, against the reference manual.
- **No `cortex-m-rt`.** The vector table, reset handler, `.data`/`.bss` initialisation and
  the entry into Rust are all hand-written. Re-deriving ARMv8-M startup by hand is part of
  the point.
- **PAC only, and only later.** `mcx-pac` is a mechanical, SVD-generated mapping of the
  reference manual into typed Rust — it adds no behaviour and is verifiable line-by-line
  against the datasheet, so it is acceptable as the one dependency. It is *not wired in
  yet* (`Cargo.toml` currently has an empty `[dependencies]`); early register pokes are
  raw pointer writes.

The dissertation write-up is the deliverable; this repo is the artefact that backs it.

---

## Current status

### Done

- [x] Toolchain / target set up: `thumbv8m.main-none-eabihf`, edition 2024, pinned via
      `.cargo/config.toml` (no `rust-toolchain.toml` yet — built with stable `rustc 1.93`).
- [x] `no_std` + `no_main` binary skeleton with a minimal `panic_handler` (spin loop).
- [x] `memory.x` — device memory regions: `FLASH` @ `0x0000_0000` (1 MiB),
      `RAM` @ `0x2000_0000` (256 KiB).
- [x] `link.x` — hand-written linker script:
  - `ENTRY(Reset)`
  - `.vector_table` forced to the start of `FLASH` with `KEEP`
  - `.text`, `.rodata` in `FLASH`
  - `.data` with VMA in `RAM`, LMA in `FLASH` (`AT>`), bracketed by `_sdata` / `_edata`
  - `.bss` in `RAM`, bracketed by `_sbss` / `_ebss`
  - exported symbols: `_estack`, `_sidata` (`LOADADDR(.data)`)
- [x] Vector table as a `#[repr(C)]` struct in `.vector_table`, `#[used]`:
      initial SP from `&_estack`, reset vector pointing at `Reset`. Only **two entries** so far.
- [x] `Reset` symbol: `extern "C"`, `#[no_mangle]`. Currently an infinite loop — **no init**.
- [x] Verified with `rust-objdump`:
  - `.vector_table` contains SP = `0x2004_0000` and reset vector = `0x0000_0019`
    (address `0x18` with the Thumb bit set)
  - `Reset` disassembles into `.text` and the linker places sections as intended

### Not done yet

- [ ] Reset handler does **not** copy `.data` from its LMA or zero `.bss`, and does not
      call a `main` — Rust code that assumes initialised statics is currently unsafe to run.
- [ ] No FPU enable (`CPACR`) despite the hard-float target; no `VTOR` set.
- [ ] Vector table has no core exception / fault handlers (NMI, HardFault, MemManage,
      BusFault, UsageFault, SVC, PendSV, SysTick) and no device IRQ slots.
- [ ] `mcx-pac` not added.
- [ ] No clock / PLL configuration — would run on the default reset clock (FRO).
- [ ] No GPIO, no SysTick, no delay/timebase.
- [ ] No I2C (LPI2C) bring-up.
- [ ] No PN532 framing or driver layer.
- [ ] No flashing / debug configuration (no `runner` in `.cargo/config.toml`, no
      probe-rs / LinkServer / pyOCD setup). Not yet run on hardware.
- [ ] No tests, no CI.
- [ ] Linker script does not yet discard/place `.ARM.exidx` / `.ARM.attributes` or add a
      stack-overflow guard; the full MCX N236 SRAM map (multiple banks) is not reflected —
      `memory.x` uses a single conservative 256 KiB region.

---

## Building

Requires the target and the LLVM tools that ship `rust-objdump`:

```sh
rustup target add thumbv8m.main-none-eabihf
rustup component add llvm-tools
cargo install cargo-binutils   # optional: gives `cargo objdump`, `cargo size`, etc.
```

Build (the target triple and linker flags come from `.cargo/config.toml`, so a plain
`cargo build` is enough):

```sh
cargo build              # debug   -> target/thumbv8m.main-none-eabihf/debug/RustNFC
cargo build --release    # release -> target/thumbv8m.main-none-eabihf/release/RustNFC
```

The output is an ELF. There is no flashing step wired up yet.

### Inspecting the image

The startup layer is verified by reading the linked ELF, not by running it:

```sh
rust-objdump -h                       target/thumbv8m.main-none-eabihf/debug/RustNFC   # sections
rust-objdump -s -j .vector_table      target/thumbv8m.main-none-eabihf/debug/RustNFC   # SP + reset vector
rust-objdump -d                       target/thumbv8m.main-none-eabihf/debug/RustNFC   # disassembly
```

Expected: `.vector_table` at VMA `0x0`, first word `0x2004_0000` (top of RAM), second word
the odd (Thumb) address of `Reset`.

---

## Repository layout

| Path                  | What it is                                                        |
|-----------------------|------------------------------------------------------------------|
| `.cargo/config.toml`  | Default target triple + `-T link.x` / `-L .` linker flags        |
| `Cargo.toml`          | Crate metadata. `[dependencies]` is intentionally empty for now  |
| `memory.x`            | `MEMORY { FLASH, RAM }` for the MCX N236                          |
| `link.x`              | Linker script: `ENTRY`, section placement, runtime symbols       |
| `src/main.rs`         | Panic handler, `VectorTable`, `Reset`                            |

---

## Architecture notes

### Why no `cortex-m-rt`

`cortex-m-rt` provides exactly the pieces this project is meant to build by hand: the
vector table, the reset handler, `.data`/`.bss` init, FPU/`VTOR` setup, the `#[entry]` and
`#[exception]` macros, and a set of linker sections/symbols its `link.x` expects. Using it
would mean the most instructive part of embedded bring-up — what the CPU does between
reset and the first line of `main`, and what has to be true about memory before Rust is
sound — happens inside a dependency.

The hand-written version here owns:

- the `.vector_table` contents and their placement at `0x0000_0000`
- the initial stack pointer (`_estack` = `ORIGIN(RAM) + LENGTH(RAM)`)
- the `Reset` entry point and (soon) the memory-init sequence it must run
- every linker symbol the runtime relies on

### Why no HAL

A HAL trades register-level knowledge for a portable API. For a dissertation whose subject
*is* that register-level knowledge, that trade is backwards. Driving LPI2C, the clock tree,
GPIO and SysTick straight from their registers keeps the reference manual in the loop and
makes the write-up concrete.

### Why the PAC is acceptable (once added)

`mcx-pac` is generated from NXP's SVD. It is a typed name for each register and field and
nothing more — no sequencing, no policy, no hidden state. It can be checked against the
datasheet mechanically, and it removes a class of transcription bugs (wrong offset, wrong
bit) without removing any of the understanding. It is the single dependency the project
will allow.

### Trade-offs (acknowledged)

More boilerplate; easy to get subtly wrong (section alignment, `Sync` impls, `#[used]`,
`volatile` access, missing memory barriers); single-target and non-portable. All
acceptable for a one-board academic artefact, none acceptable for a real driver crate.

---

## Roadmap

Roughly in dependency order:

1. **Finish startup.** In `Reset`: copy `.data` (`_sidata` → `_sdata..=_edata`), zero
   `.bss` (`_sbss..=_ebss`), enable the FPU via `CPACR`, set `VTOR`, then call `main`.
2. **Full vector table.** Core exceptions + fault handlers (at minimum a `DefaultHandler`
   that traps), SysTick slot, room for device IRQs.
3. **Add `mcx-pac`** and replace raw pointer access.
4. **Clocks.** Understand the FRO/PLL/SCG setup on MCX N; bring the core to a known
   frequency and derive a usable I2C functional clock.
5. **GPIO + blinky.** First proof of life on the onboard LED.
6. **SysTick timebase.** Blocking `delay_ms`, a monotonic tick.
7. **I2C master from registers.** LPI2C pinmux, baud-rate divider, START/STOP, TX/RX FIFO
   handling, NACK/arbitration-loss handling.
8. **PN532 transport.** I2C wakeup + status-byte polling; build and parse the normal
   information frame (preamble, `00 FF` start code, `LEN`/`LCS`, `TFI` `0xD4`/`0xD5`,
   payload, `DCS`, postamble); ACK/NACK frames; error frames.
9. **PN532 commands.** `GetFirmwareVersion`, `SAMConfiguration`, `InListPassiveTarget`
   (ISO/IEC 14443 Type A) → read a card UID end to end.
10. **Stretch.** IRQ-line-driven instead of polled; MIFARE Classic auth; NDEF record
    parsing.

---