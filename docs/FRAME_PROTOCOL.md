# FRAME_PROTOCOL

Simple binary frame protocol for the FPGA resynthesis engine (UART / WebSerial):

- START_FRAME: 0xF0
- COUNT: 1 byte (number of entries, 0..32)
- For each entry (sequential):
  - PHASE_INC: 4 bytes (big-endian) — 32-bit tuning word: round(freq * 2^32 / 12e6)
  - AMP: 2 bytes (big-endian) — unsigned amplitude (0..65535)
  - FLAGS: 1 byte (reserved)
- COMMIT: 0xF1 — atomically swap the inactive buffer into active and begin crossfade
- FREEZE: 0xF2 — toggle freeze (not fully implemented in v1)

Notes:
- Entries are written sequentially starting at index 0. To change ordering or update an index, write the frame with placeholders.
- After sending a COMMIT (0xF1) the receiver will respond with an ACK byte 0x01.

Example (pseudocode):
  frame = [0xF0, COUNT, ENTRY0(7b), ENTRY1(7b), ..., 0xF1]

Where ENTRY = [PHASE_INC(4), AMP(2), FLAGS(1)].
