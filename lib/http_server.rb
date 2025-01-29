require "webrick"
require_relative "./http_server/metrics"
require_relative "./http_server/relays"
require_relative "./http_server/genset"
require_relative "./http_server/button"
require_relative "./http_server/topas"

class HTTPServer
  def initialize(devices)
    @server = WEBrick::HTTPServer.new(Port: ENV.fetch("PORT", 8000).to_i,
                                      AccessLog: [])
    @server.mount "/metrics", Metrics, devices
    @server.mount "/relays", RelaysControl, devices.relays
    @server.mount "/genset", GensetControl, devices.genset
    @server.mount "/button1", ButtonControl, devices
    @server.mount "/topas", TopasControl, devices.topas
    @server.mount_proc("/eta") do |_req, res|
      res.content_type = "application/xml"
      res.body = devices.eta.menu
    end
  end

  def start
    @server.start
  end

  def stop
    @server.shutdown
  end
end
