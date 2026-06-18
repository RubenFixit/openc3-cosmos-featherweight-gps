# frozen_string_literal: true

require_relative 'spec_helper'

# Sample lines drawn directly from the official Featherweight GPS Tracker
# User's Manual (Feb 2025, Appendix A) and from the Rosetta project which
# captured real V2 ground station output (older firmware).

RSpec.describe FeatherweightGps::Parser do
  # -------------------------------------------------------------------------
  # Shared example lines
  # -------------------------------------------------------------------------

  # From the manual, Appendix A, page 21 (positive lat without '+' sign)
  MANUAL_GPS_STAT =
    '@ GPS_STAT 203 2020 11 15 01:20:21.986 CRC_OK TRK secondTrk ' \
    'Alt 5655 lt 39.55612 ln -105.1032 Vel 0 -155 0 Fix 3 ' \
    '# 9 4 2 0 000_00_00 000_00_00 000_00_00 000_00_00 000_00_00 CRC: 6A1D'

  # From the Rosetta project (older firmware — explicit '+' on positive values,
  # zero-padded integers, year/month/date all zeros = pre-GPS-lock)
  ROSETTA_GPS_STAT =
    '@ GPS_STAT 203 0000 00 00 00:37:53.145 CRC_OK  TRK FthrWt04072 ' \
    'Alt 002053 lt +35.34776 ln -117.80913 Vel +0000 +027 +0000 Fix 3 ' \
    '# 29 23 10  0'

  # From the manual, Appendix A, page 21 (CRC_ERR still parseable)
  MANUAL_RX_NOMTK =
    '@ RX_NOMTK 202 2020 6 17 50:56.9 CRC_ERR Rx NomTrk RLY-19-Whip ' \
    'PkRx 143 PkTx  38 RSSI -124 SNR -20 AckRx 0 AckTx 0 ' \
    'RSSI -50 SNR  +0 SF 11 frq 908599976 trk_B_V 4102  -69 C CRC: EFD0'

  # RX_NOMTK without the optional temperature field
  RX_NOMTK_NO_TEMP =
    '@ RX_NOMTK 202 2020 6 17 50:56.9 CRC_OK Rx NomTrk FthrWt04072 ' \
    'PkRx 2242 PkTx 2715 RSSI -079 SNR +08 AckRx 2218 AckTx 2248 ' \
    'RSSI -099 SNR -10 SF 10 frq 919000000 trk_B_V 4098 CRC: EFD0'

  # -------------------------------------------------------------------------
  describe '.parse_line' do
    # --- nil / blank / ignored lines ----------------------------------------

    it 'returns nil for nil input' do
      expect(described_class.parse_line(nil)).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.parse_line('')).to be_nil
    end

    it 'returns nil for a whitespace-only line' do
      expect(described_class.parse_line("   \t  ")).to be_nil
    end

    it 'returns nil for a binary FWT packet' do
      expect(described_class.parse_line('FWT' + "\x00\x01\x02\x03")).to be_nil
    end

    it 'returns nil for a non-@ info line' do
      expect(described_class.parse_line('Build date and time +DT4 Nov 7 2020')).to be_nil
    end

    # --- UNKNOWN_LINE for unrecognised @ packets -----------------------------

    it 'returns :unknown for a TX_STAT line' do
      line = '@ TX_STAT 91 2019 11 27 00:16:49.800 Tx Apid 11 Tx dur: 371 msec. SF12 Freq 926800000 CRC: B4E3'
      result = described_class.parse_line(line)
      expect(result).not_to be_nil
      expect(result[:type]).to eq(:unknown)
      expect(result[:raw]).to include('TX_STAT')
    end

    it 'returns :unknown for a BATT_BLE line' do
      line = '@ BATT_BLE 68 2020 5 17 0.176433519 4189 BLE+ 36 degC CRC: 3176 6C19'
      result = described_class.parse_line(line)
      expect(result[:type]).to eq(:unknown)
    end

    # --- GPS_STAT (manual example) ------------------------------------------

    context 'with a manual GPS_STAT example (no + prefix on positive lat)' do
      subject(:result) { described_class.parse_line(MANUAL_GPS_STAT) }

      it 'parses as :gps_status' do
        expect(result[:type]).to eq(:gps_status)
      end

      it 'extracts the UTC date' do
        expect(result[:year]).to eq(2020)
        expect(result[:month]).to eq(11)
        expect(result[:date]).to eq(15)
      end

      it 'converts time to seconds since midnight' do
        # 01:20:21.986 => 1*3600 + 20*60 + 21.986 = 4821.986
        expect(result[:uptime_s]).to be_within(0.001).of(4821.986)
      end

      it 'maps TRK to unit_type 1' do
        expect(result[:unit_type]).to eq(1)
      end

      it 'extracts tracker_id' do
        expect(result[:tracker_id]).to eq('secondTrk')
      end

      it 'extracts altitude' do
        expect(result[:altitude_ft]).to eq(5655)
      end

      it 'extracts latitude' do
        expect(result[:latitude]).to be_within(0.00001).of(39.55612)
      end

      it 'extracts longitude' do
        expect(result[:longitude]).to be_within(0.00001).of(-105.1032)
      end

      it 'extracts horizontal velocity' do
        expect(result[:h_vel_fps]).to eq(0)
      end

      it 'extracts heading' do
        expect(result[:heading_deg]).to eq(-155)
      end

      it 'extracts vertical velocity' do
        expect(result[:v_vel_fps]).to eq(0)
      end

      it 'extracts fix type 3 (3D)' do
        expect(result[:fix_type]).to eq(3)
      end

      it 'extracts satellite counts' do
        expect(result[:sat_total]).to eq(9)
        expect(result[:sat_24db]).to eq(4)
        expect(result[:sat_32db]).to eq(2)
        expect(result[:sat_40db]).to eq(0)
      end
    end

    # --- GPS_STAT (Rosetta / older firmware) --------------------------------

    context 'with a Rosetta GPS_STAT example (+ prefix, zero-padded, pre-lock date)' do
      subject(:result) { described_class.parse_line(ROSETTA_GPS_STAT) }

      it 'parses as :gps_status' do
        expect(result[:type]).to eq(:gps_status)
      end

      it 'handles all-zero year/month/date (pre-GPS-lock)' do
        expect(result[:year]).to eq(0)
        expect(result[:month]).to eq(0)
        expect(result[:date]).to eq(0)
      end

      it 'converts time with leading zeros' do
        # 00:37:53.145 => 37*60 + 53.145 = 2273.145
        expect(result[:uptime_s]).to be_within(0.001).of(2273.145)
      end

      it 'strips zero-padding from altitude' do
        expect(result[:altitude_ft]).to eq(2053)
      end

      it 'handles explicit + prefix on latitude' do
        expect(result[:latitude]).to be_within(0.00001).of(35.34776)
      end

      it 'extracts heading (+ prefix)' do
        expect(result[:heading_deg]).to eq(27)
      end

      it 'extracts satellite counts with extra whitespace' do
        expect(result[:sat_total]).to eq(29)
        expect(result[:sat_24db]).to eq(23)
        expect(result[:sat_32db]).to eq(10)
        expect(result[:sat_40db]).to eq(0)
      end
    end

    # --- RX_NOMTK (manual example, CRC_ERR, with temperature) ---------------

    context 'with a manual RX_NOMTK example (CRC_ERR, relay, temperature present)' do
      subject(:result) { described_class.parse_line(MANUAL_RX_NOMTK) }

      it 'parses as :link_status even when CRC_ERR' do
        expect(result[:type]).to eq(:link_status)
      end

      it 'extracts tracker_id with hyphens' do
        expect(result[:tracker_id]).to eq('RLY-19-Whip')
      end

      it 'extracts packet counters' do
        expect(result[:pkt_rx]).to eq(143)
        expect(result[:pkt_tx]).to eq(38)
      end

      it 'extracts GS RSSI and SNR' do
        expect(result[:gs_rssi]).to eq(-124)
        expect(result[:gs_snr]).to eq(-20)
      end

      it 'extracts ack counters' do
        expect(result[:ack_rx]).to eq(0)
        expect(result[:ack_tx]).to eq(0)
      end

      it 'extracts tracker RSSI and SNR' do
        expect(result[:trk_rssi]).to eq(-50)
        expect(result[:trk_snr]).to eq(0)
      end

      it 'extracts LoRa spreading factor' do
        expect(result[:lora_sf]).to eq(11)
      end

      it 'extracts frequency' do
        expect(result[:frequency_hz]).to eq(908_599_976)
      end

      it 'extracts raw battery millivolts' do
        expect(result[:battery_mv]).to eq(4102)
      end

      it 'extracts relay temperature' do
        expect(result[:relay_temp_c]).to eq(-69)
      end
    end

    # --- RX_NOMTK without optional temperature field ------------------------

    context 'with RX_NOMTK that has no temperature token' do
      subject(:result) { described_class.parse_line(RX_NOMTK_NO_TEMP) }

      it 'parses as :link_status' do
        expect(result[:type]).to eq(:link_status)
      end

      it 'defaults relay_temp_c to 0' do
        expect(result[:relay_temp_c]).to eq(0)
      end
    end
  end

  # -------------------------------------------------------------------------
  describe '.serialize' do
    it 'returns nil for nil input' do
      expect(described_class.serialize(nil)).to be_nil
    end

    # --- GPS_STATUS binary checks -------------------------------------------

    context 'GPS_STATUS serialization' do
      let(:result) { described_class.parse_line(MANUAL_GPS_STAT) }
      let(:blob)   { described_class.serialize(result) }

      it 'produces exactly 49 bytes' do
        expect(blob.bytesize).to eq(49)
      end

      it 'starts with PACKET_ID byte 1' do
        expect(blob.bytes[0]).to eq(1)
      end

      it 'encodes UNIT_TYPE 1 (TRK) at byte 1' do
        expect(blob.bytes[1]).to eq(1)
      end

      it 'encodes tracker_id as 10-byte null-padded field' do
        tracker_bytes = blob.byteslice(2, 10)
        id = tracker_bytes.delete("\x00")
        expect(id).to eq('secondTrk')
      end

      it 'encodes year as little-endian uint16 at bytes 12–13' do
        year = blob.byteslice(12, 2).unpack1('S<')
        expect(year).to eq(2020)
      end

      it 'encodes altitude_ft as little-endian int32' do
        alt = blob.byteslice(20, 4).unpack1('l<')
        expect(alt).to eq(5655)
      end

      it 'encodes latitude as little-endian float32' do
        lat = blob.byteslice(24, 4).unpack1('e')
        expect(lat).to be_within(0.001).of(39.55612)
      end

      it 'encodes fix_type at byte 44' do
        expect(blob.bytes[44]).to eq(3)
      end

      it 'encodes sat_total at byte 45' do
        expect(blob.bytes[45]).to eq(9)
      end

      it 'encodes sat_40db at byte 48' do
        expect(blob.bytes[48]).to eq(0)
      end
    end

    # --- LINK_STATUS binary checks ------------------------------------------

    context 'LINK_STATUS serialization' do
      let(:result) { described_class.parse_line(MANUAL_RX_NOMTK) }
      let(:blob)   { described_class.serialize(result) }

      it 'produces exactly 64 bytes' do
        expect(blob.bytesize).to eq(64)
      end

      it 'starts with PACKET_ID byte 2' do
        expect(blob.bytes[0]).to eq(2)
      end

      it 'encodes tracker_id as 10-byte field' do
        tracker_bytes = blob.byteslice(1, 10)
        id = tracker_bytes.delete("\x00")
        expect(id).to eq('RLY-19-Whi') # truncated to 10 bytes
      end

      it 'encodes gs_rssi as signed int32' do
        rssi = blob.byteslice(27, 4).unpack1('l<')
        expect(rssi).to eq(-124)
      end

      it 'encodes battery_mv as unsigned int32' do
        batt = blob.byteslice(56, 4).unpack1('L<')
        expect(batt).to eq(4102)
      end

      it 'encodes relay_temp_c as signed int32' do
        temp = blob.byteslice(60, 4).unpack1('l<')
        expect(temp).to eq(-69)
      end
    end

    # --- UNKNOWN_LINE binary checks ------------------------------------------

    context 'UNKNOWN_LINE serialization' do
      let(:result) { described_class.parse_line('@ TX_STAT 91 2019 11 27 00:16:49.800 SF12 CRC: B4E3') }
      let(:blob)   { described_class.serialize(result) }

      it 'produces exactly 201 bytes' do
        expect(blob.bytesize).to eq(201)
      end

      it 'starts with PACKET_ID byte 255' do
        expect(blob.bytes[0]).to eq(255)
      end

      it 'contains the raw line text in bytes 1–200' do
        raw = blob.byteslice(1, 200).delete("\x00")
        expect(raw).to include('TX_STAT')
      end
    end
  end

  # -------------------------------------------------------------------------
  describe 'time parsing (private, tested via parse_line)' do
    it 'handles HH:MM:SS.mmm format' do
      line = MANUAL_GPS_STAT
      result = described_class.parse_line(line)
      expect(result[:uptime_s]).to be_within(0.001).of(4821.986)
    end

    it 'handles MM:SS.s format (RX_NOMTK example)' do
      result = described_class.parse_line(MANUAL_RX_NOMTK)
      # 50:56.9 => 50*60 + 56.9 = 3056.9
      expect(result[:uptime_s]).to be_within(0.01).of(3056.9)
    end
  end
end
