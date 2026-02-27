require_relative "../modbus/tcp"

class HTTPServer
  class ModbusControl
    FORMATS = {
      "u16" => { count: 1, unpack: "n" },
      "i16" => { count: 1, unpack: "s>" },
      "u32" => { count: 2, unpack: "N" },
      "i32" => { count: 2, unpack: "l>" },
      "u64" => { count: 4, unpack: "Q>" },
      "i64" => { count: 4, unpack: "q>" },
      "f32" => { count: 2, unpack: "g" },
      "f64" => { count: 4, unpack: "G" },
    }

    def do_GET(req, res)
      # /modbus/:hostname/:unit_id/:function_code/:register_address/:number_format
      parts = req.path.split("/")
      # parts: ["", "modbus", hostname, unit_id, function_code, register_address, number_format]
      unless parts.length == 7
        res.status = 400
        res.content_type = "text/plain"
        res.body = "Usage: /modbus/:hostname/:unit_id/:function_code/:register_address/:number_format\n"
        return
      end

      hostname = parts[2]
      unit_id = parts[3].to_i
      function_code = parts[4].to_i
      register_address = parts[5].to_i(0) # support hex with 0x prefix
      number_format = parts[6]

      fmt = FORMATS[number_format]
      unless fmt
        res.status = 400
        res.content_type = "text/plain"
        res.body = "Unknown format: #{number_format}. Valid: #{FORMATS.keys.join(", ")}\n"
        return
      end

      modbus = Modbus::TCP.new(hostname)
      begin
        registers = case function_code
                    when 3 then modbus.read_holding_registers(register_address, fmt[:count], unit_id)
                    when 4 then modbus.read_input_registers(register_address, fmt[:count], unit_id)
                    else
                      res.status = 400
                      res.content_type = "text/plain"
                      res.body = "Unsupported function code: #{function_code}. Valid: 3, 4\n"
                      return
                    end

        value = registers.pack("n*").unpack1(fmt[:unpack])

        res.content_type = "text/plain"
        res.body = value.to_s
      ensure
        modbus.close
      end
    end
  end
end
