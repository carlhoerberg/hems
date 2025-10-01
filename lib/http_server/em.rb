class HTTPServer
  class EMControl
    def initialize(em)
      @em = em
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "em_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({ em: @em })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "genset_auto_started" then @em.genset_auto_started = true
      when "genset_manually_started" then @em.genset_auto_started = false
      when "stop_genset" then @em.stop_genset
      when "start_genset" then @em.start_genset
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
