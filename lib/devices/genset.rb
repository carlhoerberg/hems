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
      @genset.write_coil(0, false)
    end

    def ready_to_load?
      @genset.read_discrete_input(0x0025) == 1
    end

    def fuel_level
      @genset.read_input_register(0x001E)
    end
  end
end
