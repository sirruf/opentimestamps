# frozen_string_literal: true

require "digest"
require "openssl"
require_relative "keccak256"

module OpenTimestamps
  # A commitment operation: either a binary op that folds an argument into the
  # message (append / prepend) or a unary cryptographic digest (sha1 / ripemd160
  # / sha256). Operations are the edges of a timestamp tree.
  class Op
    UNARY  = { 0x02 => :sha1, 0x03 => :ripemd160, 0x08 => :sha256, 0x67 => :keccak256 }.freeze
    BINARY = { 0xf0 => :append, 0xf1 => :prepend }.freeze
    TAG    = UNARY.merge(BINARY).invert.freeze

    attr_reader :kind, :arg

    def initialize(kind, arg = nil)
      raise Error, "unknown op #{kind}" unless TAG.key?(kind)
      raise Error, "#{kind} takes no argument" if arg && UNARY.value?(kind)
      raise Error, "#{kind} requires an argument" if arg.nil? && BINARY.value?(kind)

      @kind = kind
      @arg = arg&.b
    end

    def binary? = BINARY.value?(@kind)

    # Apply the operation to a message, returning the new bytes.
    def apply(msg)
      case @kind
      when :append   then msg + @arg
      when :prepend  then @arg + msg
      when :sha256    then Digest::SHA256.digest(msg)
      when :sha1      then Digest::SHA1.digest(msg)
      when :keccak256 then Keccak256.digest(msg)
      when :ripemd160
        # OpenSSL 3 hides RIPEMD160 behind the legacy provider; surface a clear error.
        OpenSSL::Digest.digest("RIPEMD160", msg)
      end
    rescue OpenSSL::Digest::DigestError => e
      raise Error, "ripemd160 unavailable (enable the OpenSSL legacy provider): #{e.message}"
    end

    def serialize(writer)
      writer.u8(TAG.fetch(@kind))
      writer.varbytes(@arg) if binary?
      writer
    end

    def self.deserialize(reader, tag)
      if BINARY.key?(tag)
        new(BINARY[tag], reader.varbytes)
      elsif UNARY.key?(tag)
        new(UNARY[tag])
      else
        raise DeserializationError, format("unknown operation tag 0x%02x", tag)
      end
    end

    # Value equality so Ops work as Hash keys in a timestamp tree.
    def ==(other) = other.is_a?(Op) && other.kind == @kind && other.arg == @arg
    alias eql? ==
    def hash = [@kind, @arg].hash

    def to_s = binary? ? "#{@kind}(#{@arg.unpack1('H*')})" : @kind.to_s
  end
end
