require_relative "../modbus/tcp"

module Devices
  class Next3
    using Modbus::TypeExtensions

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
