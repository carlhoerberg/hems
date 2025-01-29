class HTTPServer
  class ButtonControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, devices)
      super(server)
      @devices = devices
    end

    def do_GET(req, res)
      case req.path
      when %r(/1$)
        @devices.relays.open_air_vents
      when %r(/2$)
        @devices.genset.stop
        @devices.genset.close_air_vents
      when %r(/3$)
        @devices.genset.close_air_vents
      when %r(/4$)
        @devices.relays.open_air_vents
        @devices.genset.start
      else
        raise HTTPStatus::NotFound, "not found."
      end
    end
  end
end
