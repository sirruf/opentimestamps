# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"

module OpenTimestamps
  # A chain oracle resolves a block height to its merkle root (in internal byte
  # order, matching what OTS operations produce) and its time. Verification
  # depends only on this interface, so a Bitcoin node can be dropped in for a
  # fully trustless check.
  module Chain
    # Public block explorer (Esplora API). Convenient, but trusts the explorer.
    class Explorer
      MAX_RESPONSE_BYTES = 1 << 20

      def initialize(base = "https://blockstream.info/api", timeout: 20)
        @base = base.chomp("/")
        @timeout = timeout
      end

      def block_merkle_root_and_time(height)
        hash = get("#{@base}/block-height/#{height}").strip
        blk = JSON.parse(get("#{@base}/block/#{hash}"))
        root_internal = [blk.fetch("merkle_root")].pack("H*").reverse # display -> internal
        [root_internal, Time.at(blk.fetch("timestamp")).utc]
      rescue JSON::ParserError, KeyError => e
        raise NetworkError, "explorer returned unexpected data: #{e.class}"
      end

      private

      def get(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        http.start do |conn|
          conn.request(Net::HTTP::Get.new(uri)) do |res|
            raise NetworkError, "explorer: HTTP #{res.code}" unless res.code == "200"

            return read_capped(res)
          end
        end
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
             OpenSSL::SSL::SSLError, IOError => e
        raise NetworkError, "explorer: #{e.class}: #{e.message}"
      end

      def read_capped(res)
        buffer = +"".b
        res.read_body do |chunk|
          buffer << chunk
          raise NetworkError, "explorer: response exceeds #{MAX_RESPONSE_BYTES} bytes" if buffer.bytesize > MAX_RESPONSE_BYTES
        end
        buffer
      end
    end
  end
end
