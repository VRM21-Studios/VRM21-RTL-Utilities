# Design Rationale

## Overview

The design philosophy of `VRM21-RTL-Utilities` is centered around reusable, synthesizable RTL primitives that can be integrated into multiple hardware projects.

The repository intentionally favors relatively small modules with explicit interfaces over large framework-level abstractions.

---

## 1. Reusable RTL Primitives

Many hardware projects require the same basic infrastructure:

- Memory.
- FIFOs.
- Streaming adapters.
- MMIO interfaces.
- DSP arithmetic.
- Double buffering.

Duplicating these implementations across repositories increases maintenance cost and can cause subtle behavioral differences between projects.

The utilities repository provides a common implementation that can be reused across the VRM21-Studios RTL ecosystem.

---

## 2. Parameterization

Where practical, modules are parameterized rather than hard-coded for a single application.

For example, memory modules expose configurable:

- Data width.
- Address width.
- Memory depth.
- RAM implementation preference.

Similarly, the DSP core exposes configurable arithmetic widths.

This allows the same RTL source to be reused for different datapath requirements.

---

## 3. FPGA Resource Inference

The repository targets FPGA-based development as an important implementation environment.

Consequently, several modules provide explicit guidance to synthesis tools regarding preferred hardware resources.

Examples include:

- Distributed RAM for small/high-throughput buffers.
- Block RAM for larger memories.
- DSP slices for arithmetic datapaths.

The intention is not to force a particular physical implementation under all circumstances, but to provide synthesis tools with useful implementation hints.

---

## 4. Ping-Pong Buffering

The ping-pong RAM architecture was selected because double buffering is a common pattern in streaming and DSP systems.

Without double buffering, a processing engine may have to wait for an input buffer to become available before the next block can be acquired.

With two banks:

```text
Time --->

Bank A:  [ Fill ] [ Process ] [ Fill ] [ Process ]
Bank B:  [ Idle ] [ Fill    ] [ Process ] [ Fill ]
```

The producer and consumer can therefore operate on different banks.

This improves system-level concurrency without requiring a more complicated multi-buffer architecture.

---

## 5. FIFO-Based Stream Decoupling

The AXI4-Stream FIFO provides temporal decoupling between producer and consumer.

A producer may temporarily operate faster than the downstream block, while a consumer may temporarily stall.

The FIFO absorbs these short-term differences.

This is particularly useful when converting AXI4-Stream traffic into simpler sequential interfaces.

---

## 6. Protocol Separation

The AXI bridge modules intentionally separate protocol handling from application logic.

For example, a peripheral does not need to implement the complete AXI4-Lite transaction protocol if it can instead operate on a simpler native MMIO interface.

Likewise, a simple memory writer does not need to implement AXI4-Stream signaling internally when the adapter can provide that conversion.

This separation improves reuse and simplifies downstream modules.

---

## 7. Explicit State Machines

Protocol bridges use explicit finite-state-machine control where transaction sequencing requires it.

This approach provides:

- Deterministic transaction sequencing.
- Clear handshake behavior.
- Straightforward simulation.
- Easier waveform debugging.
- Predictable synthesis behavior.

The state machines are intentionally compact rather than being implemented as generalized bus infrastructure.

---

## 8. Synthesis-Safe RTL

The modules are intended to remain compatible with conventional FPGA synthesis flows.

Design choices therefore favor:

- Static memory arrays.
- Synchronous sequential logic.
- Explicit state machines.
- Parameterized generate structures where appropriate.
- Vendor synthesis attributes only where useful.

The utilities do not depend on simulation-only behavior for their core functionality.

---

## 9. Verification-Oriented Design

Each reusable block is intended to be independently testable.

This is particularly important because these modules can become dependencies of multiple higher-level repositories.

A bug in a common FIFO, RAM, or interface bridge can propagate into several unrelated systems.

Independent testbenches therefore form an important part of the repository architecture.

---

## 10. Scope Control

The repository deliberately avoids becoming a general-purpose hardware framework.

Application-specific functionality belongs in the repository that consumes these utilities.

For example:

- A complete CPU belongs in the CPU repository.
- A complete FIR filter belongs in the DSP repository.
- A complete audio-processing chain belongs in its corresponding system repository.

The utilities repository should remain focused on reusable infrastructure.