# frozen_string_literal: true

require "test_helper"

class DetachedFileTest < Minitest::Test
  include OpenTimestamps

  def test_build_serialize_parse_roundtrip
    digest = Digest::SHA256.digest("hello world\n")
    df = DetachedTimestampFile.from_hash(digest)
    df.timestamp.attestations << Attestation::Bitcoin.new(100_000)

    bytes = df.serialize
    assert bytes.start_with?(Serialization::MAGIC), "starts with .ots magic"

    df2 = DetachedTimestampFile.deserialize(bytes)
    assert_equal digest, df2.file_digest
    assert_equal :sha256, df2.file_hash_op.kind
    assert_equal bytes, df2.serialize, "file round-trips byte-for-byte"
  end

  def test_deserialize_rejects_bad_magic
    assert_raises(OpenTimestamps::DeserializationError) do
      DetachedTimestampFile.deserialize("not an ots file")
    end
  end

  def test_info_dump_mentions_bitcoin
    df = DetachedTimestampFile.from_hash(Digest::SHA256.digest("x"))
    df.timestamp.attestations << Attestation::Bitcoin.new(700_000)
    assert_match(/BITCOIN block #700000/, OpenTimestamps.info(df))
  end
end
