require "webrick"
require "zlib"

class PrometheusMetrics
  def initialize(devices)
    @server = WEBrick::HTTPServer.new(Port: ENV.fetch("PORT", 8000).to_i,
                                      AccessLog: [])
    @server.mount "/metrics", Metrics, devices
    @server.mount "/relays", RelaysControl, devices.relays
    @server.mount "/genset", GensetControl, devices.genset
    @server.mount "/button1", ButtonControl, devices
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

  class RelaysControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, relays)
      super(server)
      @relays = relays
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "views", "relays_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({ status: @relays.status })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      @relays.toggle(form["id"].to_i)
      res.status = 303
      res["location"] = req.path
    end
  end

  class GensetControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, genset)
      super(server)
      @genset = genset
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "views", "genset_control.erb")))

    def do_GET(req, res)
      case req.path
      when %r(/start$)
        @genset.start
        res.body = "started"
      when %r(/stop$)
        @genset.stop
        res.body = "stopped"
      else
        res.content_type = "text/html"
        res.body = @@view.result_with_hash({ status: @genset.status,
                                             measurements: @genset.measurements })
      end
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "start" then @genset.start
      when "stop" then @genset.stop
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end

  class Metrics < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, devices)
      super(server)
      @devices = devices
    end

    @@next3 = ERB.new(File.read(File.join(__dir__, "..", "views", "next3.erb")))
    @@genset = ERB.new(File.read(File.join(__dir__, "..", "views", "genset.erb")))
    @@eta = ERB.new(File.read(File.join(__dir__, "..", "views", "eta.erb")))
    @@starlink = ERB.new(File.read(File.join(__dir__, "..", "views", "starlink.erb")))
    @@shelly = ERB.new(File.read(File.join(__dir__, "..", "views", "shelly.erb")))
    @@ups = ERB.new(File.read(File.join(__dir__, "..", "views", "ups.erb")))
    @@unifi = ERB.new(File.read(File.join(__dir__, "..", "views", "unifi.erb")))
    @@topas = ERB.new(File.read(File.join(__dir__, "..", "views", "topas.erb")))

    def do_GET(req, res)
      res.content_type = "text/plain"
      threads = [
        Thread.new { @@next3.result_with_hash({ t:, next3: @devices.next3 }) },
        Thread.new { @@eta.result_with_hash({ t:, eta: @devices.eta }) },
        Thread.new { @@starlink.result_with_hash({ t:, status: @devices.starlink.status }) },
        Thread.new { @@shelly.result_with_hash({ t:, shelly: @devices.shelly }) },
        Thread.new { @@ups.result_with_hash({ t:, ups: @devices.ups }) },
        Thread.new { @@unifi.result_with_hash({ t:, unifi_health: @devices.unifi.health }) },
        Thread.new { @@topas.result_with_hash({ t:, measurements: @topas.measurements }) },
        Thread.new do
          @@genset.result_with_hash({ t:, measurements: @devices.genset.measurements })
        rescue EOFError
          warn "Genset is offline"
        end,
      ]
      metrics = ""
      threads.each do |t|
        metrics << (t.value || "")
      rescue
        # Thread#report_on_exception
      end
      if req.accept_encoding.include? "gzip"
        res["content-encoding"] = "gzip"
        res.body = Zlib.gzip(metrics)
      else
        res.body = metrics
      end
    end

    def t
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

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
      when %r(/3$)
        @devices.genset.close_air_vents
      when %r(/4$)
        @devices.genset.start
      else
        raise HTTPStatus::NotFound, "not found."
      end
    end
  end
end
