#!/usr/bin/env python3
"""Fake iPhone: sends belt zone packets (see docs/PACKET_SPEC.md) to the ESP32.

Examples:
  ./send_fake_zones.py static --zones 0 0 255 0
  ./send_fake_zones.py sweep                      # each zone ramps 0->255->0 in turn
  ./send_fake_zones.py walk                       # obstacle on the left, getting closer
  ./send_fake_zones.py walk --loss 0.3            # same, dropping 30% of packets
  ./send_fake_zones.py garbage                    # malformed packets, motors must ignore
"""
import argparse
import random
import socket
import struct
import sys
import time

MAGIC = 0xB7
NUM_ZONES = 4


def packet(seq, zones):
    return struct.pack("BB4B", MAGIC, seq & 0xFF, *[max(0, min(255, int(z))) for z in zones])


def gen_static(args):
    while True:
        yield args.zones


def gen_sweep(args):
    # Each zone in turn ramps up and back down, others stay off.
    steps = max(2, int(args.period * args.rate))
    while True:
        for zone in range(NUM_ZONES):
            for i in range(steps):
                phase = i / (steps - 1)
                level = 255 * (1 - abs(2 * phase - 1))
                zones = [0] * NUM_ZONES
                zones[zone] = level
                yield zones


def gen_walk(args):
    # Obstacle left of centre approaches: far -> near, then resets.
    steps = max(2, int(args.period * args.rate))
    while True:
        for i in range(steps):
            near = i / (steps - 1)
            yield [255 * near, 255 * near * 0.6, 0, 0]


def gen_garbage(args):
    while True:
        kind = random.choice(["short", "long", "badmagic", "empty"])
        if kind == "short":
            yield bytes([MAGIC, 0, 255, 255])
        elif kind == "long":
            yield bytes([MAGIC, 0, 255, 255, 255, 255, 255])
        elif kind == "badmagic":
            yield bytes([0x00, 0, 255, 255, 255, 255])
        else:
            yield b""


MODES = {"static": gen_static, "sweep": gen_sweep, "walk": gen_walk, "garbage": gen_garbage}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=MODES)
    ap.add_argument("--host", default="192.168.4.1")
    ap.add_argument("--port", type=int, default=4210)
    ap.add_argument("--rate", type=float, default=5.0, help="packets per second")
    ap.add_argument("--period", type=float, default=6.0, help="seconds per sweep/walk cycle")
    ap.add_argument("--zones", type=int, nargs=NUM_ZONES, default=[0, 0, 0, 0], metavar="Z", help="static mode values")
    ap.add_argument("--loss", type=float, default=0.0, help="fraction of packets to drop, 0-1")
    ap.add_argument("--duration", type=float, default=0.0, help="stop after N seconds (0 = forever)")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dest = (args.host, args.port)
    interval = 1.0 / args.rate
    start = time.monotonic()
    seq = 0
    sent = dropped = 0

    try:
        for item in MODES[args.mode](args):
            if args.duration and time.monotonic() - start > args.duration:
                break
            data = item if isinstance(item, bytes) else packet(seq, item)
            seq += 1  # advances on drops too, so the receiver sees the gap
            if random.random() < args.loss:
                dropped += 1
            else:
                sock.sendto(data, dest)
                sent += 1
            shown = list(data[2:]) if len(data) == 6 else data.hex()
            print(f"\rseq={seq - 1:3d} {shown} sent={sent} dropped={dropped}   ", end="", flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    print()


if __name__ == "__main__":
    sys.exit(main())
