# frozen_string_literal: true

require "test_helper"

# Regressions for the hardening of the untrusted-input parser: every one of
# these once produced an uncaught Ruby error (SystemStackError, RangeError) or
# unbounded work. They must now raise DeserializationError.
class SecurityTest < Minitest::Test
  include OpenTimestamps

  VECTOR = File.join(__dir__, "vectors", "hello-world.txt.ots")

  # Build a .ots whose timestamp is a linear chain of `depth` sha256 ops ending
  # in a Bitcoin attestation.
  def chain_ots(depth)
    digest = Digest::SHA256.digest("seed")
    root = Timestamp.new(digest)
    node = root
    msg = digest
    depth.times do
      op = Op.new(:sha256)
      msg = op.apply(msg)
      child = Timestamp.new(msg)
      node.ops[op] = child
      node = child
    end
    node.attestations << Attestation::Bitcoin.new(1)
    DetachedTimestampFile.new(Op.new(:sha256), root).serialize
  end

  def test_deep_recursion_raises_deserialization_error_not_stack_overflow
    bytes = chain_ots(Timestamp::MAX_DEPTH + 5)
    assert_raises(OpenTimestamps::DeserializationError) do
      DetachedTimestampFile.deserialize(bytes)
    end
  end

  def test_shallow_chain_still_parses
    DetachedTimestampFile.deserialize(chain_ots(50)) # no raise
  end

  def test_oversized_commitment_message_raises
    digest = Digest::SHA256.digest("seed")
    root = Timestamp.new(digest)
    big = "\x00".b * (Timestamp::MAX_MSG_BYTES + 1)
    op = Op.new(:append, big)
    root.ops[op] = Timestamp.new(op.apply(digest)).tap { |t| t.attestations << Attestation::Bitcoin.new(1) }
    bytes = DetachedTimestampFile.new(Op.new(:sha256), root).serialize
    assert_raises(OpenTimestamps::DeserializationError) { DetachedTimestampFile.deserialize(bytes) }
  end

  def test_trailing_data_rejected
    bytes = File.binread(VECTOR) + "JUNKJUNK".b
    assert_raises(OpenTimestamps::DeserializationError) { DetachedTimestampFile.deserialize(bytes) }
  end

  def test_wrong_major_version_rejected
    bytes = File.binread(VECTOR).b
    bytes.setbyte(Serialization::MAGIC.bytesize, 2) # bump the version varuint
    assert_raises(OpenTimestamps::DeserializationError) { DetachedTimestampFile.deserialize(bytes) }
  end

  def test_truncation_at_every_offset_raises
    full = File.binread(VECTOR).b
    (0...full.bytesize).each do |i|
      assert_raises(OpenTimestamps::DeserializationError, "offset #{i}") do
        DetachedTimestampFile.deserialize(full.byteslice(0, i))
      end
    end
  end

  def test_attestation_trailing_bytes_rejected
    # A Bitcoin attestation payload with an extra byte after the height must be
    # rejected, not silently dropped.
    inner = Serialization::Writer.new.varuint(700_000).write("\x99".b)
    body = Serialization::Writer.new
           .u8(0x00).write(Attestation::BITCOIN_TAG).varbytes(inner.string).string
    reader = Serialization::Reader.new(body)
    assert_raises(OpenTimestamps::DeserializationError) { Timestamp.deserialize(reader, Digest::SHA256.digest("x")) }
  end
end
