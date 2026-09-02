# frozen_string_literal: true

module OpenTimestamps
  # Low-level wire primitives shared by every OTS structure: base-128 varuint,
  # length-prefixed varbytes, and the detached-file magic header.
  module Serialization
    # \x00 "OpenTimestamps" \x00\x00 "Proof" \x00 + 8-byte magic
    MAGIC = "\x00OpenTimestamps\x00\x00Proof\x00\xBF\x89\xE2\xE8\x84\xE8\x92\x94".b

    # Sequential byte reader over a binary string.
    class Reader
      def initialize(bytes)
        @b = bytes.b
        @i = 0
      end

      def eof? = @i >= @b.bytesize

      def rest = @b.byteslice(@i..) || "".b

      def u8
        byte = @b.getbyte(@i) or raise DeserializationError, "unexpected EOF"
        @i += 1
        byte
      end

      def read(n)
        s = @b.byteslice(@i, n)
        raise DeserializationError, "unexpected EOF (wanted #{n})" if s.nil? || s.bytesize < n
        @i += n
        s
      end

      # Base-128 little-endian varuint (MSB = continuation).
      def varuint
        result = 0
        shift = 0
        loop do
          byte = u8
          result |= (byte & 0x7f) << shift
          break if (byte & 0x80).zero?
          shift += 7
        end
        result
      end

      def varbytes = read(varuint)
    end

    # Sequential byte writer producing a binary string.
    class Writer
      def initialize = @s = +"".b

      def string = @s

      def u8(int)
        @s << int
        self
      end

      def write(bytes)
        @s << bytes.b
        self
      end

      def varuint(n)
        raise Error, "varuint must be non-negative" if n.negative?
        loop do
          byte = n & 0x7f
          n >>= 7
          byte |= 0x80 if n.positive?
          @s << byte
          break if n.zero?
        end
        self
      end

      def varbytes(bytes)
        varuint(bytes.bytesize)
        write(bytes)
      end
    end
  end
end
