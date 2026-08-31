# Integration Guide

## Overview

`VRM21-RTL-Utilities` is intended to be consumed as a reusable RTL dependency by other VRM21-Studios projects.

The modules are designed to be integrated individually rather than requiring the entire repository to be instantiated as one subsystem.

---

## 1. Selecting a Utility

Choose the smallest module that satisfies the required function.

Typical mappings are:

| Requirement | Recommended Utility |
|---|---|
| Simple synchronous RAM | `vrm_ram_core` |
| Two-port memory access | `vrm_tdp_ram_core` |
| Double buffering | `vrm_pingpong_ram_core` |
| AXI4-Stream buffering | `vrm_fifo` |
| FPGA DSP arithmetic | `vrm_dsp_core` |
| AXI4-Lite peripheral access | `vrm_axilite2nsi_mmio_64` |
| AXI4-Stream to sequential memory write | `vrm_axis2nsi_write` |

---

## 2. RTL Dependency Management

A consuming repository may either:

1. Copy the required RTL module into its own source tree.
2. Include the utility repository as an external dependency.
3. Use a project-level source management mechanism that references the utility repository.

The preferred approach depends on the build system of the consuming project.

Only the required modules and their dependencies should be included when practical.

---

## 3. Parameter Configuration

Before instantiation, review the module parameters.

For memory blocks, confirm:

- Data width.
- Address width.
- Required depth.
- Preferred RAM resource.

For DSP blocks, confirm:

- Operand widths.
- Product width.
- Accumulator requirements.

For interface bridges, confirm:

- Address width.
- Data width.
- Handshake behavior.
- Native-side timing.

---

## 4. Clock and Reset

All connected modules must operate under a compatible clock/reset architecture.

Verify:

- Clock frequency.
- Clock polarity.
- Reset polarity.
- Reset synchronization.
- Reset release timing.

Do not assume that a utility's reset behavior automatically matches the consuming system.

---

## 5. Memory Integration

When integrating a RAM module, determine the expected read latency.

For example:

```text
Cycle N:
    rd_addr = A

Cycle N+1:
    rd_data = MEM[A]
```

The consuming logic must align its control signals accordingly.

For dual-port memories, also define the system behavior for simultaneous access to the same location.

---

## 6. FIFO Integration

AXI4-Stream connections should follow the standard handshake model.

A transfer occurs when:

```text
TVALID && TREADY
```

The producer must maintain valid data while `TVALID` is asserted and the consumer is not ready.

The consumer must not assume that data is transferred merely because `TVALID` is high.

For frame-based transfers, `TLAST` should remain associated with the final data item of the frame.

---

## 7. AXI4-Lite MMIO Integration

The AXI4-Lite bridge should normally sit between an AXI4-Lite master and a native register/peripheral block.

Example:

```text
CPU / AXI Master
       |
       | AXI4-Lite
       v
+-------------------+
| vrm_axilite2nsi   |
|    _mmio_64       |
+-------------------+
       |
       | Native MMIO
       v
+-------------------+
| Peripheral        |
| Registers         |
+-------------------+
```

The peripheral should implement the native-side transaction semantics expected by the bridge.

---

## 8. AXI4-Stream Write Integration

The stream writer is appropriate when a producer generates sequential data and the destination expects a simple write interface.

Example:

```text
AXI4-Stream Source
        |
        v
  vrm_axis2nsi_write
        |
        +---- wr_addr
        +---- wr_data
        +---- wr_en
        |
        v
   Memory / Buffer
```

The destination does not need to understand AXI4-Stream directly.

---

## 9. Ping-Pong Buffer Integration

A typical producer/consumer architecture can be structured as:

```text
              +----------------+
              | Data Producer  |
              +-------+--------+
                      |
                      v
                +-----------+
                | Bank A/B  |
                | Ping-Pong  |
                +-----+-----+
                      |
                      v
              +----------------+
              | Data Processor |
              +----------------+
```

The system controller should ensure that a bank is not switched or reused while it is still being accessed by the processing path.

---

## 10. DSP Core Integration

The DSP core is intended to serve as an arithmetic primitive.

A larger datapath may connect it as:

```text
Input A ----\
             \
              > VRM DSP Core ---> Accumulated Result
             /
Input B ----/
```

The consuming design is responsible for:

- Input scaling.
- Numeric representation.
- Overflow handling.
- Accumulator management.
- Output formatting.

The utility does not automatically define application-level fixed-point semantics.

---

## 11. Verification After Integration

A utility that passes its standalone testbench should still be tested in the consuming system.

Integration verification should cover:

1. Reset behavior.
2. Normal transactions.
3. Boundary conditions.
4. Backpressure.
5. Memory access timing.
6. Interrupt/control interaction where applicable.
7. System-level data integrity.

The purpose is to verify not only the utility itself but also the assumptions made by the surrounding design.

---

## 12. Recommended Project Structure

A consuming repository may organize utility dependencies as:

```text
project/
├── rtl/
│   ├── application/
│   └── utilities/
│       ├── vrm_ram_core.v
│       ├── vrm_fifo.v
│       └── ...
│
├── tb/
│   └── ...
│
└── docs/
    └── ...
```

Alternatively, utilities may remain in a dedicated dependency directory if the build system supports external RTL sources.

---

## 13. Versioning Considerations

Because the utilities may be shared by multiple projects, changes to a utility should be treated as interface-sensitive changes.

Before updating a consuming repository, verify:

- Port compatibility.
- Parameter compatibility.
- Latency changes.
- Reset behavior.
- Handshake behavior.
- Synthesis behavior.

A functional change in a low-level utility can affect several higher-level repositories simultaneously.

---

## 14. Integration Checklist

Before committing an integrated utility, verify:

- [ ] Correct RTL source revision is used.
- [ ] All required dependencies are included.
- [ ] Parameters are appropriate for the target.
- [ ] Clock/reset assumptions are satisfied.
- [ ] Memory latency is accounted for.
- [ ] AXI handshakes are correctly connected.
- [ ] `TLAST` behavior is preserved where applicable.
- [ ] Backpressure behavior is verified.
- [ ] Boundary conditions are tested.
- [ ] Simulation passes.
- [ ] FPGA validation is performed when required.

---

## 15. Final Recommendation

The utilities should be treated as shared infrastructure.

When a consuming project requires behavior that is substantially different from the intended utility interface, it is generally preferable to create a dedicated wrapper or application-specific module rather than adding excessive special-case behavior to the common utility.

This keeps `VRM21-RTL-Utilities` compact, reusable, and easier to maintain across the broader VRM21-Studios hardware ecosystem.