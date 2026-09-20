#!/usr/bin/env python3
"""
Listens on the belt's UDP port and prints each packet's decoded fields.

Lets you verify the phone is sending correctly-framed belt commands before any ESP32
firmware exists or is flashed — just run this on a machine on the same WiFi as the phone
and point AppConfig.esp32Host at that machine's IP for testing.

Matches the wire format in Core/BeltProtocol.swift:
    [magic 0xB7][seq u8][z0][z1][z2][z3]   (6 bytes, leftHip -> leftPocket -> rightPocket -> rightHip)

Usage: python3 tools/belt_packet_listener.py [port]
"""
import socket
import sys
import time

MAGIC = 0xB7
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4210
ZONE_NAMES = ["leftHip", "leftPocket", "rightPocket", "rightHip"]


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", PORT))
    print(f"Listening for belt packets on UDP :{PORT} ... (Ctrl-C to stop)")

    last_seq = None
    while True:
        data, addr = sock.recvfrom(1024)
        ts = time.strftime("%H:%M:%S")

        if len(data) != 6:
            print(f"[{ts}] {addr[0]}: unexpected length {len(data)} bytes -> {data.hex()}")
            continue

        magic, seq, *zones = data
        if magic != MAGIC:
            print(f"[{ts}] {addr[0]}: bad magic 0x{magic:02x} (expected 0x{MAGIC:02x})")
            continue

        note = ""
        if last_seq is not None:
            delta = (seq - last_seq) & 0xFF
            if delta == 0 or delta > 127:
                note = "  (out of order / duplicate — would be dropped on the ESP32)"
        last_seq = seq

        zone_str = ", ".join(f"{name}={value}" for name, value in zip(ZONE_NAMES, zones))
        print(f"[{ts}] {addr[0]} seq={seq:3d}  {zone_str}{note}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
