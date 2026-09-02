# frozen_string_literal: true

require "net/http"
require "uri"

module OpenTimestamps
  # HTTP client for an OpenTimestamps calendar server. The client never
  # broadcasts a Bitcoin transaction itself; the calendar aggregates many
  # digests into one transaction. We only submit and later upgrade.
  class Calendar
    MIME = "application/vnd.opentimestamps.v1"
    MAX_RESPONSE_BYTES = 1 << 20 # a calendar reply is a small commitment path

    attr_reader :url

    def initialize(url)
      @url = url.to_s.chomp("/")
    end

    # Submit a digest; returns a pending Timestamp rooted at that digest.
    def submit(digest, timeout: 20)
      req = Net::HTTP::Post.new(URI("#{@url}/digest"))
      req["Content-Type"] = MIME
      req.body = digest.b
      code, body = request(req, timeout)
      raise NetworkError, "calendar #{host}: HTTP #{code}" unless code == "200"

      Timestamp.deserialize(Serialization::Reader.new(body), digest.b)
    end

    # Ask the calendar to upgrade a commitment to its Bitcoin path. Returns a
    # Timestamp rooted at +commitment+, or nil if it is not anchored yet (404).
    def upgrade(commitment, timeout: 20)
      req = Net::HTTP::Get.new(URI("#{@url}/timestamp/#{commitment.unpack1('H*')}"))
      code, body = request(req, timeout)
      return nil if code == "404"
      raise NetworkError, "calendar #{host}: HTTP #{code}" unless code == "200"

      Timestamp.deserialize(Serialization::Reader.new(body), commitment.b)
    end

    private

    def host = URI(@url).host

    def request(req, timeout)
      uri = URI(@url)
      req["Accept"] = MIME
      req["User-Agent"] = "opentimestamps-ruby/#{VERSION}"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout

      http.start do |conn|
        conn.request(req) do |res|
          return [res.code, read_capped(res)]
        end
      end
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout,
           OpenSSL::SSL::SSLError, IOError => e
      raise NetworkError, "calendar #{host}: #{e.class}: #{e.message}"
    end

    def read_capped(res)
      buffer = +"".b
      res.read_body do |chunk|
        buffer << chunk
        raise NetworkError, "calendar #{host}: response exceeds #{MAX_RESPONSE_BYTES} bytes" if buffer.bytesize > MAX_RESPONSE_BYTES
      end
      buffer
    end
  end
end
