# frozen_string_literal: true

module OpenTimestamps
  # Base class for every error this library raises.
  class Error < StandardError; end

  # Raised when a byte stream does not parse as a valid OTS structure. All
  # parsing of untrusted input funnels through this, never a raw Ruby error.
  class DeserializationError < Error; end

  # Raised when a proof does not verify against the chain (or has nothing to
  # verify yet).
  class VerificationError < Error; end

  # Raised when a calendar or chain oracle cannot be reached or answers badly.
  class NetworkError < Error; end

  # Raised by a chain oracle when the block a proof references does not exist (a
  # height past the chain tip, or a bogus attestation). This is a fact about the
  # proof, not an outage, so verification treats it as "not anchored" rather than
  # as an unreachable oracle.
  class BlockNotFound < Error; end
end
