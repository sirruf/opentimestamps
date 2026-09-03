# frozen_string_literal: true

require "test_helper"

class UpgradeTest < Minitest::Test
  include OpenTimestamps
  include TestBuilders

  def test_upgrade_folds_in_bitcoin_path_and_reports_change
    detached, factory, chain = pending_proof([["cal-a", :ok]])
    assert OpenTimestamps.upgrade(detached, calendar_factory: factory)
    assert OpenTimestamps.verified?(detached, chain: chain)
  end

  def test_upgrade_is_noop_when_already_bitcoin
    detached, chain = bitcoin_proof(1)
    called = false
    factory = ->(_uri) { called = true }
    refute OpenTimestamps.upgrade(detached, calendar_factory: factory)
    refute called, "must not touch calendars when already anchored"
    assert OpenTimestamps.verified?(detached, chain: chain)
  end

  def test_upgrade_survives_one_unreachable_calendar
    detached, factory, chain = pending_proof([["cal-a", :ok], ["cal-b", :fail]])
    assert OpenTimestamps.upgrade(detached, calendar_factory: factory)
    # The reachable calendar's anchor is folded in even though the other failed.
    assert OpenTimestamps.verified?(detached, chain: chain)
  end

  def test_upgrade_returns_false_when_nothing_anchored_yet
    detached, factory, = pending_proof([["cal-a", :pending], ["cal-b", :pending]])
    refute OpenTimestamps.upgrade(detached, calendar_factory: factory)
  end

  # --- quorum ---

  def test_verify_meets_quorum_with_enough_independent_anchors
    detached, chain = bitcoin_proof(2)
    results = OpenTimestamps.verify(detached, chain: chain, quorum: 2)
    assert_equal 2, results.size
    assert OpenTimestamps.verified?(detached, chain: chain, quorum: 2)
  end

  def test_verify_fails_when_quorum_not_met
    detached, chain = bitcoin_proof(1)
    err = assert_raises(VerificationError) { OpenTimestamps.verify(detached, chain: chain, quorum: 2) }
    assert_match(/2 distinct Bitcoin block/, err.message)
    refute OpenTimestamps.verified?(detached, chain: chain, quorum: 2)
  end

  def test_verify_rejects_non_positive_quorum
    detached, chain = bitcoin_proof(1)
    assert_raises(OpenTimestamps::Error) { OpenTimestamps.verify(detached, chain: chain, quorum: 0) }
  end

  def test_upgrade_then_quorum_across_two_calendars
    detached, factory, chain = pending_proof([["cal-a", :ok], ["cal-b", :ok]])
    OpenTimestamps.upgrade(detached, calendar_factory: factory)
    assert OpenTimestamps.verified?(detached, chain: chain, quorum: 2)
  end

  # A single real anchor reached by two different tree paths (append("a")+append("b")
  # vs append("ab"), both hashing to the same root) must count once: quorum cannot
  # be inflated from one block.
  def test_quorum_not_inflated_by_two_paths_to_same_anchor
    digest = "\x55".b * 32
    root = Timestamp.new(digest)

    a = Op.new(:append, "a")
    n1 = Timestamp.new(a.apply(digest))
    b = Op.new(:append, "b")
    n2 = Timestamp.new(b.apply(n1.msg))
    sha = Op.new(:sha256)
    leaf1 = Timestamp.new(sha.apply(n2.msg))
    leaf1.attestations << Attestation::Bitcoin.new(900_000)
    n2.ops[sha] = leaf1
    n1.ops[b] = n2
    root.ops[a] = n1

    ab = Op.new(:append, "ab")
    m2 = Timestamp.new(ab.apply(digest))
    sha2 = Op.new(:sha256)
    leaf2 = Timestamp.new(sha2.apply(m2.msg))
    leaf2.attestations << Attestation::Bitcoin.new(900_000)
    m2.ops[sha2] = leaf2
    root.ops[ab] = m2

    assert_equal leaf1.msg, leaf2.msg, "both paths must reach the same commitment"
    detached = DetachedTimestampFile.new(Op.new(:sha256), root)
    chain = FakeChain.new(900_000 => [leaf1.msg, Time.utc(2024, 1, 1)])

    assert OpenTimestamps.verified?(detached, chain: chain, quorum: 1)
    refute OpenTimestamps.verified?(detached, chain: chain, quorum: 2)
  end
end
