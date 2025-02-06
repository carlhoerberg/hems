module Modbus
  class CRC16
    POLYNOMIAL = 0xA001
    INITIAL_VALUE = 0xFFFF
    TABLE = Array.new(256) do |i|
      crc = i
      8.times do
        crc = (crc & 1).zero? ? (crc >> 1) : (crc >> 1) ^ POLYNOMIAL
      end
      crc & 0xFFFF
    end

    def self.compute(data)
      crc = INITIAL_VALUE
      data.each_byte do |byte|
        crc = (crc >> 8) ^ TABLE[(crc ^ byte) & 0xFF]
      end
      [crc].pack("S<")
    end

    def self.valid?(package)
      compute(package) == "\x00\x00"
    end
  end
end
