require_relative "../modbus/tcp"

module ModbusTypeExtensions
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

module Devices
  class Next3
    using ModbusTypeExtensions

    attr_reader :battery, :acsource

    def initialize
      host = ENV.fetch("NEXT3_HOST", "studer-next")
      port = ENV.fetch("NEXT3_PORT", 502).to_i
      next3 = Modbus::TCP.new(host, port)
      @battery = Battery.new next3.unit(2)
      @acsource = AcSource.new next3.unit(7)
    end

    class Battery
      def initialize(unit)
        @unit = unit
      end

      def soc
        @unit.read_holding_registers(26, 2).to_f32
      end

      def temp
        @unit.read_holding_registers(329, 2).to_f32
      end

      def charging_amps
        @unit.read_holding_registers(320, 2).to_f32
      end
    end

    class AcSource
      def initialize(unit)
        @unit = unit
      end

      def enable
        @unit.write_holding_register(1207, 1)
      end

      def disable
        @unit.write_holding_register(1207, 0)
      end
    end
  end
end
