# frozen_string_literal: true

require 'openc3/interfaces/protocols/protocol'
require_relative 'featherweight_gps_parser'

module OpenC3
  # FeatherweightGpsProtocol
  #
  # OpenC3 READ protocol for the Featherweight GPS Tracker V2 ground station.
  # Connects via the OpenC3 serial bridge (TCP client).
  #
  # The GS sends a UTF-8 line-oriented text stream at ~1 Hz.  This protocol:
  #   1. Buffers raw TCP bytes and extracts newline-terminated lines.
  #   2. Passes each line to FeatherweightGps::Parser.
  #   3. Returns a binary-serialized packet blob to OpenC3, which uses the
  #      first byte (PACKET_ID) to route it to the correct TELEMETRY definition.
  #
  # Only READ direction is implemented — this target is intentionally receive-only
  # to prevent accidental commands being sent to the tracker over RF.
  class FeatherweightGpsProtocol < Protocol
    def initialize(allow_empty_data = nil)
      super(allow_empty_data)
      @buf = +'' # mutable string buffer, encoding-agnostic
    end

    def reset
      super
      @buf = +''
    end

    # Called by the interface with raw bytes from the TCP socket.
    # Returns [binary_blob, extra] when a complete, parseable line is ready,
    # or :STOP when we need more data.
    def read_data(data, extra = nil)
      @buf << data.to_s

      while (nl_pos = @buf.index("\n"))
        line = @buf.slice!(0, nl_pos + 1).chomp

        result = FeatherweightGps::Parser.parse_line(line)
        binary = FeatherweightGps::Parser.serialize(result)

        # Return the first non-nil blob we produce.  If the line was blank,
        # binary, or a non-@ line, binary is nil and we keep scanning.
        return binary, extra if binary
      end

      # No complete line with a parseable packet yet — ask for more data.
      :STOP
    end
  end
end
