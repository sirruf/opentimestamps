# frozen_string_literal: true

# End-to-end example (needs network):
#   ruby -Ilib examples/stamp_and_verify.rb
require "opentimestamps"

data = "hello opentimestamps #{Time.now.utc.iso8601}\n"

ots = OpenTimestamps.stamp(data)                 # submit to a public calendar
File.binwrite("hello.txt.ots", ots.serialize)    # PERSIST — required to upgrade later
puts OpenTimestamps.info(ots)
puts "\nSaved hello.txt.ots (#{File.size('hello.txt.ots')} bytes)."
puts "Fresh stamps are pending; upgrade in ~1 day:"
puts "  ots = OpenTimestamps::DetachedTimestampFile.deserialize(File.binread('hello.txt.ots'))"
puts "  OpenTimestamps.upgrade(ots) && File.binwrite('hello.txt.ots', ots.serialize)"
puts "  OpenTimestamps.verify(ots)   # => [{height:, time:, verified: true}]"
