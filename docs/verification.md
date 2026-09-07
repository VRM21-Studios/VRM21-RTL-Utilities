# Verification

## Overview

Verification of `VRM21-RTL-Utilities` is performed primarily through dedicated RTL testbenches for the reusable modules.

The verification strategy focuses on functional correctness at the module level before the modules are consumed by larger CPU, DSP, or system-level repositories.

---

## 1. Verification Philosophy

The utilities repository contains infrastructure that may be reused by multiple projects.

Consequently, verification is performed at two levels:

```text
Module-Level Verification
          |
          v
Reusable Utility
          |
          v
System-Level Verification
          |
          v
Application / SoC
```

Module-level testbenches verify the standalone behavior of each utility.

Higher-level repositories are then responsible for verifying that the utility behaves correctly within their specific integration context.

---

## 2. Testbench Coverage

The repository contains dedicated testbenches for the main infrastructure blocks, including:

- RAM.
- True dual-port RAM.
- Ping-pong RAM.
- FIFO.
- DSP core.

The exact set of testbenches may evolve as additional utilities are added to the repository.

---

## 3. RAM Verification

RAM verification focuses on basic storage and retrieval behavior.

Typical checks include:

- Write operation.
- Read operation.
- Address selection.
- Data integrity.
- Reset/initial state where applicable.
- Configured memory behavior.

For dual-port RAM, verification additionally considers concurrent access through both ports.

---

## 4. Ping-Pong RAM Verification

The ping-pong RAM testbench verifies the behavior of the two-bank architecture.

Important verification points include:

- Active bank selection.
- Inactive bank accessibility.
- Bank switching.
- Data preservation between banks.
- Correct behavior across clock boundaries.
- Read/write behavior around a bank switch.

The objective is to ensure that switching the active bank does not unintentionally corrupt the previously stored data.

---

## 5. FIFO Verification

FIFO verification focuses on AXI4-Stream handshake behavior.

Important conditions include:

- Valid data transfer.
- Consumer backpressure.
- Producer throttling.
- FIFO full behavior.
- FIFO empty behavior.
- Almost-full indication.
- `TLAST` preservation.
- Ordering of streamed data.

A correct FIFO must preserve the ordering of accepted stream transactions:

```text
Input:
D0 -> D1 -> D2 -> D3

Output:
D0 -> D1 -> D2 -> D3
```

regardless of temporary downstream backpressure.

---

## 6. DSP Core Verification

The DSP core is verified against expected arithmetic results.

The verification scope includes:

- Multiplication.
- Accumulation.
- Accumulator clear behavior.
- Configured operand widths.
- Output width behavior.
- Control sequencing.

The testbench is intended to detect both arithmetic errors and control-path errors.

---

## 7. Simulation Methodology

The testbenches use synthesizable RTL modules as the device under test while simulation-only constructs are used for stimulus and checking.

Typical simulation components include:

- Clock generation.
- Reset sequencing.
- Memory models.
- Transaction stimulus.
- Expected-result checking.
- Console output.

Where practical, testbenches are self-checking rather than relying exclusively on waveform inspection.

---

## 8. Waveform Analysis

Waveforms remain useful for diagnosing protocol and timing behavior.

Particular signals of interest include:

- Clock/reset.
- Memory address/data.
- Read/write enables.
- AXI `VALID/READY`.
- `TLAST`.
- FIFO status.
- State-machine state.
- Bank-selection signals.
- DSP control signals.

Waveform inspection should be used primarily for debugging failures or investigating timing-dependent behavior rather than as the only verification method.

---

## 9. FPGA Validation

Simulation and FPGA validation are considered separate verification stages.

Simulation establishes expected RTL behavior under the testbench model.

FPGA validation evaluates the synthesized implementation on actual hardware and can expose issues that are not visible in pure RTL simulation, including:

- Resource inference differences.
- Timing behavior.
- Reset implementation.
- Hardware-specific memory behavior.
- Interface integration issues.

FPGA validation status should therefore be documented separately for each module or project rather than assumed from successful simulation.

---

## 10. Verification Status

The verification status of individual modules should be maintained based on the latest available testbench and hardware results.

A successful simulation should be interpreted as:

> The tested RTL behavior matches the expected results under the conditions covered by the testbench.

It should not automatically be interpreted as complete verification of all parameter combinations, synthesis configurations, or FPGA implementations.

---

## 11. Recommended Verification Extensions

For future revisions, verification can be expanded through:

- Parameter-sweep testing.
- Randomized transaction generation.
- More extensive AXI backpressure scenarios.
- Memory collision testing.
- Boundary-address testing.
- Overflow/underflow testing.
- Formal property checking.
- Post-synthesis simulation.
- FPGA hardware validation.

These extensions are particularly useful when a utility becomes a dependency of multiple higher-level repositories.
