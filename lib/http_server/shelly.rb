require "json"

class HTTPServer
  class ShellyControl
    def initialize(em)
      @em = em
    end

    def do_GET(req, res)
      case req.path
      when "/shelly/register"
        host = req.remote_ip
        amps = (req.query["amps"] || 16).to_f
        result = @em.register_shelly_demand(host, amps)
        res.content_type = "application/json"
        res.body = { status: "registered", host:, amps:, **result }.to_json

      when "/shelly/deregister"
        host = req.remote_ip
        @em.deregister_shelly_demand(host)
        res.content_type = "application/json"
        res.body = { status: "deregistered", host: }.to_json

      when "/shelly/status"
        res.content_type = "application/json"
        res.body = @em.shelly_demands_status.to_json

      else
        res.status = 404
        res.body = "Not Found\n"
      end
    end
  end
end
