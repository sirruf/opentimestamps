# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

class ChainTest < Minitest::Test
  include OpenTimestamps

  # A known merkle root in internal (commitment) byte order; the display form a
  # node or explorer returns is its reverse.
  INTERNAL_ROOT = ["007ee445d23ad061af4a36b809501fab1ac4f2d7e7a739817dd0cbb7ec661b8a"].pack("H*").freeze
  DISPLAY_HEX   = INTERNAL_ROOT.reverse.unpack1("H*").freeze
  TIME_UNIX     = 1_432_847_673

  # --- Explorer ---

  def test_explorer_converts_display_root_to_internal
    transport = lambda do |url|
      if url.include?("/block-height/")
        "0" * 64
      else
        JSON.generate("merkle_root" => DISPLAY_HEX, "timestamp" => TIME_UNIX)
      end
    end
    root, time = Chain::Explorer.new(transport: transport).block_merkle_root_and_time(358_391)
    assert_equal INTERNAL_ROOT, root
    assert_equal Time.at(TIME_UNIX).utc, time
  end

  def test_explorer_wraps_bad_json_as_network_error
    transport = ->(url) { url.include?("/block-height/") ? "hash" : "not json" }
    assert_raises(NetworkError) { Chain::Explorer.new(transport: transport).block_merkle_root_and_time(1) }
  end

  # --- BitcoinCore ---

  def bitcoind(map)
    lambda do |body|
      req = JSON.parse(body)
      JSON.generate("result" => map.fetch(req.fetch("method")).call(req.fetch("params")), "error" => nil)
    end
  end

  def test_bitcoincore_reads_header_root_and_time
    transport = bitcoind(
      "getblockhash"   => ->(params) { assert_equal [358_391], params; "thehash" },
      "getblockheader" => ->(params) { assert_equal ["thehash"], params; { "merkleroot" => DISPLAY_HEX, "time" => TIME_UNIX } }
    )
    root, time = Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(358_391)
    assert_equal INTERNAL_ROOT, root
    assert_equal Time.at(TIME_UNIX).utc, time
  end

  def test_bitcoincore_surfaces_rpc_error
    # A generic RPC error (not a block-not-found code) is a NetworkError.
    transport = ->(_body) { JSON.generate("result" => nil, "error" => { "code" => -1, "message" => "misc failure" }) }
    err = assert_raises(NetworkError) { Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(1) }
    assert_match(/misc failure/, err.message)
  end

  def test_bitcoincore_wraps_non_json_as_network_error
    transport = ->(_body) { "<html>502</html>" }
    assert_raises(NetworkError) { Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(1) }
  end

  def test_bitcoincore_raises_block_not_found_on_out_of_range
    transport = ->(_body) { JSON.generate("result" => nil, "error" => { "code" => -8, "message" => "Block height out of range" }) }
    assert_raises(OpenTimestamps::BlockNotFound) { Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(10**9) }
  end

  def test_bitcoincore_rejects_response_with_mismatched_id
    # A response echoing an id other than the one we sent (the id is random per call).
    transport = ->(_body) { JSON.generate("result" => "abc", "error" => nil, "id" => "someone-elses-id") }
    err = assert_raises(NetworkError) { Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(1) }
    assert_match(/id mismatch/, err.message)
  end

  def test_bitcoincore_surfaces_error_even_when_id_is_null
    # bitcoind returns id: null with request-level errors; the error message must
    # win over the id check.
    transport = ->(_body) { JSON.generate("result" => nil, "error" => { "code" => -32_700, "message" => "Parse error" }, "id" => nil) }
    err = assert_raises(NetworkError) { Chain::BitcoinCore.new(transport: transport).block_merkle_root_and_time(1) }
    assert_match(/Parse error/, err.message)
  end

  def test_explorer_raises_block_not_found_on_404
    # The real Explorer maps 404 to BlockNotFound before block_merkle_root_and_time
    # rewraps anything; here we exercise that mapping through a stub subclass.
    explorer = Chain::Explorer.new
    def explorer.get(_url) = raise(OpenTimestamps::BlockNotFound, "explorer: block not found (HTTP 404)")
    assert_raises(OpenTimestamps::BlockNotFound) { explorer.block_merkle_root_and_time(10**9) }
  end

  def test_bitcoincore_decodes_url_credentials_per_rfc3986
    # Percent-decoding, not form-decoding: %40 -> "@", %20 -> " ", and a literal
    # "+" stays a "+" (a form decoder would turn it into a space).
    client = Chain::BitcoinCore.new("http://rpc%40user:p+s%20s@127.0.0.1:8332")
    assert_equal "rpc@user", client.send(:instance_variable_get, :@user)
    assert_equal "p+s s", client.send(:instance_variable_get, :@password)
  end

  def test_bitcoincore_wraps_invalid_url
    assert_raises(OpenTimestamps::Error) { Chain::BitcoinCore.new("http://u:p%zz@host:8332") }
  end

  def test_from_cookie_reads_user_and_password
    Dir.mktmpdir do |dir|
      cookie = File.join(dir, ".cookie")
      File.write(cookie, "__cookie__:deadbeef\n")
      client = Chain::BitcoinCore.from_cookie(cookie)
      assert_instance_of Chain::BitcoinCore, client
    end
  end

  def test_from_cookie_rejects_malformed_file
    Dir.mktmpdir do |dir|
      cookie = File.join(dir, ".cookie")
      File.write(cookie, "no-colon-here")
      assert_raises(OpenTimestamps::Error) { Chain::BitcoinCore.from_cookie(cookie) }
    end
  end
end
