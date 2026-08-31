# Design Trade-Offs

## Overview

The modules in `VRM21-RTL-Utilities` prioritize reuse, predictable RTL behavior, and FPGA implementation practicality.

These goals introduce several deliberate trade-offs.

---

## 1. Simplicity vs. Generality

The modules use relatively simple interfaces rather than attempting to support every possible system configuration.

### Advantage

- Easier integration.
- Easier verification.
- Smaller RTL footprint.
- Easier waveform analysis.

### Trade-off

Applications requiring unusual protocol behavior may need an additional wrapper or a specialized implementation.

---

## 2. Parameterization vs. Implementation Complexity

Parameterized widths and depths increase reuse.

However, excessive parameterization can make RTL harder to verify and can introduce corner cases.

The repository therefore parameterizes characteristics that are expected to vary between projects while keeping the underlying control architecture relatively fixed.

---

## 3. FPGA Resource Guidance vs. Portability

Attributes such as RAM and DSP inference hints can improve FPGA implementation results.

However, these attributes are inherently dependent on synthesis tools and target architectures.

The trade-off is intentional:

```text
More implementation guidance
          |
          v
Better FPGA inference
          |
          v
Potentially less tool independence
```

The RTL therefore remains functionally understandable even when a synthesis tool ignores a particular implementation hint.

---

## 4. Registered Memory Read vs. Lower Latency

The basic RAM architecture uses registered read behavior.

### Advantages

- Predictable timing.
- Better suitability for synchronous FPGA memory resources.
- Easier timing closure for larger memories.

### Trade-off

A registered read introduces latency compared with a purely combinational lookup.

Systems integrating the RAM must therefore account for the memory read latency.

---

## 5. Double Buffering vs. Memory Utilization

Ping-pong RAM improves producer/consumer concurrency by using two banks.

The trade-off is increased memory consumption.

For a buffer of depth `N` and width `W`, the double-buffered implementation requires approximately:

```text
2 × N × W
```

bits of storage before considering implementation overhead.

This is appropriate when throughput is more important than minimizing storage.

---

## 6. FIFO Buffering vs. Resource Usage

A deeper FIFO provides more tolerance to temporary throughput mismatches.

However:

- More memory resources are required.
- Larger buffers can increase implementation cost.
- FIFO depth does not solve a sustained throughput mismatch.

The FIFO should therefore be sized according to the expected burst behavior of the system.

---

## 7. AXI4-Lite Bridge Simplicity vs. Full AXI Features

The MMIO bridge is intended for lightweight control/status access.

It should not be treated as a replacement for a complete high-performance AXI interconnect.

The implementation favors a compact transaction state machine over support for advanced AXI system-level features.

---

## 8. Sequential Stream Writer vs. Flexible Address Generation

`vrm_axis2nsi_write` is optimized for sequential data storage.

The address generation model is therefore intentionally simple.

This makes the block suitable for:

- Linear buffers.
- Frame storage.
- Sequential sample streams.

It is less appropriate when the destination requires arbitrary address generation, scatter/gather behavior, or complex DMA descriptors.

---

## 9. Common Infrastructure vs. Application-Specific Optimization

Using a common utility implementation improves consistency between projects.

However, an application-specific implementation may achieve better optimization for a particular workload.

The intended workflow is:

```text
Prototype
   |
   v
Use reusable utility
   |
   v
Verify system behavior
   |
   +----> Utility is sufficient
   |
   +----> Specialized implementation required
```

The utilities repository therefore serves as a reusable baseline rather than a claim that every application should use the generic implementation permanently.

---

## 10. Explicit Interfaces vs. Hidden System Assumptions

The modules expose their important control and data signals explicitly.

This avoids hiding system behavior inside implicit infrastructure.

The trade-off is a slightly more verbose integration interface, but the resulting design is easier to inspect and debug.

---

## 11. Resource Efficiency vs. Maximum Throughput

Some modules prioritize predictable resource usage over aggressive parallelism.

For example, a generic DSP core can serve as a reusable arithmetic primitive, while a specialized DSP architecture may instantiate multiple parallel datapaths for maximum throughput.

The utility implementation should therefore be selected according to the system-level throughput requirement.

---

## 12. Design Philosophy

The overall trade-off can be summarized as:

```text
                 VRM21 RTL Utilities

       Reuse  <-------------------->  Specialization
         |                                |
         v                                v
   Generic building                Application-
      blocks                       optimized RTL

         ^
         |
         +-- Current repository focus
```

The repository intentionally stays closer to the reusable-building-block side of this spectrum.