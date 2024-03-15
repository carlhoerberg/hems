require_relative "../modbus/rtu"

module Devices
  class Genset
    def initialize
      @genset = Modbus::RTU.new.unit(5)
    end

    def start
      @genset.write_coil(0, true)
    end

    def stop
      @genset.write_coil(1, true)
    end

    def auto
      @genset.write_coil(2, true)
    end

    def battery_voltage
      @genset.read_input_register(0x0019) / 10
    end

    def oil_pressure
      @genset.read_input_register(0x001C)
    end

    def coolant_temperature
      @genset.read_input_register(0x001D)
    end

    def fuel_level
      @genset.read_input_register(0x001E)
    end

    def maintenance_timer
      @genset.read_input_register(0x0023)
    end

    def start_counter
      @genset.read_input_register(0x0024)
    end

    def status
      keys = %i[
        starter
        fuel_solenoid
        stop_solenoid
        general_alarm
        gcb_open
        ready_to_load
        preheat
        running
        automatic_mode
        island_operation
        common_warning,
        maintenance_required
        low_battery
        low_fuel_level
        external_warning1
        external_warning2
        external_warning3
        generator_ccw_rotation
        battery_flat
        common_shutdown
        emergency_stop_active
        overspeed
        underspeed
        low_oil_pressure
        high_coolant_temperature
        external_shutdown1
        external_shutdown2
        external_shutdown3
        gcb_fail
        max_generator_voltage
        min_generator_voltage
        max_generator_frequency
        min_generator_frequency
        start_fail
        stop_fail
        generator_short_circuit
        generating_set_overload
        choke
        glow_plugs
        valve_extinguisher
      ]
      values = @genset.read_discrete_inputs(0x0020, 40)
      keys.zip(values).to_h
    end

    def ready_to_load?
      @genset.read_discrete_input(0x0025) == 1
    end

    def measurements
      @genset.read_input_registers(0, 40)
    end
  end
end
