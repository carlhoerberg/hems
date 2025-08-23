class HTTPServer
  class EnvistarControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, envistar)
      super(server)
      @envistar = envistar
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "envistar_control.erb")))

    def do_GET(req, res)
      if req.path == "/envistar/set"
        # Handle operating mode change
        if req.query["operating_mode"]
          mode = req.query["operating_mode"].to_i
          @envistar.operating_mode = mode + 1 if (-1..3).include?(mode)
        end
        
        # Redirect back to index
        res.status = 302
        res["Location"] = "/envistar"
        return
      end
      
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({
        measurements: @envistar.measurements,
        alarms: @envistar.alarms,
        current_operating_mode: @envistar.operating_mode - 1,
        operating_modes: {
          -1 => "Auto",
          0 => "Off", 
          1 => "Stage 1",
          2 => "Stage 2",
          3 => "Stage 3"
        }
      })
    end
  end
end