require_relative "../modbus/rtu"

class Devices
  class Weco
    using Modbus::TypeExtensions

    def initialize
      @weco = Modbus::RTU.new("/tmp/weco").unit(1)
    end

    def any
      @weco.read_holding_registers(40, 6)
    end
  end
end
