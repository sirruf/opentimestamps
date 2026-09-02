# frozen_string_literal: true

require "test_helper"

class OperationTest < Minitest::Test
  include OpenTimestamps

  def test_binary_op_requires_an_argument
    assert_raises(OpenTimestamps::Error) { Op.new(:append) }
    assert_raises(OpenTimestamps::Error) { Op.new(:prepend) }
  end

  def test_unary_op_rejects_an_argument
    assert_raises(OpenTimestamps::Error) { Op.new(:sha256, "x") }
  end

  def test_unknown_kind_and_tag_rejected
    assert_raises(OpenTimestamps::Error) { Op.new(:md5) }
    assert_raises(OpenTimestamps::DeserializationError) do
      Op.deserialize(Serialization::Reader.new("".b), 0x99)
    end
  end

  def test_apply_and_equality
    assert_equal Digest::SHA256.digest("m"), Op.new(:sha256).apply("m")
    assert_equal "pre-m", Op.new(:prepend, "pre-").apply("m")
    assert_equal Op.new(:append, "x"), Op.new(:append, "x")
    refute_equal Op.new(:append, "x"), Op.new(:append, "y")
  end
end
