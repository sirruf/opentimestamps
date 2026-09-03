# frozen_string_literal: true

require "test_helper"

class CalendarTest < Minitest::Test
  include OpenTimestamps

  DIGEST = ("\x44".b * 32).freeze

  # A calendar reply body: the children serialization of a Timestamp rooted at
  # the digest (deserialize is given the digest as the initial message).
  def pending_body(uri)
    ts = Timestamp.new(DIGEST)
    ts.attestations << Attestation::Pending.new(uri)
    ts.serialize(Serialization::Writer.new).string
  end

  def test_submit_returns_pending_timestamp
    body = pending_body("https://alice.example")
    cal = Calendar.new("https://cal.example", transport: ->(_req, _to) { ["200", body] })
    ts = cal.submit(DIGEST)
    atts = ts.each_attestation.to_a
    assert_equal 1, atts.size
    assert atts.first.last.pending?
  end

  def test_submit_raises_on_non_200
    cal = Calendar.new("https://cal.example", transport: ->(_req, _to) { ["500", "boom"] })
    err = assert_raises(NetworkError) { cal.submit(DIGEST) }
    assert_match(/HTTP 500/, err.message)
  end

  def test_upgrade_returns_nil_on_404
    cal = Calendar.new("https://cal.example", transport: ->(_req, _to) { ["404", ""] })
    assert_nil cal.upgrade(DIGEST)
  end

  def test_upgrade_returns_timestamp_on_200
    body = pending_body("https://alice.example")
    cal = Calendar.new("https://cal.example", transport: ->(_req, _to) { ["200", body] })
    refute_nil cal.upgrade(DIGEST)
  end

  def test_upgrade_raises_on_other_error_code
    cal = Calendar.new("https://cal.example", transport: ->(_req, _to) { ["503", ""] })
    assert_raises(NetworkError) { cal.upgrade(DIGEST) }
  end
end
