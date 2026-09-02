# frozen_string_literal: true

module OpenTimestamps
  # A `.ots` detached timestamp file: a magic header, a version, the operation
  # used to hash the original file, and the timestamp of that file hash.
  class DetachedTimestampFile
    # hash op kind => [tag, digest length]
    HASH_OPS = { sha1: 20, ripemd160: 20, sha256: 32 }.freeze

    attr_reader :file_hash_op, :timestamp

    def initialize(file_hash_op, timestamp)
      @file_hash_op = file_hash_op
      @timestamp = timestamp
    end

    # Build a fresh, unstamped file from an already-computed digest.
    def self.from_hash(digest, hash: :sha256)
      new(Op.new(hash), Timestamp.new(digest))
    end

    def self.deserialize(bytes)
      reader = Serialization::Reader.new(bytes)
      magic = reader.read(Serialization::MAGIC.bytesize)
      raise DeserializationError, "not an .ots file (bad magic)" unless magic == Serialization::MAGIC

      _major = reader.varuint
      tag = reader.u8
      kind = Op::UNARY[tag]
      len = HASH_OPS[kind]
      raise DeserializationError, format("unsupported file-hash op 0x%02x", tag) unless len

      digest = reader.read(len)
      new(Op.new(kind), Timestamp.deserialize(reader, digest))
    end

    def serialize
      w = Serialization::Writer.new
      w.write(Serialization::MAGIC).varuint(1)
      w.u8(Op::TAG.fetch(@file_hash_op.kind))
      w.write(@timestamp.msg)
      @timestamp.serialize(w)
      w.string
    end

    def file_digest = @timestamp.msg
  end
end
