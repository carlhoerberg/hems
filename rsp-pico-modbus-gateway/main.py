import network
import socket
import time
import json
from machine import Pin, UART
import uasyncio as asyncio
import gc
import struct

# Modbus RTU implementation
class ModbusRTU:
    def __init__(self, uart_id=0, baudrate=9600, tx_pin=0, rx_pin=1, de_pin=2):
        self.uart = UART(uart_id, baudrate=baudrate, tx=Pin(tx_pin), rx=Pin(rx_pin))
        self.de_pin = Pin(de_pin, Pin.OUT)  # Direction Enable pin for RS485
        self.de_pin.value(0)  # Start in receive mode
        self.lock = asyncio.Lock()  # Prevent concurrent RTU requests

    def _calculate_crc(self, data):
        """Calculate Modbus CRC16"""
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc >>= 1
                    crc ^= 0xA001
                else:
                    crc >>= 1
        return crc.to_bytes(2, 'little')

    def _send_request(self, frame):
        """Send Modbus RTU frame"""
        # Calculate and append CRC
        crc = self._calculate_crc(frame)
        complete_frame = frame + crc

        # Switch to transmit mode
        self.de_pin.value(1)
        time.sleep_ms(1)

        # Send frame
        self.uart.write(complete_frame)

        # Wait for transmission to complete
        time.sleep_ms(10)

        # Switch back to receive mode
        self.de_pin.value(0)
        time.sleep_ms(1)

        return complete_frame

    def _receive_response(self, expected_length=None, timeout=1000):
        """Receive Modbus RTU response"""
        start_time = time.ticks_ms()
        response = b''

        while time.ticks_diff(time.ticks_ms(), start_time) < timeout:
            if self.uart.any():
                response += self.uart.read()
                if len(response) >= 4:  # Minimum valid response
                    # Check if we have a complete frame
                    if len(response) >= 4:
                        expected_len = response[2] + 5 if response[1] in [1, 2, 3, 4] else 8
                        if len(response) >= expected_len:
                            break
            time.sleep_ms(10)

        if len(response) < 4:
            return None

        # Verify CRC
        data = response[:-2]
        received_crc = response[-2:]
        calculated_crc = self._calculate_crc(data)

        if received_crc != calculated_crc:
            return None

        return response

    async def read_holding_registers(self, slave_id, start_addr, count):
        """Read holding registers (Function Code 3)"""
        async with self.lock:
            frame = bytes([
                slave_id,
                0x03,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return None

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            # Parse data
            byte_count = response[2]
            data = response[3:3+byte_count]
            registers = []

            for i in range(0, byte_count, 2):
                reg_val = (data[i] << 8) | data[i+1]
                registers.append(reg_val)

            return registers

    async def write_single_register(self, slave_id, register_addr, value):
        """Write single register (Function Code 6)"""
        async with self.lock:
            frame = bytes([
                slave_id,
                0x06,  # Function code
                (register_addr >> 8) & 0xFF,
                register_addr & 0xFF,
                (value >> 8) & 0xFF,
                value & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return False

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            return True

    async def read_input_registers(self, slave_id, start_addr, count):
        """Read input registers (Function Code 4)"""
        async with self.lock:
            frame = bytes([
                slave_id,
                0x04,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return None

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            # Parse data
            byte_count = response[2]
            data = response[3:3+byte_count]
            registers = []

            for i in range(0, byte_count, 2):
                reg_val = (data[i] << 8) | data[i+1]
                registers.append(reg_val)

            return registers

    async def write_multiple_registers(self, slave_id, start_addr, values):
        """Write multiple holding registers (Function Code 16)"""
        async with self.lock:
            count = len(values)
            byte_count = count * 2

            frame = bytes([
                slave_id,
                0x10,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF,
                byte_count
            ])

            # Add register values
            for value in values:
                frame += bytes([
                    (value >> 8) & 0xFF,
                    value & 0xFF
                ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return False

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            return True

    async def read_coils(self, slave_id, start_addr, count):
        """Read coils (Function Code 1)"""
        async with self.lock:
            frame = bytes([
                slave_id,
                0x01,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return None

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            # Parse data
            byte_count = response[2]
            data = response[3:3+byte_count]
            coils = []

            for byte_val in data:
                for bit in range(8):
                    if len(coils) < count:
                        coils.append(bool(byte_val & (1 << bit)))

            return coils[:count]

    async def read_discrete_inputs(self, slave_id, start_addr, count):
        """Read discrete inputs (Function Code 2)"""
        async with self.lock:
            frame = bytes([
                slave_id,
                0x02,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return None

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            # Parse data
            byte_count = response[2]
            data = response[3:3+byte_count]
            inputs = []

            for byte_val in data:
                for bit in range(8):
                    if len(inputs) < count:
                        inputs.append(bool(byte_val & (1 << bit)))

            return inputs[:count]

    async def write_single_coil(self, slave_id, coil_addr, value):
        """Write single coil (Function Code 5)"""
        async with self.lock:
            coil_value = 0xFF00 if value else 0x0000
            frame = bytes([
                slave_id,
                0x05,  # Function code
                (coil_addr >> 8) & 0xFF,
                coil_addr & 0xFF,
                (coil_value >> 8) & 0xFF,
                coil_value & 0xFF
            ])

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return False

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            return True

    async def write_multiple_coils(self, slave_id, start_addr, values):
        """Write multiple coils (Function Code 15)"""
        async with self.lock:
            count = len(values)
            byte_count = (count + 7) // 8  # Round up to nearest byte

            frame = bytes([
                slave_id,
                0x0F,  # Function code
                (start_addr >> 8) & 0xFF,
                start_addr & 0xFF,
                (count >> 8) & 0xFF,
                count & 0xFF,
                byte_count
            ])

            # Pack coil values into bytes
            coil_bytes = []
            for i in range(byte_count):
                byte_val = 0
                for bit in range(8):
                    coil_index = i * 8 + bit
                    if coil_index < count and values[coil_index]:
                        byte_val |= (1 << bit)
                coil_bytes.append(byte_val)

            frame += bytes(coil_bytes)

            self._send_request(frame)
            response = self._receive_response()

            if response is None:
                return False

            if response[1] & 0x80:  # Error response
                return {'error': response[2]}

            return True

# Modbus TCP Server implementation
class ModbusTCPServer:
    def __init__(self, modbus_rtu, port=502):
        self.modbus = modbus_rtu
        self.port = port
        self.socket = None
        self.transaction_id = 0

    async def start(self):
        """Start the Modbus TCP server"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(('', self.port))
        self.socket.listen(5)
        self.socket.setblocking(False)

        print(f"Modbus TCP Server listening on port {self.port}")

        while True:
            try:
                client_socket, addr = self.socket.accept()
                print(f"Modbus TCP connection from {addr}")
                asyncio.create_task(self.handle_client(client_socket))
            except OSError:
                await asyncio.sleep(0.1)

    async def handle_client(self, client_socket):
        """Handle Modbus TCP client connection"""
        try:
            client_socket.setblocking(False)

            while True:
                try:
                    # Read MBAP header (7 bytes)
                    header = await self._read_exact(client_socket, 7)
                    if not header:
                        break

                    # Parse MBAP header
                    transaction_id, protocol_id, length, unit_id = struct.unpack('>HHHB', header)

                    # Verify protocol ID (should be 0 for Modbus)
                    if protocol_id != 0:
                        print(f"Invalid protocol ID: {protocol_id}")
                        break

                    # Read PDU (length - 1 byte for unit_id)
                    pdu = await self._read_exact(client_socket, length - 1)
                    if not pdu:
                        break

                    # Process Modbus request
                    response_pdu = await self._process_modbus_request(unit_id, pdu)

                    if response_pdu:
                        # Create MBAP header for response
                        response_length = len(response_pdu) + 1  # +1 for unit_id
                        response_header = struct.pack('>HHHB', transaction_id, 0, response_length, unit_id)

                        # Send response
                        full_response = response_header + response_pdu
                        await self._send_all(client_socket, full_response)

                except OSError:
                    break
                except Exception as e:
                    print(f"Error processing Modbus TCP request: {e}")
                    break

        except Exception as e:
            print(f"Error handling Modbus TCP client: {e}")
        finally:
            try:
                client_socket.close()
            except:
                pass

    async def _read_exact(self, sock, length):
        """Read exactly 'length' bytes from socket"""
        data = b''
        while len(data) < length:
            try:
                chunk = sock.recv(length - len(data))
                if not chunk:
                    return None
                data += chunk
            except OSError:
                await asyncio.sleep(0.01)
        return data

    async def _send_all(self, sock, data):
        """Send all data to socket"""
        total_sent = 0
        while total_sent < len(data):
            try:
                sent = sock.send(data[total_sent:])
                if sent == 0:
                    raise RuntimeError("Socket connection broken")
                total_sent += sent
            except OSError:
                await asyncio.sleep(0.01)

    async def _process_modbus_request(self, unit_id, pdu):
        """Process Modbus request and return response PDU"""
        if len(pdu) < 1:
            return None

        function_code = pdu[0]

        try:
            if function_code == 0x01:  # Read Coils
                return await self._handle_read_coils(unit_id, pdu)
            elif function_code == 0x02:  # Read Discrete Inputs
                return await self._handle_read_discrete_inputs(unit_id, pdu)
            elif function_code == 0x03:  # Read Holding Registers
                return await self._handle_read_holding_registers(unit_id, pdu)
            elif function_code == 0x04:  # Read Input Registers
                return await self._handle_read_input_registers(unit_id, pdu)
            elif function_code == 0x05:  # Write Single Coil
                return await self._handle_write_single_coil(unit_id, pdu)
            elif function_code == 0x06:  # Write Single Register
                return await self._handle_write_single_register(unit_id, pdu)
            elif function_code == 0x0F:  # Write Multiple Coils
                return await self._handle_write_multiple_coils(unit_id, pdu)
            elif function_code == 0x10:  # Write Multiple Holding Registers
                return await self._handle_write_multiple_registers(unit_id, pdu)
            else:
                # Function not supported
                return bytes([function_code | 0x80, 0x01])  # Illegal function
        except Exception as e:
            print(f"Error processing function {function_code}: {e}")
            return bytes([function_code | 0x80, 0x04])  # Server device failure

    async def _handle_read_holding_registers(self, unit_id, pdu):
        """Handle Read Holding Registers (0x03)"""
        if len(pdu) < 5:
            return bytes([0x83, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]

        # Forward to RTU
        result = await self.modbus.read_holding_registers(unit_id, start_addr, count)

        if result is None:
            return bytes([0x83, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x83, result['error']])
        else:
            # Build response
            byte_count = len(result) * 2
            response = bytes([0x03, byte_count])
            for reg in result:
                response += struct.pack('>H', reg)
            return response

    async def _handle_read_input_registers(self, unit_id, pdu):
        """Handle Read Input Registers (0x04)"""
        if len(pdu) < 5:
            return bytes([0x84, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]

        # Forward to RTU
        result = await self.modbus.read_input_registers(unit_id, start_addr, count)

        if result is None:
            return bytes([0x84, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x84, result['error']])
        else:
            # Build response
            byte_count = len(result) * 2
            response = bytes([0x04, byte_count])
            for reg in result:
                response += struct.pack('>H', reg)
            return response

    async def _handle_write_single_register(self, unit_id, pdu):
        """Handle Write Single Register (0x06)"""
        if len(pdu) < 5:
            return bytes([0x86, 0x03])  # Illegal data value

        register_addr = struct.unpack('>H', pdu[1:3])[0]
        value = struct.unpack('>H', pdu[3:5])[0]

        # Forward to RTU
        result = await self.modbus.write_single_register(unit_id, register_addr, value)

        if result is None:
            return bytes([0x86, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x86, result['error']])
        else:
            # Echo back the request for successful write
            return pdu

    async def _handle_write_multiple_registers(self, unit_id, pdu):
        """Handle Write Multiple Holding Registers (0x10)"""
        if len(pdu) < 6:
            return bytes([0x90, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]
        byte_count = pdu[5]

        if len(pdu) < 6 + byte_count:
            return bytes([0x90, 0x03])  # Illegal data value

        if byte_count != count * 2:
            return bytes([0x90, 0x03])  # Illegal data value

        # Extract values
        values = []
        for i in range(0, byte_count, 2):
            value = struct.unpack('>H', pdu[6+i:6+i+2])[0]
            values.append(value)

        # Forward to RTU
        result = await self.modbus.write_multiple_registers(unit_id, start_addr, values)

        if result is None:
            return bytes([0x90, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x90, result['error']])
        else:
            # Return start address and count for successful write
            return pdu[0:5]  # Function code + start address + count

    async def _handle_read_coils(self, unit_id, pdu):
        """Handle Read Coils (0x01)"""
        if len(pdu) < 5:
            return bytes([0x81, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]

        # Forward to RTU
        result = await self.modbus.read_coils(unit_id, start_addr, count)

        if result is None:
            return bytes([0x81, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x81, result['error']])
        else:
            # Build response
            byte_count = (len(result) + 7) // 8
            response = bytes([0x01, byte_count])

            # Pack coils into bytes
            for i in range(byte_count):
                byte_val = 0
                for bit in range(8):
                    coil_index = i * 8 + bit
                    if coil_index < len(result) and result[coil_index]:
                        byte_val |= (1 << bit)
                response += bytes([byte_val])

            return response

    async def _handle_read_discrete_inputs(self, unit_id, pdu):
        """Handle Read Discrete Inputs (0x02)"""
        if len(pdu) < 5:
            return bytes([0x82, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]

        # Forward to RTU
        result = await self.modbus.read_discrete_inputs(unit_id, start_addr, count)

        if result is None:
            return bytes([0x82, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x82, result['error']])
        else:
            # Build response
            byte_count = (len(result) + 7) // 8
            response = bytes([0x02, byte_count])

            # Pack inputs into bytes
            for i in range(byte_count):
                byte_val = 0
                for bit in range(8):
                    input_index = i * 8 + bit
                    if input_index < len(result) and result[input_index]:
                        byte_val |= (1 << bit)
                response += bytes([byte_val])

            return response

    async def _handle_write_single_coil(self, unit_id, pdu):
        """Handle Write Single Coil (0x05)"""
        if len(pdu) < 5:
            return bytes([0x85, 0x03])  # Illegal data value

        coil_addr = struct.unpack('>H', pdu[1:3])[0]
        coil_value = struct.unpack('>H', pdu[3:5])[0]

        # Convert coil value (0xFF00 = ON, 0x0000 = OFF)
        value = coil_value == 0xFF00

        # Forward to RTU
        result = await self.modbus.write_single_coil(unit_id, coil_addr, value)

        if result is None:
            return bytes([0x85, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x85, result['error']])
        else:
            # Echo back the request for successful write
            return pdu

    async def _handle_write_multiple_coils(self, unit_id, pdu):
        """Handle Write Multiple Coils (0x0F)"""
        if len(pdu) < 6:
            return bytes([0x8F, 0x03])  # Illegal data value

        start_addr = struct.unpack('>H', pdu[1:3])[0]
        count = struct.unpack('>H', pdu[3:5])[0]
        byte_count = pdu[5]

        if len(pdu) < 6 + byte_count:
            return bytes([0x8F, 0x03])  # Illegal data value

        # Extract coil values
        values = []
        for i in range(byte_count):
            byte_val = pdu[6 + i]
            for bit in range(8):
                if len(values) < count:
                    values.append(bool(byte_val & (1 << bit)))

        # Forward to RTU
        result = await self.modbus.write_multiple_coils(unit_id, start_addr, values)

        if result is None:
            return bytes([0x8F, 0x04])  # Server device failure
        elif isinstance(result, dict) and 'error' in result:
            return bytes([0x8F, result['error']])
        else:
            # Return start address and count for successful write
            return pdu[0:5]  # Function code + start address + count

# HTTP Server implementation
class HTTPServer:
    def __init__(self, modbus_rtu, port=80):
        self.modbus = modbus_rtu
        self.port = port
        self.socket = None

    async def start(self):
        """Start the HTTP server"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(('', self.port))
        self.socket.listen(5)
        self.socket.setblocking(False)

        print(f"HTTP Server listening on port {self.port}")

        while True:
            try:
                client_socket, addr = self.socket.accept()
                print(f"Connection from {addr}")
                asyncio.create_task(self.handle_client(client_socket))
            except OSError:
                await asyncio.sleep(0.1)

    async def handle_client(self, client_socket):
        """Handle HTTP client request"""
        try:
            client_socket.setblocking(False)
            request = b''

            # Read request
            while True:
                try:
                    chunk = client_socket.recv(1024)
                    if not chunk:
                        break
                    request += chunk
                    if b'\r\n\r\n' in request:
                        break
                except OSError:
                    await asyncio.sleep(0.01)

            # Parse HTTP request
            try:
                request_str = request.decode('utf-8')
            except:
                request_str = request.decode()
            lines = request_str.split('\r\n')

            if not lines or not lines[0]:
                client_socket.close()
                return

            # Parse HTTP request line safely
            request_parts = lines[0].split(' ')
            if len(request_parts) < 2:
                client_socket.close()
                return
                
            method = request_parts[0]
            path = request_parts[1]

            # Route handling
            if path == '/':
                response = self.serve_index()
            elif path.startswith('/api/'):
                response = await self.handle_api(path, request_str)
            else:
                response = self.serve_404()

            # Send response
            client_socket.send(response.encode())
            client_socket.close()

        except Exception as e:
            print(f"Error handling client: {e}")
            try:
                client_socket.close()
            except:
                pass

    def serve_index(self):
        """Serve main HTML page"""
        html = """<!DOCTYPE html>
<html>
<head>
    <title>Modbus Gateway</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        .form-group { margin: 10px 0; }
        label { display: inline-block; width: 150px; }
        input, select, button { padding: 5px; margin: 5px; }
        button { background: #007cba; color: white; border: none; padding: 10px 20px; cursor: pointer; }
        button:hover { background: #005a87; }
        .result { margin-top: 20px; padding: 10px; background: #f0f0f0; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Modbus RTU Gateway</h1>

        <div class="form-group">
            <label>Slave ID:</label>
            <input type="number" id="slaveId" value="1" min="1" max="247">
        </div>

        <div class="form-group">
            <label>Function:</label>
            <select id="function">
                <option value="read_coils">Read Coils</option>
                <option value="read_discrete">Read Discrete Inputs</option>
                <option value="read_holding">Read Holding Registers</option>
                <option value="read_input">Read Input Registers</option>
                <option value="write_coil">Write Single Coil</option>
                <option value="write_single">Write Single Register</option>
                <option value="write_coils">Write Multiple Coils</option>
                <option value="write_multiple">Write Multiple Registers</option>
            </select>
        </div>

        <div class="form-group">
            <label>Start Address:</label>
            <input type="number" id="startAddr" value="0" min="0" max="65535">
        </div>

        <div class="form-group" id="countGroup">
            <label>Count:</label>
            <input type="number" id="count" value="1" min="1" max="125">
        </div>

        <div class="form-group" id="valueGroup" style="display:none;">
            <label>Value:</label>
            <input type="number" id="value" value="0" min="0" max="65535">
        </div>

        <div class="form-group" id="valuesGroup" style="display:none;">
            <label>Values:</label>
            <input type="text" id="values" placeholder="1,2,3,4,5" title="Comma-separated values">
        </div>

        <div class="form-group" id="coilValueGroup" style="display:none;">
            <label>Coil Value:</label>
            <select id="coilValue">
                <option value="0">OFF (0)</option>
                <option value="1">ON (1)</option>
            </select>
        </div>

        <div class="form-group" id="coilValuesGroup" style="display:none;">
            <label>Coil Values:</label>
            <input type="text" id="coilValues" placeholder="1,0,1,0,1" title="Comma-separated boolean values (1/0, true/false, on/off)">
        </div>

        <button onclick="executeModbus()">Execute</button>

        <div class="result" id="result"></div>
    </div>

    <script>
        document.getElementById('function').addEventListener('change', function() {
            const func = this.value;
            const countGroup = document.getElementById('countGroup');
            const valueGroup = document.getElementById('valueGroup');
            const valuesGroup = document.getElementById('valuesGroup');
            const coilValueGroup = document.getElementById('coilValueGroup');
            const coilValuesGroup = document.getElementById('coilValuesGroup');

            // Hide all groups first
            countGroup.style.display = 'none';
            valueGroup.style.display = 'none';
            valuesGroup.style.display = 'none';
            coilValueGroup.style.display = 'none';
            coilValuesGroup.style.display = 'none';

            if (func === 'write_single') {
                valueGroup.style.display = 'block';
            } else if (func === 'write_multiple') {
                valuesGroup.style.display = 'block';
            } else if (func === 'write_coil') {
                coilValueGroup.style.display = 'block';
            } else if (func === 'write_coils') {
                coilValuesGroup.style.display = 'block';
            } else {
                // Read functions
                countGroup.style.display = 'block';
            }
        });

        async function executeModbus() {
            const slaveId = document.getElementById('slaveId').value;
            const func = document.getElementById('function').value;
            const startAddr = document.getElementById('startAddr').value;
            const count = document.getElementById('count').value;
            const value = document.getElementById('value').value;
            const values = document.getElementById('values').value;
            const coilValue = document.getElementById('coilValue').value;
            const coilValues = document.getElementById('coilValues').value;

            let url = `/api/${func}?slave_id=${slaveId}&start_addr=${startAddr}`;

            if (func === 'write_single') {
                url += `&value=${value}`;
            } else if (func === 'write_multiple') {
                url += `&values=${encodeURIComponent(values)}`;
            } else if (func === 'write_coil') {
                url += `&value=${coilValue}`;
            } else if (func === 'write_coils') {
                url += `&values=${encodeURIComponent(coilValues)}`;
            } else {
                url += `&count=${count}`;
            }

            try {
                const response = await fetch(url);
                const result = await response.json();
                document.getElementById('result').innerHTML = 
                    '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
            } catch (error) {
                document.getElementById('result').innerHTML = 
                    '<pre>Error: ' + error.message + '</pre>';
            }
        }
    </script>
</body>
</html>"""

        return f"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {len(html)}\r\n\r\n{html}"

    def serve_404(self):
        """Serve 404 error"""
        html = "<html><body><h1>404 Not Found</h1></body></html>"
        return f"HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: {len(html)}\r\n\r\n{html}"

    async def handle_api(self, path, request_str):
        """Handle API requests"""
        try:
            # Parse query parameters
            if '?' in path:
                path, query = path.split('?', 1)
                params = {}
                for param in query.split('&'):
                    if '=' in param:
                        key, val = param.split('=', 1)
                        params[key] = val
            else:
                params = {}

            # API routing
            if path == '/api/read_coils':
                return await self.api_read_coils(params)
            elif path == '/api/read_discrete':
                return await self.api_read_discrete(params)
            elif path == '/api/read_holding':
                return await self.api_read_holding(params)
            elif path == '/api/read_input':
                return await self.api_read_input(params)
            elif path == '/api/write_coil':
                return await self.api_write_coil(params)
            elif path == '/api/write_single':
                return await self.api_write_single(params)
            elif path == '/api/write_coils':
                return await self.api_write_coils(params)
            elif path == '/api/write_multiple':
                return await self.api_write_multiple(params)
            else:
                return self.api_error("Unknown API endpoint")

        except Exception as e:
            return self.api_error(f"API Error: {str(e)}")

    async def api_read_coils(self, params):
        """API: Read coils"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        count = int(params.get('count', 1))

        result = await self.modbus.read_coils(slave_id, start_addr, count)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "data": result}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_read_discrete(self, params):
        """API: Read discrete inputs"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        count = int(params.get('count', 1))

        result = await self.modbus.read_discrete_inputs(slave_id, start_addr, count)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "data": result}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_read_holding(self, params):
        """API: Read holding registers"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        count = int(params.get('count', 1))

        result = await self.modbus.read_holding_registers(slave_id, start_addr, count)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "data": result}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_read_input(self, params):
        """API: Read input registers"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        count = int(params.get('count', 1))

        result = await self.modbus.read_input_registers(slave_id, start_addr, count)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "data": result}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_write_single(self, params):
        """API: Write single register"""
        slave_id = int(params.get('slave_id', 1))
        register_addr = int(params.get('start_addr', 0))
        value = int(params.get('value', 0))

        result = await self.modbus.write_single_register(slave_id, register_addr, value)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "message": "Register written successfully"}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_write_multiple(self, params):
        """API: Write multiple holding registers"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        values_str = params.get('values', '0')

        # Parse values - expect comma-separated integers
        try:
            values = [int(v.strip()) for v in values_str.split(',')]
        except ValueError:
            response = {"success": False, "error": "Invalid values format. Use comma-separated integers."}
            json_str = json.dumps(response)
            return f"HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

        result = await self.modbus.write_multiple_registers(slave_id, start_addr, values)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "message": f"Written {len(values)} registers successfully"}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_write_coil(self, params):
        """API: Write single coil"""
        slave_id = int(params.get('slave_id', 1))
        coil_addr = int(params.get('start_addr', 0))
        value_str = params.get('value', '0').lower()

        # Parse boolean value
        value = value_str in ['1', 'true', 'on', 'yes']

        result = await self.modbus.write_single_coil(slave_id, coil_addr, value)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "message": "Coil written successfully"}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    async def api_write_coils(self, params):
        """API: Write multiple coils"""
        slave_id = int(params.get('slave_id', 1))
        start_addr = int(params.get('start_addr', 0))
        values_str = params.get('values', '0')

        # Parse values - expect comma-separated boolean values
        try:
            values = []
            for v in values_str.split(','):
                v = v.strip().lower()
                values.append(v in ['1', 'true', 'on', 'yes'])
        except ValueError:
            response = {"success": False, "error": "Invalid values format. Use comma-separated boolean values."}
            json_str = json.dumps(response)
            return f"HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

        result = await self.modbus.write_multiple_coils(slave_id, start_addr, values)

        if result is None:
            response = {"success": False, "error": "Communication timeout"}
        elif isinstance(result, dict) and 'error' in result:
            response = {"success": False, "error": f"Modbus error: {result['error']}"}
        else:
            response = {"success": True, "message": f"Written {len(values)} coils successfully"}

        json_str = json.dumps(response)
        return f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

    def api_error(self, message):
        """Return API error response"""
        response = {"success": False, "error": message}
        json_str = json.dumps(response)
        return f"HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {len(json_str)}\r\n\r\n{json_str}"

# WiFi connection
def connect_wifi(ssid, password):
    """Connect to WiFi network"""
    print(f"[DEBUG] Initializing WiFi connection to SSID: {ssid}")
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    print(f"[DEBUG] WiFi interface activated")
    
    wlan.connect(ssid, password)
    print(f"[DEBUG] Connection request sent to {ssid}")

    print("Connecting to WiFi...")
    timeout = 10
    while timeout > 0:
        status = wlan.status()
        if status < 0 or status >= 3:
            break
        timeout -= 1
        print(f"[DEBUG] Connection status: {status}, timeout: {timeout}s")
        time.sleep(1)

    status = wlan.status()
    if status != 3:
        print(f"[ERROR] Failed to connect to WiFi. Status: {status}")
        status_messages = {
            0: "Link down",
            1: "Link join",
            2: "Link no IP",
            -1: "Link fail",
            -2: "No AP found",
            -3: "Wrong password"
        }
        print(f"[ERROR] Status meaning: {status_messages.get(status, 'Unknown status')}")
        return False
    else:
        print("[SUCCESS] Connected to WiFi!")
        ifconfig = wlan.ifconfig()
        print(f"[DEBUG] Network configuration:")
        print(f"[DEBUG]   IP Address: {ifconfig[0]}")
        print(f"[DEBUG]   Subnet Mask: {ifconfig[1]}")
        print(f"[DEBUG]   Gateway: {ifconfig[2]}")
        print(f"[DEBUG]   DNS Server: {ifconfig[3]}")
        return True

# Main application
async def main():
    """Main application"""
    # WiFi credentials - modify these for your network
    WIFI_SSID = "E-lodge"
    WIFI_PASSWORD = "Futurama"

    # Connect to WiFi
    print("[DEBUG] Starting WiFi connection...")
    if not connect_wifi(WIFI_SSID, WIFI_PASSWORD):
        print("[ERROR] Cannot start without WiFi connection")
        return

    # Get IP address for display
    wlan = network.WLAN(network.STA_IF)
    ip_address = wlan.ifconfig()[0]

    # Initialize Modbus RTU
    print("[DEBUG] Initializing Modbus RTU interface...")
    # Adjust pins according to your Waveshare RS485 HAT connections
    modbus = ModbusRTU(
        uart_id=0,      # UART0
        baudrate=9600,  # Common Modbus baudrate
        tx_pin=0,       # TX pin
        rx_pin=1,       # RX pin
        de_pin=2        # Direction Enable pin for RS485
    )
    print("[DEBUG] Modbus RTU initialized on UART0, 9600 baud")

    # Initialize HTTP server
    print("[DEBUG] Initializing HTTP server on port 80...")
    http_server = HTTPServer(modbus, port=80)

    # Initialize Modbus TCP server
    print("[DEBUG] Initializing Modbus TCP server on port 502...")
    modbus_tcp_server = ModbusTCPServer(modbus, port=502)

    print("[SUCCESS] Starting Modbus Gateway...")
    print(f"[INFO] Access the web interface at: http://{ip_address}")
    print(f"[INFO] Modbus TCP server available at: {ip_address}:502")

    # Start both servers concurrently
    print("[DEBUG] Starting HTTP and Modbus TCP servers...")
    await asyncio.gather(
        http_server.start(),
        modbus_tcp_server.start()
    )
    print("[SUCCESS] All servers started successfully!")

# Run the application
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
    except Exception as e:
        print(f"Error: {e}")
