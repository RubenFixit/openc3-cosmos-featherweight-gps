# openc3-cosmos-featherweight-gps

An [OpenC3 COSMOS](https://openc3.com/) plugin that adds receive-only telemetry for the
[Featherweight GPS Tracker](https://www.featherweightaltimeters.com/) ground station (V2).

The plugin reads the Featherweight ground station's USB serial stream, parses the
`GPS_STAT` and `RX_NOMTK` ASCII telemetry lines, and exposes position, velocity, RF link
health, and battery data as standard OpenC3 telemetry packets.

> **Receive-only by design.** No commands are implemented.  The plugin never writes to
> the serial port, preventing accidental RF transmissions to the tracker.

---

## Requirements

| Item | Notes |
|------|-------|
| OpenC3 COSMOS | 5.x (tested) |
| Featherweight GPS Tracker | Ground Station **Version 2** only — V1 USB is charge-only |
| USB driver | CP2102 or CH340, depending on your GS board revision |
| OpenC3 serial bridge | Installed on the host laptop (`openc3-cosmos-bridge-serial` gem) |

---

## Quick Start

**1. Plug in the V2 ground station**

Connect the ground station's micro-USB port to your laptop.  Turn the ground station on.
The LoRa radio must be powered for the USB serial port to emit data.

**2. Identify the serial port**

| Platform | Typical port |
|----------|-------------|
| Windows  | `COM4` (check Device Manager → Ports) |
| Linux    | `/dev/ttyUSB0` or `/dev/ttyACM0` |
| macOS    | `/dev/cu.usbserial-*` or `/dev/cu.SLAB_USBtoUART` |

**3. Install the plugin gem into OpenC3**

*Via Admin → Plugins (drag-and-drop):*

1. Download the `.gem` file from the [Releases](../../releases) page.
2. Open OpenC3 → Admin → Plugins → Upload Plugin.
3. Set the plugin variables (see table below) and click Install.

*Via CLI:*

```bash
openc3cli load openc3-cosmos-featherweight-gps-0.1.0.gem
```

**4. Start the OpenC3 serial bridge on your laptop**

The bridge forwards the serial port to a TCP socket that OpenC3 can reach.
Replace `COM4` / `/dev/ttyUSB0` with your actual port:

```bash
# Windows
openc3cli bridgegem openc3-cosmos-bridge-serial \
  router_port=2950 \
  write_port_name=COM4 \
  read_port_name=COM4 \
  baud_rate=115200 \
  parity=NONE

# Linux
openc3cli bridgegem openc3-cosmos-bridge-serial \
  router_port=2950 \
  write_port_name=/dev/ttyUSB0 \
  read_port_name=/dev/ttyUSB0 \
  baud_rate=115200 \
  parity=NONE

# macOS
openc3cli bridgegem openc3-cosmos-bridge-serial \
  router_port=2950 \
  write_port_name=/dev/cu.usbserial-0001 \
  read_port_name=/dev/cu.usbserial-0001 \
  baud_rate=115200 \
  parity=NONE
```

**5. View telemetry screens**

In OpenC3 → TlmViewer, open:
- `FEATHERWEIGHT_GPS` → **gps** — position, velocity, satellites, fix state
- `FEATHERWEIGHT_GPS` → **link** — RSSI, SNR, frequency, packet counters, battery

---

## Plugin Variables

Set these when installing through the OpenC3 Admin UI or CLI:

| Variable | Default | Description |
|----------|---------|-------------|
| `target_name` | `FEATHERWEIGHT_GPS` | OpenC3 target name (change to run two trackers simultaneously) |
| `bridge_host` | `host.docker.internal` | Hostname where the serial bridge is running (`host.docker.internal` works for Docker Desktop on Windows/macOS; use the host's LAN IP on Linux) |
| `bridge_port` | `2950` | TCP port the serial bridge listens on |

---

## Telemetry Reference

### GPS_STATUS (1 Hz)

Source: `@ GPS_STAT` lines from the ground station.

| Field | Type | Units | Notes |
|-------|------|-------|-------|
| `TRACKER_ID` | STRING | — | Tracker callsign / LoRa ID |
| `UNIT_TYPE` | UINT | — | 1=TRK (tracker), 2=GS (ground station), 3=FND (lost rocket) |
| `FIX_TYPE` | UINT | — | 0=NO_FIX, 2=FIX_2D, 3=FIX_3D |
| `LATITUDE` | FLOAT | degrees | Decimal degrees, negative = South |
| `LONGITUDE` | FLOAT | degrees | Decimal degrees, negative = West |
| `ALTITUDE_FT` | INT | feet | Altitude above sea level |
| `H_VEL_FPS` | INT | ft/s | Horizontal speed |
| `HEADING_DEG` | INT | degrees | Track heading from North |
| `V_VEL_FPS` | INT | ft/s | Vertical speed (up = positive) |
| `SAT_TOTAL` | UINT | — | Total satellites in view |
| `SAT_24DB` | UINT | — | Sats > 24 dB-Hz (yellow bar) |
| `SAT_32DB` | UINT | — | Sats > 32 dB-Hz (green bar) |
| `SAT_40DB` | UINT | — | Sats > 40 dB-Hz (blue bar) |
| `YEAR` / `MONTH` / `DATE` | UINT | — | UTC date (0 before first GPS lock) |
| `UPTIME_S` | FLOAT | seconds | Seconds since midnight UTC |

### LINK_STATUS (1 Hz)

Source: `@ RX_NOMTK` lines from the ground station.

| Field | Type | Units | Notes |
|-------|------|-------|-------|
| `TRACKER_ID` | STRING | — | Tracker callsign / LoRa ID |
| `GS_RSSI` | INT | dBm | Ground station received RSSI |
| `GS_SNR` | INT | dB | Ground station received SNR |
| `TRK_RSSI` | INT | dBm | Tracker received RSSI (ack direction) |
| `TRK_SNR` | INT | dB | Tracker received SNR (ack direction) |
| `LORA_SF` | UINT | — | LoRa spreading factor (7–12) |
| `FREQUENCY` | UINT | Hz | LoRa center frequency |
| `PKT_RX` | UINT | — | Tracker packets received by GS (cumulative) |
| `PKT_TX` | UINT | — | Tracker packets sent (cumulative) |
| `ACK_RX` | UINT | — | GS acks received by tracker |
| `ACK_TX` | UINT | — | GS acks sent |
| `BATTERY_MV` | UINT | mV | Tracker battery voltage in millivolts (÷1000 = volts) |
| `RELAY_TEMP` | INT | °C | Relay node temperature (0 when not a relay packet) |

### UNKNOWN_LINE

Any `@`-prefixed line that did not match `GPS_STAT` or `RX_NOMTK` is forwarded
here for debugging.  Inspect `RAW_LINE` in TlmViewer to see the raw text.

---

## Building the Gem

```bash
# Clone and enter the repo
git clone https://github.com/rubenfixit/openc3-cosmos-featherweight-gps.git
cd openc3-cosmos-featherweight-gps

# Install dev dependencies (rspec)
bundle install

# Run parser tests — no OpenC3 gem required
bundle exec rspec

# Build the gem
gem build openc3-cosmos-featherweight-gps.gemspec
# → openc3-cosmos-featherweight-gps-0.1.0.gem
```

---

## Running Tests

```bash
bundle exec rspec
```

Tests cover:
- Parsing of `GPS_STAT` lines from the official manual and from real device captures (Rosetta project reference)
- Parsing of `RX_NOMTK` lines including `CRC_ERR`, missing temperature field, hyphens in tracker ID
- Blank / binary / non-@ lines returning nil
- Unknown `@` packet types forwarded as `UNKNOWN_LINE`
- Binary serialization: packet sizes, byte layout, signed/unsigned field encoding
- Time-field parsing for all three formats (`HH:MM:SS.mmm`, `MM:SS.s`, bare float)

---

## Serial Protocol Notes

- Only V2 ground stations (sold from November 2020) have an active USB data port.
  The V1 micro-USB is for charging only.
- All formatted packets start with `@`.  Binary LoRa microcontroller packets start
  with `FWT` and are discarded by this plugin.
- The packet timestamp comes from the GPS module.  Year/month/date fields are `0`
  until the first GPS lock is acquired.
- CRC-16/BUYPASS checksums appear at the end of each packet (`CRC: XXXX`).
  The plugin logs `CRC_ERR` lines but does not discard them.

---

## Known TODOs (v0.1 → v0.2)

- [ ] Satellite triplet parsing (azimuth / elevation / strength per satellite) — Appendix A includes up to 5 triplets per `GPS_STAT` line in `AAA_EE_SS` format
- [ ] `BATT_BLE` packet → add `GS_STATUS` packet for ground station battery voltage and BLE connection state
- [ ] `TX_STAT` packet → add `TX_STATUS` packet for per-transmission spreading factor and frequency
- [ ] CRC-16/BUYPASS verification — optionally reject lines where CRC does not match
- [ ] Validate heading sign convention against real V2 GS hardware (manual example shows -155°, which is unusual)
- [ ] Validate whether positive latitude/longitude always includes `+` prefix or varies by firmware version
- [ ] Add `ALTITUDE_AGL` field when a ground-elevation reference is available

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).
