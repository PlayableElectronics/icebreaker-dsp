#!/usr/bin/env python3
"""Extract a compact modal description from an isolated PCM WAV strike."""

import argparse
import cmath
import json
import math
import struct
import wave


def fft(values):
    n = len(values)
    values = [complex(v, 0.0) for v in values]
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            values[i], values[j] = values[j], values[i]
    size = 2
    while size <= n:
        step = cmath.exp(-2j * math.pi / size)
        for start in range(0, n, size):
            factor = 1 + 0j
            half = size >> 1
            for i in range(start, start + half):
                even = values[i]
                odd = factor * values[i + half]
                values[i] = even + odd
                values[i + half] = even - odd
                factor *= step
        size <<= 1
    return values


def read_mono_wav(path):
    with wave.open(path, "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    if width != 2:
        raise ValueError("only 16-bit PCM WAV files are supported")
    raw = struct.unpack("<%dh" % (len(frames) // 2), frames)
    if channels == 1:
        return rate, [sample / 32768.0 for sample in raw]
    return rate, [sum(raw[i:i + channels]) / (32768.0 * channels)
                  for i in range(0, len(raw), channels)]


def peak_candidates(spectrum, rate, count, minimum, maximum):
    limit = len(spectrum) // 2
    bins = []
    for index in range(2, limit - 1):
        frequency = index * rate / (2 * (limit))
        if frequency < minimum or frequency > maximum:
            continue
        magnitude = abs(spectrum[index])
        if magnitude >= abs(spectrum[index - 1]) and magnitude > abs(spectrum[index + 1]):
            bins.append((magnitude, index))
    bins.sort(reverse=True)
    selected = []
    for magnitude, index in bins:
        if all(abs(index - old_index) > 3 for _, old_index in selected):
            selected.append((magnitude, index))
        if len(selected) == count:
            break
    return selected


def estimate_decay(samples, rate, frequency, window, count):
    values = []
    step = window // 2
    omega = 2 * math.pi * frequency / rate
    for start in range(0, min(len(samples) - window, step * count), step):
        real = 0.0
        imag = 0.0
        for offset, sample in enumerate(samples[start:start + window]):
            angle = omega * offset
            real += sample * math.cos(angle)
            imag -= sample * math.sin(angle)
        values.append(abs(complex(real, imag)))
    values = [(i, math.log(max(value, 1e-12)))
              for i, value in enumerate(values) if value > 1e-8]
    if len(values) < 3:
        return 1.0
    mean_x = sum(x for x, _ in values) / len(values)
    mean_y = sum(y for _, y in values) / len(values)
    denominator = sum((x - mean_x) ** 2 for x, _ in values)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in values) / max(denominator, 1e-9)
    seconds_per_step = step / rate
    if slope >= 0:
        return 30.0
    return min(30.0, max(0.05, math.log(1000.0) / (-slope / seconds_per_step)))


def estimate_amplitude_phase(samples, rate, frequency, window):
    real = 0.0
    imag = 0.0
    omega = 2 * math.pi * frequency / rate
    for offset, sample in enumerate(samples[:window]):
        angle = omega * offset
        real += sample * math.cos(angle)
        imag += sample * math.sin(angle)
    scale = 2.0 / max(window, 1)
    amplitude = scale * math.hypot(real, imag)
    phase = math.atan2(real, imag)
    return amplitude, phase


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--fundamental", type=float, required=True)
    parser.add_argument("--target-rate", type=int, default=None)
    parser.add_argument("--modes", type=int, default=16)
    parser.add_argument("--min-hz", type=float, default=40)
    parser.add_argument("--max-hz", type=float, default=4000)
    parser.add_argument("--json", default="modal.json")
    parser.add_argument("--verilog", default="modal_tables.vh")
    args = parser.parse_args()

    rate, samples = read_mono_wav(args.input)
    fft_size = 1 << (min(len(samples), 32768).bit_length() - 1)
    window = samples[:fft_size]
    window = [sample * (0.5 - 0.5 * math.cos(2 * math.pi * i / fft_size))
              for i, sample in enumerate(window)]
    spectrum = fft(window)
    candidates = peak_candidates(spectrum, rate, args.modes, args.min_hz, args.max_hz)
    modes = []
    maximum = max((magnitude for magnitude, _ in candidates), default=1.0)
    for magnitude, index in candidates:
        frequency = index * rate / fft_size
        amplitude, phase = estimate_amplitude_phase(samples, rate, frequency, min(4096, fft_size))
        modes.append({
            "frequency_hz": frequency,
            "ratio": frequency / args.fundamental,
            "amplitude": amplitude,
            "gain": magnitude / maximum,
            "phase_rad": phase,
            "t60_s": max(8.0, estimate_decay(samples, rate, frequency,
                                               min(2048, fft_size // 4), 24)),
        })

    result = {"sample_rate": rate, "fundamental_hz": args.fundamental, "modes": modes}
    with open(args.json, "w") as output:
        json.dump(result, output, indent=2)
        output.write("\n")

    with open(args.verilog, "w") as output:
        output.write("// Generated by tools/extract_modal.py\n")
        output.write("localparam integer MODAL_COUNT = %d;\n" % len(modes))
        for index, mode in enumerate(modes):
            target_rate = args.target_rate or rate
            tw = round(mode["frequency_hz"] * (2 ** 32) / target_rate)
            output.write("localparam [31:0] MODAL_TW_%d = 32'd%d; // %.3f Hz\n"
                         % (index, tw, mode["frequency_hz"]))
        for index, mode in enumerate(modes):
            output.write("localparam integer MODAL_GAIN_Q15_%d = %d;\n"
                         % (index, round(mode["gain"] * 32767)))
        for index, mode in enumerate(modes):
            phase = round((mode["phase_rad"] / (2 * math.pi)) * 65536) & 0xffff
            output.write("localparam [15:0] MODAL_PHASE_Q16_%d = 16'd%d;\n"
                         % (index, phase))
        for index, mode in enumerate(modes):
            target_rate = args.target_rate or rate
            decay = math.exp(-math.log(1000.0) / max(mode["t60_s"] * target_rate, 1.0))
            output.write("localparam [31:0] MODAL_DECAY_Q31_%d = 32'd%d;\n"
                         % (index, round(decay * (2 ** 31))))


if __name__ == "__main__":
    main()
