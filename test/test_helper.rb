# frozen_string_literal: true

require "minitest/autorun"
require "opentimestamps"

# A deterministic, offline chain oracle for tests: maps a height to a fixed
# root and time, so verification runs with no network.
class FakeChain
  def initialize(map) = @map = map # height => [root_bytes, Time]
  def block_merkle_root_and_time(height)
    @map.fetch(height) { raise OpenTimestamps::Error, "no block #{height}" }
  end
end
