import os
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import math
from matplotlib.ticker import FuncFormatter


plt.rcParams["agg.path.chunksize"] = 10000


# ==============================================================================
# Column Classification Helper
# ==============================================================================
def classify_column(col_name):
    """
    Classify a column according to signal direction and channel side.

    Returns
    -------
    tuple
        (signal_type, channel_side)

        signal_type:
            'input', 'output', or 'unknown'

        channel_side:
            'L', 'R', or 'unknown'
    """

    low = str(col_name).lower()

    # Determine signal direction.
    if any(keyword in low for keyword in ["input", "in", "masukan"]):
        col_type = "input"
    elif any(keyword in low for keyword in ["output", "out", "keluaran"]):
        col_type = "output"
    else:
        col_type = "unknown"

    # Determine channel side.
    if (
        any(keyword in low for keyword in ["left", "l", "kiri"])
        or "_l" in low
        or low.endswith("l")
    ):
        side = "L"

    elif (
        any(keyword in low for keyword in ["right", "r", "kanan"])
        or "_r" in low
        or low.endswith("r")
    ):
        side = "R"

    else:
        side = "unknown"

    return col_type, side


# ==============================================================================
# Plot Group Construction Helper
# ==============================================================================
def build_plot_groups(df_num, merge_lr, merge_inout):
    """
    Generate plotting groups according to the selected channel merge options.

    Parameters
    ----------
    df_num : pandas.DataFrame
        Numeric data to be grouped.

    merge_lr : bool
        Merge left and right channels.

    merge_inout : bool
        Merge input and output signals.

    Returns
    -------
    list of dict
        Each dictionary contains:

        {
            "label": str,
            "columns": [column_name_1, column_name_2, ...]
        }
    """

    cols = list(df_num.columns)
    groups = []
    used = set()

    for col in cols:
        if col in used:
            continue

        col_type, side = classify_column(col)

        # Determine the grouping key.
        if merge_lr and merge_inout:
            group_key = col_type

        elif merge_lr and not merge_inout:
            group_key = col_type

        elif not merge_lr and merge_inout:
            group_key = side

        else:
            group_key = col

        members = []

        for candidate in cols:
            if candidate in used:
                continue

            candidate_type, candidate_side = classify_column(candidate)

            if merge_lr and merge_inout:
                key = candidate_type

            elif merge_lr and not merge_inout:
                key = candidate_type

            elif not merge_lr and merge_inout:
                key = candidate_side

            else:
                key = candidate

            if key == group_key:
                members.append(candidate)
                used.add(candidate)

        if members:

            if merge_lr and merge_inout:
                label = (
                    group_key.capitalize()
                    if group_key != "unknown"
                    else "Other"
                )

            elif merge_lr and not merge_inout:
                label = (
                    group_key.capitalize()
                    if group_key != "unknown"
                    else "Other"
                )

            elif not merge_lr and merge_inout:

                if group_key == "L":
                    label = "Left Channel (L)"

                elif group_key == "R":
                    label = "Right Channel (R)"

                else:
                    label = "Other"

            else:
                label = group_key

            groups.append(
                {
                    "label": label,
                    "columns": members,
                }
            )

    return groups


# ==============================================================================
# Plot Layout Helper
# ==============================================================================
def center_last_row(axes, n_rows, n_cols, num_plots):
    """
    Center plots in the final row when the grid is only partially populated.
    """

    remainder = num_plots % n_cols

    if remainder != 0 and n_cols > 1 and n_rows > 1:

        pos0 = axes[0, 0].get_position()
        pos1 = axes[0, 1].get_position()

        dx = pos1.x0 - pos0.x0
        shift = (n_cols - remainder) * dx / 2.0

        for j in range(remainder):

            ax = axes[n_rows - 1, j]
            pos = ax.get_position()

            pos.x0 += shift
            pos.x1 += shift

            ax.set_position(pos)


# ==============================================================================
# Logarithmic Frequency Axis Formatter
# ==============================================================================
def log_format(x, pos):
    """
    Format frequency-axis labels for logarithmic plots.
    """

    if x <= 0:
        return ""

    if x >= 1000:
        return f"{int(x / 1000)}k"

    return f"{int(x)}"


# ==============================================================================
# Main File Processing Function
# ==============================================================================
def process_file(
    filepath,
    fs=48000.0,
    use_log_freq=True,
    merge_lr=False,
    merge_inout=False,
    skip_existing=True,
    td_ylim=None,
    fd_ylim=None,
    start_sample=None,
    end_sample=None,
):
    """
    Process a single CSV or text file and generate time-domain and
    frequency-domain plots.

    Parameters
    ----------
    filepath : str
        Path to the input file.

    fs : float
        Sampling frequency in Hz.

    use_log_freq : bool
        Use a logarithmic frequency axis.

    merge_lr : bool
        Merge left and right channels.

    merge_inout : bool
        Merge input and output signals.

    skip_existing : bool
        Skip processing when both output images already exist.

    td_ylim : tuple or None
        Optional (ymin, ymax) limits for time-domain plots.

    fd_ylim : tuple or None
        Optional (ymin, ymax) limits for frequency-domain plots.

    start_sample : int or None
        Starting sample index.

    end_sample : int or None
        Ending sample index (exclusive).
    """

    filename = os.path.basename(filepath)
    name, _ = os.path.splitext(filename)

    out_td_png = os.path.join(
        os.path.dirname(filepath),
        name + "_TD.png",
    )

    out_fd_png = os.path.join(
        os.path.dirname(filepath),
        name + "_FD.png",
    )

    # Skip files that have already been processed.
    if (
        skip_existing
        and os.path.exists(out_td_png)
        and os.path.exists(out_fd_png)
    ):
        print(
            f"[SKIP] {filename} -> "
            "already processed (both TD and FD images exist)"
        )
        return

    # Load the input data.
    try:
        df = pd.read_csv(
            filepath,
            sep=None,
            engine="python",
        )

    except Exception as e:
        print(
            f"[SKIP] {filename} -> "
            f"unable to read file ({e})"
        )
        return

    # Select numeric columns only.
    df_num = df.select_dtypes(include=[np.number])

    if df_num.empty:
        print(
            f"[SKIP] {filename} -> "
            "no numeric data found"
        )
        return

    # --------------------------------------------------------------------------
    # Remove columns that are likely to represent time, indices, or labels.
    # --------------------------------------------------------------------------
    forbidden = [
        "time",
        "no",
        "nomor",
        "number",
        "index",
        "waktu",
        "label",
    ]

    cols_to_keep = []

    for col in df_num.columns:

        # Remove explicitly identified metadata columns.
        if any(
            keyword in str(col).lower()
            for keyword in forbidden
        ):
            continue

        # Remove monotonically increasing columns that likely represent
        # time or sample indices.
        if (
            df_num[col].is_monotonic_increasing
            and df_num[col].diff().std() < 1e-5
        ):
            continue

        cols_to_keep.append(col)

    if not cols_to_keep:
        print(
            f"[SKIP] {filename} -> "
            "no valid signal columns found"
        )
        return

    df_clean = df_num[cols_to_keep]
    n_total = len(df_clean)

    # --------------------------------------------------------------------------
    # Apply optional sample-range selection.
    # --------------------------------------------------------------------------
    if start_sample is not None or end_sample is not None:

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

        if start < 0:

            start = 0

            print(
                f"[WARNING] {filename}: "
                "start_sample was below zero and has been set to 0"
            )

        if end > n_total:

            end = n_total

            print(
                f"[WARNING] {filename}: "
                f"end_sample exceeded the total sample count "
                f"and has been set to {n_total}"
            )

        if start >= end:

            print(
                f"[SKIP] {filename}: "
                f"invalid sample range "
                f"(start_sample={start}, end_sample={end})"
            )

            return

        df_clean = df_clean.iloc[start:end]

        print(
            f"[INFO] {filename}: "
            f"processing samples {start} through {end - 1} "
            f"({len(df_clean)} samples total)"
        )

    # --------------------------------------------------------------------------
    # Build plotting groups.
    # --------------------------------------------------------------------------
    groups = build_plot_groups(
        df_clean,
        merge_lr,
        merge_inout,
    )

    num_plots = len(groups)

    if num_plots == 0:
        return

    # --------------------------------------------------------------------------
    # Determine plot grid dimensions.
    # --------------------------------------------------------------------------
    if num_plots == 1:

        n_cols = 1
        n_rows = 1

    else:

        n_cols = math.ceil(
            math.sqrt(num_plots)
        )

        n_rows = math.ceil(
            num_plots / n_cols
        )

    fig_w = 8 * n_cols
    fig_h = 5 * n_rows

    n = len(df_clean)

    if n == 0:

        print(
            f"[SKIP] {filename} -> "
            "no samples remain after range selection"
        )

        return

    dt = 1.0 / fs
    duration = n / fs

    x_vals_td = np.arange(n) * dt

    # ==========================================================================
    # TIME-DOMAIN ANALYSIS
    # ==========================================================================
    fig_td, axes_td = plt.subplots(
        n_rows,
        n_cols,
        figsize=(fig_w, fig_h),
        squeeze=False,
    )

    fig_td.patch.set_facecolor("white")

    ax_td_flat = axes_td.flatten()

    for i, group in enumerate(groups):

        ax = ax_td_flat[i]

        label = group["label"]
        columns = group["columns"]

        for j, col in enumerate(columns):

            y = df_clean[col].values

            ax.plot(
                x_vals_td,
                y,
                label=col,
                color=f"C{j}",
                alpha=0.8,
                linewidth=0.8,
            )

        ax.set_ylabel(
            "Amplitude",
            fontsize=12,
        )

        ax.set_title(
            label,
            fontsize=14,
            fontweight="bold",
        )

        ax.tick_params(
            axis="both",
            which="major",
            labelsize=10,
        )

        ax.grid(
            True,
            linestyle=":",
            alpha=0.6,
            linewidth=0.5,
            color="gray",
        )

        ax.set_xlim(
            0,
            duration,
        )

        if td_ylim is not None:
            ax.set_ylim(td_ylim)

        ax.legend(
            loc="upper right",
            fontsize=8,
        )

        # Add the X-axis label only to plots on the final row.
        if i + n_cols >= num_plots:

            ax.set_xlabel(
                "Time (Seconds)",
                fontsize=12,
            )

    # Disable unused plot axes.
    for j in range(
        i + 1,
        len(ax_td_flat),
    ):
        ax_td_flat[j].axis("off")

    # --------------------------------------------------------------------------
    # Construct plot metadata.
    # --------------------------------------------------------------------------
    merge_info = ""

    if merge_lr:
        merge_info += " Merged L/R"

    if merge_inout:
        merge_info += " Merged Input/Output"

    sample_info = ""

    if (
        start_sample is not None
        or end_sample is not None
    ):

        start_display = (
            start_sample
            if start_sample is not None
            else 0
        )

        end_display = (
            end_sample
            if end_sample is not None
            else n_total
        )

        sample_info = (
            f" (Samples {start_display} "
            f"to {end_display - 1})"
        )

    fig_td.suptitle(
        f"Time Domain: {filename}"
        f"{merge_info}"
        f"{sample_info}\n"
        f"Duration: {duration:.4f} s, "
        f"Fs: {fs} Hz",
        fontsize=16,
        fontweight="bold",
        y=0.98,
    )

    plt.tight_layout(
        rect=[0, 0.03, 1, 0.96]
    )

    center_last_row(
        axes_td,
        n_rows,
        n_cols,
        num_plots,
    )

    plt.savefig(
        out_td_png,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close(fig_td)

    # ==========================================================================
    # FREQUENCY-DOMAIN ANALYSIS
    # ==========================================================================
    freqs = np.fft.rfftfreq(
        n,
        d=dt,
    )

    nyquist_limit = fs / 2.0

    min_freq_log = 20.0

    max_freq_log = min(
        20000.0,
        nyquist_limit,
    )

    fig_fd, axes_fd = plt.subplots(
        n_rows,
        n_cols,
        figsize=(fig_w, fig_h),
        squeeze=False,
    )

    fig_fd.patch.set_facecolor("white")

    ax_fd_flat = axes_fd.flatten()

    for i, group in enumerate(groups):

        ax = ax_fd_flat[i]

        label = group["label"]
        columns = group["columns"]

        for j, col in enumerate(columns):

            y = df_clean[col].values

            # ------------------------------------------------------------------
            # Compute the one-sided FFT spectrum.
            # ------------------------------------------------------------------
            fft_vals = np.fft.rfft(y)

            fft_mag = (
                np.abs(fft_vals) / n
            )

            if len(fft_mag) > 1:
                fft_mag[1:] = (
                    2.0 * fft_mag[1:]
                )

            # Convert magnitude to decibels.
            fft_mag_db = (
                20
                * np.log10(
                    fft_mag + 1e-12
                )
            )

            if use_log_freq:

                # Limit the displayed frequency range.
                mask = (
                    freqs >= min_freq_log
                )

                ax.plot(
                    freqs[mask],
                    fft_mag_db[mask],
                    label=col,
                    color=f"C{j}",
                    alpha=0.8,
                    linewidth=0.8,
                )

                # Use logarithmic frequency scaling.
                ax.set_xscale("log")

                ax.set_xlim(
                    min_freq_log,
                    max_freq_log,
                )

                # Define conventional audio-frequency tick positions.
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

                ax.set_xticks(ticks)
                ax.set_xticklabels(tick_labels)

                ax.set_xlabel(
                    "Frequency (Hz)",
                    fontsize=12,
                )

            else:

                ax.plot(
                    freqs,
                    fft_mag_db,
                    label=col,
                    color=f"C{j}",
                    alpha=0.8,
                    linewidth=0.8,
                )

                ax.set_xlim(
                    0,
                    max_freq_log,
                )

                ax.set_xlabel(
                    "Frequency (Hz) - Linear Scale",
                    fontsize=12,
                )

        ax.set_ylabel(
            "Magnitude (dB)",
            fontsize=12,
        )

        ax.set_title(
            f"Audio Spectrum: {label}",
            fontsize=14,
            fontweight="bold",
        )

        ax.tick_params(
            axis="both",
            which="major",
            labelsize=10,
        )

        # Configure major and minor grid lines.
        ax.grid(
            True,
            which="major",
            linestyle="-",
            alpha=0.5,
            linewidth=0.5,
            color="gray",
        )

        ax.grid(
            True,
            which="minor",
            linestyle=":",
            alpha=0.3,
            linewidth=0.3,
            color="gray",
        )

        if fd_ylim is not None:
            ax.set_ylim(fd_ylim)

        ax.legend(
            loc="upper right",
            fontsize=8,
        )

        # ----------------------------------------------------------------------
        # Annotate the dominant spectral peak using the first signal in the
        # current plot group.
        # ----------------------------------------------------------------------
        if columns:

            y_all = (
                df_clean[
                    columns[0]
                ].values
            )

            fft_all = (
                np.abs(
                    np.fft.rfft(y_all)
                )
                / n
            )

            if len(fft_all) > 1:
                fft_all[1:] = (
                    2.0 * fft_all[1:]
                )

            fft_all_db = (
                20
                * np.log10(
                    fft_all + 1e-12
                )
            )

            # Ignore the DC component when searching for the peak.
            max_idx = (
                np.argmax(
                    fft_all_db[1:]
                )
                + 1
            )

            if max_idx < len(freqs):

                peak_freq = (
                    freqs[max_idx]
                )

                peak_mag_db = (
                    fft_all_db[max_idx]
                )

                ax.annotate(
                    f"Peak: "
                    f"{peak_freq:.1f} Hz "
                    f"({peak_mag_db:.1f} dB)",
                    xy=(
                        peak_freq,
                        peak_mag_db,
                    ),
                    xytext=(5, 5),
                    textcoords="offset points",
                    fontsize=9,
                    bbox=dict(
                        boxstyle="round,pad=0.3",
                        facecolor="yellow",
                        alpha=0.8,
                    ),
                )

    # Disable unused plot axes.
    for j in range(
        i + 1,
        len(ax_fd_flat),
    ):
        ax_fd_flat[j].axis("off")

    scale_type = (
        "Logarithmic Scale"
        if use_log_freq
        else "Linear Scale"
    )

    fig_fd.suptitle(
        f"Frequency Domain ({scale_type}): "
        f"{filename}"
        f"{merge_info}"
        f"{sample_info}\n"
        f"Fs: {fs} Hz",
        fontsize=16,
        fontweight="bold",
        y=0.98,
    )

    plt.tight_layout(
        rect=[0, 0.03, 1, 0.96]
    )

    center_last_row(
        axes_fd,
        n_rows,
        n_cols,
        num_plots,
    )

    plt.savefig(
        out_fd_png,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close(fig_fd)

    print(
        f"[OK] {filename} -> "
        f"time-domain and frequency-domain plots generated "
        f"[{num_plots} plot group(s)]"
    )


# ==============================================================================
# Manual Y-Axis Limit Input Helper
# ==============================================================================
def get_ylim_input(domain_name):
    """
    Request optional manual Y-axis limits from the user.
    """

    print(
        f"\n--- Configure Y-Axis Limits: "
        f"{domain_name} ---"
    )

    user_input = input(
        "Enter ymin,ymax separated by a comma, "
        "or leave blank for automatic scaling: "
    ).strip()

    if user_input == "":
        return None

    parts = user_input.split(",")

    if len(parts) != 2:

        print(
            "Invalid format. Use: ymin,ymax "
            "(for example: -1.5,1.5). "
            "Automatic scaling will be used."
        )

        return None

    try:

        ymin = float(
            parts[0].strip()
        )

        ymax = float(
            parts[1].strip()
        )

        if ymin >= ymax:

            print(
                "Invalid range: ymin must be smaller than ymax. "
                "Automatic scaling will be used."
            )

            return None

        return (
            ymin,
            ymax,
        )

    except ValueError:

        print(
            "Invalid numeric input. "
            "Automatic scaling will be used."
        )

        return None


# ==============================================================================
# Sample Range Input Helper
# ==============================================================================
def get_sample_range_input(total_samples=None):
    """
    Request an optional sample range from the user.

    Input values are specified using 1-based indexing.
    """

    print(
        "\n--- Configure Sample Range ---"
    )

    print(
        "Leave the field blank to process all samples."
    )

    user_input = input(
        "Enter start,end using 1-based indexing "
        "(for example: 1000,5000): "
    ).strip()

    if user_input == "":
        return None, None

    parts = user_input.split(",")

    if len(parts) != 2:

        print(
            "Invalid format. Use: start,end "
            "(for example: 1000,5000). "
            "All samples will be processed."
        )

        return None, None

    try:

        start_1based = int(
            parts[0].strip()
        )

        end_1based = int(
            parts[1].strip()
        )

        if start_1based < 1:

            print(
                "The starting sample must be greater than or equal to 1. "
                "All samples will be processed."
            )

            return None, None

        if end_1based < start_1based:

            print(
                "The ending sample must not be smaller than the "
                "starting sample. All samples will be processed."
            )

            return None, None

        return (
            start_1based - 1,
            end_1based,
        )

    except ValueError:

        print(
            "Invalid numeric input. "
            "All samples will be processed."
        )

        return None, None


# ==============================================================================
# Batch Processing Entry Point
# ==============================================================================
def main():

    folder = input(
        "Enter the input data directory path: "
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
    # Sampling Frequency Configuration
    # --------------------------------------------------------------------------
    fs_input = input(
        "Enter the sampling frequency in Hz "
        "(default: 48000): "
    ).strip()

    try:

        user_fs = (
            float(fs_input)
            if fs_input
            else 48000.0
        )

    except ValueError:

        user_fs = 48000.0

        print(
            "[WARNING] Invalid sampling frequency. "
            "Using the default value of 48000 Hz."
        )

    # --------------------------------------------------------------------------
    # Frequency-Axis Configuration
    # --------------------------------------------------------------------------
    log_input = input(
        "Use a logarithmic frequency scale? "
        "(recommended for audio) "
        "[y/n, default: y]: "
    ).strip().lower()

    use_log = (
        log_input != "n"
    )

    # --------------------------------------------------------------------------
    # Channel Merge Configuration
    # --------------------------------------------------------------------------
    merge_lr_input = input(
        "Merge left and right channels into the same plot? "
        "[y/n, default: n]: "
    ).strip().lower()

    merge_lr = (
        merge_lr_input == "y"
    )

    merge_inout_input = input(
        "Merge input and output signals into the same plot? "
        "[y/n, default: n]: "
    ).strip().lower()

    merge_inout = (
        merge_inout_input == "y"
    )

    # --------------------------------------------------------------------------
    # Existing Output Configuration
    # --------------------------------------------------------------------------
    skip_input = input(
        "Skip files that already have both TD and FD output images? "
        "[y/n, default: y]: "
    ).strip().lower()

    skip_existing = (
        skip_input != "n"
    )

    # --------------------------------------------------------------------------
    # Manual Amplitude Limits
    # --------------------------------------------------------------------------
    manual_amp_input = input(
        "Configure amplitude limits manually? "
        "[y/n, default: n]: "
    ).strip().lower()

    td_ylim = None
    fd_ylim = None

    if manual_amp_input == "y":

        td_ylim = get_ylim_input(
            "TIME DOMAIN (Amplitude)"
        )

        fd_ylim = get_ylim_input(
            "FREQUENCY DOMAIN "
            "(Magnitude in dB, for example: -100,0)"
        )

    # --------------------------------------------------------------------------
    # Sample Range Configuration
    # --------------------------------------------------------------------------
    range_input = input(
        "Limit the processed sample range? "
        "[y/n, default: n]: "
    ).strip().lower()

    start_sample = None
    end_sample = None

    if range_input == "y":

        (
            start_sample,
            end_sample,
        ) = get_sample_range_input()

    # --------------------------------------------------------------------------
    # Processing Summary
    # --------------------------------------------------------------------------
    print(
        "\n============================================================"
    )

    print(
        "Processing Configuration"
    )

    print(
        "============================================================"
    )

    print(
        f"Input files           : {len(files)}"
    )

    print(
        f"Sampling frequency    : {user_fs} Hz"
    )

    print(
        f"Log frequency scale   : {use_log}"
    )

    print(
        f"Merge left/right      : {merge_lr}"
    )

    print(
        f"Merge input/output    : {merge_inout}"
    )

    print(
        f"Skip existing outputs : {skip_existing}"
    )

    print(
        f"Time-domain Y limits  : {td_ylim}"
    )

    print(
        f"Frequency Y limits    : {fd_ylim}"
    )

    print(
        f"Sample range          : "
        f"start={start_sample}, "
        f"end={end_sample} "
        f"(0-based, end exclusive)"
    )

    print(
        "============================================================\n"
    )

    # --------------------------------------------------------------------------
    # Process All Supported Files
    # --------------------------------------------------------------------------
    for filename in sorted(files):

        process_file(
            os.path.join(
                folder,
                filename,
            ),
            fs=user_fs,
            use_log_freq=use_log,
            merge_lr=merge_lr,
            merge_inout=merge_inout,
            skip_existing=skip_existing,
            td_ylim=td_ylim,
            fd_ylim=fd_ylim,
            start_sample=start_sample,
            end_sample=end_sample,
        )

    print(
        "\n[COMPLETE] Processing finished."
    )

    print(
        "Output files: *_TD.png and *_FD.png"
    )


if __name__ == "__main__":
    main()
