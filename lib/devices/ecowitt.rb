require_relative "../modbus/rtu"

class Devices
  class Ecowitt
    def initialize
      @m = Modbus::RTU.new("/dev/ttyUSB1").unit(0x90)
    end

    def measurements
      values = @m.read_holding_registers(0x0165, 9)
      {
        light: values[0] * 10,
        uvi: (values[1] * 0.1).round(1),
        temperature: ((values[2] - 400) * 0.1).round(1),
        humidity: values[3],
        wind_speed: (values[4] * 0.1).round(1),
        gust_speed: (values[5] * 0.1).round(1),
        wind_direction: values[6],
        rainfall: (values[7] * 0.1).round(1),
        abs_pressure: (values[8] * 0.1).round(1),
      }
    end
  end
end
