# frozen_string_literal: true

module OpenTimestamps
  # Wire primitives shared by every OTS structure: the base-128 varuint,
  # length-prefixed varbytes, and the detached-file magic header. The reader
  # treats its input as untrusted and only ever raises DeserializationError.
  module Serialization
    MAGIC = "\x00OpenTimestamps\x00\x00Proof\x00\xBF\x89\xE2\xE8\x84\xE8\x92\x94".b

    # Upper bound on any decoded varuint. Real lengths (bounded by a file) and
    # block heights fit comfortably; the cap stops a crafted length prefix from
    # producing a bignum that would blow up byteslice.
    MAX_VARUINT = (1 << 32) - 1

    class Reader
      def initialize(bytes)
        @b = bytes.b
        @i = 0
      end

      def eof? = @i >= @b.bytesize

      def rest = @b.byteslice(@i..) || "".b

      def u8
        byte = @b.getbyte(@i) or raise DeserializationError, "unexpected end of input"
        @i += 1
        byte
      end

      def read(n)
        raise DeserializationError, "want #{n} bytes, #{@b.bytesize - @i} left" if n > @b.bytesize - @i

        s = @b.byteslice(@i, n)
        @i += n
        s
      end

      def varuint
        result = 0
        shift = 0
        loop do
          byte = u8
          result |= (byte & 0x7f) << shift
          raise DeserializationError, "varuint out of range" if result > MAX_VARUINT

          break if (byte & 0x80).zero?

          shift += 7
        end
        result
      end

      def varbytes = read(varuint)
    end

    class Writer
      def initialize
        @string = +"".b
      end

      attr_reader :string

      def u8(int)
        @string << int
        self
      end

      def write(bytes)
        @string << bytes.b
        self
      end

      def varuint(n)
        raise Error, "varuint must be non-negative" if n.negative?

        loop do
          byte = n & 0x7f
          n >>= 7
          byte |= 0x80 if n.positive?
          @string << byte
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
