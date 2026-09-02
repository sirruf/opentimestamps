# frozen_string_literal: true

require "test_helper"

# Interop against real .ots files produced by the reference OpenTimestamps
# client (vendored in test/vectors/). These are the acceptance bar: if we can
# re-emit the exact bytes the reference wrote, we are wire-compatible.
class InteropTest < Minitest::Test
  include OpenTimestamps

  VECTORS = Dir[File.join(__dir__, "vectors", "*.ots")].freeze

  def test_vectors_present
    assert_operator VECTORS.size, :>=, 10, "vendored interop vectors should exist"
  end

  def test_every_vector_round_trips_byte_for_byte
    VECTORS.each do |path|
      bytes = File.binread(path).b
      df = DetachedTimestampFile.deserialize(bytes)
      assert_equal bytes, df.serialize,
                   "#{File.basename(path)} does not round-trip byte-for-byte"
    end
  end

  def test_structural_expectations
    kinds = lambda do |name|
      df = DetachedTimestampFile.deserialize(File.binread(File.join(__dir__, "vectors", name)))
      df.timestamp.each_attestation.map { |_, a| a.class.name.split("::").last }.tally
    end

    assert_equal({ "Bitcoin" => 1 }, kinds.call("hello-world.txt.ots"))
    assert_equal 1, kinds.call("unknown-notary.txt.ots")["Unknown"], "unknown attestation preserved"
    # different-blockchains exercises keccak256 (Ethereum) + Litecoin (Unknown) + Bitcoin
    dbc = kinds.call("different-blockchains.txt.ots")
    assert_equal 1, dbc["Bitcoin"]
    assert_operator dbc["Unknown"], :>=, 1
  end

  # hello-world.txt.ots attests to Bitcoin block 358391. Our operation engine
  # must walk the reference merkle path to *exactly* that block's real merkle
  # root — checked here against the historical value (deterministic, offline).
  BLOCK_358391_ROOT =
    ["007ee445d23ad061af4a36b809501fab1ac4f2d7e7a739817dd0cbb7ec661b8a"].pack("H*").freeze
  BLOCK_358391_TIME = Time.at(1_432_827_678).utc

  def test_verify_hello_world_against_real_block
    df = DetachedTimestampFile.deserialize(File.binread(File.join(__dir__, "vectors", "hello-world.txt.ots")))
    chain = FakeChain.new(358_391 => [BLOCK_358391_ROOT, BLOCK_358391_TIME])

    results = df.timestamp.verify(chain)
    assert_equal 1, results.size
    assert results.first[:verified], "commitment must equal block 358391 merkle root"
    assert_equal BLOCK_358391_TIME, results.first[:time]
  end

  def test_verify_fails_against_wrong_root
    df = DetachedTimestampFile.deserialize(File.binread(File.join(__dir__, "vectors", "hello-world.txt.ots")))
    chain = FakeChain.new(358_391 => ["\x00" * 32, BLOCK_358391_TIME])
    refute df.timestamp.verify(chain).first[:verified]
  end
end
