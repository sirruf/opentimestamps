# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/), and this
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

Initial release: a pure-Ruby OpenTimestamps client with no runtime dependencies.

### Added

- `OpenTimestamps.stamp` and `.stamp_digest` submit a hash to the calendar
  servers (`stamp_digest` keeps the content itself private) and merge the
  replies, so one calendar being down is not fatal.
- `OpenTimestamps.upgrade` folds a calendar's Bitcoin path into a pending proof;
  `verify` / `verified?` check it against a block through a `Chain` oracle and
  fail closed.
- `DetachedTimestampFile` reads and writes the `.ots` file format.
- `Timestamp`, `Op`, and `Attestation` (Pending, Bitcoin, Unknown) model the wire
  format, with byte-exact serialization and unknown attestation types preserved
  intact.
- `Keccak256`, a pure-Ruby implementation of Ethereum's Keccak-256, for proofs
  that also anchor to Ethereum.
- `Chain::Explorer`, a public block-explorer oracle behind a small interface a
  Bitcoin node can replace.

The parser is hardened against untrusted input (depth, varuint, and message-size
caps; only `DeserializationError` on malformed bytes). Tested with byte-exact
round-trips of twelve reference vectors, an offline check against Bitcoin block
358391, and Keccak-256 known-answer vectors.

[Unreleased]: https://github.com/sirruf/opentimestamps/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sirruf/opentimestamps/releases/tag/v0.1.0
