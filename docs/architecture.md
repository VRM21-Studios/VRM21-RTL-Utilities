# Architecture

## Overview

`VRM21-RTL-Utilities` is a reusable RTL infrastructure library containing basic hardware building blocks intended to be integrated into other VRM21-Studios projects.

The repository focuses on commonly reused structures such as memory blocks, buffering, streaming interfaces, DSP-oriented datapaths, and lightweight bus bridges. The modules are designed to remain relatively self-contained so that individual blocks can be integrated without requiring the complete repository.

The architecture can be broadly divided into four functional categories:

```text
VRM21 RTL Utilities
│
├── Memory
│   ├── Single-Port RAM
│   ├── True Dual-Port RAM
│   └── Ping-Pong / Double-Buffer RAM
│
├── Streaming & Buffering
│   └── AXI4-Stream FIFO
│
└── DSP Infrastructure
    └── Configurable DSP / MAC Core


```

The modules are intentionally implemented as independent building blocks rather than as a single tightly coupled subsystem.

---

## 1. Memory Architecture

### 1.1 Single-Port RAM

The basic RAM primitive is implemented by `vrm_ram_core`.

Its main characteristics are:

* Parameterized data width.
* Parameterized address width.
* Configurable inferred RAM style.
* Synchronous write operation.
* Registered read output.
* FPGA-oriented RAM inference support.

The RAM style can be selected through the `RAM_STYLE` parameter, allowing the implementation to target inferred block RAM, distributed RAM, or tool-selected memory resources depending on the target design.

Conceptually:

```text
              +------------------+
addr -------->|                  |
wr_data ----->|    VRM RAM       |----> rd_data
wr_en ------->|                  |
clk --------->|                  |
              +------------------+
```

The module is intended to provide a simple reusable memory abstraction for other RTL blocks.

---

### 1.2 True Dual-Port RAM

`vrm_tdp_ram_core` provides independent access ports to the same memory storage.

Conceptually:

```text
             +----------------------+
Port A ----->|                      |
             |   Dual-Port Memory   |
Port B ----->|                      |
             +----------------------+
```

The two ports allow simultaneous access to the memory array and are useful for architectures requiring concurrent producer/consumer or read/write access.

The implementation is designed for FPGA memory inference, with the memory style selectable through a parameter.

---

### 1.3 Ping-Pong RAM

`vrm_pingpong_ram_core` builds a double-buffering structure from two RAM instances.

The design maintains:

* One active bank.
* One inactive bank.
* A bank-selection mechanism.
* A controlled bank-switch operation.

Conceptually:

```text
                    +----------------+
                    | Active Bank    |
                    |    RAM A       |
                    +----------------+
                           ^
                           |
                     active select
                           |
Controller ---------------+
                           |
                           v
                    +----------------+
                    | Inactive Bank  |
                    |    RAM B       |
                    +----------------+
```

The two banks allow one memory region to be processed while the other is being filled or prepared.

This structure is particularly useful for streaming and DSP systems where continuous processing benefits from separating the current processing buffer from the next data buffer.

---

## 2. Streaming and Buffering Architecture

### AXI4-Stream FIFO

`vrm_fifo` provides an AXI4-Stream-compatible buffering structure.

The module exposes:

* AXI4-Stream slave input.
* AXI4-Stream master output.
* `TLAST` propagation.
* Standard `TVALID/TREADY` flow control.
* Almost-full indication.

Conceptually:

```text
        AXI4-Stream                  AXI4-Stream
             IN                          OUT
              |                           ^
              v                           |
        +-------------------------------------+
        |             VRM FIFO                |
        |                                     |
        |  Buffer + valid/ready management    |
        +-------------------------------------+
```

The FIFO is intended to absorb temporary differences between producer and consumer throughput while preserving AXI4-Stream packet boundaries through `TLAST`.

The implementation can be configured to use FPGA distributed RAM/LUTRAM where required.

---

## 3. DSP Infrastructure

### DSP Core

`vrm_dsp_core` provides a configurable arithmetic datapath intended to map efficiently onto FPGA DSP resources.

The core supports:

* Configurable operand widths.
* Configurable product width.
* Accumulation.
* Accumulator clear/control.
* DSP resource inference hints.

Conceptually:

```text
             A ----------------\
                                 \
                                  > Multiply ---> Product ---> Accumulator
                                 /
             B ----------------/

                                      ^
                                      |
                                  acc_clr
```

The core is intended as a low-level arithmetic building block for larger DSP architectures rather than as a complete application-specific DSP processor.

---

## 4. Integration Philosophy

The utilities repository follows a layered integration model.

Low-level primitives are intended to remain independent:

```text
             Application / System
                     |
          +----------+----------+
          |          |          |
        DSP       CPU/System   Streaming
          |          |          |
          +----------+----------+
                     |
              RTL Utilities
                     |
       +-------------+-------------+
       |             |             |
    Memory        FIFO         Interfaces
```

Higher-level repositories can therefore select only the required modules.

This approach reduces duplicated RTL across projects while keeping each application repository focused on its primary function.

---

## 5. Clocking and Reset

The utility modules generally operate in a synchronous single-clock domain unless explicitly stated otherwise by their individual interfaces.

The modules do not attempt to provide a general-purpose clock-domain crossing infrastructure.

Consequently, integration into multiple asynchronous clock domains requires an appropriate CDC mechanism at the system level.

---

## 6. FPGA-Oriented Implementation

The repository is designed with FPGA synthesis in mind.

Several modules contain synthesis attributes or parameters intended to influence resource inference, including:

* Block RAM.
* Distributed RAM.
* DSP resources.

These hints are implementation guidance rather than absolute guarantees. The final resource mapping remains dependent on the FPGA device, synthesis tool, configuration, and surrounding RTL.

---

## 7. Module Independence

Each utility is intended to have a clearly defined interface and limited assumptions about the surrounding system.

This enables modules to be:

* Reused by multiple repositories.
* Tested independently.
* Synthesized as part of larger systems.
* Replaced by application-specific implementations when necessary.

The repository therefore acts as a common RTL infrastructure layer for the broader VRM21-Studios hardware ecosystem.
