# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class Base
    # FC01, read bit values
    def read_coils(addr, count, unit = 255)
      function = 1
      request([unit, function, addr, count].pack("CCnn")) do
        len = read(1).unpack1("C")
        bits = read(len).unpack1("b*")
        Array.new(count) { |i| bits[i] == '1' }
      end
    end

    # FC02, read bit values
    def read_discrete_inputs(addr, count, unit = 255)
      function = 2
      request([unit, function, addr, count].pack("CCnn")) do
        len = read(1).unpack1("C")
        bits = read(len).unpack1("b*")
        Array.new(count) { |i| bits[i] == '1' }
      end
    end

    def read_discrete_input(addr, unit = 255)
      read_discrete_inputs(addr, 1, unit).first
    end

    # FC03, read 16-bit values
    def read_holding_registers(addr, count, unit = 255)
      function = 3
      request([unit, function, addr, count].pack("CCnn")) do
        len = read(1).unpack1("C")
        read(len).unpack("n*")
      end
    end

    def read_holding_register(addr, unit = 255)
      read_holding_registers(addr, 1, unit).first
    end

    # FC04. read 16-bit values
    def read_input_registers(addr, count, unit = 255)
      function = 4
      request([unit, function, addr, count].pack("CCnn")) do
        len = read(1).unpack1("C")
        read(len).unpack("n*")
      end
    end

    def read_input_register(addr, unit = 255)
      read_input_registers(addr, 1, unit).first
    end

    # FC05
    def write_coil(addr, value, unit = 255)
      function = 5
      v = case value
          when true then 0xFF00
          when false then 0
          when Integer then value
          else raise ArgumentError, "Boolean or Integer value required"
          end
      request([unit, function, addr, v].pack("CCnn")) do
        raddr, rvalue = read(4).unpack("nn")
        raddr == addr && rvalue == value
      end
    end

    # FC16, write 16 bit integers
    def write_holding_registers(addr, values, unit = 255)
      values.each do |v|
        unless -2**15 < v && v < 2**15
          raise ArgumentError, "Values are not 16 bit integers: #{values.inspect}"
        end
      end
      function = 16
      count = values.size
      bytes = count * 2
      request([unit, function, addr, count, bytes, *values].pack("CCnnCn#{count}")) do
        raddr, written = read(4).unpack("nn")
        raddr == addr && written == count
      end
    end

    # FC16, write 16 bit integer
    def write_holding_register(addr, value, unit = 255)
      write_holding_registers(addr, [value], unit)
    end

    def unit(id)
      Unit.new(self, id)
    end

    class Unit
      def initialize(modbus, unit = 255)
        @modbus = modbus
        @unit = unit
      end

      def read_coils(addr, count)
        @modbus.read_coils(addr, count, @unit)
      end

      def read_coil(addr)
        @modbus.read_coil(addr, @unit)
      end

      def read_holding_registers(addr, count)
        @modbus.read_holding_registers(addr, count, @unit)
      end

      def read_holding_register(addr)
        @modbus.read_holding_register(addr, @unit)
      end

      def read_input_registers(addr, count)
        @modbus.read_input_registers(addr, count, @unit)
      end

      def read_input_register(addr)
        @modbus.read_input_register(addr, @unit)
      end

      def write_holding_registers(addr, values)
        @modbus.write_holding_registers(addr, values, @unit)
      end

      def write_holding_register(addr, value)
        @modbus.write_holding_register(addr, value, @unit)
      end

      def write_coil(addr, value)
        @modbus.write_coil(addr, value, @unit)
      end

      def read_discrete_inputs(addr, count)
        @modbus.read_discrete_inputs(addr, count, @unit)
      end

      def read_discrete_input(addr)
        @modbus.read_discrete_input(addr, @unit)
      end
    end

    protected

    def check_exception!(function)
      return if function[7] != 1 # highest bit set indicates an exception
      exception_code = read(1).unpack1("C")
      case exception_code
      when 1 then raise ResponseError.new("Invalid function")
      when 2 then raise ResponseError.new("Invalid address")
      when 3 then raise ResponseError.new("Invalid data")
      else raise ResponseError.new("Invalid response code #{exception_code}")
      end
    end

    class ResponseError < StandardError; end
    class ProtocolException < IOError; end
  end

  # Adds methods to Array for easier type conversions where 16 bit values aren't enough
  module TypeExtensions
    refine Array do
      # Converts two 16-bit values to one 32-bit float
      def to_f32
        pack("n2").unpack1("g")
      end

      # Converts four 16-bit values to one 64-bit float
      def to_f64
        pack("n4").unpack1("G")
      end

      # Converts two 16-bit values to one 32-bit integer
      def to_i32
        pack("nn").unpack1("l>")
      end

      # Converts two 16-bit values to one 32-bit unsigned integer
      def to_u32
        pack("nn").unpack1("L>")
      end

      def to_i16
        pack("n").unpack1("s>")
      end
    end

    refine Float do
      def to_f32_to_i16s
        [self].pack("g").unpack("nn")
      end
    end

    refine Integer do
      def to_f32_to_i16s
        [self].pack("g").unpack("nn")
      end
    end
  end
end
