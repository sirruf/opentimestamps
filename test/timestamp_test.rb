# frozen_string_literal: true

require "test_helper"

class TimestampTest < Minitest::Test
  include OpenTimestamps

  # Build: leaf --append(0102)--> n1 --sha256--> n2 [BITCOIN #555]
  def build
    leaf = Digest::SHA256.digest("leaf")
    op_a = Op.new(:append, "\x01\x02".b)
    op_h = Op.new(:sha256)

    n2 = Timestamp.new(op_h.apply(op_a.apply(leaf)))
    n2.attestations << Attestation::Bitcoin.new(555)
    n1 = Timestamp.new(op_a.apply(leaf))
    n1.ops[op_h] = n2
    root = Timestamp.new(leaf)
    root.ops[op_a] = n1
    [leaf, root, n2.msg]
  end

  def test_serialize_deserialize_roundtrip
    leaf, ts, = build
    bytes = ts.serialize(Serialization::Writer.new).string
    ts2 = Timestamp.deserialize(Serialization::Reader.new(bytes), leaf)
    bytes2 = ts2.serialize(Serialization::Writer.new).string
    assert_equal bytes, bytes2, "serialize is stable across a round-trip"
  end

  def test_each_attestation_reports_commitment
    _leaf, ts, commitment = build
    found = ts.each_attestation.to_a
    assert_equal 1, found.size
    msg, att = found.first
    assert att.bitcoin?
    assert_equal 555, att.height
    assert_equal commitment, msg
  end

  def test_verify_against_matching_and_mismatching_chain
    _leaf, ts, commitment = build
    t = Time.utc(2020, 1, 1)

    good = FakeChain.new(555 => [commitment, t])
    assert_equal [{ height: 555, time: t, verified: true }], ts.verify(good)

    bad = FakeChain.new(555 => ["\x00" * 32, t])
    refute ts.verify(bad).first[:verified]
  end

  def test_unknown_attestation_preserved_on_roundtrip
    leaf = Digest::SHA256.digest("x")
    ts = Timestamp.new(leaf)
    ts.attestations << Attestation::Unknown.new("\x11" * 8, "\xaa\xbb".b)
    bytes = ts.serialize(Serialization::Writer.new).string
    ts2 = Timestamp.deserialize(Serialization::Reader.new(bytes), leaf)
    assert_equal bytes, ts2.serialize(Serialization::Writer.new).string
  end
end
