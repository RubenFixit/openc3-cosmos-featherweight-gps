# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'openc3-cosmos-featherweight-gps'
  spec.version       = '0.1.0'
  spec.authors       = ['Ruben Fixit']
  spec.email         = ['github@rubenfixit.com']

  spec.summary       = 'OpenC3 COSMOS plugin for Featherweight GPS Tracker ground station'
  spec.description   = 'Receive-only telemetry plugin for the Featherweight GPS Tracker V2 ' \
                       'USB ground station. Connects via the OpenC3 serial bridge over TCP ' \
                       'and exposes GPS position, RF link, and battery telemetry.'
  spec.homepage      = 'https://github.com/rubenfixit/openc3-cosmos-featherweight-gps'
  spec.license       = 'Apache-2.0'

  spec.required_ruby_version = '>= 2.7'

  spec.files = Dir[
    'plugin.txt',
    'targets/**/*',
    'LICENSE',
    'README.md'
  ].reject { |f| File.directory?(f) }

  spec.require_paths = ['lib']
end
