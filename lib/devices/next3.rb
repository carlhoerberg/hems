require_relative "../modbus/tcp"

class Devices
  class Next3
    using Modbus::TypeExtensions

    attr_reader :acload, :system_total, :battery, :battery2, :acsource, :solar, :solar2, :aux1, :converter, :converter2

    def initialize(host: nil, port: nil)
      host ||= ENV.fetch("NEXT3_HOST", "studer-next")
      port ||= ENV.fetch("NEXT3_PORT", 502).to_i
      next3 = Modbus::TCP.new(host, port)
      system_unit = next3.unit(1)
      @acload = AcLoad.new system_unit
      @system_total = SystemTotal.new system_unit
      @battery = Battery.new next3.unit(2)
      @battery2 = Battery.new next3.unit(3)
      @acsource = AcSource.new next3.unit(7)
      @solar = Solar.new next3.unit(14)
      @solar2 = Solar.new next3.unit(15)
      @aux1 = Aux.new next3.unit(14), 1
      @converter = Converter.new next3.unit(14)
      @converter2 = Converter.new next3.unit(15)
    end

    class SystemTotal
      def initialize(unit)
        @unit = unit
      end

      # Bitfield enum: 1=device, 2=battery, 4=solar, 8=phase, 16=AC input phase
      def warnings
        @unit.read_holding_registers(8110, 2).to_u32
      end

      # Bitfield enum: 1=device, 2=battery, 4=solar, 8=phase, 16=AC input phase
      def errors
        @unit.read_holding_registers(8120, 2).to_u32
      end
    end

    class Battery
      def initialize(unit)
        @unit = unit
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

      def target_charging_current_low_limit
        @unit.read_holding_registers(306, 2).to_f32
      end

      def target_charging_current_high_limit
        @unit.read_holding_registers(308, 2).to_f32
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

      WARNINGS_BITS = {
        0 => "Overvoltage", 1 => "Undervoltage",
        2 => "Charging overcurrent", 3 => "Discharging overcurrent",
        4 => "Charging overtemperature", 5 => "Discharging overtemperature",
        6 => "Charging undertemperature", 7 => "Discharging undertemperature",
        8 => "Contactor", 9 => "Short circuit",
        10 => "BMS internal", 11 => "Cell imbalance",
        12 => "SMA general", 13 => "Charging recommended",
        14 => "Discharging recommended", 15 => "Full charging recommended",
        16 => "Abnormal measured temperature", 17 => "Soon disconnected"
      }

      ERRORS_BITS = {
        0 => "Overvoltage", 1 => "Undervoltage",
        2 => "Charging overcurrent", 3 => "Discharging overcurrent",
        4 => "Charging overtemperature", 5 => "Discharging overtemperature",
        6 => "Charging undertemperature", 7 => "Discharging undertemperature",
        8 => "Contactor", 9 => "Short circuit",
        10 => "BMS internal", 11 => "Cell imbalance",
        12 => "SMA general", 13 => "Battery damaged",
        14 => "Communication lost", 15 => "Emergency stop",
        16 => "Charging not allowed", 17 => "Discharging not allowed",
        18 => "SOC below end of discharge", 19 => "Abnormal measured voltage"
      }

      def active_warnings
        active_bits(warnings, WARNINGS_BITS)
      end

      def active_errors
        active_bits(errors, ERRORS_BITS)
      end

      private

      def active_bits(value, mapping)
        mapping.filter_map { |bit, name| name if value[bit] == 1 }
      end
    end

    class AcSource
      def initialize(unit)
        @unit = unit
      end

      WARNINGS_BITS = {
        0 => "Active power response to overfrequency", 1 => "Active power response to underfrequency",
        2 => "Reactive power response to voltage", 3 => "Undervoltage ride through",
        4 => "Overvoltage ride through", 5 => "Power limited by increase gradient",
        6 => "Ceasing active power", 7 => "Reduced active power on setpoint",
        8 => "Active power response to overvoltage", 9 => "Overtemperature"
      }

      def warnings(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(1504 + 300 * phase, 2).to_u32
      end

      def active_warnings(phase)
        value = warnings(phase)
        WARNINGS_BITS.filter_map { |bit, name| name if value[bit] == 1 }
      end

      ERRORS_BITS = {
        9 => "Overfrequency", 10 => "Underfrequency",
        11 => "Overvoltage", 12 => "Undervoltage",
        13 => "Synchronization loss", 14 => "Outside of envelope",
        15 => "Islanding detected", 16 => "Phase error",
        17 => "Excessive dc voltage", 18 => "Earthing error",
        19 => "Error relay failure 1", 20 => "Synchronization failed",
        21 => "Error relay failure 2", 22 => "Error relay failure 3",
        23 => "Error relay failure 4", 24 => "Error relay failure 5",
        25 => "Error relay failure 6", 26 => "Too large current at relay open",
        27 => "Overtemperature"
      }

      def errors(phase)
        raise ArgumentError.new("Phase 1, 2 or 3") unless [1,2,3].include? phase
        @unit.read_holding_registers(1506 + 300 * phase, 2).to_u32
      end

      def active_errors(phase)
        value = errors(phase)
        ERRORS_BITS.filter_map { |bit, name| name if value[bit] == 1 }
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
      def initialize(unit)
        @unit = unit
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

      WARNINGS_BITS = { 0 => "Overload", 1 => "Overtemperature" }

      ERRORS_BITS = {
        0 => "Overload", 1 => "Device fault", 2 => "Communication error",
        3 => "Earthing error", 4 => "Backfeed power error", 5 => "AC source error",
        30 => "Other error"
      }

      def active_warnings(phase)
        value = warnings(phase)
        WARNINGS_BITS.filter_map { |bit, name| name if value[bit] == 1 }
      end

      def active_errors(phase)
        value = errors(phase)
        ERRORS_BITS.filter_map { |bit, name| name if value[bit] == 1 }
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

    class Converter
      def initialize(unit)
        @unit = unit
      end

      def errors
        @unit.read_holding_registers(5102, 2).to_u32
      end

      ERRORS_BITS = {
        0 => "Fans failure", 1 => "Internal temperature sensor failure",
        2 => "Abnormal voltage on acLoad port", 3 => "AcLoad port broken connexion",
        4 => "Battery port broken connexion", 5 => "Battery contactor failure",
        6 => "Inverter1 overcurrent", 7 => "Inverter2 overcurrent", 8 => "Inverter3 overcurrent",
        9 => "Inverter1 failure", 10 => "Inverter2 failure", 11 => "Inverter3 failure",
        12 => "Inverters disconnected by residual current", 13 => "Solars disconnected by residual current",
        14 => "Residual current critical failure",
        15 => "Internal power supply failure", 16 => "Internal power supply overvoltage", 17 => "Internal power supply undervoltage",
        18 => "Battery capacitors preload failed",
        19 => "Battery overvoltage", 20 => "Battery undervoltage",
        21 => "Internal dclink overvoltage", 22 => "Internal dclink undervoltage", 23 => "Internal dclink voltage unbalanced",
        24 => "Internal dcdc converter failure", 25 => "Communication error",
        26 => "Battery temperature sensor short circuit", 27 => "Battery fault",
        28 => "Inverters disconnected by solar", 29 => "Internal ADC noised"
      }

      NOISED_ADC_BITS = {
        0 => "Inverter voltage L1", 1 => "Inverter voltage L2", 2 => "Inverter voltage L3",
        3 => "Inverter current L1", 4 => "Inverter current L2", 5 => "Inverter current L3",
        6 => "PV2 inductor current", 7 => "Main power supply voltage", 8 => "Isolated PS voltage",
        9 => "AC out voltage L1", 10 => "AC out voltage L2", 11 => "AC out voltage L3",
        12 => "PV1 voltage", 13 => "DC link low voltage", 14 => "DC link high voltage",
        15 => "Battery voltage", 16 => "Battery capacitor voltage", 17 => "External PS current",
        18 => "Earth current", 19 => "PV2 voltage", 20 => "PV1 inductor current",
        21 => "Battery negative earth voltage", 22 => "PV1 positive earth voltage", 23 => "PV2 positive earth voltage",
        24 => "Transformer temperature", 25 => "Battery temperature",
        26 => "Solar 1 temperature", 27 => "Solar 2 temperature",
        28 => "Cooler plate 1 temperature", 29 => "Cooler plate 2 temperature",
        30 => "Battery power temperature"
      }

      def active_errors
        value = errors
        ERRORS_BITS.filter_map { |bit, name| name if value[bit] == 1 }
      end

      def warning_noised_adc_channels
        @unit.read_holding_registers(5156, 2).to_u32
      end

      def active_noised_adc_channels
        value = warning_noised_adc_channels
        NOISED_ADC_BITS.filter_map { |bit, name| name if value[bit] == 1 }
      end

      def error_noised_adc_channels
        @unit.read_holding_registers(5158, 2).to_u32
      end

      def active_noised_adc_error_channels
        value = error_noised_adc_channels
        NOISED_ADC_BITS.filter_map { |bit, name| name if value[bit] == 1 }
      end

      def adc_noise
        @unit.read_holding_registers(5162, 2).to_f32
      end

      def contributor_temp
        @unit.read_holding_registers(9904, 2).to_f32
      end
    end

    class Aux
      def initialize(unit, id)
        raise ArgumentError.new("Aux ID must be 1-2") unless (1..2).include? id
        @unit = unit
        @base = 8100 + 300 * (id - 1)
      end

      def is_connected
        @unit.read_holding_register(@base) != 0
      end

      # 0 = Safe state opened, 1 = Safe state closed,
      # 2 = Rel. man. opened, 3 = Rel. man. closed,
      # 4 = Rel. auto. opened, 5 = Rel. auto. closed
      def position
        @unit.read_holding_registers(@base + 1, 2).to_u32
      end

      # Operating mode: 0 = Manual Off, 1 = Manual On, 2 = Auto
      def operating_mode
        @unit.read_holding_registers(@base + 7, 2).to_u32
      end

      def operating_mode=(value)
        @unit.write_holding_registers(@base + 7, value.to_u32_to_i16s)
      end

      # Auto mode: 0 = Battery voltage, 1 = Battery SOC, etc.
      def auto_mode
        @unit.read_holding_registers(@base + 9, 2).to_u32
      end

      def auto_mode=(value)
        @unit.write_holding_registers(@base + 9, value.to_u32_to_i16s)
      end

      # SoC threshold at which relay activates (closes)
      def soc_activation_threshold
        @unit.read_holding_registers(@base + 17, 2).to_u32
      end

      def soc_activation_threshold=(value)
        @unit.write_holding_registers(@base + 17, value.to_u32_to_i16s)
      end

      # SoC threshold at which relay deactivates (opens)
      def soc_deactivation_threshold
        @unit.read_holding_registers(@base + 19, 2).to_u32
      end

      def soc_deactivation_threshold=(value)
        @unit.write_holding_registers(@base + 19, value.to_u32_to_i16s)
      end

      # Configure for genset control: auto mode with SoC thresholds
      def configure_for_genset(activation_soc: 20, deactivation_soc: 95)
        self.auto_mode = 1 # Battery SOC
        self.soc_activation_threshold = activation_soc
        self.soc_deactivation_threshold = deactivation_soc
        self.operating_mode = 2 # Auto
      end
    end
  end
end
