# frozen_string_literal: true

require "test_helper"

class Keccak256Test < Minitest::Test
  # Known-answer vectors for Ethereum's Keccak-256 (0x01 padding, not SHA3).
  KAT = {
    "" => "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
    "abc" => "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
    "The quick brown fox jumps over the lazy dog" =>
      "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15"
  }.freeze

  def test_known_answers
    KAT.each do |msg, hex|
      assert_equal hex, OpenTimestamps::Keccak256.hexdigest(msg), "keccak256(#{msg.inspect})"
    end
  end

  def test_multiblock_input
    # > 136 bytes forces multiple sponge blocks.
    msg = "a" * 200
    assert_equal 32, OpenTimestamps::Keccak256.digest(msg).bytesize
    assert_equal OpenTimestamps::Keccak256.hexdigest(msg),
                 OpenTimestamps::Op.new(:keccak256).apply(msg).unpack1("H*")
  end
end
