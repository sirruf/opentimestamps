# frozen_string_literal: true

require "test_helper"

class ApiTest < Minitest::Test
  # Offline: stamp_digest must validate the digest length before any network I/O.
  def test_stamp_digest_rejects_wrong_length
    err = assert_raises(OpenTimestamps::Error) do
      OpenTimestamps.stamp_digest("too short", hash: :sha256)
    end
    assert_match(/32 bytes/, err.message)
  end

  def test_stamp_digest_rejects_unknown_hash
    assert_raises(OpenTimestamps::Error) do
      OpenTimestamps.stamp_digest("\x00" * 32, hash: :md5)
    end
  end

  def test_info_dump_roundtrips_a_known_vector
    bytes = File.binread(File.join(__dir__, "vectors", "hello-world.txt.ots"))
    df = OpenTimestamps::DetachedTimestampFile.deserialize(bytes)
    assert_match(/BITCOIN block #358391/, OpenTimestamps.info(df))
  end
end
