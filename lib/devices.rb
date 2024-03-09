require_relative "./modbus/tcp"
require_relative "./modbus/rtu"

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
end

class Next3
  attr_reader :battery, :acsource

  def initialize(host, port)
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

class Relays
  def initialize(host, port = 502)
    @modbus = Modbus::TCP.new(host, port)
  end

  def activate(id)
    @modbus.write_coil(id, true, 1)
  end

  def deactivate(id)
    @modbus.write_coil(id, false, 1)
  end
end

class PelletsBoiler
  def initialize(host, port = 502)
    @modbus = Modbus::TCP.new(host, port)
  end
end

class Array
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
