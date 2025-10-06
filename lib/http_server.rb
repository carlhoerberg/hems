require "socket"
require "erb"
require_relative "./http_server/metrics"
require_relative "./http_server/relays"
require_relative "./http_server/genset"
require_relative "./http_server/button"
require_relative "./http_server/topas"
require_relative "./http_server/casa"
require_relative "./http_server/envistar"
require_relative "./http_server/em"
require_relative "./http_server/eta"

# Simple multithreaded HTTP server
class HTTPServer
  def initialize(devices, em)
    @server = TCPServer.new("0.0.0.0", ENV.fetch("PORT", 8000).to_i)
    @queue = Queue.new
    @controllers = {
      "/metrics" => Metrics.new(devices),
      "/relays" => RelaysControl.new(devices.relays),
      "/genset" => GensetControl.new(devices.genset),
      "/button1" => ButtonControl.new(devices),
      "/topas" => TopasControl.new(devices.topas),
      "/casa" => CasaControl.new(devices.casa),
      "/envistar" => EnvistarControl.new(devices.envistar),
      "/eta" => ETAControl.new(devices.eta),
      "/em" => EMControl.new(em),
    }
  end

  def start
    @workers = 8.times.map do
      Thread.new do
        loop do
          client = @queue.pop || break
          handle_client(client)
        end
      end
    end

    puts "Starting HTTP server on port #{@server.addr[1]}..."
    loop do
      socket = @server.accept
      @queue << socket
    end
  rescue IOError
    # server closed
  rescue ClosedQueueError
    @server.close
  end

  def stop
    puts "Stopping HTTP server..."
    @server.close
    @queue.close
    @workers&.each(&:join)
  end

  private

  def handle_client(socket)
    loop do
      request_line = socket.gets("\r\n", chomp: true)
      break if request_line.nil?
      next if request_line.empty?

      method, path_query, http_version = request_line.split(" ", 3) # ["GET", "/path", "HTTP/1.1"]
      http_version ||= "HTTP/1.0"
      status_line_version = http_version.start_with?("HTTP/") ? http_version : "HTTP/1.0"

      # Parse path and query string
      path_query ||= "/"
      path, query_string = path_query.split("?", 2)
      query = {}
      query_string&.split("&") do |pair|
        key, value = pair.split("=", 2)
        query[key] = value
      end

      # Parse headers
      headers = {}
      loop do
        line = socket.gets("\r\n", chomp: true)
        return if line.nil?
        break if line.empty?
        key, value = line.split(": ", 2)
        headers[key.downcase] = value
      end

      # Read body if Content-Length is present
      body = if headers["content-length"]
               socket.read(headers["content-length"].to_i)
             else
               ""
             end

      # Handle the request
      request = Request.new(method, path.chomp("/"), query, headers, body, status_line_version)
      response = Response.new
      first_part = path[0, path.index("/", 1) || path.length]
      if (controller = @controllers[first_part])
        begin
          case method
          when "GET"
            controller.do_GET(request, response)
          when "POST"
            controller.do_POST(request, response)
          else
          end
        rescue => e
          response.status = 500
          response.headers = {}
          response.content_type = "text/plain"
          response.body = "Internal Server Error\n#{e.message}\n"
        end
      else
        response.status = 404
        response.body = "Not Found\n"
      end

      connection_header = headers["connection"]&.downcase
      keep_alive = case status_line_version
                   when "HTTP/1.1"
                     connection_header != "close"
                   when "HTTP/1.0"
                     connection_header == "keep-alive"
                   else
                     false
                   end

      response.headers ||= {}
      response.headers["Connection"] ||= keep_alive ? "keep-alive" : "close"

      response_body = response.body || ""
      socket.print "#{status_line_version} #{response.status_header}\r\n"
      response.headers.each do |key, value|
        socket.print "#{key}: #{value}\r\n"
      end
      socket.print "Content-Length: #{response_body.bytesize}\r\n"
      socket.print "\r\n"
      socket.print response_body

      break unless keep_alive
    end
  ensure
    socket.close
  end

  class Request
    attr_reader :method, :path, :query, :headers, :body, :http_version

    def initialize(method, path, query, headers, body, http_version)
      @method = method
      @path = path
      @query = query
      @headers = headers
      @body = body
      @http_version = http_version
    end
  end

  class Response
    attr_accessor :status, :headers, :body

    def initialize(status = 200, headers = {}, body = "")
      @status = status
      @headers = headers
      @body = body
    end

    def content_type=(type)
      self.headers ||= {}
      self.headers["Content-Type"] = type
    end

    def []=(key, value)
      self.headers ||= {}
      self.headers[key] = value
    end

    def status_header
      case status
      when 200 then "200 OK"
      when 201 then "201 Created"
      when 303 then "303 See Other"
      when 400 then "400 Bad Request"
      when 401 then "401 Unauthorized"
      when 403 then "403 Forbidden"
      when 404 then "404 Not Found"
      when 500 then "500 Internal Server Error"
      else "#{status} Unknown Status"
      end
    end
  end
end
