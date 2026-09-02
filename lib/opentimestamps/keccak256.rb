# frozen_string_literal: true

module OpenTimestamps
  # Pure-Ruby Keccak-256 (Ethereum's original Keccak, 0x01 padding — NOT NIST
  # SHA3-256, which uses 0x06). Needed only to parse OTS proofs that also anchor
  # to Ethereum; Bitcoin proofs never use it. Verified against known-answer
  # vectors in the test suite. OpenSSL does not ship original Keccak.
  module Keccak256
    MASK = (1 << 64) - 1
    RATE = 136 # bytes (1088-bit rate, 512-bit capacity → 256-bit output)

    RNDC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
            0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
            0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
            0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
            0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008].freeze
    ROTC = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44].freeze
    PILN = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1].freeze

    module_function

    def digest(message)
      m = message.b.dup
      pad = RATE - (m.bytesize % RATE)
      tail = "\x00".b * pad
      tail.setbyte(0, 0x01)
      tail.setbyte(pad - 1, tail.getbyte(pad - 1) | 0x80)
      m << tail

      state = Array.new(25, 0)
      m.bytes.each_slice(RATE) do |block|
        (RATE / 8).times { |i| state[i] ^= block[i * 8, 8].pack("C*").unpack1("Q<") }
        keccak_f(state)
      end
      (0..3).map { |i| [state[i]].pack("Q<") }.join.b
    end

    def hexdigest(message) = digest(message).unpack1("H*")

    def rotl(x, n) = ((x << n) | (x >> (64 - n))) & MASK

    def keccak_f(st)
      bc = Array.new(5, 0)
      24.times do |round|
        5.times { |i| bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20] }
        5.times do |i|
          t = bc[(i + 4) % 5] ^ rotl(bc[(i + 1) % 5], 1)
          (0...25).step(5) { |j| st[j + i] ^= t }
        end
        t = st[1]
        24.times do |i|
          j = PILN[i]
          tmp = st[j]
          st[j] = rotl(t, ROTC[i])
          t = tmp
        end
        (0...25).step(5) do |j|
          5.times { |i| bc[i] = st[j + i] }
          5.times { |i| st[j + i] ^= (~bc[(i + 1) % 5] & MASK) & bc[(i + 2) % 5] }
        end
        st[0] ^= RNDC[round]
        st.map! { |v| v & MASK }
      end
    end
  end
end
