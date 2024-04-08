class Devices
  class ShellyHT
    attr_reader :device_id
    attr_accessor :humidity, :temperature

    def initialize(device_id)
      @device_id = device_id
    end
  end
end
