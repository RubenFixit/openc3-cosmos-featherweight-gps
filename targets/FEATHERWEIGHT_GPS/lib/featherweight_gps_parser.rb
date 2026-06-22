# frozen_string_literal: true

# FeatherweightGps::Parser
#
# Pure-Ruby parser for Featherweight GPS Tracker V2 ground station USB serial
# output.  No OpenC3 dependency — fully testable in isolation.
#
# Protocol reference: Featherweight GPS Tracker User's Manual, Feb 2025, Appendix A.
# Serial settings: 115200 baud, 8N1, no flow control.
#
# Input is a single text line (already stripped of its trailing newline).
# Output is a Hash with a :type key, or nil when the line should be silently
# discarded (blank, binary FWT packet, or non-@ line).
#
# Call Parser.serialize(result) to turn the Hash into the binary blob that
# FeatherweightGpsProtocol returns to OpenC3.  The binary format is kept in
# strict sync with telemetry.txt — see comments there for bit offsets.

module FeatherweightGps
  module Parser
    # -----------------------------------------------------------------------
    # Regex patterns
    #
    # Header common to every formatted packet:
    #   @ {TYPE} {len} {year} {month} {date} {time} CRC_OK|CRC_ERR ...
    #
    # We capture year/month/date/time but do NOT enforce CRC_OK — the device
    # sometimes outputs CRC_ERR on valid-looking data and we still want it.
    # -----------------------------------------------------------------------

    # Matches GPS_STAT packets.  Captures groups:
    #  1=year 2=month 3=date 4=time  5=unit_type  6=tracker_id
    #  7=altitude_ft  8=latitude  9=longitude
    # 10=h_vel_fps  11=heading_deg  12=v_vel_fps
    # 13=fix_type  14=sat_total  15=sat_24db  16=sat_32db  17=sat_40db
    #
    # Tolerances:
    #  - Positive numbers may or may not have a leading '+' (firmware variation)
    #  - Integers may be zero-padded (e.g. 002053, +0000)
    #  - Multiple spaces between tokens (\s+)
    GPS_STAT_RE = /
      \A@ \s* GPS_STAT \s+ \S+ \s+          # sync + type + packet-length
      (\d+) \s+ (\d+) \s+ (\d+) \s+         # year month date
      ([\d:.eE+\-]+) \s+                     # time (various formats)
      CRC_\w+ \s+                            # CRC status (OK or ERR)
      (TRK|GS|FND) \s+                       # unit type
      (\S+) \s+                              # tracker ID
      Alt \s+ ([+-]?\d+) \s+                # altitude ft
      lt \s+ ([+-]?\d+(?:\.\d+)?) \s+        # latitude deg
      ln \s+ ([+-]?\d+(?:\.\d+)?) \s+       # longitude deg
      Vel \s+ ([+-]?\d+) \s+                # horizontal velocity fps
            ([+-]?\d+) \s+                  # heading deg
            ([+-]?\d+) \s+                  # vertical velocity fps
      Fix \s+ (\d) \s+                      # fix type
      \# \s+ (\d+) \s+                      # total satellites
             (\d+) \s+                      # sats > 24 dB
             (\d+) \s+                      # sats > 32 dB
             (\d+)                          # sats > 40 dB
    /x.freeze

    # Matches RX_NOMTK packets.  Captures groups:
    #  1=year 2=month 3=date 4=time  5=tracker_id
    #  6=pkt_rx  7=pkt_tx  8=gs_rssi  9=gs_snr
    # 10=ack_rx  11=ack_tx  12=trk_rssi  13=trk_snr
    # 14=lora_sf  15=frequency_hz  16=battery_mv
    # 17=relay_temp_c  (optional — nil when absent)
    RX_NOMTK_RE = /
      \A@ \s* RX_NOMTK \s+ \S+ \s+          # sync + type + packet-length
      (\d+) \s+ (\d+) \s+ (\d+) \s+         # year month date
      ([\d:.eE+\-]+) \s+                     # time
      CRC_\w+ \s+                            # CRC status
      Rx \s+ NomTrk \s+                      # literal header
      (\S+) \s+                              # tracker ID (may contain hyphens)
      PkRx \s+ (\d+) \s+                    # packets received
      PkTx \s+ (\d+) \s+                    # packets sent
      RSSI \s+ ([+-]?\d+) \s+               # GS RSSI dBm
      SNR  \s+ ([+-]?\d+) \s+               # GS SNR dB
      AckRx \s+ (\d+) \s+                   # ack received
      AckTx \s+ (\d+) \s+                   # ack sent
      RSSI \s+ ([+-]?\d+) \s+               # tracker RSSI dBm
      SNR  \s+ ([+-]?\d+) \s+               # tracker SNR dB
      SF \s+ (\d+) \s+                      # LoRa spreading factor
      frq \s+ (\d+) \s+                     # frequency Hz
      trk_B_V \s+ (\d+)                     # battery millivolts
      (?:                                    # optional temperature
        \s+ ([+-]?\d+) \s+ C
      )?
    /x.freeze

    UNIT_TYPE_MAP = { 'TRK' => 1, 'GS' => 2, 'FND' => 3 }.freeze

    # -----------------------------------------------------------------------
    # Public interface
    # -----------------------------------------------------------------------

    # Parse one text line.  Returns a Hash or nil.
    # nil  → caller should discard (blank / binary / non-@ line)
    # Hash → call serialize() to get the binary blob for OpenC3
    def self.parse_line(line)
      return nil if line.nil?

      stripped = line.strip
      return nil if stripped.empty?

      # Binary packets from the LoRa MCU start with "FWT" — discard silently.
      return nil if stripped.start_with?('FWT')

      # Only formatted telemetry lines start with '@'.
      # Anything else (info/debug text, blank separator lines) is ignored.
      return nil unless stripped.start_with?('@')

      if (m = GPS_STAT_RE.match(stripped))
        parse_gps_stat(m)
      elsif (m = RX_NOMTK_RE.match(stripped))
        parse_rx_nomtk(m)
      else
        # Known other types: TX_STAT FRST_FIX RX_TMOUT RLY_DIST RX_FOUND
        #                    RX_COORD RX_CRDFD GS_COORD COORDFND FS_CHNGE BATT_BLE
        # Forward to UNKNOWN_LINE so OpenC3 can log it without crashing.
        { type: :unknown, raw: stripped }
      end
    end

    # Serialize a parsed Hash into a binary blob for OpenC3.
    # Returns nil for nil input (convenience pass-through).
    def self.serialize(result)
      return nil unless result

      case result[:type]
      when :gps_status  then serialize_gps_status(result)
      when :link_status then serialize_link_status(result)
      when :unknown     then serialize_unknown(result)
      else raise ArgumentError, "unhandled packet type: #{result[:type].inspect}"
      end
    end

    # -----------------------------------------------------------------------
    # Private helpers
    # -----------------------------------------------------------------------

    private_class_method def self.parse_gps_stat(m)
      {
        type:        :gps_status,
        year:        m[1].to_i,
        month:       m[2].to_i,
        date:        m[3].to_i,
        uptime_s:    parse_time(m[4]),
        unit_type:   UNIT_TYPE_MAP[m[5]],
        tracker_id:  m[6],
        altitude_ft: m[7].to_i,
        latitude:    m[8].to_f,
        longitude:   m[9].to_f,
        h_vel_fps:   m[10].to_i,
        heading_deg: m[11].to_i,
        v_vel_fps:   m[12].to_i,
        fix_type:    m[13].to_i,
        sat_total:   m[14].to_i,
        sat_24db:    m[15].to_i,
        sat_32db:    m[16].to_i,
        sat_40db:    m[17].to_i
      }
    end

    private_class_method def self.parse_rx_nomtk(m)
      {
        type:          :link_status,
        year:          m[1].to_i,
        month:         m[2].to_i,
        date:          m[3].to_i,
        uptime_s:      parse_time(m[4]),
        tracker_id:    m[5],
        pkt_rx:        m[6].to_i,
        pkt_tx:        m[7].to_i,
        gs_rssi:       m[8].to_i,
        gs_snr:        m[9].to_i,
        ack_rx:        m[10].to_i,
        ack_tx:        m[11].to_i,
        trk_rssi:      m[12].to_i,
        trk_snr:       m[13].to_i,
        lora_sf:       m[14].to_i,
        frequency_hz:  m[15].to_i,
        battery_mv:    m[16].to_i,
        # TODO: relay_temp_c is present only when this is a relay-forwarded packet
        relay_temp_c:  m[17]&.to_i || 0
      }
    end

    # Convert the time token from a packet header to floating-point seconds.
    # The GS produces several formats depending on packet type and GPS lock:
    #   HH:MM:SS.mmm  — GPS_STAT with GPS lock (most common)
    #   MM:SS.s       — some packet types using internal clock
    #   SS.sss        — bare seconds (float)
    #   scientific    — firmware quirk; falls back to 0
    private_class_method def self.parse_time(str)
      return 0.0 if str.nil? || str.empty?
      return str.to_f if str.match?(/[eE]/)

      parts = str.split(':').map(&:to_f)
      case parts.length
      when 3 then parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
      when 2 then parts[0] * 60.0 + parts[1]
      else        parts[0]
      end
    end

    # Binary serialization helpers.
    # Formats must stay in byte-perfect sync with telemetry.txt.
    # Ruby pack: 'e' = little-endian float32 (IEEE 754 single).
    # 'f<' is NOT valid Ruby syntax — floats use letter codes, not modifiers.
    #
    # GPS_STATUS: C C a10 S< C C e l< e e l< l< l< C C C C C  = 49 bytes
    private_class_method def self.serialize_gps_status(d)
      tid = pad_tracker_id(d[:tracker_id])
      [1, d[:unit_type].to_i].pack('CC') +
        tid +
        [d[:year].to_i].pack('S<') +
        [d[:month].to_i, d[:date].to_i].pack('CC') +
        [d[:uptime_s].to_f].pack('e') +
        [d[:altitude_ft].to_i].pack('l<') +
        [d[:latitude].to_f].pack('e') +
        [d[:longitude].to_f].pack('e') +
        [d[:h_vel_fps].to_i, d[:heading_deg].to_i, d[:v_vel_fps].to_i].pack('l<l<l<') +
        [d[:fix_type].to_i,
         d[:sat_total].to_i, d[:sat_24db].to_i,
         d[:sat_32db].to_i,  d[:sat_40db].to_i].pack('CCCCC')
    end

    # LINK_STATUS: C a10 S< C C e L< L< l< l< L< L< l< l< C L< L< l<  = 64 bytes
    private_class_method def self.serialize_link_status(d)
      tid = pad_tracker_id(d[:tracker_id])
      [2].pack('C') +
        tid +
        [d[:year].to_i].pack('S<') +
        [d[:month].to_i, d[:date].to_i].pack('CC') +
        [d[:uptime_s].to_f].pack('e') +
        [d[:pkt_rx].to_i, d[:pkt_tx].to_i].pack('L<L<') +
        [d[:gs_rssi].to_i, d[:gs_snr].to_i].pack('l<l<') +
        [d[:ack_rx].to_i, d[:ack_tx].to_i].pack('L<L<') +
        [d[:trk_rssi].to_i, d[:trk_snr].to_i].pack('l<l<') +
        [d[:lora_sf].to_i].pack('C') +
        [d[:frequency_hz].to_i].pack('L<') +
        [d[:battery_mv].to_i].pack('L<') +
        [d[:relay_temp_c].to_i].pack('l<')
    end

    # UNKNOWN_LINE: C a200  = 201 bytes
    private_class_method def self.serialize_unknown(d)
      raw = d[:raw].to_s
               .encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
               .b
               .slice(0, 200)
               .ljust(200, "\x00")
      [255].pack('C') + raw
    end

    # Truncate / null-pad tracker ID to exactly 10 bytes (binary-safe).
    private_class_method def self.pad_tracker_id(id)
      id.to_s.b.slice(0, 10).ljust(10, "\x00")
    end
  end
end
