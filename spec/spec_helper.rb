# frozen_string_literal: true

require 'rspec'

# Load only the pure-Ruby parser — no OpenC3 gem needed for tests.
require_relative '../targets/FEATHERWEIGHT_GPS/lib/featherweight_gps_parser'

RSpec.configure do |config|
  config.order = :random
  config.color = true
  config.formatter = :documentation
end
