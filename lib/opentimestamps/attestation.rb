# frozen_string_literal: true

module OpenTimestamps
  # A leaf claim about a commitment: a pending calendar promise, a Bitcoin block
  # header, or an unknown type kept verbatim for forward compatibility.
  module Attestation
    PENDING_TAG = "\x83\xDF\xE3\x0D\x2E\xF9\x0C\x8E".b
    BITCOIN_TAG = "\x05\x88\x96\x0D\x73\xD7\x19\x01".b

    # Layout: an 8-byte tag then a length-prefixed payload. The length prefix
    # means an unknown tag can be preserved whole. For a known tag we require
    # the payload to be fully consumed, so a crafted trailing byte is rejected
    # rather than silently dropped.
    def self.deserialize(reader)
      tag = reader.read(8)
      payload = reader.varbytes
      return Unknown.new(tag, payload) unless [PENDING_TAG, BITCOIN_TAG].include?(tag)

      inner = Serialization::Reader.new(payload)
      att = tag == PENDING_TAG ? Pending.new(inner.varbytes) : Bitcoin.new(inner.varuint)
      raise DeserializationError, "trailing bytes in attestation payload" unless inner.eof?

      att
    end

    # Value equality across attestation types, keyed on each type's components.
    class Base
      def bitcoin? = false
      def pending? = false

      def ==(other)
        other.class == self.class && other.components == components
      end
      alias eql? ==

      def hash = [self.class, *components].hash
    end

    # A calendar has accepted the commitment; it is not yet in a block.
    class Pending < Base
      attr_reader :uri

      def initialize(uri)
        @uri = uri.dup.force_encoding("UTF-8")
      end

      def pending? = true
      def components = [@uri]
      def sort_key = [PENDING_TAG, @uri.b]
      def to_s = "PENDING #{@uri}"

      def serialize(writer)
        inner = Serialization::Writer.new.varbytes(@uri.b)
        writer.write(PENDING_TAG).varbytes(inner.string)
      end
    end

    # The commitment equals the merkle root of Bitcoin block +height+.
    class Bitcoin < Base
      attr_reader :height

      def initialize(height)
        @height = height
      end

      def bitcoin? = true
      def components = [@height]
      def sort_key = [BITCOIN_TAG, @height]
      def to_s = "BITCOIN block ##{@height}"

      def serialize(writer)
        inner = Serialization::Writer.new.varuint(@height)
        writer.write(BITCOIN_TAG).varbytes(inner.string)
      end
    end

    # A type this version does not model (Litecoin, Ethereum, or something newer)
    # carried through untouched so a round-trip never corrupts the proof.
    class Unknown < Base
      attr_reader :tag, :payload

      def initialize(tag, payload)
        @tag = tag.b
        @payload = payload.b
      end

      def components = [@tag, @payload]
      def sort_key = [@tag, @payload]
      def to_s = "UNKNOWN(#{@tag.unpack1('H*')})"

      def serialize(writer)
        writer.write(@tag).varbytes(@payload)
      end
    end
  end
end
