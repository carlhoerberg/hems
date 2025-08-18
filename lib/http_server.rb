require "webrick"
require_relative "./http_server/metrics"
require_relative "./http_server/relays"
require_relative "./http_server/genset"
require_relative "./http_server/button"
require_relative "./http_server/topas"
require_relative "./http_server/casa"
require_relative "./http_server/em"
require_relative "./http_server/eta"

class HTTPServer
  def initialize(devices, em)
    @server = WEBrick::HTTPServer.new(Port: ENV.fetch("PORT", 8000).to_i,
                                      AccessLog: [])
    @server.mount "/metrics", Metrics, devices
    @server.mount "/relays", RelaysControl, devices.relays
    @server.mount "/genset", GensetControl, devices.genset
    @server.mount "/button1", ButtonControl, devices
    @server.mount "/topas", TopasControl, devices.topas
    @server.mount "/casa", CasaControl, devices.casa
    @server.mount "/eta", ETAControl, devices.eta
    @server.mount "/em", EMControl, em
  end

  def start
    @server.start
  end

  def stop
    @server.shutdown
  end
end
