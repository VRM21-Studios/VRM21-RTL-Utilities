# VRM21 RTL Utilities

A collection of reusable, parameterized **Verilog RTL building blocks** for FPGA-based digital systems, DSP pipelines, memory infrastructure, and streaming architectures.

This repository provides common low-level RTL infrastructure used across projects developed by **VRM21 Studios**, with an emphasis on:

* Reusable and parameterized hardware modules
* FPGA-oriented memory and resource utilization
* Deterministic synchronous datapaths
* Streaming data movement and flow control
* Fixed-point and integer arithmetic infrastructure
* Modular hardware composition
* Clear separation between infrastructure and application-specific logic

The modules are developed primarily with **AMD/Xilinx Vivado** and FPGA-oriented RTL flows in mind, while maintaining generic Verilog structures where practical.

---

## Repository Scope

This repository contains low-level RTL infrastructure intended to be reused as building blocks or dependencies by larger FPGA and digital hardware projects.

The current repository scope covers:

* Memory infrastructure
* Streaming infrastructure
* DSP arithmetic infrastructure
* General-purpose RTL utilities

Application-specific architectures such as complete audio effects, processor systems, NPUs, synthesizers, and research-specific processing blocks are maintained in separate repositories.

The purpose of this repository is to avoid repeatedly implementing common low-level hardware infrastructure across those projects.

---

## Module Catalog

### Memory Infrastructure

#### `vrm_ram_core`

Parameterized synchronous RAM core with configurable memory implementation style and data-width-aware physical packing.

Main characteristics include:

* Parameterized data width
* Parameterized address width
* Configurable memory implementation style
* FPGA-oriented RAM inference
* Data-width-dependent physical packing
* Support for several common FPGA memory packing configurations
* Synchronous read behavior
* Simulation-time memory initialization

The core provides a logical memory interface while allowing the physical organization of the underlying memory array to be adapted according to the selected data width and implementation style.

See [`docs/architecture.md`](docs/architecture.md) and [`docs/design_rationale.md`](docs/design_rationale.md) for architectural details.

---

#### `vrm_tdp_ram_core`

Parameterized true dual-port RAM core with independent clocks and configurable memory implementation style.

Main characteristics include:

* Independent Port A and Port B
* Independent clocks
* Independent write enables
* Synchronous read outputs
* Shared physical memory array
* Configurable RAM inference style
* Data-width-aware memory packing
* Independent logical address mapping for each port

Both ports access the same physical memory resource. Consequently, simultaneous accesses to the same physical memory location require consideration of the target FPGA memory primitive and synthesis configuration.

Collision behavior is therefore not treated as a deterministic architectural guarantee unless explicitly documented for a particular implementation.

---

### Streaming Infrastructure

#### `vrm_fifo`

Parameterized **AXI4-Stream FIFO** with First-Word Fall-Through (FWFT) behavior.

Main characteristics include:

* Parameterized payload width
* Parameterized FIFO depth
* AXI4-Stream slave interface
* AXI4-Stream master interface
* `TVALID` / `TREADY` handshake support
* `TLAST` preservation
* Distributed RAM / LUTRAM-oriented implementation
* Combinational memory read path for FWFT operation
* FIFO occupancy tracking
* Almost-full flow-control indication

The FIFO stores the AXI4-Stream payload together with its associated `TLAST` flag.

Conceptually:

```text
+------------------+--------+
|      TDATA       | TLAST  |
+------------------+--------+
```

The module is intended for buffering, packet/frame preservation, and flow-control applications in streaming FPGA pipelines.

---

### DSP Infrastructure

#### `vrm_dsp_core`

Parameterized pipelined DSP arithmetic core with runtime-selectable operation modes.

Supported operations:

| `mode_sel` | Operation | Description         |
| ---------: | --------- | ------------------- |
|    `2'b00` | MUL       | Multiply            |
|    `2'b01` | MADD      | Multiply + Add      |
|    `2'b10` | MAC       | Multiply-Accumulate |
|    `2'b11` | ADD       | Addition            |

Main characteristics include:

* Parameterized A, B, and P widths
* Runtime-selectable operation mode
* Three-stage pipelined datapath
* Deterministic pipeline latency
* Clock-enable based pipeline control
* Explicit accumulator clear control
* Signed arithmetic
* FPGA DSP inference guidance

The datapath is organized conceptually as:

```text
Input Capture
      |
      v
Multiplication / Operand Alignment
      |
      v
Operation Selection / Accumulation
      |
      v
Output
```

The `acc_clr` control allows a MAC sequence to begin a new accumulation period.

The core is intended as reusable arithmetic infrastructure for larger DSP datapaths where deterministic timing and FPGA DSP resource inference are important.

---

## Design Conventions

The RTL in this repository generally follows a common set of conventions to simplify integration across projects.

### Reset

Reset signals are generally active-low and use names such as:

* `rstn`
* `aresetn`

The exact reset behavior is module-specific and is documented in the corresponding module documentation.

---

### Clock Enable and Valid Control

Where applicable, datapath modules use explicit control signals such as:

* `ce`
* `valid_in`
* `valid_out`

These signals are used to control datapath activity and maintain deterministic relationships between data and pipeline stages.

---

### AXI4-Stream Interfaces

Streaming modules follow the standard AXI4-Stream transfer convention:

```text
Transfer occurs when:

TVALID && TREADY
```

Modules that carry packet or frame boundaries preserve `TLAST` alongside the corresponding data element.

---

### Parameterization

Important architectural characteristics are exposed through module parameters where practical, including:

* Data width
* Address width
* Memory depth
* FIFO depth
* DSP operand width
* Output width
* Memory implementation style

The intent is to allow a single RTL implementation to support multiple system configurations.

---

### FPGA Resource Inference

FPGA-oriented modules may use synthesis attributes to guide resource inference.

Examples include:

```verilog
(* ram_style = "block" *)
```

```verilog
(* ram_style = "distributed" *)
```

and other vendor-supported synthesis directives where appropriate.

These attributes are implementation guidance rather than functional requirements of the logical RTL interface.

---

## Repository Structure

The repository follows a modular structure separating RTL implementation, verification collateral, results, and documentation.

```text
VRM21-RTL-Utilities/
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
│   ├── design_rationale.md
│   ├── verification.md
│   ├── limitations.md
│   └── ...
|
└── README.md
```

The exact structure may evolve as additional modules and verification collateral are introduced.

---

## Documentation

Detailed design and verification information is maintained separately from the root README.

The documentation set is intended to cover:

* Architecture and module organization
* Design rationale and implementation trade-offs
* Verification methodology
* Verification results
* Known limitations
* Integration considerations
* FPGA-specific implementation notes

Relevant documentation should be consulted before integrating a module into a larger design.

---

## Verification

Verification is performed primarily through RTL simulation using dedicated module-level testbenches.

Depending on the module, verification may cover:

* Functional correctness
* Reset behavior
* Boundary conditions
* Parameterized configurations
* Memory read/write behavior
* Address mapping
* Memory packing
* FIFO full and empty behavior
* AXI4-Stream handshake behavior
* `TLAST` preservation
* DSP operation modes
* Pipeline latency
* Valid-data alignment
* Accumulator behavior

Verification results are documented separately rather than treating the repository as having a single global verification status.

See [`docs/verification.md`](docs/verification.md) for the verification methodology and current status.

---

## Validation Levels

The repository distinguishes simulation verification from physical FPGA validation.

| Status                      | Meaning                                                                              |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `Simulation Verified`       | Functional behavior verified through RTL simulation                                  |
| `Post-Synthesis Verified`   | Behavior verified through synthesis or post-synthesis simulation                     |
| `Timing Verified`           | Timing closure achieved for a documented target configuration                        |
| `FPGA Validated`            | Design tested on physical FPGA hardware                                              |
| `Experimental`              | Functional implementation exists, but verification is incomplete                     |
| `Not Yet Validated on FPGA` | Simulation may be available, but physical FPGA validation has not yet been performed |

These labels are applied at the module or project level where appropriate.

A successful RTL simulation should not be interpreted as evidence of physical FPGA validation.

---

## Implementation and Toolchain

Primary development and implementation environment:

* **AMD Vivado**
* Verilog HDL
* FPGA-oriented RTL simulation
* Vendor-specific synthesis attributes where required

Target-specific implementation results, including synthesis utilization, timing, and FPGA validation, are documented separately when available.

The RTL is intended to remain structurally portable where practical, but some modules intentionally expose FPGA-specific implementation guidance to achieve predictable resource inference.

---

## Design Philosophy

The repository is intended to function as a reusable **RTL infrastructure layer** rather than as a collection of complete end-user designs.

The main design principles are:

* **Reusability** — common infrastructure should be implemented once and reused across projects.
* **Parameterization** — important hardware characteristics should be configurable where practical.
* **Deterministic timing** — pipeline latency and synchronous behavior should be explicit.
* **Modular composition** — larger systems should be assembled from independently understandable building blocks.
* **FPGA awareness** — RTL should consider practical FPGA resource inference and implementation behavior.
* **Clear interfaces** — module boundaries should expose predictable and documented interfaces.
* **Separation of concerns** — generic infrastructure should remain independent from application-specific algorithms whenever practical.

This repository therefore acts as a shared low-level foundation for other VRM21 Studios hardware projects.

---

## Limitations

The modules in this repository are not intended to provide universal technology-independent guarantees.

Some implementations depend on:

* FPGA memory primitive behavior
* Vivado synthesis and inference rules
* Target-device architecture
* Parameter combinations
* Clocking configuration
* Memory collision behavior
* Simulation-model assumptions

In particular, successful RTL simulation does not guarantee successful synthesis, timing closure, or physical FPGA operation for every parameter configuration.

Module-specific limitations and unsupported configurations are documented in the corresponding documentation.

See [`docs/limitations.md`](docs/limitations.md).

---

## Current Status

The repository is **actively maintained and expanded** as a shared RTL utility library for VRM21 Studios projects.

The current collection contains reusable memory, streaming, and DSP infrastructure. Individual modules may have different levels of verification and hardware validation.

The status of a particular module should therefore be determined from its associated verification documentation rather than from the repository status alone.

New modules, dedicated testbenches, simulation results, implementation reports, and supporting documentation will be added progressively.

---

## Roadmap

Planned improvements include:

* Additional reusable RTL utility modules
* Expanded module-level testbenches
* More comprehensive verification result documentation
* Simulation result archives
* Representative synthesis and implementation reports
* Timing results for selected FPGA targets
* Additional architecture documentation
* Integration examples
* Expanded parameterization and configuration support
* Improved cross-repository reuse of common RTL infrastructure

The roadmap may evolve as the library and its dependent projects develop.

---

## Related Projects

`VRM21-RTL-Utilities` is intended to serve as a low-level dependency for other projects developed by **VRM21 Studios**.

Potential consumers include projects involving:

* FPGA-based DSP
* Audio processing
* RISC-V processor architectures
* FPGA accelerators
* Memory subsystems
* Streaming data pipelines
* Research-oriented digital hardware

Application-specific functionality is intentionally kept outside this repository when it does not belong to the generic infrastructure layer.

---

## License

Licensed under the MIT License.

Provided as-is, without warranty.
