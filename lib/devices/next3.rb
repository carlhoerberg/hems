require_relative "../modbus/tcp"

class Devices
  class Next3
    using Modbus::TypeExtensions

    attr_reader :acload, :battery, :acsource, :solar, :aux1

    def initialize
      host = ENV.fetch("NEXT3_HOST", "studer-next")
      port = ENV.fetch("NEXT3_PORT", 502).to_i
      next3 = Modbus::TCP.new(host, port)
      @acload = AcLoad.new next3
      @battery = Battery.new next3
      @acsource = AcSource.new next3
      @solar = Solar.new next3
      @aux1 = Aux.new next3, 1
    end

    class Battery
      def initialize(next3)
        @unit = next3.unit(2)
      end

      def soc
        @unit.read_holding_registers(26, 2).to_f32
      end

      def voltage
        @unit.read_holding_registers(318, 2).to_f32
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

      def target_voltage_max
        @unit.read_holding_registers(314, 2).to_f32
      end

      def target_voltage_min
        @unit.read_holding_registers(316, 2).to_f32
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

      def total_charging_energy
        @unit.read_holding_registers(10, 4).to_f64
      end

      def total_discharging_energy
        @unit.read_holding_registers(22, 4).to_f64
      end

      def charging_current_high_limit
        @unit.read_holding_registers(312, 2).to_f32
      end

      def bms_recommended_charging_current
        @unit.read_holding_registers(427, 2).to_f32
      end

      def bms_recommended_discharging_current
        @unit.read_holding_registers(429, 2).to_f32
      end

      def status
        @unit.read_holding_registers(300, 2).to_u32
      end

      def errors
        @unit.read_holding_registers(302, 2).to_u32
      end

      def warnings
        @unit.read_holding_registers(304, 2).to_u32
      end
    end

    class AcSource
      def initialize(next3)
        @unit = next3.unit(7)
      end

      def enabled?
        @unit.read_holding_register(1207) != 0
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
        @unit.read_holding_registers(1209, 2).to_f32
      end

      def rated_current=(value)
        @unit.write_holding_registers(1209, value.to_f32_to_i16s)
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

      def day_consumed_energy(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 28, 2).to_f32
      end

      def active_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 4, 2).to_f32
      end

      def reactive_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 6, 2).to_f32
      end

      def apparent_power(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 8, 2).to_f32
      end

      def total_consumed_energy(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(300 * phase + 36, 4).to_f64
      end
    end

    class AcLoad
      def initialize(next3)
        @unit = next3.unit(1)
      end

      def frequency
        @unit.read_holding_registers(3900, 2).to_f32
      end

      def total_apparent_power
        @unit.read_holding_registers(3910, 2).to_f32
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

      def day_consumed_energy(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3928 + 300 * phase, 2).to_f32
      end

      def total_consumed_energy(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3936 + 300 * phase, 4).to_f64
      end

      def warnings(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3002 + (phase - 1) * 300, 2).to_u32
      end

      def errors(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(3004 + (phase - 1) * 300, 2).to_u32
      end
    end

    # Each solar MPPT has two arrays, 1 and 2
    class Solar
      def initialize(next3)
        @unit = next3.unit(14)
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
        @unit.read_holding_registers(6900 + (array - 1) * 300, 2).to_f32
      end

      def current(array)
        @unit.read_holding_registers(6902 + (array - 1) * 300, 2).to_f32
      end

      def day_sunshine(array)
        @unit.read_holding_registers(6904 + (array - 1) * 300, 2).to_u32
      end

      def power_limit(array)
        @unit.read_holding_registers(6922 + (array - 1) * 300, 2).to_f32
      end

      def total_energy(array)
        @unit.read_holding_registers(6019 + (array - 1) * 300, 4).to_f64
      end

      # At least one solar array is in production limited due to solar excess.
      def excess?
        status_enum = @unit.read_holding_registers(6602, 2).to_u32
        status_enum & 256 != 0
      end

      # Currently produced power (kW) by all arrays
      def total_power
        @unit.read_holding_registers(5705, 2).to_f32
      end

      # Energy produced today, in wH
      def total_day_energy
        @unit.read_holding_registers(5711, 2).to_f32
      end

      # Returns an enum where:
      # 0 not limited, 1 temperature limited, 2 max power reached, 3 max current reached, 4 solar excess
      def limitation(array)
        @unit.read_holding_registers(6918 + (array - 1) * 300, 2).to_u32
      end
    end

    class Aux
      def initialize(next3, id)
        raise ArgumentError.new("Aux ID must be 1-2") unless (1..2).include? id
        @unit = next3.unit(14)
        @base = 8100 + 300 * (id - 1)
      end

      def is_connected
        @unit.read_holding_register(@base)
      end
    end
  end
end
