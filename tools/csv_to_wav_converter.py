import os
import pandas as pd
import numpy as np
from scipy.io import wavfile
import matplotlib.pyplot as plt
import math
import warnings


warnings.filterwarnings("ignore")


# ==============================================================================
# Audio Signal Detection
# ==============================================================================
def is_audio_column(
    series,
    threshold_variance=1e-6,
    unique_threshold=10,
):
    """
    Determine whether a numeric column is likely to represent an audio signal.

    The classification uses the following criteria:

    - The number of unique values must exceed the specified threshold.
    - The signal variance must exceed the specified threshold.
    - The signal amplitude range must be sufficiently large.

    Parameters
    ----------
    series : pandas.Series
        Input numeric data.

    threshold_variance : float
        Minimum variance required for a column to be considered an audio signal.

    unique_threshold : int
        Minimum number of unique values required.

    Returns
    -------
    bool
        True if the column is likely to represent an audio signal.
    """

    # Reject signals with too few unique values, such as binary control signals.
    if series.nunique() <= unique_threshold:
        return False

    # Reject nearly constant signals.
    if series.var() < threshold_variance:
        return False

    # Reject signals with an extremely small amplitude range.
    if (
        series.max()
        - series.min()
        < 1e-3
    ):
        return False

    return True


# ==============================================================================
# CSV/TXT to WAV Conversion
# ==============================================================================
def csv_to_wav_per_column(
    filepath,
    fs=48000,
    normalize=True,
    bit_depth=np.int16,
    start_sample=None,
    end_sample=None,
    output_folder=None,
    generate_plot=False,
    use_log_freq=True,
):
    """
    Convert detected audio columns from a CSV or TXT file into individual
    mono WAV files.

    Parameters
    ----------
    filepath : str
        Path to the input CSV or TXT file.

    fs : float
        Sampling frequency in Hz.

    normalize : bool
        Normalize each signal independently to the range approximately
        [-1, 1] before integer conversion.

    bit_depth : numpy.dtype
        Output integer format. Supported values are np.int16 and np.int32.

    start_sample : int or None
        Starting sample index.

    end_sample : int or None
        Ending sample index (exclusive).

    output_folder : str or None
        Directory for generated WAV files. If None, the input file directory
        is used.

    generate_plot : bool
        Generate time-domain and frequency-domain plots.

    use_log_freq : bool
        Use a logarithmic frequency axis when generating spectrum plots.

    Returns
    -------
    bool
        True if processing completes successfully.
    """

    filename = os.path.basename(filepath)

    name, _ = os.path.splitext(filename)

    # Use the input file directory when no output directory is specified.
    if output_folder is None:

        output_folder = (
            os.path.dirname(filepath)
        )

    os.makedirs(
        output_folder,
        exist_ok=True,
    )

    print(
        f"\n[PROCESS] {filename}"
    )

    # --------------------------------------------------------------------------
    # Read Input Data
    # --------------------------------------------------------------------------
    try:

        df = pd.read_csv(
            filepath,
            sep=None,
            engine="python",
        )

    except Exception as e:

        print(
            f"  [ERROR] Unable to read file: {e}"
        )

        return False

    # --------------------------------------------------------------------------
    # Select Numeric Columns
    # --------------------------------------------------------------------------
    df_num = df.select_dtypes(
        include=[np.number]
    )

    if df_num.empty:

        print(
            "  [SKIP] No numeric data found."
        )

        return False

    # --------------------------------------------------------------------------
    # Remove Columns That Are Clearly Not Audio Signals
    # --------------------------------------------------------------------------
    forbidden = [
        "time",
        "no",
        "nomor",
        "number",
        "index",
        "waktu",
        "label",
        "tlast",
        "tkeep",
        "tvalid",
        "tready",
    ]

    potential_cols = []

    for col in df_num.columns:

        # Exclude known metadata and protocol-control columns.
        if any(
            keyword in str(col).lower()
            for keyword in forbidden
        ):
            continue

        # Exclude monotonically increasing columns that likely represent
        # time or sample indices.
        if (
            df_num[col].is_monotonic_increasing
            and df_num[col].diff().std() < 1e-5
        ):
            continue

        potential_cols.append(col)

    if not potential_cols:

        print(
            "  [SKIP] No potential audio columns remain "
            "after metadata filtering."
        )

        return False

    # --------------------------------------------------------------------------
    # Identify Audio Signal Columns
    # --------------------------------------------------------------------------
    audio_cols = []

    for col in potential_cols:

        series = df_num[col]

        if is_audio_column(series):

            audio_cols.append(col)

        else:

            print(
                f"  [INFO] Column '{col}' was ignored "
                "because it does not appear to be an audio signal."
            )

    if not audio_cols:

        print(
            "  [SKIP] No valid audio signal columns were detected."
        )

        return False

    print(
        f"  [INFO] Detected audio columns: {audio_cols}"
    )

    # --------------------------------------------------------------------------
    # Apply Optional Sample Range
    # --------------------------------------------------------------------------
    n_total = len(df_num)

    if (
        start_sample is not None
        or end_sample is not None
    ):

        start = (
            start_sample
            if start_sample is not None
            else 0
        )

        end = (
            end_sample
            if end_sample is not None
            else n_total
        )

        start = max(
            0,
            start,
        )

        end = min(
            n_total,
            end,
        )

        if start >= end:

            print(
                f"  [ERROR] Invalid sample range: "
                f"start={start}, end={end}"
            )

            return False

        df_num = df_num.iloc[
            start:end
        ]

        print(
            f"  [INFO] Processing samples "
            f"{start} through {end - 1} "
            f"({len(df_num)} samples total)."
        )

    # --------------------------------------------------------------------------
    # Convert Each Audio Column into a Mono WAV File
    # --------------------------------------------------------------------------
    for col in audio_cols:

        audio_data = (
            df_num[col]
            .values
            .astype(np.float64)
        )

        # ----------------------------------------------------------------------
        # Optional Amplitude Normalization
        # ----------------------------------------------------------------------
        if normalize:

            max_val = np.max(
                np.abs(audio_data)
            )

            if max_val > 0:

                audio_data = (
                    audio_data / max_val
                )

                print(
                    f"    [INFO] Column '{col}' normalized "
                    f"(scale factor: 1/{max_val:.6f})"
                )

            else:

                print(
                    f"    [WARNING] Column '{col}' contains only zeros. "
                    "Normalization was skipped."
                )

        # ----------------------------------------------------------------------
        # Convert Floating-Point Samples to the Selected Integer Format
        # ----------------------------------------------------------------------
        if bit_depth == np.int16:

            audio_int = np.int16(
                audio_data * 32767
            )

        elif bit_depth == np.int32:

            audio_int = np.int32(
                audio_data * 2147483647
            )

        else:

            # Preserve the original fallback behavior.
            audio_int = np.int16(
                audio_data * 32767
            )

        # ----------------------------------------------------------------------
        # Generate Output Filename
        # ----------------------------------------------------------------------
        out_wav = os.path.join(
            output_folder,
            f"{name}_{col}.wav",
        )

        try:

            wavfile.write(
                out_wav,
                int(fs),
                audio_int,
            )

            print(
                f"    [OK] WAV file generated: "
                f"{os.path.basename(out_wav)}"
            )

        except Exception as e:

            print(
                f"    [ERROR] Failed to write WAV file "
                f"for column '{col}': {e}"
            )

    # --------------------------------------------------------------------------
    # Optional Plot Generation
    # --------------------------------------------------------------------------
    if (
        generate_plot
        and audio_cols
    ):

        try:

            generate_plots(
                df_num[audio_cols],
                fs,
                output_folder,
                name,
                start_sample,
                end_sample,
                use_log_freq,
            )

        except Exception as e:

            print(
                f"  [ERROR] Failed to generate plots: {e}"
            )

    return True


# ==============================================================================
# Time-Domain and Frequency-Domain Plot Generation
# ==============================================================================
def generate_plots(
    df_audio,
    fs,
    output_folder,
    name,
    start_sample,
    end_sample,
    use_log_freq=True,
):
    """
    Generate combined time-domain and frequency-domain plots for the
    detected audio columns.
    """

    n = len(df_audio)

    if n == 0:

        raise ValueError(
            "The audio data contains no samples."
        )

    dt = 1.0 / fs

    duration = n / fs

    x_td = (
        np.arange(n)
        * dt
    )

    # ==========================================================================
    # TIME-DOMAIN PLOT
    # ==========================================================================
    fig_td, ax_td = plt.subplots(
        figsize=(10, 4)
    )

    for col in df_audio.columns:

        ax_td.plot(
            x_td,
            df_audio[col].values,
            label=col,
            alpha=0.7,
            linewidth=0.8,
        )

    ax_td.set_xlabel(
        "Time (Seconds)"
    )

    ax_td.set_ylabel(
        "Amplitude"
    )

    ax_td.grid(
        True,
        linestyle=":",
        alpha=0.5,
    )

    ax_td.legend()

    ax_td.set_title(
        f"Time Domain: {name}"
    )

    out_td = os.path.join(
        output_folder,
        f"{name}_TD.png",
    )

    plt.tight_layout()

    plt.savefig(
        out_td,
        dpi=200,
    )

    plt.close(fig_td)

    print(
        f"  [OK] Time-domain plot generated: "
        f"{os.path.basename(out_td)}"
    )

    # ==========================================================================
    # FREQUENCY-DOMAIN PLOT
    # ==========================================================================
    freqs = np.fft.rfftfreq(
        n,
        d=dt,
    )

    fig_fd, ax_fd = plt.subplots(
        figsize=(10, 4)
    )

    for col in df_audio.columns:

        y = (
            df_audio[col]
            .values
        )

        # Compute the one-sided FFT.
        fft_vals = np.fft.rfft(y)

        fft_mag = (
            np.abs(fft_vals)
            / n
        )

        if len(fft_mag) > 1:

            fft_mag[1:] = (
                2.0
                * fft_mag[1:]
            )

        # Convert the magnitude spectrum to decibels.
        fft_db = (
            20
            * np.log10(
                fft_mag + 1e-12
            )
        )

        ax_fd.plot(
            freqs,
            fft_db,
            label=col,
            alpha=0.7,
            linewidth=0.8,
        )

    if use_log_freq:

        ax_fd.set_xscale(
            "log"
        )

        ax_fd.set_xlim(
            20,
            fs / 2,
        )

        ticks = [
            20,
            50,
            100,
            200,
            500,
            1000,
            2000,
            5000,
            10000,
            20000,
        ]

        tick_labels = [
            "20",
            "50",
            "100",
            "200",
            "500",
            "1k",
            "2k",
            "5k",
            "10k",
            "20k",
        ]

        ax_fd.set_xticks(ticks)

        ax_fd.set_xticklabels(
            tick_labels
        )

        ax_fd.set_xlabel(
            "Frequency (Hz) - Logarithmic Scale"
        )

    else:

        ax_fd.set_xlabel(
            "Frequency (Hz)"
        )

        ax_fd.set_xlim(
            0,
            fs / 2,
        )

    ax_fd.set_ylabel(
        "Magnitude (dB)"
    )

    ax_fd.grid(
        True,
        linestyle=":",
        alpha=0.5,
    )

    ax_fd.legend()

    ax_fd.set_title(
        f"Frequency Domain: {name}"
    )

    out_fd = os.path.join(
        output_folder,
        f"{name}_FD.png",
    )

    plt.tight_layout()

    plt.savefig(
        out_fd,
        dpi=200,
    )

    plt.close(fig_fd)

    print(
        f"  [OK] Frequency-domain plot generated: "
        f"{os.path.basename(out_fd)}"
    )


# ==============================================================================
# Batch Processing Entry Point
# ==============================================================================
def main():

    print(
        "=" * 70
    )

    print(
        "ADVANCED CSV/TXT TO WAV CONVERTER"
    )

    print(
        "Each detected audio column is exported as an individual mono WAV file."
    )

    print(
        "=" * 70
    )

    # --------------------------------------------------------------------------
    # Input Directory
    # --------------------------------------------------------------------------
    folder = input(
        "Enter the directory containing CSV/TXT files: "
    ).strip().replace(
        '"',
        "",
    )

    if not os.path.isdir(folder):

        print(
            "[ERROR] The specified directory is invalid."
        )

        return

    files = [
        filename
        for filename in os.listdir(folder)
        if filename.lower().endswith(
            (
                ".csv",
                ".txt",
            )
        )
    ]

    if not files:

        print(
            "[ERROR] No CSV or TXT files were found "
            "in the specified directory."
        )

        return

    # --------------------------------------------------------------------------
    # Sampling Frequency
    # --------------------------------------------------------------------------
    fs_input = input(
        "Enter the sampling frequency in Hz "
        "(default: 48000): "
    ).strip()

    try:

        fs = (
            float(fs_input)
            if fs_input
            else 48000.0
        )

    except ValueError:

        fs = 48000.0

        print(
            "[WARNING] Invalid sampling frequency. "
            "Using the default value of 48000 Hz."
        )

    # --------------------------------------------------------------------------
    # Normalization
    # --------------------------------------------------------------------------
    norm_input = input(
        "Normalize each signal to approximately [-1, 1]? "
        "[y/n, default: y]: "
    ).strip().lower()

    normalize = (
        norm_input != "n"
    )

    # --------------------------------------------------------------------------
    # Output Bit Depth
    # --------------------------------------------------------------------------
    bit_input = input(
        "Select output bit depth [16/32, default: 16]: "
    ).strip()

    if bit_input == "32":

        bit_depth = np.int32

    else:

        bit_depth = np.int16

    # --------------------------------------------------------------------------
    # Optional Plot Generation
    # --------------------------------------------------------------------------
    plot_input = input(
        "Generate time-domain and frequency-domain plots? "
        "[y/n, default: n]: "
    ).strip().lower()

    generate_plot = (
        plot_input == "y"
    )

    # --------------------------------------------------------------------------
    # Optional Sample Range
    # --------------------------------------------------------------------------
    range_input = input(
        "Limit the processed sample range? "
        "[y/n, default: n]: "
    ).strip().lower()

    start_sample = None
    end_sample = None

    if range_input == "y":

        range_str = input(
            "Enter start,end using 1-based indexing: "
        ).strip()

        if range_str:

            parts = (
                range_str.split(",")
            )

            if len(parts) == 2:

                try:

                    start_1based = int(
                        parts[0].strip()
                    )

                    end_1based = int(
                        parts[1].strip()
                    )

                    if (
                        start_1based >= 1
                        and end_1based > start_1based
                    ):

                        start_sample = (
                            start_1based - 1
                        )

                        end_sample = (
                            end_1based
                        )

                    else:

                        print(
                            "[WARNING] Invalid sample range. "
                            "All samples will be processed."
                        )

                except ValueError:

                    print(
                        "[WARNING] Invalid numeric input. "
                        "All samples will be processed."
                    )

    # --------------------------------------------------------------------------
    # Output Directory
    # --------------------------------------------------------------------------
    output_folder = input(
        "Enter the output directory "
        "(leave blank to use the source directory): "
    ).strip().replace(
        '"',
        "",
    )

    if not output_folder:
        output_folder = None

    # --------------------------------------------------------------------------
    # Processing Summary
    # --------------------------------------------------------------------------
    print(
        "\n"
        + "=" * 70
    )

    print(
        f"Processing {len(files)} file(s) with the following configuration:"
    )

    print(
        f"  Sampling frequency : {fs} Hz"
    )

    print(
        f"  Normalization      : {normalize}"
    )

    print(
        f"  Output bit depth   : {bit_depth}"
    )

    print(
        f"  Generate plots     : {generate_plot}"
    )

    print(
        f"  Sample range       : "
        f"start={start_sample}, end={end_sample}"
    )

    print(
        "=" * 70
    )

    # --------------------------------------------------------------------------
    # Process All Supported Files
    # --------------------------------------------------------------------------
    for filename in sorted(files):

        filepath = os.path.join(
            folder,
            filename,
        )

        csv_to_wav_per_column(
            filepath,
            fs=fs,
            normalize=normalize,
            bit_depth=bit_depth,
            start_sample=start_sample,
            end_sample=end_sample,
            output_folder=output_folder,
            generate_plot=generate_plot,
        )

    print(
        "\n[COMPLETE] All files have been processed."
    )


if __name__ == "__main__":
    main()
