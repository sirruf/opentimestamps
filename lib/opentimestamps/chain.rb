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
    MAX_RESPONSE_BYTES = 1 << 20

    HEX64 = /\A[0-9a-fA-F]{64}\z/

    # Turn a block's display-order merkle-root hex into internal byte order, the
    # form an OTS commitment is compared against. Rejects anything that is not a
    # 32-byte hex string so junk from an oracle fails loudly, not as a silent
    # mismatch.
    def self.root_display_to_internal(hex)
      raise NetworkError, "chain oracle returned an invalid merkle root" unless hex.is_a?(String) && hex.match?(HEX64)

      [hex].pack("H*").reverse
    end

    # Public block explorer (Esplora API). Convenient, but trusts the explorer.
    class Explorer
      # Preserved for backward compatibility; the cap now lives on the module.
      MAX_RESPONSE_BYTES = Chain::MAX_RESPONSE_BYTES

      # +transport+ is an injection seam for tests and custom clients: a callable
      # taking a URL and returning the response body. It defaults to a capped
      # Net::HTTP GET.
      def initialize(base = "https://blockstream.info/api", timeout: 20, transport: nil)
        @base = base.chomp("/")
        @timeout = timeout
        @transport = transport
      end

      def block_merkle_root_and_time(height)
        hash = get("#{@base}/block-height/#{Integer(height)}").strip
        raise NetworkError, "explorer returned an invalid block hash" unless hash.match?(Chain::HEX64)

        blk = JSON.parse(get("#{@base}/block/#{hash}"))
        raise NetworkError, "explorer returned unexpected data" unless blk.is_a?(Hash)

        [Chain.root_display_to_internal(blk.fetch("merkle_root")), Time.at(Integer(blk.fetch("timestamp"))).utc]
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
        raise NetworkError, "explorer returned unexpected data: #{e.class}"
      end

      private

      def get(url)
        return @transport.call(url) if @transport

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        http.start do |conn|
          conn.request(Net::HTTP::Get.new(uri)) do |res|
            raise NetworkError, "explorer: HTTP #{res.code}" unless res.code == "200"

            return Chain.read_capped(res) { |n| "explorer: response exceeds #{n} bytes" }
          end
        end
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
             OpenSSL::SSL::SSLError, IOError => e
        raise NetworkError, "explorer: #{e.class}: #{e.message}"
      end
    end

    # Your own Bitcoin Core node over JSON-RPC. Trusts nothing external: the
    # merkle root and time come straight from the block header your node holds.
    #
    #   Chain::BitcoinCore.new("http://127.0.0.1:8332", user: "rpcuser", password: "secret")
    #
    # Credentials may also be embedded in the URL (http://user:pass@host:port) or
    # read from the node's cookie file (Chain::BitcoinCore.from_cookie(path)).
    class BitcoinCore
      # +transport+ is an injection seam for tests: a callable taking the request
      # body (a JSON string) and returning the response body. It defaults to a
      # capped Net::HTTP POST with basic auth.
      def initialize(url = "http://127.0.0.1:8332", user: nil, password: nil, timeout: 20, transport: nil)
        @uri = URI(url)
        # userinfo is percent-encoded per RFC 3986, not form-encoded, so "+" is a
        # literal plus, not a space.
        @user = user || unescape(@uri.user)
        @password = password || unescape(@uri.password)
        @timeout = timeout
        @transport = transport
      rescue URI::InvalidURIError => e
        raise Error, "invalid node URL: #{e.message}"
      end

      # Build a client from a node's .cookie file (contents are "__cookie__:hex").
      def self.from_cookie(cookie_path, url = "http://127.0.0.1:8332", **opts)
        user, password = File.read(cookie_path).strip.split(":", 2)
        raise Error, "malformed cookie file #{cookie_path}" unless user && password

        new(url, user: user, password: password, **opts)
      end

      def block_merkle_root_and_time(height)
        hash = rpc("getblockhash", [Integer(height)])
        raise NetworkError, "bitcoind returned an invalid block hash" unless hash.is_a?(String)

        header = rpc("getblockheader", [hash])
        raise NetworkError, "bitcoind returned unexpected data" unless header.is_a?(Hash)

        [Chain.root_display_to_internal(header.fetch("merkleroot")), Time.at(Integer(header.fetch("time"))).utc]
      rescue KeyError, TypeError, ArgumentError => e
        raise NetworkError, "bitcoind returned unexpected data: #{e.class}"
      end

      private

      def unescape(str)
        str && URI::DEFAULT_PARSER.unescape(str)
      end

      def rpc(method, params)
        body = JSON.generate(jsonrpc: "1.0", id: "opentimestamps", method: method, params: params)
        parsed = JSON.parse(post(body))
        raise NetworkError, "bitcoind returned a non-object JSON-RPC response" unless parsed.is_a?(Hash)

        if (error = parsed["error"])
          message = error.is_a?(Hash) ? error["message"] : error
          raise NetworkError, "bitcoind error: #{message}"
        end

        parsed.fetch("result")
      rescue JSON::ParserError => e
        raise NetworkError, "bitcoind returned non-JSON: #{e.class}"
      end

      def post(body)
        return @transport.call(body) if @transport

        req = Net::HTTP::Post.new(@uri)
        req["Content-Type"] = "application/json"
        req.basic_auth(@user, @password) if @user
        req.body = body

        http = Net::HTTP.new(@uri.host, @uri.port)
        http.use_ssl = (@uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        http.start do |conn|
          conn.request(req) do |res|
            # bitcoind answers 200 on success and 500 with a JSON error body for
            # RPC-level errors (parsed in #rpc). Any other status is a transport or
            # auth failure, not a usable response.
            raise NetworkError, "bitcoind: HTTP #{res.code}" unless %w[200 500].include?(res.code)

            return Chain.read_capped(res) { |n| "bitcoind: response exceeds #{n} bytes" }
          end
        end
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
             OpenSSL::SSL::SSLError, IOError => e
        raise NetworkError, "bitcoind: #{e.class}: #{e.message}"
      end
    end

    # Stream a response body, capping its size. The block builds the error message
    # so each caller names itself.
    def self.read_capped(res)
      buffer = +"".b
      res.read_body do |chunk|
        buffer << chunk
        raise NetworkError, yield(MAX_RESPONSE_BYTES) if buffer.bytesize > MAX_RESPONSE_BYTES
      end
      buffer
    end
  end
end
