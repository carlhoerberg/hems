require_relative "../modbus/tcp"

# Östberg HERU FTX ventilation unit (HERU 62-250, Gen 3)
# Registers as per "Modbus Registers HERU v0.7"
class Devices
  class Heru
    # Digital inputs, not alarms
    INPUT_KEYS = %i[fire_alarm_switch boost_switch overpressure_switch aux_switch].freeze
    # Status bits reported among the discrete inputs, not alarms
    STATE_KEYS = %i[freeze_protection_b_level freeze_protection_a_level startup_1st_phase
                    startup_2nd_phase heating recovering_heat_cold cooling co2_boost rh_boost].freeze
    FAN_SPEEDS = ["Off", "Min", "Std", "Mod", "Max"].freeze
    REGULATION_MODES = ["Supply", "Exhaust", "Room"].freeze

    def initialize(host = "192.168.0.5", port = 502, unit: 1)
      @modbus = Modbus::TCP.new(host, port).unit(unit)
    end

    def on?
      read "0x00001"
    end

    def on=(value)
      write "0x00001", value ? true : false
    end

    def overpressure_mode?
      read "0x00002"
    end

    def overpressure_mode=(value)
      write "0x00002", value ? true : false
    end

    def boost_mode?
      read "0x00003"
    end

    def boost_mode=(value)
      write "0x00003", value ? true : false
    end

    def away_mode?
      read "0x00004"
    end

    def away_mode=(value)
      write "0x00004", value ? true : false
    end

    def clear_alarms
      write "0x00005", true
    end

    def reset_filter_timer
      write "0x00006", true
    end

    def modes
      v = @modbus.read_coils(0, 4)
      {
        on: v[0],
        overpressure: v[1],
        boost: v[2],
        away: v[3],
      }
    end

    def temperatures
      v = @modbus.read_input_registers(1, 7).pack("n*").unpack("s>*")
      {
        outdoor: v[0] / 10.0,
        supply: v[1] / 10.0,
        exhaust: v[2] / 10.0, # extract air, from the rooms
        waste: v[3] / 10.0,   # air blown out
        water: v[4] / 10.0,
        heat_recovery_wheel: v[5] / 10.0,
        room: v[6] / 10.0,
      }
    end

    def measurements
      v = @modbus.read_input_registers(1, 32).pack("n*").unpack("s>*")
      {
        outdoor_temperature: v[0] / 10.0,
        supply_air_temperature: v[1] / 10.0,
        exhaust_air_temperature: v[2] / 10.0,
        waste_air_temperature: v[3] / 10.0,
        water_temperature: v[4] / 10.0,
        heat_recovery_wheel_temperature: v[5] / 10.0,
        room_temperature: v[6] / 10.0,
        supply_pressure: v[10] / 10.0,
        exhaust_pressure: v[11] / 10.0,
        relative_humidity: v[12] / 10.0,
        carbon_dioxide: v[13],
        sensors_open: v[16],
        sensors_shorted: v[17],
        filter_days_left: v[18],
        current_weektimer_program: v[19],
        current_fan_speed: v[20],
        current_supply_fan_step: v[21],
        current_exhaust_fan_step: v[22],
        current_supply_fan_power: v[23],
        current_exhaust_fan_power: v[24],
        current_supply_fan_speed: v[25],
        current_exhaust_fan_speed: v[26],
        current_heating_power: (v[27] * 100 / 255.0).round(1),
        current_heat_cold_recovery_power: (v[28] * 100 / 255.0).round(1),
        current_cooling_power: (v[29] * 100 / 255.0).round(1),
        supply_fan_control_voltage: v[30] / 10.0,
        exhaust_fan_control_voltage: v[31] / 10.0,
      }
    end

    def outdoor_temperature
      read_i16("3x00002") / 10.0
    end

    def supply_air_temperature
      read_i16("3x00003") / 10.0
    end

    # 0 = Off, 1 = Min, 2 = Std, 3 = Mod, 4 = Max
    def current_fan_speed
      read "3x00022"
    end

    def filter_days_left
      read "3x00020"
    end

    def alarms
      # 1x00005-1x00009 doesn't exist, the unit doesn't answer requests spanning them
      sw = @modbus.read_discrete_inputs(0, 4)
      v = @modbus.read_discrete_inputs(9, 25)
      {
        fire_alarm_switch: sw[0],
        boost_switch: sw[1],
        overpressure_switch: sw[2],
        aux_switch: sw[3],
        fire_alarm: v[0],
        rotor_alarm: v[1],
        freeze_alarm: v[3],
        low_supply_alarm: v[4],
        low_rotor_temperature_alarm: v[5],
        temperature_sensor_open_circuit_alarm: v[8],
        temperature_sensor_short_circuit_alarm: v[9],
        pulser_alarm: v[10],
        supply_fan_alarm: v[11],
        exhaust_fan_alarm: v[12],
        supply_filter_alarm: v[13],
        exhaust_filter_alarm: v[14],
        filter_timer_alarm: v[15],
        freeze_protection_b_level: v[16],
        freeze_protection_a_level: v[17],
        startup_1st_phase: v[18],
        startup_2nd_phase: v[19],
        heating: v[20],
        recovering_heat_cold: v[21],
        cooling: v[22],
        co2_boost: v[23],
        rh_boost: v[24],
      }
    end

    # Any real alarm active, ignoring the inputs and status bits
    def active_alarms
      alarms.except(*INPUT_KEYS, *STATE_KEYS).select { |_, v| v }.keys
    end

    # 15-40 °C
    def temperature_setpoint
      read "4x00002"
    end

    def temperature_setpoint=(value)
      write "4x00002", value.round.clamp(15, 40)
    end

    # 0 = Off, 1 = Min, 2 = Std, 3 = Mod, 4 = Max, AC fans only
    def user_fan_speed
      read "4x00001"
    end

    def user_fan_speed=(value)
      write "4x00001", value.clamp(0, 4)
    end

    # Supply fan speed in % for EC fans
    def supply_fan_speed
      read "4x00003"
    end

    def supply_fan_speed=(value)
      write "4x00003", value.round.clamp(0, 100)
    end

    # Exhaust fan speed in % for EC fans
    def exhaust_fan_speed
      read "4x00004"
    end

    def exhaust_fan_speed=(value)
      write "4x00004", value.round.clamp(0, 100)
    end

    def settings
      v = @modbus.read_holding_registers(0, 53).pack("n*").unpack("s>*")
      {
        user_fan_speed: v[0],
        temperature_setpoint: v[1],
        supply_fan_speed: v[2],
        exhaust_fan_speed: v[3],
        min_exhaust_fan_speed: v[4],
        mod_exhaust_fan_speed: v[5],
        max_exhaust_fan_speed: v[6],
        min_supply_temperature: v[9],
        max_supply_temperature: v[10],
        regulation_mode: v[11],
        snc_indoor_outdoor_diff_limit: v[12] / 10.0,
        snc_exhaust_low_limit: v[13],
        snc_exhaust_high_limit: v[14],
        snc_enable: v[15],
        freeze_protection_limit: v[16],
        co2_limit: v[19] * 10,
        co2_interval: v[20],
        co2_ramp: v[21],
        rh_limit: v[22],
        rh_interval: v[23],
        rh_ramp: v[24],
        boost_speed: v[25],
        boost_duration: v[26],
        overpressure_duration: v[27],
        supply_cold_limit_a: v[28],
        supply_cold_limit_b: v[29],
        filter_speed_increase: v[39],
        filter_change_period: v[43],
        sensor_calibration: v[46] / 10.0,
        maximum_temperature: v[47],
        water_heater_connected: v[49],
        electric_heater_connected: v[50],
        cooler_connected: v[51],
        flow_direction: v[52],
      }
    end

    # Read addresses as defined in the docs,
    # eg. 3x00002 where 3 means input register and 2 the register number (1-indexed)
    def read(addr)
      reg = addr[2..].to_i - 1
      case addr[0]
      when "0" then @modbus.read_coil(reg)
      when "1" then @modbus.read_discrete_input(reg)
      when "3" then @modbus.read_input_register(reg)
      when "4" then @modbus.read_holding_register(reg)
      end
    end

    # Read a register as a signed 16 bit integer
    def read_i16(addr)
      [read(addr)].pack("n").unpack1("s>")
    end

    def write(addr, value)
      reg = addr[2..].to_i - 1
      case addr[0]
      when "0" then @modbus.write_coil(reg, value)
      when "4" then @modbus.write_holding_register(reg, value)
      else raise ArgumentError, "Register #{addr} is read only"
      end
    end
  end
end
