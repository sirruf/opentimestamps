# frozen_string_literal: true

module OpenTimestamps
  # A node in the timestamp tree: a message plus the attestations that commit to
  # it and the operations that lead to child nodes. Serialization mirrors the
  # OTS wire format's 0x00 (attestation) / 0xff (fork) markers.
  class Timestamp
    attr_reader :msg, :attestations, :ops # ops: Hash[Op => Timestamp]

    def initialize(msg)
      @msg = msg.b
      @attestations = []
      @ops = {}
    end

    def self.deserialize(reader, initial_msg)
      ts = new(initial_msg)
      tag = reader.u8
      while tag == 0xff # fork: another child follows at this node
        ts.__send__(:read_child, reader, reader.u8)
        tag = reader.u8
      end
      ts.__send__(:read_child, reader, tag) # the last (or only) child
      ts
    end

    def serialize(writer)
      children = @attestations.map { |a| [:att, a] } +
                 @ops.map { |op, child| [:op, op, child] }
      raise Error, "timestamp node has no children" if children.empty?

      children.each_with_index do |child, i|
        writer.u8(0xff) unless i == children.size - 1
        if child[0] == :att
          writer.u8(0x00)
          child[1].serialize(writer)
        else
          child[1].serialize(writer) # op tag (+ arg)
          child[2].serialize(writer) # recurse
        end
      end
      writer
    end

    # Yields [commitment_msg, attestation] for every attestation in the tree.
    def each_attestation(&block)
      return enum_for(:each_attestation) unless block

      @attestations.each { |att| block.call(@msg, att) }
      @ops.each_value { |child| child.each_attestation(&block) }
    end

    # First node whose message equals `target`, or nil.
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
        @ops.key?(op) ? @ops[op].merge(child) : @ops[op] = child
      end
      self
    end

    # Verify every Bitcoin attestation against a chain oracle.
    # Returns [{ height:, time:, verified: }], one per Bitcoin attestation.
    def verify(chain)
      each_attestation.filter_map do |commitment, att|
        next unless att.bitcoin?

        root, time = chain.block_merkle_root_and_time(att.height)
        { height: att.height, time: time, verified: commitment == root }
      end
    end

    private

    def read_child(reader, tag)
      if tag == 0x00
        @attestations << Attestation.deserialize(reader)
      else
        op = Op.deserialize(reader, tag)
        @ops[op] = Timestamp.deserialize(reader, op.apply(@msg))
      end
    end
  end
end
