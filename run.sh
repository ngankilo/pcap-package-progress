#!/bin/bash

# Get the directory containing the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

show_help() {
    echo "Usage: ./run.sh [options]"
    echo "Options:"
    echo "  -i, --input     Input PCAP file path (required)"
    echo "  -r, --rate      Packets per second (default: 1000)"
    echo "  -t, --target    Target IP address (default: 127.0.0.1)"
    echo "  -c, --concurrent Number of concurrent tasks (default: 10)"
    echo "  -l, --loops     Number of loops (e.g., 5, 10, 15) or 'infinite' (default: 1)"
    echo "  -h, --help      Show this help message"
}

# Default values
RATE=1000
TARGET_IP="127.0.0.1"
INPUT_FILE=""
CONCURRENT=10
LOOPS="1"

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
        -c|--concurrent)
            CONCURRENT="$2"
            shift
            shift
            ;;
        -l|--loops)
            LOOPS="$2"
            shift
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
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

# Convert relative input file path to absolute path
INPUT_FILE="$(realpath "$INPUT_FILE")"

# Validate rate is a positive integer
if ! [[ "$RATE" =~ ^[0-9]+$ ]] || [ "$RATE" -le 0 ]; then
    echo "Error: Rate must be a positive integer"
    exit 1
fi

# Validate concurrent is a positive integer
if ! [[ "$CONCURRENT" =~ ^[0-9]+$ ]] || [ "$CONCURRENT" -le 0 ]; then
    echo "Error: Concurrent must be a positive integer"
    exit 1
fi

# Validate loops is a positive integer or 'infinite'
if ! [[ "$LOOPS" =~ ^[0-9]+$ || "$LOOPS" =~ ^[Ii][Nn][Ff][Ii][Nn][Ii][Tt][Ee]$ ]]; then
    echo "Error: Loops must be a positive integer or 'infinite'"
    exit 1
fi
if [[ "$LOOPS" =~ ^[0-9]+$ ]] && [ "$LOOPS" -le 0 ]; then
    echo "Error: Loops must be a positive integer or 'infinite'"
    exit 1
fi

# Check if the binary exists
if [ ! -f "${SCRIPT_DIR}/pcap_replayer/target/release/pcap_replayer" ]; then
    echo "Building pcap_replayer..."
    cd "${SCRIPT_DIR}/pcap_replayer" || exit 1
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
echo "Concurrent tasks: $CONCURRENT"
echo "Loops: $LOOPS"

"${SCRIPT_DIR}/pcap_replayer/target/release/pcap_replayer" \
    --input "$INPUT_FILE" \
    --rate "$RATE" \
    --target-ip "$TARGET_IP" \
    --concurrent "$CONCURRENT" \
    --loops "$LOOPS"

# Check if the program executed successfully
if [ $? -ne 0 ]; then
    echo "Error: pcap_replayer failed to execute"
    exit 1
fi