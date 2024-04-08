require "json"

class Devices
  class Starlink
    def status
      json = `grpcurl -plaintext -d '{"get_status": {}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle`
      raise Error.new("Status failure: #{json}") unless $?.success?

      JSON.parse(json)
    end

    class Error < StandardError; end
  end
end
