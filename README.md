# opentimestamps

A **pure-Ruby, zero-dependency** client for [OpenTimestamps](https://opentimestamps.org):
stamp a hash against the Bitcoin blockchain via public calendar servers, upgrade
the proof to a block attestation, and verify it — using only the standard library
(`digest`, `openssl`, `net/http`, `json`). Proofs are self-verifying and outlive
both this gem and any single server.

> Status: **v0.1** — read/write path, verification, calendar client, and `.ots`
> (de)serialization are implemented and tested, including **byte-exact interop
> against 12 reference `.ots` vectors** (the Bitcoin whitepaper timestamp among
> them) and a real-block verification. See _Roadmap_ for what's next.

## Why

The reference OpenTimestamps clients are Python and JavaScript; there is no
maintained Ruby implementation. This gem fills that gap so a Ruby app (a Rails
service, a background job) can anchor and verify timestamps **without shelling
out to another language**.

## Install

```ruby
gem "opentimestamps"
```

## Usage

```ruby
require "opentimestamps"

# 1. Stamp — submits a SHA-256 to a public calendar; returns a *pending* proof.
ots = OpenTimestamps.stamp("hello world\n")

# 2. PERSIST — the calendar indexes by a per-request commitment. Keep only the
#    hash and you can never upgrade. Always save the .ots.
File.binwrite("hello.txt.ots", ots.serialize)

# 3. Upgrade — hours later, fold in the Bitcoin path the calendar has anchored.
ots = OpenTimestamps::DetachedTimestampFile.deserialize(File.binread("hello.txt.ots"))
OpenTimestamps.upgrade(ots) && File.binwrite("hello.txt.ots", ots.serialize)

# 4. Verify — recompute the commitment and check it against the block merkle root.
OpenTimestamps.verify(ots)
# => [{ height: 913442, time: 2026-09-01 15:58:00 UTC, verified: true }]
```

## Design

- **Zero runtime dependencies.** Standard library only; no native extensions.
- **Trust the chain, not a provider.** Verification depends on a `Chain` oracle
  interface (`#block_merkle_root_and_time(height)`). Ships with a public-explorer
  adapter; inject your own Bitcoin node for a fully trustless check.
- **Forward compatible.** Attestation types this version doesn't model (Litecoin,
  Ethereum, future) are preserved byte-for-byte, so round-tripping never corrupts
  a proof.
- **The client never broadcasts Bitcoin.** Calendars aggregate thousands of
  digests into one transaction; you only submit and upgrade.

## Roadmap

- [x] Byte-exact interop against reference `.ots` vectors (`test/vectors/`, incl.
      Bitcoin/Litecoin/Ethereum, unknown notaries, merkle trees).
- [x] Keccak-256 (Ethereum branch) — pure Ruby, known-answer tested.
- [x] Real-block verification (deterministic, offline).
- [ ] Multi-calendar submit/upgrade with quorum.
- [ ] `Chain::BitcoinCore` JSON-RPC adapter (trustless verification via own node).
- [ ] Cross-check that our freshly-created proofs verify with the reference `ots` CLI.
- [ ] RIPEMD160 via the OpenSSL legacy provider; SHA-1 calendars.
- [ ] Optional CLI (`ots stamp | upgrade | verify | info`).

## License

MIT.
