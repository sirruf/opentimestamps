# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# Drives the exe/ots executable as a subprocess. Only offline-safe commands are
# exercised here (network paths are covered by the unit tests).
class CliTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXE  = File.join(ROOT, "exe", "ots")
  LIB  = File.join(ROOT, "lib")
  VECTOR = File.join(ROOT, "test", "vectors", "hello-world.txt.ots")

  def ots(*args, **opts)
    Open3.capture3(RbConfig.ruby, "-I#{LIB}", EXE, *args, **opts)
  end

  def test_version_prints_library_version
    out, _err, status = ots("version")
    assert status.success?
    assert_match(/opentimestamps #{Regexp.escape(OpenTimestamps::VERSION)}/, out)
  end

  def test_no_command_shows_usage_and_fails
    _out, err, status = ots
    refute status.success?
    assert_match(/Usage: ots/, err)
  end

  def test_unknown_command_fails
    _out, err, status = ots("frobnicate")
    refute status.success?
    assert_match(/unknown command/, err)
  end

  def test_info_dumps_structure_of_a_vector
    out, _err, status = ots("info", VECTOR)
    assert status.success?
    assert_match(/BITCOIN block #358391/, out)
  end

  def test_missing_argument_fails
    _out, err, status = ots("info")
    refute status.success?
    assert_match(/missing argument/, err)
  end

  def test_stamp_refuses_to_overwrite_existing_ots
    Dir.mktmpdir do |dir|
      file = File.join(dir, "doc.txt")
      File.write(file, "hi")
      File.write("#{file}.ots", "existing")
      _out, err, status = ots("stamp", file)
      refute status.success?
      assert_match(/refusing to overwrite/, err)
    end
  end

  def test_verify_reports_mismatch_offline_for_wrong_file
    # Binding is checked before any chain lookup, so a wrong file is rejected with
    # no network I/O — the assertion holds offline.
    Dir.mktmpdir do |dir|
      file = File.join(dir, "other.txt")
      File.write(file, "not the stamped content")
      File.binwrite("#{file}.ots", File.binread(VECTOR))
      _out, err, status = ots("verify", file)
      refute status.success?
      assert_match(/does NOT match/, err)
    end
  end

  # Every expected failure must be a clean one-line "ots:" message, never a raw
  # Ruby backtrace.
  def test_missing_file_is_a_clean_error
    _out, err, status = ots("info", "/no/such/file.ots")
    refute status.success?
    assert_match(/ots:/, err)
    refute_match(/\.rb:\d+:in/, err)
  end

  def test_bad_option_is_a_clean_error
    Dir.mktmpdir do |dir|
      file = File.join(dir, "doc.txt")
      File.write(file, "hi")
      _out, err, status = ots("stamp", "--bogus", file)
      refute status.success?
      assert_match(/ots:/, err)
      refute_match(/\.rb:\d+:in/, err)
    end
  end

  def test_bad_integer_option_is_a_clean_error
    _out, err, status = ots("verify", "x", "--quorum", "abc")
    refute status.success?
    assert_match(/ots:/, err)
    refute_match(/\.rb:\d+:in/, err)
  end

  def test_extra_arguments_rejected
    _out, err, status = ots("info", VECTOR, "extra-arg")
    refute status.success?
    assert_match(/unexpected argument/, err)
  end

  def test_non_positive_timeout_rejected
    Dir.mktmpdir do |dir|
      file = File.join(dir, "doc.txt")
      File.write(file, "hi")
      _out, err, status = ots("stamp", file, "--timeout", "0")
      refute status.success?
      assert_match(/timeout must be a positive/, err)
    end
  end

  def test_negative_timeout_rejected
    Dir.mktmpdir do |dir|
      file = File.join(dir, "doc.txt")
      File.write(file, "hi")
      _out, err, status = ots("stamp", file, "--timeout=-5")
      refute status.success?
      assert_match(/timeout must be a positive/, err)
    end
  end

  def test_upgrade_rejects_extra_arguments
    _out, err, status = ots("upgrade", VECTOR, "extra-arg")
    refute status.success?
    assert_match(/unexpected argument/, err)
  end
end
