# frozen_string_literal: true

require_relative "lib/opentimestamps/version"

Gem::Specification.new do |spec|
  spec.name        = "opentimestamps"
  spec.version     = OpenTimestamps::VERSION
  spec.summary     = "Pure-Ruby OpenTimestamps client: Bitcoin-anchored timestamps, zero dependencies."
  spec.description = <<~DESC
    A dependency-free Ruby implementation of the OpenTimestamps protocol: stamp a
    hash against the Bitcoin blockchain via public calendar servers, upgrade the
    proof to a block attestation, and verify it — using only the standard library.
    Proofs are self-verifying and outlive both this gem and any single server.
  DESC

  spec.authors  = ["Artem Kolesnikov"]
  spec.email    = ["you@example.com"] # TODO: set contact email before publishing
  spec.homepage = "https://github.com/OWNER/opentimestamps-ruby" # TODO
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # No runtime dependencies — stdlib only (digest, openssl, net/http, json).
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"

  spec.metadata["rubygems_mfa_required"] = "true"
end
