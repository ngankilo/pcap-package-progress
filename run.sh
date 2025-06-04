#!/bin/bash

# Get the directory containing the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

show_help() {
    echo "Usage: ./run.sh [options]"
    echo "Options:"
    echo "  -i, --input     Input PCAP file path"
    echo "  -r, --rate      Packets per second (default: 1000)"
    echo "  -t, --target    Target IP address (default: 127.0.0.1)"
    echo "  -h, --help      Show this help message"
}

# Default values
RATE=1000
TARGET_IP="127.0.0.1"
INPUT_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -i|--input)
            INPUT_FILE="$2"
            shift
            shift
            ;;
        -r|--rate)
            RATE="$2"
            shift
            shift
            ;;
        -t|--target)
            TARGET_IP="$2"
            shift
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if input file is provided
if [ -z "$INPUT_FILE" ]; then
    echo "Error: Input PCAP file is required"
    show_help
    exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' does not exist"
    exit 1
fi

# Check if the binary exists
if [ ! -f "${SCRIPT_DIR}/pcap_replayer/target/release/pcap_replayer" ]; then
    echo "Error: pcap_replayer binary not found. Building project..."
    cd "${SCRIPT_DIR}/pcap_replayer"
    cargo build --release
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build project"
        exit 1
    fi
    cd - > /dev/null
fi

# Run the program with absolute path
echo "Running pcap_replayer..."
echo "Input file: $INPUT_FILE"
echo "Rate: $RATE packets/sec"
echo "Target IP: $TARGET_IP"

"${SCRIPT_DIR}/pcap_replayer/target/release/pcap_replayer" -i "$INPUT_FILE" -r "$RATE" -t "$TARGET_IP"

chmod +x run.sh