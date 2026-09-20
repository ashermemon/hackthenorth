# Belt firmware

The real firmware: the ESP32 hosts a WiFi network, listens for the phone's UDP packets
([docs/PACKET_SPEC.md](../../docs/PACKET_SPEC.md)), and drives the four L298N inputs with PWM.
It makes no decisions. Wiring and power are the same as the bench test:
[../bench_pwm/README.md](../bench_pwm/README.md) (GPIO 33, 25, 26, 27 → IN1–IN4).

## How it works

```
udp_rx_task --(queue, length 1)--> motor_task --> LEDC PWM --> L298N IN1..IN4
```

- **`udp_rx_task`** validates each datagram (exactly 6 bytes, magic `0xB7`), drops reordered
  packets, and overwrites the queue with the newest state.
- **`motor_task`** waits on that queue with a 500 ms timeout. A packet applies immediately. If
  none arrives in time, all motors go off. That single timeout is both "hold the last state
  briefly instead of zeroing on one missed packet" and the failsafe if the phone or the link
  dies while a motor is buzzing.
- **Onboard LED** (GPIO 2): on while packets are arriving, off when idle.
- **WiFi:** the ESP32 is an access point (`BeltNav`, password in `main/belt_config.h`) at
  `192.168.4.1`, UDP port `4210`. Power saving is off for latency.

Settings live in [main/belt_config.h](main/belt_config.h). Two are placeholders to set from the
bench-test results: `BELT_PWM_FREQ_HZ` and `BELT_MAX_DUTY`.

## Test without hardware

The packet parsing and the accept/reject rule are plain C, tested on the Mac:

```sh
firmware/belt_fw/test_host/run.sh
```

## Build and flash

```sh
. ~/esp/esp-idf/export.sh          # once per terminal
cd firmware/belt_fw
idf.py set-target esp32            # first time only
idf.py -p /dev/cu.usbserial-XXXX flash monitor
```

Exit the monitor with `Ctrl+]`. The log should show the network coming up, then "listening for
belt packets on UDP :4210".

## Test with the ESP32 (no phone app)

1. Join the **BeltNav** WiFi from the Mac. The Mac will say it has no internet; that's expected.
2. Send fake packets:
   ```sh
   python3 tools/send_fake_zones.py sweep          # each zone ramps up and down in turn
   python3 tools/send_fake_zones.py walk           # an obstacle approaching on the left
   python3 tools/send_fake_zones.py walk --loss 0.3   # with 30% of packets dropped
   python3 tools/send_fake_zones.py garbage        # malformed packets: motors must stay off
   ```
3. Check, in the monitor and on the belt:
   - The LED lights while the script runs and goes off shortly after you stop it.
   - Motors stop about half a second after you press Ctrl+C. That's the failsafe.
   - At 30% loss the buzz doesn't flicker (the 500 ms hold covers gaps).
   - Restarting the script mid-run makes the belt respond again right away (sequence numbers
     restart at 0).

## Test with the phone

1. On the iPhone: Settings → Wi-Fi → **BeltNav**. iOS says "No Internet Connection"; keep it
   connected, and turn **Auto-Join** on.
2. In the app, leave the belt host at `192.168.4.1` (clear the field and tap Apply to reset it).
3. Voice queries use cellular while the phone is on BeltNav.
