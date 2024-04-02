require "webrick"
require "zlib"

class PrometheusMetrics
  def initialize(devices)
    next3 = ERB.new(File.read(File.join(__dir__, "..", "views", "next3.erb")))
    genset = ERB.new(File.read(File.join(__dir__, "..", "views", "genset.erb")))
    eta = ERB.new(File.read(File.join(__dir__, "..", "views", "eta.erb")))
    starlink = ERB.new(File.read(File.join(__dir__, "..", "views", "starlink.erb")))
    @server = WEBrick::HTTPServer.new(
      Port: ENV.fetch("PORT", 8000).to_i,
      AccessLog: [[STDOUT, "#{WEBrick::AccessLog::COMMON_LOG_FORMAT} %T"]])
    @server.mount_proc("/metrics") do |req, res|
      res.content_type = "text/plain"
      metrics = ""
      begin
        metrics << next3.result_with_hash({ next3: devices.next3 })
      rescue => ex
        STDERR.puts "Could not fetch next3 metrics: #{ex.inspect}"
        ex.backtrace.each { |l| STDERR.print "\t", l, "\n" }
      end
      begin
        metrics << genset.result_with_hash({ measurements: devices.genset.measurements })
      rescue => ex
        STDERR.puts "Could not fetch genset metrics: #{ex.inspect}"
        ex.backtrace.each { |l| STDERR.print "\t", l, "\n" }
      end
      begin
        metrics << eta.result_with_hash({ eta: devices.eta })
      rescue => ex
        STDERR.puts "Could not fetch ETA metrics: #{ex.inspect}"
        ex.backtrace.each { |l| STDERR.print "\t", l, "\n" }
      end
      begin
        metrics << starlink.result_with_hash({ status: devices.starlink.status })
      rescue => ex
        STDERR.puts "Could not fetch starlink metrics: #{ex.inspect}"
        ex.backtrace.each { |l| STDERR.print "\t", l, "\n" }
      end
      if req.accept_encoding.include? "gzip"
        res["content-encoding"] = "gzip"
        res.body = Zlib.gzip(metrics)
      else
        res.body = metrics
      end
    end
    @server.mount_proc("/eta") do |req, res|
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
