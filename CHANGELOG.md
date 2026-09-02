# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and versioning is [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-09-01

Initial release. A pure-Ruby, zero-dependency OpenTimestamps client.

### Added
- `OpenTimestamps.stamp` / `.stamp_digest` — submit a hash to a calendar server
  (`stamp_digest` keeps the content sealed: only the hash leaves the caller).
- `OpenTimestamps.upgrade` — fold a calendar's Bitcoin path into a pending proof.
- `OpenTimestamps.verify` — check a commitment against a block via a chain oracle.
- `DetachedTimestampFile` — read/write the `.ots` file format (magic header,
  file-hash op, timestamp tree).
- `Timestamp`, `Op`, `Attestation` (Pending / Bitcoin / Unknown) — the wire model,
  with byte-exact serialization and forward-compatible preservation of unknown
  attestation types.
- `Keccak256` — pure-Ruby Ethereum Keccak-256, for proofs that also anchor to
  Ethereum (Bitcoin proofs never use it).
- `Chain::Explorer` — a public block-explorer oracle; verification depends only on
  the `#block_merkle_root_and_time(height)` interface, so a Bitcoin node can be
  injected for a fully trustless check.

### Tested
- Byte-exact interop against 12 reference `.ots` vectors (incl. the Bitcoin
  whitepaper timestamp, multi-blockchain, unknown notaries, merkle trees).
- Real-block verification against Bitcoin block #358391 (deterministic).
- Keccak-256 known-answer vectors.

[Unreleased]: https://github.com/sirruf/opentimestamps/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sirruf/opentimestamps/releases/tag/v0.1.0
