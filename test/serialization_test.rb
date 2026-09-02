# frozen_string_literal: true

require "test_helper"

class SerializationTest < Minitest::Test
  R = OpenTimestamps::Serialization::Reader
  W = OpenTimestamps::Serialization::Writer

  MAX = OpenTimestamps::Serialization::MAX_VARUINT

  def test_varuint_roundtrip
    [0, 1, 127, 128, 255, 300, 16_384, 100_000, MAX].each do |n|
      bytes = W.new.varuint(n).string
      assert_equal n, R.new(bytes).varuint, "varuint #{n}"
    end
  end

  def test_reader_rejects_oversized_varuint
    # A length prefix past the cap must raise DeserializationError, not leak a
    # bignum RangeError or trigger a huge allocation. This encodes 1 << 35.
    oversized = "\x80\x80\x80\x80\x80\x01".b
    assert_raises(OpenTimestamps::DeserializationError) { R.new(oversized).varuint }
  end

  def test_varbytes_roundtrip
    payload = "\x00\xffhello\x00".b
    bytes = W.new.varbytes(payload).string
    assert_equal payload, R.new(bytes).varbytes
  end

  def test_reader_raises_on_eof
    assert_raises(OpenTimestamps::DeserializationError) { R.new("").u8 }
    assert_raises(OpenTimestamps::DeserializationError) { R.new("\x01").read(4) }
  end

  def test_read_rejects_oversized_length
    assert_raises(OpenTimestamps::DeserializationError) { R.new("abc").read(9_999) }
  end
end
