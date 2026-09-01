# VRM21 RTL Utilities - Analysis Tools

This directory contains Python-based utility tools intended to assist with the analysis and post-processing of simulation data generated during RTL, DSP, and FPGA development.

The tools are not part of the synthesizable RTL implementation. They are provided as supporting utilities for inspecting recorded signal data and converting compatible simulation outputs into more convenient formats for analysis.

## Included Tools

### `csv_signal_analyzer.py`

A batch-processing utility for generating time-domain and frequency-domain visualizations from CSV or TXT data files.

The script automatically identifies numeric signal columns and attempts to exclude common metadata fields such as time, sample indices, and labels.

Main capabilities include:

* Batch processing of CSV and TXT files
* Automatic numeric-column detection
* Time-domain waveform visualization
* Frequency-domain analysis using the FFT
* One-sided magnitude spectrum generation
* Magnitude representation in decibels
* Optional logarithmic frequency scaling
* Audio-oriented frequency display from approximately 20 Hz to 20 kHz
* Automatic dominant-frequency annotation
* Optional left/right channel grouping
* Optional input/output signal grouping
* Configurable time-domain amplitude limits
* Configurable frequency-domain magnitude limits
* Optional sample-range processing
* Automatic output-image naming
* Optional skipping of previously processed files

For each processed input file, the script generates:

```text
<filename>_TD.png
<filename>_FD.png
```

The generated files contain time-domain and frequency-domain representations of the detected numeric signals.

---

## Signal Grouping

The signal analyzer attempts to classify columns according to naming conventions.

The following keywords may be used to identify signal direction:

```text
input
in
masukan
```

These are interpreted as input signals.

The following keywords may be used to identify output signals:

```text
output
out
keluaran
```

Channel-side classification attempts to identify names associated with:

```text
left
l
kiri
```

and:

```text
right
r
kanan
```

The classification is heuristic and depends on the naming convention used by the input data.

Users should therefore verify automatically generated groupings when analyzing datasets with non-standard column names.

---

## Frequency-Domain Processing

The frequency-domain analysis uses a real-valued Fast Fourier Transform:

```text
numpy.fft.rfft()
```

The resulting magnitude is converted into a one-sided spectrum.

For non-DC frequency components, the magnitude is multiplied by two before conversion to decibels.

Magnitude values are calculated as:

```text
Magnitude_dB = 20 × log10(Magnitude + ε)
```

where a small numerical offset is used to prevent logarithm-of-zero errors.

The script can display the frequency axis using either:

* Logarithmic scaling
* Linear scaling

Logarithmic scaling is generally more suitable for audio-oriented analysis because it provides better visual representation across a wide frequency range.

---

# `csv_to_wav_converter.py`

This utility converts compatible numeric signal columns from CSV or TXT files into individual mono WAV files.

The script is primarily intended for analyzing simulation-generated audio or audio-like signals outside the original RTL verification environment.

For example, a simulation output containing multiple audio channels may be converted into separate WAV files for listening, external inspection, or further signal processing.

## Audio Signal Detection

The script attempts to distinguish audio signals from metadata and control signals.

Columns may be excluded when they:

* Contain too few unique values
* Have extremely low variance
* Have an extremely small amplitude range
* Appear to represent time or sample indices
* Contain common AXI-stream control names such as `tvalid`, `tready`, `tlast`, or `tkeep`

The detection process is heuristic.

A column identified as numeric is not automatically guaranteed to represent an audio signal, and users should verify the generated output when processing datasets with unusual formats.

---

## WAV Output

Each detected audio column is exported as a separate mono WAV file using the naming format:

```text
<input_filename>_<column_name>.wav
```

For example:

```text
simulation_output.csv
```

with a detected column:

```text
audio_output_l
```

may generate:

```text
simulation_output_audio_output_l.wav
```

Supported output formats include:

* 16-bit signed PCM
* 32-bit signed PCM

---

## Signal Normalization

Optional independent normalization is provided for each exported signal.

When enabled, the maximum absolute sample value of each signal is scaled to approximately:

```text
[-1, 1]
```

before conversion to the selected integer PCM representation.

This can be useful when simulation data uses floating-point or fixed-point values with inconsistent amplitude ranges.

However, independent normalization changes the relative amplitude relationship between different exported signals.

For amplitude-sensitive comparisons, normalization should therefore be disabled or the input data should be scaled using a consistent reference.

---

## Optional Plot Generation

The WAV conversion tool can optionally generate:

```text
<filename>_TD.png
<filename>_FD.png
```

These plots contain combined representations of all detected audio columns from the processed file.

The frequency-domain plot can optionally use logarithmic frequency scaling.

---

# Requirements

The tools require Python and several scientific-computing libraries.

## Recommended Python Version

The tools are maintained and tested against the following Python version:

```text
Python 3.11.9
```

The scripts use standard Python features together with widely available scientific Python packages.

## Required Libraries

The following packages are required:

```text
numpy
pandas
matplotlib
scipy
```

A suitable `requirements.txt` file is:

```text
numpy>=1.24,<3.0
pandas>=2.0,<4.0
matplotlib>=3.7,<4.0
scipy>=1.10,<2.0
```

These version ranges are compatible with a typical Python 3.11 environment.

---

# Installation

Clone the repository and enter the project directory:

```bash
git clone https://github.com/VRM21-Studios/VRM21-RTL-Utilities.git
cd VRM21-RTL-Utilities
```

It is recommended to create a Python virtual environment:

```bash
python -m venv .venv
```

On Windows:

```bash
.venv\Scripts\activate
```

On Linux:

```bash
source .venv/bin/activate
```

Install the required dependencies:

```bash
pip install -r requirements.txt
```

The tools can then be executed directly with Python.

---

# Usage

## CSV Signal Analyzer

Run:

```bash
python tools/csv_signal_analyzer.py
```

The script will request:

* Input directory
* Sampling frequency
* Frequency-axis scale
* Left/right channel merge options
* Input/output signal merge options
* Existing-output handling
* Optional manual amplitude limits
* Optional sample range

The input directory may contain multiple CSV or TXT files.

Each supported file is processed individually.

---

## CSV to WAV Converter

Run:

```bash
python tools/csv_to_wav_converter.py
```

The script will request:

* Input directory
* Sampling frequency
* Normalization option
* Output bit depth
* Optional plot generation
* Optional sample range
* Output directory

Each detected audio signal column is exported as an individual mono WAV file.

---

# Expected Input Format

The tools accept delimited text files readable by:

```python
pandas.read_csv()
```

Delimiter detection is performed automatically through:

```python
sep=None
engine="python"
```

Typical CSV input may contain a structure similar to:

```text
sample,input_l,input_r,output_l,output_r
0,0.000,0.000,0.000,0.000
1,0.125,0.118,0.110,0.105
2,0.245,0.230,0.220,0.210
3,0.340,0.320,0.310,0.295
...
```

The tools automatically attempt to ignore columns that appear to represent:

* Time
* Sample numbers
* Indices
* Labels
* Protocol control signals

The automatic filtering is heuristic and is not intended to replace explicit knowledge of the dataset structure.

---

# Intended Use

These utilities are primarily intended to support:

* RTL simulation analysis
* DSP signal inspection
* FPGA verification workflows
* Audio signal analysis
* Waveform post-processing
* CSV-based simulation result visualization
* Frequency-domain inspection
* Conversion of simulation-generated signals into WAV files

The tools are supporting utilities and do not modify or participate in the synthesizable RTL implementation.

They may be used independently of the hardware modules in this repository when their input-data format is compatible.

---

# Limitations

Several limitations should be considered.

## Heuristic Signal Detection

Column classification and audio-signal detection are based on column names and simple statistical properties.

The tools may therefore misclassify signals when:

* Column names use unexpected conventions
* Control signals contain many unique values
* Valid signals have very small amplitudes
* Audio signals are nearly constant
* Input datasets use non-standard metadata naming

Users should inspect generated results rather than treating automatic classification as a definitive signal-identification mechanism.

## FFT Windowing

The current frequency-domain implementation performs the FFT directly on the selected data.

No explicit window function is applied before the FFT.

Consequently, spectral leakage may occur when the analyzed sample range does not contain an integer number of signal periods.

For detailed spectral measurements, additional preprocessing or windowing may be required.

## WAV Normalization

When normalization is enabled, each column is normalized independently.

This may alter relative amplitude relationships between different channels or signals.

Normalization should be disabled when preserving absolute amplitude relationships is important.

## Sampling Frequency

The sampling frequency is provided manually by the user.

The tools do not automatically extract sampling frequency information from the input data.

Incorrect sampling-frequency configuration will result in incorrect time and frequency axes and incorrect WAV playback speed.

---

# Repository Integration

These tools are provided as supporting analysis utilities within the VRM21 RTL Utilities repository.

A typical repository structure may be:

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
│   └── ...
|
├── tools/
│   ├── csv_signal_analyzer.py
│   ├── csv_to_wav_converter.py
│   └── README.md
|
├── docs/
│   └── ...
|
├── requirements.txt
|
└── README.md
```

The Python tools complement the RTL and verification infrastructure by providing reusable utilities for simulation-result processing and signal analysis.

---

# License

Unless otherwise stated, the tools in this directory are distributed under the same license as the parent repository.

The software is provided as-is, without warranty.
