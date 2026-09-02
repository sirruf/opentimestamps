# frozen_string_literal: true

module OpenTimestamps
  # A leaf claim about a commitment: a pending calendar promise, a Bitcoin block
  # header, or an unknown type preserved verbatim for forward compatibility.
  module Attestation
    PENDING_TAG = "\x83\xDF\xE3\x0D\x2E\xF9\x0C\x8E".b
    BITCOIN_TAG = "\x05\x88\x96\x0D\x73\xD7\x19\x01".b

    # tag (8 bytes) + varbytes(payload). The length prefix lets us skip — and
    # re-emit — attestation types we do not understand.
    def self.deserialize(reader)
      tag = reader.read(8)
      payload = reader.varbytes
      inner = Serialization::Reader.new(payload)
      case tag
      when PENDING_TAG then Pending.new(inner.varbytes.force_encoding("UTF-8"))
      when BITCOIN_TAG then Bitcoin.new(inner.varuint)
      else Unknown.new(tag, payload)
      end
    end

    class Base
      def bitcoin? = false
      def pending? = false
    end

    # A calendar server has accepted the commitment but it is not yet in a block.
    class Pending < Base
      attr_reader :uri

      def initialize(uri) = @uri = uri
      def pending? = true

      def serialize(writer)
        inner = Serialization::Writer.new.varbytes(@uri.b)
        writer.write(PENDING_TAG).varbytes(inner.string)
      end

      def ==(other) = other.is_a?(Pending) && other.uri == @uri
      alias eql? ==
      def hash = [Pending, @uri].hash
      def to_s = "PENDING #{@uri}"
    end

    # The commitment equals the merkle root of Bitcoin block `height`.
    class Bitcoin < Base
      attr_reader :height

      def initialize(height) = @height = height
      def bitcoin? = true

      def serialize(writer)
        inner = Serialization::Writer.new.varuint(@height)
        writer.write(BITCOIN_TAG).varbytes(inner.string)
      end

      def ==(other) = other.is_a?(Bitcoin) && other.height == @height
      alias eql? ==
      def hash = [Bitcoin, @height].hash
      def to_s = "BITCOIN block ##{@height}"
    end

    # An attestation type this version does not model; kept byte-for-byte so
    # round-tripping never corrupts a proof (e.g. Litecoin, Ethereum, future).
    class Unknown < Base
      attr_reader :tag, :payload

      def initialize(tag, payload)
        @tag = tag.b
        @payload = payload.b
      end

      def serialize(writer) = writer.write(@tag).varbytes(@payload)

      def ==(other) = other.is_a?(Unknown) && other.tag == @tag && other.payload == @payload
      alias eql? ==
      def hash = [Unknown, @tag, @payload].hash
      def to_s = "UNKNOWN(#{@tag.unpack1('H*')})"
    end
  end
end
