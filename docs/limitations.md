# Limitations

## Overview

`VRM21-RTL-Utilities` provides reusable RTL building blocks, but the modules are not intended to cover every possible system configuration.

This document records important limitations and integration considerations.

---

## 1. Module-Specific Behavior

The exact timing, latency, collision behavior, and parameter restrictions of each module are determined by its RTL implementation.

Users should therefore review the source module before integrating it into a timing-sensitive system.

---

## 2. RAM Collision Behavior

Dual-port and multi-access memory structures may have implementation-dependent behavior when both ports access the same memory location under conflicting read/write conditions.

Such behavior should not be assumed to match a particular FPGA vendor's RAM primitive unless the implementation explicitly guarantees it.

System architectures should avoid relying on undefined collision cases.

---

## 3. RAM Read Latency

The basic RAM architecture uses synchronous/registered read behavior.

Consequently, memory reads are not equivalent to combinational array lookups.

Downstream logic must account for the associated read latency.

---

## 4. Memory Resource Inference

Parameters and synthesis attributes provide implementation guidance but do not guarantee a particular physical resource.

For example, requesting distributed RAM does not guarantee that every synthesis configuration will map the memory exclusively to LUTRAM.

Actual resource mapping depends on:

- FPGA family.
- Synthesis tool.
- Tool version.
- Memory dimensions.
- Optimization settings.
- Surrounding logic.

---

## 5. FIFO Capacity

The FIFO can absorb temporary bursts and backpressure, but it cannot compensate for a permanent throughput mismatch.

If the average input rate remains higher than the average output rate, the FIFO will eventually fill.

Similarly, a sustained output rate higher than the input rate will eventually result in an empty FIFO.

---

## 6. FIFO Boundary Conditions

System-level designs should explicitly consider:

- Empty FIFO behavior.
- Full FIFO behavior.
- Almost-full thresholds.
- Producer behavior during backpressure.
- Consumer behavior when no data is available.

The surrounding system remains responsible for correctly handling the AXI4-Stream handshake.

---

## 7. AXI4-Lite Bridge Scope

`vrm_axilite2nsi_mmio_64` is intended for lightweight MMIO/control transactions.

It is not a replacement for a complete AXI interconnect or high-performance memory subsystem.

Designs requiring advanced AXI features may require a dedicated interconnect or bridge.

---

## 8. Native MMIO Timing

The native-side peripheral must satisfy the bridge's expected request/response timing.

A peripheral that requires additional latency must be integrated according to the bridge's native interface contract.

The bridge does not automatically solve arbitrary peripheral timing requirements.

---

## 9. AXI4-Stream Writer Addressing

`vrm_axis2nsi_write` is intended primarily for sequential writes.

Applications requiring arbitrary address patterns, scatter/gather transfers, or descriptor-based DMA should use a more capable address-generation architecture.

---

## 10. Clock-Domain Crossing

The utilities are not a general-purpose CDC library.

Modules should normally be used within a common clock domain unless the specific module explicitly documents otherwise.

Signals crossing between asynchronous clock domains require appropriate CDC handling at the system level.

---

## 11. Reset Assumptions

Reset behavior is module-specific.

A system integrating several utilities should verify that their reset polarity, synchronization, and release behavior are compatible.

Reset should not be assumed to initialize all memory contents unless the corresponding RTL explicitly implements such behavior.

---

## 12. Parameter Combinations

Although the modules are parameterized, not every theoretical combination of parameters is necessarily meaningful or equally well supported.

Extreme configurations may result in:

- Inefficient FPGA resource utilization.
- Unexpected synthesis results.
- Timing difficulties.
- Tool-specific inference behavior.

Parameters should therefore be validated for the intended target device.

---

## 13. Simulation vs. Hardware

Successful RTL simulation does not guarantee successful FPGA implementation.

Hardware validation may expose issues involving:

- Timing closure.
- Memory inference.
- Reset implementation.
- Physical resource constraints.
- Vendor-specific behavior.
- System-level integration.

FPGA validation should therefore be performed when the utility is used in a hardware-critical application.

---

## 14. No Universal Performance Guarantee

The repository does not guarantee a specific maximum clock frequency, latency, throughput, or resource utilization for every target FPGA.

These properties depend on:

- Parameter configuration.
- Target FPGA.
- Synthesis settings.
- Placement and routing.
- Surrounding logic.
- Clock constraints.

Performance claims should therefore be made using measurements from the actual target configuration.

---

## 15. Application-Level Responsibility

The utilities provide infrastructure, not complete system-level correctness.

The integrating project remains responsible for:

- Protocol compliance at the system boundary.
- Correct parameter selection.
- Clock/reset architecture.
- Address-map integration.
- Error handling.
- System-level verification.
- Hardware validation where required.