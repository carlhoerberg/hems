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
      when "aux_manual_on" then @em.set_aux_mode(1)
      when "aux_manual_off" then @em.set_aux_mode(0)
      when "aux_auto" then @em.set_aux_mode(2)
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
