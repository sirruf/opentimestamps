# frozen_string_literal: true

require "minitest/autorun"
require "opentimestamps"

# A deterministic, offline chain oracle for tests: maps a height to a fixed
# root and time, so verification runs with no network.
class FakeChain
  def initialize(map) = @map = map # height => [root_bytes, Time]
  def block_merkle_root_and_time(height)
    @map.fetch(height) { raise OpenTimestamps::Error, "no block #{height}" }
  end
end

# A stand-in Calendar for orchestration tests. Keyed by the commitment it is
# asked to upgrade; the value is either a Timestamp to return, nil (not anchored
# yet), or :fail (raises NetworkError, i.e. unreachable).
class FakeCalendar
  def initialize(responses) = @responses = responses # commitment_bytes => Timestamp | nil | :fail
  def upgrade(commitment, timeout: 20)
    response = @responses[commitment]
    raise OpenTimestamps::NetworkError, "unreachable" if response == :fail

    response
  end
end

module TestBuilders
  include OpenTimestamps

  # A pending proof plus the fake-calendar responses that would upgrade it.
  # +calendars+ is an array of [uri, outcome], where outcome is :ok, :pending
  # (404, not anchored yet), or :fail (unreachable). Returns [detached, factory,
  # chain] wired so OpenTimestamps.upgrade(detached, calendar_factory: factory)
  # then verify(detached, chain: chain) exercises the merge.
  def pending_proof(calendars)
    digest = "\x33".b * 32
    root = Timestamp.new(digest)
    responses = {}
    chain_map = {}
    calendars.each_with_index do |(uri, outcome), i|
      op = Op.new(:append, [i].pack("C"))
      commitment = op.apply(digest)
      leaf = Timestamp.new(commitment)
      leaf.attestations << Attestation::Pending.new(uri)
      root.ops[op] = leaf

      case outcome
      when :ok
        height = 700_000 + i
        upgraded = Timestamp.new(commitment)
        upgraded.attestations << Attestation::Bitcoin.new(height)
        responses[commitment] = upgraded
        chain_map[height] = [commitment, Time.utc(2024, 1, 1 + i)]
      when :pending then responses[commitment] = nil
      when :fail    then responses[commitment] = :fail
      end
    end

    detached = DetachedTimestampFile.new(Op.new(:sha256), root)
    factory = ->(_uri) { FakeCalendar.new(responses) }
    [detached, factory, FakeChain.new(chain_map)]
  end

  # A proof already carrying +count+ independent Bitcoin attestations, with a
  # matching FakeChain. Returns [detached, chain].
  def bitcoin_proof(count)
    digest = "\x22".b * 32
    root = Timestamp.new(digest)
    chain_map = {}
    count.times do |i|
      op = Op.new(:append, [i].pack("C"))
      commitment = op.apply(digest)
      leaf = Timestamp.new(commitment)
      height = 800_000 + i
      leaf.attestations << Attestation::Bitcoin.new(height)
      root.ops[op] = leaf
      chain_map[height] = [commitment, Time.utc(2024, 6, 1 + i)]
    end
    [DetachedTimestampFile.new(Op.new(:sha256), root), FakeChain.new(chain_map)]
  end
end
