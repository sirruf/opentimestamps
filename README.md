# opentimestamps

A pure-Ruby client for [OpenTimestamps](https://opentimestamps.org), with no
runtime dependencies. It stamps a hash against the Bitcoin blockchain through
public calendar servers, upgrades the resulting proof to a block attestation,
and verifies it, using only the standard library (`digest`, `openssl`,
`net/http`, `json`). The proofs it produces are self-verifying and stay valid
without this gem or any particular server.

The reference OpenTimestamps clients are Python and JavaScript; nothing
equivalent is published for Ruby on RubyGems. This gem lets a Ruby app anchor
and verify timestamps in-process, without shelling out to another language.

## Install

```ruby
gem "opentimestamps"
```

## Usage

```ruby
require "opentimestamps"

# Stamp: hashes the data (SHA-256), submits the digest to the default calendars,
# and returns a pending proof. Use stamp_digest to submit a precomputed hash and
# keep the content itself private.
ots = OpenTimestamps.stamp("hello world\n")

# Persist it. The calendar indexes each submission by a per-request commitment,
# so if you keep only the hash you can never upgrade. Always save the .ots.
File.binwrite("hello.txt.ots", ots.serialize)

# Upgrade, an hour or so later, once a calendar has anchored the commitment in a
# Bitcoin transaction. Returns true if the file changed.
ots = OpenTimestamps::DetachedTimestampFile.deserialize(File.binread("hello.txt.ots"))
OpenTimestamps.upgrade(ots) && File.binwrite("hello.txt.ots", ots.serialize)

# Verify against the chain. Raises VerificationError unless a block attestation
# matches; returns the confirmed attestations, each carrying the proven digest.
OpenTimestamps.verify(ots)
# => [#<struct Verification height=358391, time=2015-05-28 ..., digest="\x00..">]

OpenTimestamps.verified?(ots)   # boolean form; never raises
```

Compare `verify`'s `digest` against the hash of your own file to bind the proof
to your document.

## Notes on the design

The parser treats its input as untrusted: malformed bytes, oversized length
prefixes, and pathologically deep or large proofs all raise `DeserializationError`
rather than a raw Ruby error, and depth and message-size caps bound the work a
single proof can cause.

Verification goes through a `Chain` oracle (`#block_merkle_root_and_time`), so
the bundled public-explorer adapter can be swapped for your own Bitcoin node when
you want a check that trusts nothing external.

Attestation types the library does not model (Litecoin, Ethereum, or anything
added later) are carried through untouched, so re-serializing a proof never
corrupts it. Ethereum's Keccak-256 is implemented in pure Ruby for the proofs
that need it; Bitcoin proofs never do.

The client never broadcasts a Bitcoin transaction. Calendars batch many digests
into one; the client only submits and upgrades.

## Interop

`test/vectors/` holds twelve `.ots` files produced by the reference client
(among them the timestamp of the Bitcoin whitepaper, plus multi-chain, unknown
notary, and merkle-tree proofs). The suite asserts each one re-serializes
byte-for-byte, and checks a proof against Bitcoin block 358391 using a recorded
merkle root, offline. The reference `ots` client also reads proofs this gem
creates.

## Command line

The gem installs an `ots` executable, a thin wrapper over the library:

```console
$ ots stamp report.pdf                 # writes report.pdf.ots (pending)
$ ots upgrade report.pdf.ots           # an hour later: fold in the Bitcoin path
$ ots verify report.pdf                # checks report.pdf.ots and binds it to the file
$ ots info report.pdf.ots              # dump the proof's structure
```

`verify` recomputes the file's hash and confirms it matches the proof, so a
success means *this* document is anchored, not just that the proof is valid. It
can also require the proof to be anchored in several distinct Bitcoin blocks
(`--quorum 2`) and check against your own node (see below).

## Verifying against your own node

`Chain::Explorer` trusts a public explorer. For a check that trusts nothing
external, point verification at your own Bitcoin Core:

```ruby
chain = OpenTimestamps::Chain::BitcoinCore.new(
  "http://127.0.0.1:8332", user: "rpcuser", password: "secret"
)
OpenTimestamps.verify(ots, chain: chain, quorum: 2)
```

`BitcoinCore.from_cookie(path)` reads the node's `.cookie` file instead of a
password. From the CLI: `ots verify file --node http://127.0.0.1:8332 --cookie ~/.bitcoin/.cookie`.

## Roadmap

- [x] Byte-exact interop with reference `.ots` vectors, both directions.
- [x] Multi-calendar submit with merge (a single calendar being down is not fatal).
- [x] `Chain::BitcoinCore` JSON-RPC adapter (verification against your own node).
- [x] Quorum (m-of-n distinct Bitcoin blocks), enforced at verify.
- [x] CLI (`ots stamp | upgrade | verify | info`).

## License

MIT.
