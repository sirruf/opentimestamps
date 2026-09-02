# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"

module OpenTimestamps
  # Chain oracles resolve a block height to its merkle root (in internal byte
  # order, matching what OTS operations produce) and its time. Verification
  # depends only on this interface, never on a specific provider — inject your
  # own Bitcoin node for a fully trustless check.
  module Chain
    # Public block explorer (Esplora API). Convenient, but trusts the explorer.
    class Explorer
      def initialize(base = "https://blockstream.info/api", timeout: 20)
        @base = base.chomp("/")
        @timeout = timeout
      end

      def block_merkle_root_and_time(height)
        hash = get("#{@base}/block-height/#{height}").strip
        blk = JSON.parse(get("#{@base}/block/#{hash}"))
        root_internal = [blk.fetch("merkle_root")].pack("H*").reverse # display -> internal
        [root_internal, Time.at(blk.fetch("timestamp")).utc]
      end

      private

      def get(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        res = http.get(uri)
        raise Error, "explorer: HTTP #{res.code}" unless res.code == "200"

        res.body
      end
    end

    # TODO: BitcoinCore — a JSON-RPC adapter (getblockhash + getblockheader)
    # for verification against your own node with no third party trusted.
    # Same interface: #block_merkle_root_and_time(height) -> [root_internal, Time].
  end
end
