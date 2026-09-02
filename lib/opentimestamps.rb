# frozen_string_literal: true

require "digest"

require_relative "opentimestamps/version"
require_relative "opentimestamps/error"
require_relative "opentimestamps/serialization"
require_relative "opentimestamps/operation"
require_relative "opentimestamps/attestation"
require_relative "opentimestamps/timestamp"
require_relative "opentimestamps/detached_file"
require_relative "opentimestamps/calendar"
require_relative "opentimestamps/chain"

# A pure-Ruby (zero runtime dependencies) client for OpenTimestamps: stamp a
# hash against Bitcoin via public calendars, upgrade to a block attestation,
# and verify — with proofs that outlive this library or any server.
#
#   ots = OpenTimestamps.stamp("hello world\n")   # => DetachedTimestampFile (pending)
#   File.binwrite("hello.txt.ots", ots.serialize) # persist! (or you cannot upgrade)
#   OpenTimestamps.upgrade(ots)                    # later: fold in the Bitcoin path
#   OpenTimestamps.verify(ots)                     # => [{height:, time:, verified:}]
module OpenTimestamps
  DEFAULT_CALENDARS = %w[
    https://alice.btc.calendar.opentimestamps.org
    https://bob.btc.calendar.opentimestamps.org
  ].freeze

  module_function

  # Stamp raw data: hashes it, then stamps the digest.
  def stamp(data, calendar: DEFAULT_CALENDARS.first, hash: :sha256)
    stamp_digest(digest_for(data, hash), calendar: calendar, hash: hash)
  end

  # Stamp an already-computed digest — the content itself never leaves the
  # caller (privacy / "sealed" mode). `hash` names the algorithm that produced
  # it, so verification knows the digest length.
  def stamp_digest(digest, calendar: DEFAULT_CALENDARS.first, hash: :sha256)
    len = DetachedTimestampFile::HASH_OPS.fetch(hash) { raise Error, "unsupported hash #{hash.inspect}" }
    raise Error, "digest must be #{len} bytes for #{hash}, got #{digest.bytesize}" unless digest.bytesize == len

    timestamp = Calendar.new(calendar).submit(digest.b)
    DetachedTimestampFile.new(Op.new(hash), timestamp)
  end

  # Try to upgrade every pending attestation to its Bitcoin path.
  # Returns true if anything changed. Persist the file afterwards.
  def upgrade(detached, timeout: 20)
    changed = false
    pendings = detached.timestamp.each_attestation.select { |_, a| a.pending? }
    pendings.each do |commitment, att|
      upgraded = Calendar.new(att.uri).upgrade(commitment, timeout: timeout)
      next unless upgraded

      node = detached.timestamp.find(commitment)
      node&.merge(upgraded)
      changed = true
    end
    changed
  end

  def verify(detached, chain: Chain::Explorer.new)
    results = detached.timestamp.verify(chain)
    raise VerificationError, "no Bitcoin attestation (still pending?)" if results.empty?

    results
  end

  # Human-readable dump of a proof's structure.
  def info(detached)
    lines = ["file digest (#{detached.file_hash_op.kind}): #{detached.file_digest.unpack1('H*')}"]
    detached.timestamp.each_attestation do |commitment, att|
      lines << "  #{att} @ #{commitment.unpack1('H*')[0, 32]}…"
    end
    lines.join("\n")
  end

  def digest_for(data, hash)
    case hash
    when :sha256 then Digest::SHA256.digest(data)
    when :sha1   then Digest::SHA1.digest(data)
    else raise Error, "unsupported hash #{hash.inspect}"
    end
  end
end
