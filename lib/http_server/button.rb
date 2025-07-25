class HTTPServer
  class ButtonControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, devices)
      super(server)
      @devices = devices
    end

    def do_GET(req, res)
      case req.path
      when %r(/short$)
        @devices.relays.open_air_vents
      when %r(/double$)
        @devices.genset.stop
        @devices.genset.close_air_vents
      when %r(/triple$)
        @devices.genset.close_air_vents
      when %r(/long$)
        @devices.relays.open_air_vents
        @devices.genset.start
      else
        raise WEBrick::HTTPStatus::NotFound
      end
    end
  end
end
