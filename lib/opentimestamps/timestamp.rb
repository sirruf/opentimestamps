# frozen_string_literal: true

module OpenTimestamps
  # A node in the timestamp tree: a message, the attestations that commit to it,
  # and the operations leading to child nodes. Serialization follows the OTS
  # wire format's 0x00 (attestation) / 0xff (fork) markers.
  class Timestamp
    # Caps that keep an untrusted proof from exhausting the process: a depth
    # limit (real proofs are shallow) and a per-node message-size limit that
    # bounds append/prepend growth.
    MAX_DEPTH = 1_000
    MAX_MSG_BYTES = 1 << 20

    attr_reader :msg, :attestations, :ops # ops: Hash[Op => Timestamp]

    def initialize(msg)
      @msg = msg.b
      @attestations = []
      @ops = {}
    end

    def self.deserialize(reader, initial_msg, depth = 0)
      raise DeserializationError, "timestamp nested too deeply" if depth > MAX_DEPTH

      node = new(initial_msg)
      tag = reader.u8
      while tag == 0xff # fork: another child follows at this node
        read_child(reader, node, reader.u8, depth)
        tag = reader.u8
      end
      read_child(reader, node, tag, depth) # the last (or only) child
      node
    end

    def self.read_child(reader, node, tag, depth)
      if tag == 0x00
        node.attestations << Attestation.deserialize(reader)
      else
        op = Op.deserialize(reader, tag)
        child_msg = op.apply(node.msg)
        raise DeserializationError, "commitment message too large" if child_msg.bytesize > MAX_MSG_BYTES

        node.ops[op] = deserialize(reader, child_msg, depth + 1)
      end
    end
    private_class_method :read_child

    def serialize(writer)
      total = @attestations.size + @ops.size
      raise Error, "timestamp node has no children" if total.zero?

      written = 0
      @attestations.each do |att|
        writer.u8(0xff) if (written += 1) < total
        writer.u8(0x00)
        att.serialize(writer)
      end
      @ops.each do |op, child|
        writer.u8(0xff) if (written += 1) < total
        op.serialize(writer)
        child.serialize(writer)
      end
      writer
    end

    # Yields [commitment_msg, attestation] for every attestation in the tree.
    def each_attestation(&block)
      return enum_for(:each_attestation) unless block

      @attestations.each { |att| block.call(@msg, att) }
      @ops.each_value { |child| child.each_attestation(&block) }
    end

    # First node whose message equals +target+, or nil.
    def find(target)
      return self if @msg == target

      @ops.each_value do |child|
        found = child.find(target)
        return found if found
      end
      nil
    end

    # Fold another timestamp rooted at the same message into this one (upgrade).
    def merge(other)
      raise Error, "cannot merge: message mismatch" unless other.msg == @msg

      other.attestations.each { |a| @attestations << a unless @attestations.include?(a) }
      other.ops.each do |op, child|
        if @ops.key?(op)
          @ops[op].merge(child)
        else
          @ops[op] = child
        end
      end
      self
    end

    # Checks every Bitcoin attestation against the chain oracle. Returns one
    # { height:, time:, verified: } entry per Bitcoin attestation.
    def verify(chain)
      each_attestation.filter_map do |commitment, att|
        next unless att.bitcoin?

        root, time = chain.block_merkle_root_and_time(att.height)
        { height: att.height, time: time, verified: commitment == root }
      end
    end
  end
end
