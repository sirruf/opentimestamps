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
    assert_equal [{ height: 555, time: t, verified: true, commitment: commitment, error: nil }], ts.verify(good)

    bad = FakeChain.new(555 => ["\x00" * 32, t])
    refute ts.verify(bad).first[:verified]
  end

  def test_verify_records_network_error_per_attestation
    _leaf, ts, = build
    down = Object.new
    def down.block_merkle_root_and_time(_height) = raise(OpenTimestamps::NetworkError, "down")
    result = ts.verify(down).first
    refute result[:verified]
    assert_nil result[:time]
    assert_instance_of OpenTimestamps::NetworkError, result[:error]
  end

  def test_verify_records_no_error_for_missing_block
    _leaf, ts, = build
    missing = Object.new
    def missing.block_merkle_root_and_time(_height) = raise(OpenTimestamps::BlockNotFound, "nope")
    result = ts.verify(missing).first
    refute result[:verified]
    assert_nil result[:error]
  end

  def test_find_locates_a_node_by_commitment
    _leaf, ts, commitment = build
    node = ts.find(commitment)
    refute_nil node
    assert_equal commitment, node.msg
    assert_nil ts.find("nonexistent")
  end

  def test_merge_folds_a_bitcoin_path_into_a_pending_one
    leaf = Digest::SHA256.digest("leaf")
    op = Op.new(:sha256)
    commitment = op.apply(leaf)

    pending = Timestamp.new(leaf)
    pending.ops[op] = Timestamp.new(commitment).tap { |n| n.attestations << Attestation::Pending.new("https://cal") }

    anchored = Timestamp.new(leaf)
    anchored.ops[Op.new(:sha256)] = Timestamp.new(commitment).tap { |n| n.attestations << Attestation::Bitcoin.new(42) }

    pending.merge(anchored)
    kinds = pending.each_attestation.map { |_, a| a.class }
    assert_includes kinds, Attestation::Pending
    assert_includes kinds, Attestation::Bitcoin
  end

  def test_merge_rejects_mismatched_root
    assert_raises(OpenTimestamps::Error) do
      Timestamp.new("a" * 32).merge(Timestamp.new("b" * 32))
    end
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
