require_relative "../modbus/tcp"

class Devices
  class Next3
    using Modbus::TypeExtensions

    attr_reader :acload, :battery, :acsource, :solar

    def initialize
      host = ENV.fetch("NEXT3_HOST", "studer-next")
      port = ENV.fetch("NEXT3_PORT", 502).to_i
      next3 = Modbus::TCP.new(host, port)
      @acload = AcLoad.new next3.unit(1)
      @battery = Battery.new next3.unit(2)
      @acsource = AcSource.new next3.unit(7)
      @solar = Solar.new next3.unit(14)
    end

    class Battery
      def initialize(unit)
        @unit = unit
      end

      def soc
        @unit.read_holding_registers(26, 2).to_f32
      end

      def cycles
        @unit.read_holding_registers(322, 4).to_f64
      end

      def state_of_health
        @unit.read_holding_registers(326, 2).to_f32
      end

      def temp
        @unit.read_holding_registers(329, 2).to_f32
      end

      def voltage
        @unit.read_holding_registers(318, 2).to_f32
      end

      def charging_current
        @unit.read_holding_registers(320, 2).to_f32
      end

      def charging_power
        @unit.read_holding_registers(0, 2).to_f32
      end

      def day_charging_energy
        @unit.read_holding_registers(2, 2).to_f32
      end

      def day_discharging_energy
        @unit.read_holding_registers(14, 2).to_f32
      end

      def charging_current_high_limit
        @unit.read_holding_registers(312, 2).to_f32
      end

      def bms_recommended_charging_current
        @unit.read_holding_registers(427, 2).to_f32
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

      def frequency
        @unit.read_holding_registers(0, 2).to_f32
      end

      def rated_current
        @unit.read_holding_register(1209, 2).to_f32
      end

      def rated_current=(value)
        @unit.write_holding_registers(1209, [value].pack("g"))
      end

      def voltage(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase, 2).to_f32
      end

      def current(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 2, 2).to_f32
      end

      def power_factor(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 10, 2).to_f32
      end
    end

    class AcLoad
      def initialize(unit)
        @unit = unit
      end

      def frequency
        @unit.read_holding_registers(3900, 2).to_f32
      end

      def voltage(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3900 + 300 * phase, 2).to_f32
      end

      def current(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3902 + 300 * phase, 2).to_f32
      end

      def active_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3904 + 300 * phase, 2).to_f32
      end

      def reactive_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3906 + 300 * phase, 2).to_f32
      end

      def apparent_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3908 + 300 * phase, 2).to_f32
      end

      def power_factor(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3910 + 300 * phase, 2).to_f32
      end

      def day_produced_energy
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3928, 2).to_f32
      end

      def day_consumed_energy(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3928 + 300 * phase, 2).to_f32
      end
    end

    # Each solar MPPT has two arrays, 1 and 2
    class Solar
      def initialize(unit)
        @unit = unit
      end

      def power(array)
        @unit.read_holding_registers(6005 + (array - 1) * 300, 2).to_f32
      end

      def max_power_limit(array)
        @unit.read_holding_registers(6009 + (array - 1) * 300, 2).to_u32
      end

      def day_energy(array)
        @unit.read_holding_registers(6011 + (array - 1) * 300, 2).to_f32
      end

      def voltage(array)
        @unit.read_holding_registers(7200 + (array - 1) * 300, 2).to_f32
      end

      def current(array)
        @unit.read_holding_registers(7202 + (array - 1) * 300, 2).to_f32
      end

      def day_sunshine(array)
        @unit.read_holding_registers(7204 + (array - 1) * 300, 2).to_u32
      end

      def power_limit(array)
        @unit.read_holding_registers(7222 + (array - 1) * 300, 2).to_f32
      end
    end
  end
end
