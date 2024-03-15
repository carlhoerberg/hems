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

    def ready_to_load?
      @genset.read_discrete_input(0x0025) == 1
    end

    def battery_voltage
      @genset.read_input_register(0x0019)
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
      @genset.read_discrete_inputs(0x0020, 40)
    end
  end
end
