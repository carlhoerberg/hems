require "socket"

# Simple multithreaded HTTP server
class HTTPServer
  def initialize(controllers)
    @server = TCPServer.new("0.0.0.0", ENV.fetch("PORT", 8000).to_i)
    @queue = Queue.new
    @controllers = controllers 
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
    request = parse_request(socket) || return
    response = handle_request(request)
    send_response(socket, response)
  rescue => e
    puts "Unhandled error in worker thread: #{e.message}"
    e.backtrace.each { |line| puts "  at #{line}" }
  ensure
    socket.close
  end

  def parse_request(socket)
    remote_ip = socket.peeraddr[3] # get remote IP address first, later socket may be closed

    request_line = socket.gets("\r\n", chomp: true) || return # read request line
    method, path_query, _http_version = request_line.split(" ", 3) # ["GET", "/path", "HTTP/1.1"]

    # Parse path and query string
    path, query_string = path_query.split("?", 2)
    query = {}
    query_string&.split("&") do |pair|
      key, value = pair.split("=", 2)
      query[key] = value
    end

    # Parse headers
    headers = {}
    loop do
      line = socket.gets("\r\n", chomp: true) || return
      break if line.empty?
      key, value = line.split(": ", 2)
      headers[key.downcase] = value
    end

    # Read body if Content-Length is present
    body = if (content_length = headers["content-length"])
             socket.read(content_length.to_i)
           else
              ""
           end

    Request.new(method, path.chomp("/"), query, headers, body, remote_ip)
  end

  def handle_request(request)
    response = Response.new
    path = request.path
    first_part = path[0, path.index("/", 1) || path.length]
    if (controller = @controllers[first_part])
      begin
        case request.method
        when "GET"
          controller.do_GET(request, response)
        when "POST"
          controller.do_POST(request, response)
        else
          response.status = 405
          response.headers = {}
          response.content_type = "text/plain"
          response.body = "Method Not Allowed\n"
        end
      rescue => e
        response.status = 500
        response.headers = {}
        response.content_type = "text/plain"
        bt = e.backtrace.map { |line| "  at #{line}" }.join("\n")
        response.body = "Internal Server Error\n#{e.message}\n#{bt}\n"
      end
    else
      response.status = 404
      response.body = "Not Found\n"
    end
    response
  end

  def send_response(socket, response)
    headers = if (hdrs = response.headers)
                hdrs.flat_map { |k, v| [k, ": ", v, "\r\n"] }
              else
                []
              end
    socket.write(
      "HTTP/1.0 ", response.status_header, "\r\n",
      *headers,
      "Content-Length: ", response.body.bytesize.to_s, "\r\n\r\n",
      response.body
    )
  rescue SystemCallError => e
    puts "Error sending response to client: #{e.message}"
    puts "At line #{e.backtrace.first}"
  end

  class Request
    attr_reader :method, :path, :query, :headers, :body, :remote_ip

    def initialize(method, path, query, headers, body, remote_ip = nil)
      @method = method
      @path = path
      @query = query
      @headers = headers
      @body = body
      @remote_ip = remote_ip
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
