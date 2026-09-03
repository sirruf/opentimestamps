# frozen_string_literal: true

require "test_helper"

# The serializer must emit children in the reference client's canonical order and
# must not let a proof carry padding that inflates a quorum.
class CanonicalTest < Minitest::Test
  include OpenTimestamps

  MSG = ("\x00".b * 32).freeze

  # Serialize a node's children and read them back, so we observe the on-wire
  # order rather than the in-memory insertion order.
  def roundtrip(node)
    bytes = node.serialize(Serialization::Writer.new).string
    Timestamp.deserialize(Serialization::Reader.new(bytes), node.msg)
  end

  def test_bitcoin_attestations_sort_by_height_not_serialized_bytes
    node = Timestamp.new(MSG)
    node.attestations << Attestation::Bitcoin.new(358_400)
    node.attestations << Attestation::Bitcoin.new(358_391)
    assert_equal [358_391, 358_400], roundtrip(node).attestations.map(&:height)
  end

  def test_pending_attestations_sort_by_uri
    node = Timestamp.new(MSG)
    node.attestations << Attestation::Pending.new("z")
    node.attestations << Attestation::Pending.new("aa")
    assert_equal %w[aa z], roundtrip(node).attestations.map(&:uri)
  end

  def test_ops_sort_by_raw_operand_not_length_prefixed_bytes
    node = Timestamp.new(MSG)
    short = Op.new(:append, "\x01\x02")       # 2-byte operand
    long  = Op.new(:append, "\x00".b * 16)    # 16-byte operand, but lexically first
    [short, long].each do |op|
      child = Timestamp.new(op.apply(MSG))
      child.attestations << Attestation::Bitcoin.new(1)
      node.ops[op] = child
    end
    # Reference orders by [tag, raw operand]: 0x00.. precedes 0x01.., regardless of
    # the length prefix (a bytes-of-serialization sort would put the short one first).
    assert_equal ["\x00".b * 16, "\x01\x02".b], roundtrip(node).ops.keys.map(&:arg)
  end

  def test_reference_vectors_still_round_trip_byte_for_byte
    Dir[File.join(__dir__, "vectors", "*.ots")].each do |path|
      next if File.basename(path) == "bad-stamp.txt.ots" # intentionally invalid

      bytes = File.binread(path)
      reserialized = DetachedTimestampFile.deserialize(bytes).serialize
      assert_equal bytes, reserialized, "#{File.basename(path)} did not round-trip"
    end
  end

  # --- hardening: a proof cannot pad a quorum ---

  def test_duplicate_attestation_is_dropped_on_deserialize
    att = Attestation::Bitcoin.new(500)
    w = Serialization::Writer.new
    w.u8(0xff).u8(0x00)
    att.serialize(w)
    w.u8(0x00)
    att.serialize(w)
    parsed = Timestamp.deserialize(Serialization::Reader.new(w.string), MSG)
    assert_equal 1, parsed.attestations.size
  end

  def test_empty_operand_rejected_on_construction
    assert_raises(OpenTimestamps::Error) { Op.new(:append, "") }
    assert_raises(OpenTimestamps::Error) { Op.new(:prepend, "") }
  end

  def test_empty_operand_rejected_as_deserialization_error
    # Op.deserialize is given the tag; the reader holds only the operand's varbytes,
    # here a zero length.
    reader = Serialization::Reader.new(Serialization::Writer.new.varuint(0).string)
    err = assert_raises(OpenTimestamps::DeserializationError) { Op.deserialize(reader, 0xf0) }
    assert_match(/empty argument/, err.message)
  end
end
