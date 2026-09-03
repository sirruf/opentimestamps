# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/), and this
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0]

### Added

- `OpenTimestamps.digest_file` streams a file through a file-hash op, so the `ots`
  CLI no longer reads a whole file into memory to stamp or verify it.

### Changed

- `verify` tolerates a chain oracle that is unreachable for some blocks: if the
  reachable anchors already meet the quorum it succeeds; if a quorum is reachable
  but blocked by the outage it raises `NetworkError` (carrying the underlying
  cause) rather than `VerificationError`; and if the quorum is unreachable no
  matter the oracle it still raises `VerificationError`. A transient outage is
  never reported as a failed proof, and an impossible quorum is never reported as
  an outage.
- A chain oracle now signals a nonexistent block with the new `BlockNotFound`
  (HTTP 404 for the explorer, RPC -8/-5 for a node), which `verify` treats as "not
  anchored" (a `VerificationError`), not as an outage.
- **Breaking for direct callers of `Timestamp#verify`:** each result now includes
  an `error:` field, and `verified: false` can mean either a root mismatch or an
  oracle that could not be reached (check `error`). The high-level `verify` /
  `verified?` API is unchanged.

### Hardened

- `BitcoinCore` tags each JSON-RPC call with a unique id and rejects a response
  that does not echo it (a stale or mixed-up connection), after surfacing any
  bitcoind error first.
- More transport failures (`Timeout::Error`, `Net::ProtocolError`) are wrapped as
  `NetworkError` instead of escaping as a raw error.
- The CLI rejects unexpected extra arguments and a non-positive `--timeout`.

## [0.2.0]

### Added

- `Chain::BitcoinCore`, a JSON-RPC oracle that verifies against your own Bitcoin
  Core node (`getblockhash` + `getblockheader`) for a fully trustless check;
  supports basic-auth credentials via argument, URL, or `.cookie` file.
- `ots` command-line tool (`stamp | upgrade | verify | info | version`), a thin
  wrapper over the library. `verify` binds the proof to the file and can target a
  node (`--node`) and require an m-of-n quorum (`--quorum`).
- `verify` / `verified?` take a `quorum:` (m-of-n): require the proof to be
  anchored in at least that many *distinct Bitcoin blocks*. Several tree paths
  proving the same anchor collapse to one, so a single anchor can never satisfy
  quorum > 1.
- `OpenTimestamps.digest_for_kind`, which hashes data with any file-hash op
  (sha1 / ripemd160 / sha256) to bind a proof to a document.

### Changed

- Timestamp children now serialize in the reference client's canonical order (ops
  by `[tag, operand]`, Bitcoin attestations by height, pending by uri), so a proof
  we build or merge is byte-identical to `ots` output and any reference proof
  still round-trips byte-for-byte.

### Hardened

- Duplicate attestations are dropped on deserialize (the reference keeps a set),
  and a binary op with an empty operand is rejected, closing two ways a proof
  could otherwise pad a quorum from a single real anchor.
- Chain oracles validate the shape of everything they read (merkle-root hex,
  block hash, JSON-RPC envelope, HTTP status) and raise `NetworkError` rather than
  a raw Ruby error on malformed responses.

### Internal

- `Calendar`, `Chain::Explorer`, and `Chain::BitcoinCore` take an injectable
  transport; `stamp_digest` / `upgrade` take a `calendar_factory`, enabling
  offline unit tests of the network paths and merge logic.

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

[Unreleased]: https://github.com/sirruf/opentimestamps/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/sirruf/opentimestamps/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sirruf/opentimestamps/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sirruf/opentimestamps/releases/tag/v0.1.0
