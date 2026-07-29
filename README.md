# VRM RTL Library

A collection of reusable, parameterized **Verilog RTL building blocks** for FPGA-based digital systems, DSP pipelines, memory infrastructure, and streaming architectures.

This repository is intended to provide a common RTL foundation for projects developed by **VRM21 Studios**, with an emphasis on:

* Parameterized and reusable hardware modules
* FPGA-oriented memory utilization
* Deterministic synchronous datapaths
* Streaming data processing
* Fixed-point arithmetic building blocks
* Clean separation between infrastructure and application-specific logic

The modules in this repository are designed primarily for **AMD/Xilinx Vivado-based FPGA development**, while maintaining a generic RTL structure where practical.

---

## Repository Scope

This repository contains reusable RTL infrastructure and low-level processing cores that can be used as dependencies by larger FPGA projects.

The current scope includes:

* Memory infrastructure
* Streaming infrastructure
* DSP arithmetic infrastructure
* Utility RTL modules

Higher-level applications such as complete audio effects, synthesizers, NPU architectures, and research-specific processing blocks are maintained separately.

---

## Module Catalog

### Memory Infrastructure

#### `vrm_ram_core`

Parameterized synchronous RAM core with automatic data-width packing.

Main characteristics:

* Parameterized data width
* Parameterized address width
* Configurable Vivado RAM inference style
* Automatic packing for selected data widths
* 72-bit packing mode for 9-bit, 18-bit, and 36-bit data
* 72-bit / 144-bit packing mode for 24-bit and 48-bit data
* 64-bit packing mode for 8-bit, 16-bit, and 32-bit data
* Native-width mode for wide or non-standard data widths
* Synchronous read behavior
* Simulation-time memory initialization

The module is intended to provide a reusable memory abstraction while allowing the physical FPGA memory organization to be adapted to the selected data width.

---

#### `vrm_tdp_ram_core`

Parameterized true dual-port RAM core with independent clocks and automatic data-width packing.

Main characteristics:

* Independent Port A and Port B
* Independent clocks
* Independent write enables
* Synchronous read outputs
* Shared physical memory array
* Configurable Vivado RAM inference style
* 72-bit packing mode for 9-bit, 18-bit, and 36-bit data
* 72-bit / 144-bit packing mode for 24-bit and 48-bit data
* 64-bit packing mode for 8-bit, 16-bit, and 32-bit data
* Native-width mode for unsupported or non-standard data widths

Each port independently maps a logical user address to the corresponding physical memory word and, when applicable, the logical data chunk within the packed word.

Concurrent access to the same physical memory location from both ports should be treated according to the target FPGA memory primitive behavior. Collision behavior is not currently specified as a deterministic architectural guarantee.

---

### Streaming Infrastructure

#### `vrm_fifo`

Parameterized AXI4-Stream FIFO with First-Word Fall-Through (FWFT) behavior.

Main characteristics:

* Parameterized payload width
* Parameterized FIFO depth
* AXI4-Stream slave interface
* AXI4-Stream master interface
* `TVALID` / `TREADY` handshake support
* `TLAST` preservation
* Distributed RAM / LUTRAM inference
* Combinational memory read path for FWFT behavior
* Occupancy tracking
* Almost-full flow-control indication

FIFO memory stores the AXI4-Stream payload and `TLAST` flag together:

```text
[DATA_WIDTH]     -> TLAST
[DATA_WIDTH-1:0] -> TDATA
```

The `s_axis_almost_full` signal is asserted when the FIFO occupancy reaches the configured threshold of two or fewer remaining entries.

This module is intended for buffering and flow-control applications in streaming DSP and FPGA pipelines.

---

### DSP Infrastructure

#### `vrm_dsp_core`

Parameterized pipelined DSP arithmetic core with runtime operation-mode selection.

Supported operations:

| `mode_sel` | Operation | Description         |
| ---------: | --------- | ------------------- |
|    `2'b00` | MUL       | Multiply            |
|    `2'b01` | MADD      | Multiply + Add      |
|    `2'b10` | MAC       | Multiply-Accumulate |
|    `2'b11` | ADD       | Addition            |

Main characteristics:

* Parameterized A, B, and P widths
* Runtime-selectable operation mode
* Three-stage pipelined datapath
* Fixed valid pipeline latency
* Clock-enable based pipeline control
* Explicit MAC accumulator clear control
* Signed arithmetic
* DSP inference guidance through `use_dsp = "yes"`

Pipeline structure:

```text
Stage 1
Input Capture
    |
    v
Stage 2
Multiplication + Operand Alignment
    |
    v
Stage 3
ALU Mode Selection + MAC Accumulation
    |
    v
Output
```

The `acc_clr` control allows the MAC operation to start a new accumulation sequence from the current multiplication result.

The core is designed as a reusable arithmetic building block for larger DSP datapaths where runtime operation selection and deterministic pipeline timing are required.

---

## Common Design Conventions

The modules in this repository generally follow the following conventions:

### Reset

Reset signals are active-low and are named according to the interface context:

* `rstn`
* `aresetn`

The reset behavior is synchronous unless explicitly stated otherwise.

### Enable and Handshake

Pipeline and streaming modules use explicit enable or handshake signals where appropriate.

Examples:

* `ce` for datapath clock enable
* `valid_in` / `valid_out` for data validity tracking
* AXI4-Stream `TVALID` / `TREADY` for transfer control

### Parameterization

Modules are designed to expose important architectural parameters such as:

* Data width
* Address width
* Memory depth
* FIFO depth
* DSP operand width
* Memory implementation style

This allows the same RTL core to be reused across different FPGA designs.

### FPGA Memory Inference

Where appropriate, memory implementations use Vivado synthesis attributes such as:

```verilog
(* ram_style = "block" *)
```

or:

```verilog
(* ram_style = "ultra" *)
```

or:

```verilog
(* ram_style = "distributed" *)
```

The selected memory style is intended to guide synthesis toward the desired FPGA memory resource.

---

## Repository Structure

The repository is expected to follow a structure similar to:

```text
VRM-RTL-Library/
|
├── rtl/
│   ├── vrm_ram_core.v
│   ├── vrm_tdp_ram_core.v
│   ├── vrm_fifo.v
│   ├── vrm_dsp_core.v
│   └── ...
|
├── tb/
│   ├── tb_vrm_ram_core.v
│   ├── tb_vrm_tdp_ram_core.v
│   ├── tb_vrm_fifo.v
│   ├── tb_vrm_dsp_core.v
│   └── ...
|
├── result/
│   └── ...
|
├── docs/
│   ├── architecture.md
│   ├── verification.md
│   └── ...
|
└── README.md
```

The exact repository structure may evolve as additional modules and verification collateral are added.

---

## Verification Status

Verification documentation is currently under development.

Dedicated testbenches and verification results will be added for the individual modules in subsequent updates.

The current verification process is intended to cover, where applicable:

* Functional correctness
* Reset behavior
* Boundary conditions
* Parameterized configurations
* Read/write behavior
* AXI4-Stream handshake behavior
* FIFO full and empty conditions
* DSP operation modes
* Pipeline latency and valid alignment
* Memory packing and address mapping

At this checkpoint stage, no general claim of FPGA hardware validation is made for the repository as a whole.

Individual modules may have different validation levels, which will be documented separately once the corresponding testbench and implementation results are available.

---

## Validation Levels

The repository will use the following status terminology:

| Status                      | Meaning                                                                  |
| --------------------------- | ------------------------------------------------------------------------ |
| `Simulation Verified`       | Functional behavior verified using RTL simulation                        |
| `Post-Synthesis Verified`   | Verified after synthesis or post-synthesis simulation                    |
| `Timing Verified`           | Timing closure achieved for a documented target configuration            |
| `FPGA Validated`            | Tested on physical FPGA hardware                                         |
| `Experimental`              | Functional implementation exists but verification is incomplete          |
| `Not Yet Validated on FPGA` | Simulation may exist, but hardware validation has not yet been completed |

These labels are intended to distinguish simulation results from physical FPGA validation.

---

## Toolchain

Primary development environment:

* **AMD Vivado**
* Verilog HDL
* FPGA-oriented RTL simulation

Specific synthesis, timing, and hardware validation results will be documented together with the relevant target device and project configuration.

---

## Design Philosophy

This repository focuses on reusable low-level RTL rather than complete end-user applications.

The general design approach is based on:

* Reusability
* Parameterization
* Explicit timing behavior
* Deterministic data movement
* FPGA-aware architecture
* Modular composition
* Separation of infrastructure and application logic

The goal is to allow higher-level designs to reuse common building blocks instead of repeatedly implementing the same low-level infrastructure.

---

## Current Status

This repository is currently under active development.

The modules currently included should be considered a mixture of reusable building blocks and ongoing development work. Verification results, dedicated testbenches, implementation reports, and supporting documentation will be added progressively.

The repository is intended to serve as a common RTL dependency for future VRM21 Studios projects, including FPGA-based DSP and other digital hardware systems.

---

## Roadmap

Planned repository improvements include:

* Additional reusable RTL utility modules
* Dedicated testbenches for each core
* Verification result documentation
* Simulation result archives
* Synthesis and timing reports for representative targets
* Expanded module documentation
* Architecture and integration notes
* Additional FPGA-oriented infrastructure components

The roadmap may change as the library evolves.

---

## Related Projects

This repository serves as a low-level RTL foundation for other VRM21 Studios FPGA projects.

Higher-level modules and application-specific implementations may be maintained in separate repositories.

Examples include:

* FPGA-based DSP processing
* Audio processing systems
* RISC-V processor architectures
* FPGA accelerators
* Research-oriented hardware implementations

---

## License

Licensed under the MIT License.

Provided as-is, without warranty.
