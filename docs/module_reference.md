# Module Reference

This document provides a functional overview of the reusable RTL modules contained in `VRM21-RTL-Utilities`.

The repository is organized around small infrastructure blocks rather than complete application-specific systems.

---

## 1. Memory Modules

### `vrm_ram_core`

Basic parameterized single-port RAM.

**Primary use cases:**

- Sample storage.
- Lookup tables.
- Small buffers.
- Register-like memory structures.
- FPGA RAM inference.

**Key parameters:**

- `DATA_WIDTH` — memory word width.
- `ADDR_WIDTH` — address width.
- `RAM_STYLE` — preferred FPGA memory implementation.

**Interface concept:**

| Signal | Direction | Description |
|---|---|---|
| `clk` | Input | Clock |
| `wr_en` | Input | Write enable |
| `wr_addr` | Input | Write address |
| `wr_data` | Input | Write data |
| `rd_addr` | Input | Read address |
| `rd_data` | Output | Read data |

The exact interface should be taken from the RTL source when integrating a specific revision.

---

### `vrm_tdp_ram_core`

True dual-port RAM implementation.

**Primary use cases:**

- Concurrent memory access.
- Producer/consumer architectures.
- Parallel processing.
- Buffering between independent datapaths.

The two memory ports provide independent access to the shared storage array.

---

### `vrm_pingpong_ram_core`

Double-buffered memory structure based on two RAM banks.

**Primary use cases:**

- DSP frame buffering.
- Streaming acquisition.
- Continuous processing.
- Producer/consumer buffering.

The design maintains an active and inactive memory bank and provides controlled switching between them.

---

## 2. FIFO Module

### `vrm_fifo`

AXI4-Stream FIFO.

**Primary use cases:**

- Rate matching.
- Temporary buffering.
- Stream decoupling.
- Packet/frame buffering.

**Supported stream concepts:**

- `TDATA`
- `TVALID`
- `TREADY`
- `TLAST`
- Almost-full indication.

The FIFO preserves `TLAST` together with its associated data item.

The implementation is suitable for FPGA distributed-memory inference when configured accordingly.

---

## 3. DSP Module

### `vrm_dsp_core`

Configurable DSP arithmetic core.

**Primary use cases:**

- Multiply-accumulate operations.
- FIR-style datapaths.
- Vector arithmetic.
- FPGA DSP slice utilization.
- Arithmetic building blocks for larger DSP systems.

**Main configuration concepts:**

| Parameter | Purpose |
|---|---|
| `A_WIDTH` | Width of operand A |
| `B_WIDTH` | Width of operand B |
| `P_WIDTH` | Product/accumulator datapath width |

The module provides control over accumulation and accumulator clearing.

---

## 4. AXI4-Lite Bridge

### `vrm_axilite2nsi_mmio_64`

AXI4-Lite to native memory-mapped interface bridge.

**Primary use cases:**

- Peripheral register access.
- CPU-to-hardware control paths.
- AXI-based system integration.
- Lightweight MMIO peripherals.

The bridge handles AXI4-Lite protocol transactions and exposes a simpler native-side interface.

The write and read paths use independent control state machines.

---

## 5. AXI4-Stream Write Bridge

### `vrm_axis2nsi_write`

AXI4-Stream to native sequential write interface.

**Primary use cases:**

- Stream-to-memory transfer.
- Frame storage.
- DMA-like internal datapaths.
- Connecting AXI4-Stream producers to simple memory interfaces.

The module uses the repository FIFO infrastructure to decouple stream reception from the native write side.

`TLAST` is used as the transfer/frame boundary indicator.

---

## 6. Dependency Relationships

The main internal dependency relationships can be summarized as:

```text
vrm_ram_core
     |
     +----------------------+
     |                      |
     v                      v
vrm_pingpong_ram_core   Other systems


vrm_fifo
     |
     v
vrm_axis2nsi_write


vrm_axilite2nsi_mmio_64
     |
     v
Native MMIO peripherals


vrm_dsp_core
     |
     v
DSP processing systems
```

The dependency structure is intentionally shallow so that modules remain portable across repositories.

---

## 7. Integration Recommendation

When integrating a module into another repository:

1. Copy or reference the required RTL module.
2. Preserve its parameter configuration.
3. Review the module's clock/reset assumptions.
4. Review memory collision and handshake behavior where applicable.
5. Integrate the corresponding testbench when practical.
6. Verify the module again in the target system.

The utilities repository should be treated as reusable infrastructure rather than as a complete system-level framework.