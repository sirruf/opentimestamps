# frozen_string_literal: true

module OpenTimestamps
  # Base class for every error this library raises.
  class Error < StandardError; end

  # Raised when the byte stream does not parse as a valid OTS structure.
  class DeserializationError < Error; end

  # Raised when a proof cannot be verified against the chain.
  class VerificationError < Error; end
end
