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

# Client for the OpenTimestamps protocol, in pure Ruby with no runtime
# dependencies.
#
#   ots = OpenTimestamps.stamp("hello world\n")   # DetachedTimestampFile (pending)
#   File.binwrite("hello.txt.ots", ots.serialize) # persist, or you cannot upgrade
#   OpenTimestamps.upgrade(ots)                    # hours later: fold in the Bitcoin path
#   OpenTimestamps.verify(ots)                     # => [Verification(height:, time:, digest:)]
module OpenTimestamps
  DEFAULT_CALENDARS = %w[
    https://alice.btc.calendar.opentimestamps.org
    https://bob.btc.calendar.opentimestamps.org
  ].freeze

  # One confirmed Bitcoin attestation: the block that anchors +digest+, and when.
  Verification = Struct.new(:height, :time, :digest, keyword_init: true)

  module_function

  # Stamp raw data: hash it, then stamp the digest.
  def stamp(data, calendars: DEFAULT_CALENDARS, hash: :sha256, timeout: 20)
    stamp_digest(digest_for(data, hash), calendars: calendars, hash: hash, timeout: timeout)
  end

  # Stamp an already-computed digest. The content itself never leaves the caller
  # (privacy / "sealed" mode). The digest is submitted to every calendar and the
  # replies are merged, so a single calendar being down is not fatal.
  def stamp_digest(digest, calendars: DEFAULT_CALENDARS, hash: :sha256, timeout: 20)
    DetachedTimestampFile.from_hash(digest, hash: hash) # validate digest length before any network

    merged = nil
    failures = []
    Array(calendars).each do |url|
      timestamp = Calendar.new(url).submit(digest, timeout: timeout)
      merged ? merged.merge(timestamp) : merged = timestamp
    rescue NetworkError => e
      failures << e.message
    end
    raise NetworkError, "every calendar failed: #{failures.join('; ')}" if merged.nil?

    DetachedTimestampFile.new(Op.new(hash), merged)
  end

  # Ask each pending calendar to upgrade to its Bitcoin path, folding the result
  # in. Returns true if anything changed; persist the file afterwards. A calendar
  # that is unreachable is skipped, not fatal.
  def upgrade(detached, timeout: 20)
    return false if detached.timestamp.each_attestation.any? { |_, att| att.bitcoin? }

    changed = false
    detached.timestamp.each_attestation.select { |_, att| att.pending? }.each do |commitment, att|
      upgraded = begin
        Calendar.new(att.uri).upgrade(commitment, timeout: timeout)
      rescue NetworkError
        nil
      end
      next unless upgraded

      detached.timestamp.find(commitment)&.merge(upgraded)
      changed = true
    end
    changed
  end

  # Verify against the chain, failing closed: raises VerificationError unless at
  # least one Bitcoin attestation matches its block. Returns the confirmed
  # attestations, each carrying the proven digest to compare with your document.
  def verify(detached, chain: Chain::Explorer.new)
    digest = detached.file_digest
    confirmed = detached.timestamp.verify(chain).select { |result| result[:verified] }
    raise VerificationError, "not anchored in Bitcoin (still pending, or the proof does not match)" if confirmed.empty?

    confirmed.map { |result| Verification.new(height: result[:height], time: result[:time], digest: digest) }
  end

  # Boolean form of verify that never raises.
  def verified?(detached, chain: Chain::Explorer.new)
    !verify(detached, chain: chain).empty?
  rescue VerificationError
    false
  end

  # Human-readable dump of a proof's structure.
  def info(detached)
    lines = ["file digest (#{detached.file_hash_op.kind}): #{detached.file_digest.unpack1('H*')}"]
    detached.timestamp.each_attestation do |commitment, att|
      lines << "  #{att} @ #{commitment.unpack1('H*')[0, 32]}..."
    end
    lines.join("\n")
  end

  def digest_for(data, hash)
    case hash
    when :sha256 then Digest::SHA256.digest(data)
    when :sha1   then Digest::SHA1.digest(data)
    else raise Error, "cannot hash raw data with #{hash.inspect}; pass a precomputed digest to stamp_digest"
    end
  end
  private_class_method :digest_for
end
