class HTTPServer
  class WecoControl
    def initialize(weco)
      @weco = weco
    end

    def do_GET(req, res)
      res.content_type = "application/json"
      res.body = @weco.values.map(&:master).to_json
    end
  end
end
