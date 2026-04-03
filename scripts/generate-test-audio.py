#!/usr/bin/env python3
"""Generate a 60-second test track that exercises all frequency bands for Sanctum testing.

Pattern: 128 BPM electronic with:
- Sub-bass sine sweeps (20-80Hz)
- Kick drum hits on beats (80-250Hz)
- Synth pad mid content (250-4000Hz)
- Hi-hat on off-beats (4000-20000Hz)
- Energy builds over 60 seconds to test corruption arc
"""

import wave
import struct
import math
import random

SAMPLE_RATE = 48000
DURATION = 60  # seconds
BPM = 128
BEAT_INTERVAL = 60.0 / BPM  # ~0.469s
NUM_SAMPLES = SAMPLE_RATE * DURATION

def generate():
    samples = []

    for i in range(NUM_SAMPLES):
        t = i / SAMPLE_RATE
        beat_pos = t / BEAT_INTERVAL
        beat_frac = beat_pos % 1.0
        bar_pos = (beat_pos % 4) / 4.0

        # Energy envelope: builds over 60 seconds
        energy = min(1.0, t / 50.0)  # ramps from 0 to 1 over 50 seconds

        sample = 0.0

        # === Sub-bass (20-80Hz) — sine sweep, always present ===
        sub_freq = 30 + 20 * math.sin(t * 0.1)  # slow sweep 30-50Hz
        sub_bass = math.sin(2 * math.pi * sub_freq * t) * 0.15 * energy
        sample += sub_bass

        # === Kick drum (80-250Hz) — on each beat ===
        if beat_frac < 0.15:
            kick_env = (1.0 - beat_frac / 0.15)
            kick_freq = 150 * kick_env + 50  # pitch drops from 200 to 50Hz
            kick = math.sin(2 * math.pi * kick_freq * t) * kick_env * 0.4 * (0.5 + energy * 0.5)
            sample += kick

        # === Snare/clap on beats 2 and 4 (adds mid + high content) ===
        beat_in_bar = int(beat_pos) % 4
        if beat_in_bar in (1, 3) and beat_frac < 0.1:
            snare_env = (1.0 - beat_frac / 0.1)
            # Noise burst + tone
            noise = (random.random() * 2 - 1) * snare_env * 0.2 * energy
            tone = math.sin(2 * math.pi * 200 * t) * snare_env * 0.15 * energy
            sample += noise + tone

        # === Hi-hat on off-beats (4kHz+ content) ===
        eighth_pos = (beat_pos * 2) % 1.0
        if eighth_pos < 0.05:
            hh_env = (1.0 - eighth_pos / 0.05)
            # High frequency noise burst
            hh = (random.random() * 2 - 1) * hh_env * 0.12 * (0.3 + energy * 0.7)
            # Bandpass-ish: multiply by high freq carrier
            hh *= math.sin(2 * math.pi * 8000 * t)
            sample += hh

        # === Synth pad (250-4000Hz mid content) — swells with energy ===
        pad = 0.0
        for harmonic, amp in [(1, 0.08), (2, 0.04), (3, 0.02), (5, 0.01)]:
            pad_freq = 220 * harmonic  # A3 and harmonics
            pad += math.sin(2 * math.pi * pad_freq * t + math.sin(t * 0.3) * 2) * amp
        # Tremolo
        pad *= (0.5 + 0.5 * math.sin(2 * math.pi * 0.25 * t)) * energy * 0.8
        sample += pad

        # === Build section: add intensity in last 20 seconds ===
        if t > 40:
            build_energy = (t - 40) / 20.0
            # Rising synth
            rise_freq = 200 + 2000 * build_energy
            rise = math.sin(2 * math.pi * rise_freq * t) * 0.1 * build_energy
            sample += rise
            # Extra bass weight
            sample += math.sin(2 * math.pi * 60 * t) * 0.1 * build_energy

        # === Drop at 50 seconds: sudden energy spike ===
        if 50 < t < 50.5:
            drop_env = 1.0 - (t - 50) / 0.5
            sample += math.sin(2 * math.pi * 40 * t) * 0.5 * drop_env
            sample += (random.random() * 2 - 1) * 0.3 * drop_env

        # === Breakdown at 55 seconds: quiet moment ===
        if 54 < t < 56:
            breakdown = 1.0 - abs(t - 55) / 1.0
            sample *= (1.0 - breakdown * 0.8)

        # Soft clip
        sample = max(-0.95, min(0.95, sample))
        samples.append(sample)

    # Write WAV
    output_path = "/Users/mvacirca/dev/sanctum/Assets/test-track.wav"
    with wave.open(output_path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(SAMPLE_RATE)
        for s in samples:
            wf.writeframes(struct.pack('<h', int(s * 32767)))

    print(f"Generated {output_path}")
    print(f"  Duration: {DURATION}s at {SAMPLE_RATE}Hz")
    print(f"  BPM: {BPM}")
    print(f"  Samples: {len(samples)}")

if __name__ == "__main__":
    generate()
