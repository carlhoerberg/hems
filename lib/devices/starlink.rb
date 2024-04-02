require "json"

class Devices
  class Starlink
    def status
      json = `grpcurl -plaintext -d '{"get_status": {}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle`
      raise "Starlink status failure: #{json}" unless $?.success?

      JSON.parse(json)
    end
  end
end
