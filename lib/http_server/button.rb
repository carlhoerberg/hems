class HTTPServer
  class ButtonControl
    def initialize(devices)
      @devices = devices
    end

    def do_GET(req, res)
      case req.path
      when %r(/short$)
        res.status = 204
      when %r(/double$)
        @devices.next3.aux1.operating_mode = 2 # Auto
        res.status = 204
      when %r(/triple$)
        res.status = 204
      when %r(/long$)
        @devices.next3.aux1.operating_mode = 1 # Manual On
        res.status = 204
      else
        res.status = 404
        res.body = 'Not Found'
      end
    end
  end
end
