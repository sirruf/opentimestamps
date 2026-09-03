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

  # Builds a Calendar from a URL. Overridable in stamp_digest / upgrade as an
  # injection seam for tests and custom transports.
  DEFAULT_CALENDAR_FACTORY = ->(url) { Calendar.new(url) }

  module_function

  # Stamp raw data: hash it, then stamp the digest.
  def stamp(data, calendars: DEFAULT_CALENDARS, hash: :sha256, timeout: 20)
    stamp_digest(digest_for(data, hash), calendars: calendars, hash: hash, timeout: timeout)
  end

  # Stamp an already-computed digest. The content itself never leaves the caller
  # (privacy / "sealed" mode). The digest is submitted to every calendar and the
  # replies are merged, so a single calendar being down is not fatal.
  def stamp_digest(digest, calendars: DEFAULT_CALENDARS, hash: :sha256, timeout: 20,
                   calendar_factory: DEFAULT_CALENDAR_FACTORY)
    DetachedTimestampFile.from_hash(digest, hash: hash) # validate digest length before any network

    merged = nil
    failures = []
    Array(calendars).each do |url|
      timestamp = calendar_factory.call(url).submit(digest, timeout: timeout)
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
  def upgrade(detached, timeout: 20, calendar_factory: DEFAULT_CALENDAR_FACTORY)
    before = detached.serialize

    detached.timestamp.each_attestation.select { |_, att| att.pending? }.each do |commitment, att|
      node = detached.timestamp.find(commitment)
      # Skip a calendar whose commitment is already anchored at this leaf, but keep
      # going for the others: with two calendars, one may anchor days before the
      # other, and a later upgrade must still fold the second one in (so quorum > 1
      # can eventually be met).
      next if node&.attestations&.any?(&:bitcoin?)

      upgraded = begin
        calendar_factory.call(att.uri).upgrade(commitment, timeout: timeout)
      rescue NetworkError
        nil
      end
      node&.merge(upgraded) if upgraded
    end

    detached.serialize != before
  end

  # Verify against the chain, failing closed: raises VerificationError unless the
  # proof is anchored in at least +quorum+ distinct Bitcoin blocks. Returns one
  # confirmed attestation per distinct block, each carrying the proven digest to
  # compare with your document.
  #
  # +quorum+ counts distinct block heights, not raw attestations: several tree
  # paths that prove the same anchor collapse to one, so a single anchor (however
  # a calendar dresses it up) can never satisfy quorum > 1. Requiring quorum > 1
  # therefore means the document is provably in that many separate blocks.
  def verify(detached, chain: Chain::Explorer.new, quorum: 1)
    raise Error, "quorum must be a positive integer" unless quorum.is_a?(Integer) && quorum >= 1

    digest = detached.file_digest
    results = detached.timestamp.verify(chain)
    confirmed = results.select { |result| result[:verified] }
                       .uniq { |result| [result[:height], result[:commitment]] }
    confirmed_heights = confirmed.map { |result| result[:height] }.uniq

    if confirmed_heights.size < quorum
      outage_heights = results.select { |result| result[:error] }.map { |result| result[:height] }.uniq
      # The best case even if every unreachable block eventually confirmed. If that
      # still falls short, the quorum is unreachable for this proof no matter the
      # oracle, so it is a verification failure, not an outage.
      if (confirmed_heights | outage_heights).size < quorum
        raise VerificationError,
              "not anchored in #{quorum} distinct Bitcoin block(s) " \
              "(confirmed #{confirmed_heights.size}; still pending, or the proof does not match)"
      end

      # A reachable quorum is only blocked by the oracle being down for some blocks:
      # a transient outage, carried with its cause so the real reason is not lost.
      cause = results.filter_map { |result| result[:error] }.first
      raise NetworkError,
            "chain oracle unreachable for #{(outage_heights - confirmed_heights).size} block(s); " \
            "confirmed #{confirmed_heights.size} of #{quorum} required (#{cause&.message})",
            cause: cause
    end

    confirmed.map { |result| Verification.new(height: result[:height], time: result[:time], digest: digest) }
  end

  # Boolean form of verify: returns false instead of raising when a proof does
  # not verify. A misused +quorum+ (Error) or an unreachable chain (NetworkError)
  # still propagates, since those are not verification outcomes.
  def verified?(detached, chain: Chain::Explorer.new, quorum: 1)
    !verify(detached, chain: chain, quorum: quorum).empty?
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

  # Hash +data+ with a given file-hash op kind (:sha1, :ripemd160, :sha256), used
  # to bind a proof to a document. Unlike digest_for, this covers every op a
  # `.ots` file can carry as its file hash.
  def digest_for_kind(data, kind)
    raise Error, "#{kind.inspect} is not a valid file-hash op" unless DetachedTimestampFile::HASH_OPS.key?(kind)

    Op.new(kind).apply(data)
  end

  # Stream a file through a file-hash op, so a large file is never read whole into
  # memory. Same result as digest_for_kind(File.binread(path), kind).
  def digest_file(path, kind)
    raise Error, "#{kind.inspect} is not a valid file-hash op" unless DetachedTimestampFile::HASH_OPS.key?(kind)

    digest = case kind
             when :sha256 then Digest::SHA256.new
             when :sha1   then Digest::SHA1.new
             when :ripemd160
               begin
                 OpenSSL::Digest.new("RIPEMD160")
               rescue OpenSSL::Digest::DigestError => e
                 raise Error, "ripemd160 unavailable (enable the OpenSSL legacy provider): #{e.message}"
               end
             end
    File.open(path, "rb") do |file|
      while (chunk = file.read(64 * 1024))
        digest.update(chunk)
      end
    end
    digest.digest
  end
end
