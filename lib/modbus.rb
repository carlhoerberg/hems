# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class Base
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
      raise ArgumentError.new "Boolean value required" if value != true && value != false
      function = 5
      value = value ? 0xFF00 : 0x0000
      request([unit, function, addr, value].pack("CCnn")) do
        raddr, rvalue = read(4).unpack("nn")
        raddr == addr && rvalue == value
      end
    end

    # FC16
    def write_holding_registers(addr, values, unit = 255)
      function = 16
      count = values.size
      bytes = count * 2
      request([unit, function, addr, count, bytes, *values].pack("CCnnCn#{count}")) do
        raddr, written = read(4).unpack("nn")
        raddr == addr && written == count
      end
    end

    def unit(id)
      Unit.new(self, id)
    end

    class Unit
      def initialize(modbus, unit = 255)
        @modbus = modbus
        @unit = unit
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

    def handle_exception
      exception_code = read(1).unpack1("C")
      case exception_code
      when 1 then raise "Modbus exception invalid function"
      when 2 then raise "Modbus exception invalid address"
      when 3 then raise "Modbus exception invalid data"
      else raise "Modbus exception code #{exception_code}"
      end
    end
  end

  # Adds methods to Array for easier type conversions where 16 bit values aren't enough
  module TypeExtensions
    refine Array do
      # Converts two 16-bit values to one 32-bit float, as Modbus only deals with 16 bit values
      def to_f32
        raise ArgumentError.new("Two 16 bit values required for 32 bit float") if size != 2
        pack("n2").unpack1("g")
      end

      # Converts four 16-bit values to one 64-bit float, as Modbus only deals with 16 bit values
      def to_f64
        raise ArgumentError.new("Four 16 bit values required for 64 bit float") if size != 4
        pack("n4").unpack1("G")
      end
    end
  end
end
