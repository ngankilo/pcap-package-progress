# PCAP Replayer

A Rust-based tool for replaying UDP packets from a PCAP file to a specified target IP address, designed for performance testing with configurable packet rates, concurrency, and looping options.

## Features
- Replay UDP packets from a PCAP file to a target IP and port.
- Configurable packet sending rate (packets per second).
- Support for concurrent packet sending (10, 100, 1k, 10k, 100k tasks).
- Loop the PCAP file a specific number of times (e.g., 5, 10, 15) or infinitely.
- Real-time logging of messages sent per second.
- Cumulative statistics (total packets sent, failed, and overall throughput).

## Prerequisites
- **Rust**: Ensure Rust is installed (version 1.56 or later). Install via:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **PCAP File**: A valid PCAP file containing UDP packets.
- **System Resources**: For high concurrency (e.g., 100k tasks), increase file descriptor limits:
  ```bash
  ulimit -n 100000
  ```

## Setup
1. **Create the Project**:
   Run the provided `make.sh` script to set up the Rust project and dependencies:
   ```bash
   chmod +x make.sh
   ./make.sh
   ```
   This creates a `pcap_replayer` directory, sets up the Rust project, and builds the release binary.

2. **Prepare a PCAP File**:
   Ensure you have a valid PCAP file (e.g., `test.pcap`) containing UDP packets to replay.

## Usage
The program is executed using the `run.sh` script, which provides a convenient wrapper for command-line arguments.

1. **Make the Script Executable**:
   ```bash
   chmod +x run.sh
   ```

2. **Run the Program**:
   ```bash
   ./run.sh --input <pcap_file> --rate <packets_per_second> --target <ip_address> --concurrent <tasks> --loops <loops>
   ```

   **Arguments**:
    - `--input <path>`: Path to the PCAP file (required).
    - `--rate <number>`: Packets per second (default: 1000).
    - `--target <ip>`: Target IP address (default: 127.0.0.1).
    - `--concurrent <number>`: Number of concurrent tasks (default: 10).
    - `--loops <number|infinite>`: Number of times to loop the PCAP file (e.g., 5, 10, 15) or "infinite" (default: 1).

3. **Example Commands**:
    - Replay a PCAP file once with 1000 packets/sec and 100 concurrent tasks:
      ```bash
      ./run.sh --input test.pcap --rate 1000 --target 127.0.0.1 --concurrent 100 --loops 1
      ```
    - Replay 5 times with 500 packets/sec and 50 concurrent tasks:
      ```bash
      ./run.sh --input test.pcap --rate 500 --target 192.168.1.1 --concurrent 50 --loops 5
      ```
    - Replay infinitely with 1000 packets/sec and 1000 concurrent tasks:
      ```bash
      ./run.sh --input test.pcap --rate 1000 --target 127.0.0.1 --concurrent 1000 --loops infinite
      ```

## Output
- **Real-Time Logging**: The program logs the number of messages sent per second:
  ```
  [INFO] Messages sent in last second: 998
  ```
- **Loop Progress**: Logs the start and completion of each loop:
  ```
  [INFO] Starting loop 1 of 5
  [INFO] Completed loop 1 of 5
  ```
- **Final Statistics**: At the end, logs total packets sent, failed, and overall throughput:
  ```
  [INFO] Completed: 5000 packets sent, 0 failed in 5.03s
  [INFO] Throughput: 994.04 packets/s
  ```

## Troubleshooting
- **Invalid PCAP File**: Ensure the input file is a valid PCAP file containing UDP packets.
- **Socket Binding Errors**: Increase file descriptor limits for high concurrency:
  ```bash
  ulimit -n 100000
  ```
- **Permission Issues**: Run `run.sh` with sufficient permissions (e.g., `sudo` if required for network operations).
- **Program Termination**: Press Ctrl+C to stop infinite looping; final statistics will be logged.

## Notes
- The program supports high concurrency (up to 100k tasks) but may require system tuning for optimal performance.
- Only UDP packets are currently supported. TCP support can be added by extending the code.
- For large PCAP files, ensure sufficient disk I/O performance to avoid bottlenecks.

## Contributing
Contributions are welcome! To add features (e.g., TCP support, CSV statistics), submit a pull request or open an issue.

## License
This project is licensed under the MIT License.