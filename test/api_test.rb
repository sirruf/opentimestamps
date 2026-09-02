# frozen_string_literal: true

require "test_helper"

class ApiTest < Minitest::Test
  include OpenTimestamps

  BLOCK_358391_ROOT =
    ["007ee445d23ad061af4a36b809501fab1ac4f2d7e7a739817dd0cbb7ec661b8a"].pack("H*").freeze

  def hello_world
    DetachedTimestampFile.deserialize(File.binread(File.join(__dir__, "vectors", "hello-world.txt.ots")))
  end

  # Offline: stamp_digest must validate the digest before any network I/O.
  def test_stamp_digest_rejects_wrong_length
    err = assert_raises(OpenTimestamps::Error) { OpenTimestamps.stamp_digest("too short", hash: :sha256) }
    assert_match(/32 bytes/, err.message)
  end

  def test_stamp_digest_rejects_unknown_hash
    assert_raises(OpenTimestamps::Error) { OpenTimestamps.stamp_digest("\x00" * 32, hash: :md5) }
  end

  def test_from_hash_rejects_keccak256_as_file_hash_op
    # keccak256 is a valid op but not a valid file-hash op; reject up front
    # rather than build a file this gem cannot re-read.
    assert_raises(OpenTimestamps::Error) { DetachedTimestampFile.from_hash("\x00" * 32, hash: :keccak256) }
  end

  # verify must fail closed.
  def test_verify_raises_on_pending_proof
    pending = DetachedTimestampFile.deserialize(File.binread(File.join(__dir__, "vectors", "incomplete.txt.ots")))
    assert_raises(OpenTimestamps::VerificationError) { OpenTimestamps.verify(pending, chain: FakeChain.new({})) }
    refute OpenTimestamps.verified?(pending, chain: FakeChain.new({}))
  end

  def test_verify_raises_on_mismatched_attestation
    chain = FakeChain.new(358_391 => ["\x00" * 32, Time.now.utc])
    assert_raises(OpenTimestamps::VerificationError) { OpenTimestamps.verify(hello_world, chain: chain) }
    refute OpenTimestamps.verified?(hello_world, chain: chain)
  end

  def test_verify_returns_confirmed_with_digest
    df = hello_world
    chain = FakeChain.new(358_391 => [BLOCK_358391_ROOT, Time.utc(2015, 5, 28)])
    results = OpenTimestamps.verify(df, chain: chain)
    assert_equal 1, results.size
    assert_equal 358_391, results.first.height
    assert_equal df.file_digest, results.first.digest
    assert OpenTimestamps.verified?(df, chain: chain)
  end

  def test_info_dump_names_the_block
    assert_match(/BITCOIN block #358391/, OpenTimestamps.info(hello_world))
  end
end
