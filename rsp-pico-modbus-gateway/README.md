# RSP Pico Modbus Gateway

A Modbus TCP to RTU gateway implementation for Raspberry Pi Pico (or compatible microcontrollers) using MicroPython. This gateway allows TCP/IP clients to communicate with Modbus RTU devices over RS485.

## Features

- **Modbus TCP Server** on port 502
- **HTTP Web Interface** on port 80 for testing and configuration
- **Modbus RTU Client** via RS485/UART
- **Concurrent Operation** - handles multiple TCP and HTTP connections simultaneously
- **Thread Safety** - prevents RTU request intermingling using async locks

## Supported Modbus Functions

### Data Access Functions
- **Function Code 01**: Read Coils
- **Function Code 02**: Read Discrete Inputs
- **Function Code 03**: Read Holding Registers
- **Function Code 04**: Read Input Registers
- **Function Code 05**: Write Single Coil
- **Function Code 06**: Write Single Register
- **Function Code 15**: Write Multiple Coils
- **Function Code 16**: Write Multiple Holding Registers

All standard Modbus data access functions are supported with proper bit packing/unpacking for coil operations and comprehensive error handling.

## Hardware Requirements

- Raspberry Pi Pico (or compatible MicroPython board)
- RS485 HAT/Module (e.g., Waveshare RS485 HAT)
- WiFi connectivity

## Pin Configuration

Default pin assignments (configurable in code):
- **UART0 TX**: Pin 0
- **UART0 RX**: Pin 1
- **RS485 DE**: Pin 2 (Direction Enable)
- **Baudrate**: 9600 (configurable)

## Installation

1. Flash MicroPython firmware to your Pico
2. Copy `main.py` to the Pico's filesystem
3. Update WiFi credentials in the code:
   ```python
   WIFI_SSID = "YOUR_WIFI_SSID"
   WIFI_PASSWORD = "YOUR_WIFI_PASSWORD"
   ```
4. Reset the Pico to start the gateway

## Usage

### Web Interface

Access `http://[PICO_IP_ADDRESS]` to use the web-based testing interface:
- Select Modbus function (Read Coils/Discrete Inputs/Registers, Write Coils/Registers)
- Set slave ID, start address, and count/values
- For coil operations: use boolean values (1/0, true/false, on/off)
- Execute requests and view responses

### Modbus TCP Client

Connect to port 502 on the Pico's IP address using any Modbus TCP client:
```python
# Example using pymodbus
from pymodbus.client.sync import ModbusTcpClient

client = ModbusTcpClient('192.168.1.100', port=502)
result = client.read_holding_registers(0, 10, unit=1)
```

### HTTP API

Direct API access for programmatic control:

#### Read Functions
```
GET /api/read_coils?slave_id=1&start_addr=0&count=10
GET /api/read_discrete?slave_id=1&start_addr=0&count=10
GET /api/read_holding?slave_id=1&start_addr=0&count=10
GET /api/read_input?slave_id=1&start_addr=0&count=10
```

#### Write Functions
```
GET /api/write_coil?slave_id=1&start_addr=0&value=1
GET /api/write_single?slave_id=1&start_addr=0&value=1234
GET /api/write_coils?slave_id=1&start_addr=0&values=1,0,1,0,1
GET /api/write_multiple?slave_id=1&start_addr=0&values=1,2,3,4,5
```

**Note**: For coil operations, use boolean values: `1/0`, `true/false`, `on/off`, `yes/no`

## API Response Format

All API responses return JSON:

**Read Operations**:
```json
{
  "success": true,
  "data": [1, 2, 3, 4, 5]
}
```

**Coil Read Operations**:
```json
{
  "success": true,
  "data": [true, false, true, false, true]
}
```

**Write Operations**:
```json
{
  "success": true,
  "message": "Register written successfully"
}
```

**Error Responses**:
```json
{
  "success": false,
  "error": "Communication timeout"
}
```

## Configuration

### WiFi Settings
Update in `main()` function:
```python
WIFI_SSID = "your_network_name"
WIFI_PASSWORD = "your_password"
```

### Modbus RTU Settings
Update in `main()` function:
```python
modbus = ModbusRTU(
    uart_id=0,      # UART port
    baudrate=9600,  # Baud rate
    tx_pin=0,       # TX pin
    rx_pin=1,       # RX pin
    de_pin=2        # Direction enable pin
)
```

### Server Ports
- HTTP Server: Port 80 (configurable)
- Modbus TCP Server: Port 502 (standard)

## Architecture

### Classes

- **ModbusRTU**: Handles RTU protocol communication over UART/RS485
- **ModbusTCPServer**: Implements Modbus TCP server on port 502
- **HTTPServer**: Provides web interface and REST API on port 80

### Async Operation

The gateway uses `asyncio` for concurrent operation:
- Both servers run simultaneously using `asyncio.gather()`
- RTU requests are serialized using `asyncio.Lock()` to prevent interference
- Non-blocking socket operations with proper error handling

### Protocol Translation

TCP requests are translated to RTU:
1. Parse Modbus TCP MBAP header
2. Extract PDU (Protocol Data Unit)
3. Forward to RTU device via RS485
4. Translate response back to TCP format

## Error Handling

- **Communication Timeouts**: 1-second timeout for RTU responses
- **CRC Validation**: Automatic CRC calculation and verification
- **Modbus Exceptions**: Proper error code translation
- **Connection Management**: Automatic cleanup of failed connections

## Development

### Adding New Functions

To add support for additional Modbus function codes:

1. Add handler in `ModbusRTU` class
2. Add TCP handler in `ModbusTCPServer._process_modbus_request()`
3. Add HTTP API endpoint in `HTTPServer.handle_api()`
4. Update web interface if needed

### Debugging

Enable debug output by adding print statements or use the web interface to test individual requests.

## License

This project is provided as-is for educational and development purposes.