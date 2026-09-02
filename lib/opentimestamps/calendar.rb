# frozen_string_literal: true

require "net/http"
require "uri"

module OpenTimestamps
  # HTTP client for an OpenTimestamps calendar server. The client never
  # broadcasts a Bitcoin transaction itself - the calendar aggregates many
  # digests into a single transaction. We only submit and later upgrade.
  class Calendar
    MIME = "application/vnd.opentimestamps.v1"

    attr_reader :url

    def initialize(url)
      @url = url.to_s.chomp("/")
    end

    # Submit a digest; returns a pending Timestamp rooted at that digest.
    def submit(digest, timeout: 20)
      body = post("#{@url}/digest", digest.b, timeout)
      Timestamp.deserialize(Serialization::Reader.new(body), digest.b)
    end

    # Ask the calendar to upgrade a commitment to its Bitcoin path.
    # Returns a Timestamp rooted at `commitment`, or nil if not anchored yet.
    def upgrade(commitment, timeout: 20)
      code, body = get("#{@url}/timestamp/#{commitment.unpack1('H*')}", timeout)
      return nil unless code == "200"

      Timestamp.deserialize(Serialization::Reader.new(body), commitment.b)
    end

    private

    def client(uri, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout
      http.read_timeout = timeout
      http
    end

    def post(url, body, timeout)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = MIME
      req["Accept"] = MIME
      req["User-Agent"] = "opentimestamps-ruby/#{VERSION}"
      req.body = body
      res = client(uri, timeout).request(req)
      raise Error, "calendar #{uri.host}: HTTP #{res.code}" unless res.code == "200"

      res.body
    end

    def get(url, timeout)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = MIME
      req["User-Agent"] = "opentimestamps-ruby/#{VERSION}"
      res = client(uri, timeout).request(req)
      [res.code, res.body]
    end
  end
end
