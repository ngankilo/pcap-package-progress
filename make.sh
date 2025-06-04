#!/bin/bash

# Kiểm tra Rust đã được cài đặt chưa
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source $HOME/.cargo/env
fi

# Tạo project mới
echo "Creating new Rust project..."
cargo new pcap_replayer
cd pcap_replayer

# Thêm dependencies vào Cargo.toml
cat > Cargo.toml << EOL
[package]
name = "pcap_replayer"
version = "0.1.0"
edition = "2021"

[dependencies]
pcap = "1.1.0"
clap = { version = "4.4", features = ["derive"] }
tokio = { version = "1.32", features = ["full"] }
anyhow = "1.0"
tracing = "0.1"
tracing-subscriber = "0.3"
etherparse = "0.13"
EOL

# Tạo source code
cat > src/main.rs << EOL
use anyhow::Result;
use clap::Parser;
use pcap::Capture;
use std::collections::HashSet;
use std::net::UdpSocket;
use std::time::Duration;
use etherparse::{SlicedPacket, TransportSlice};

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Input PCAP file
    #[arg(short, long)]
    input: String,

    /// Packets per second rate limit
    #[arg(short, long, default_value = "1000")]
    rate: u32,

    /// Target IP address
    #[arg(short, long, default_value = "127.0.0.1")]
    target_ip: String,
}

fn extract_udp_info(packet_data: &[u8]) -> Option<(u16, &[u8])> {
    match SlicedPacket::from_ethernet(packet_data) {
        Ok(packet) => {
            if let Some(TransportSlice::Udp(udp)) = packet.transport {
                return Some((udp.destination_port(), packet.payload));
            }
            None
        }
        Err(_) => None
    }
}

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let args = Args::parse();
    
    let mut cap = Capture::from_file(&args.input)?;
    
    let mut ports = HashSet::new();
    while let Ok(packet) = cap.next_packet() {
        if let Some((port, _)) = extract_udp_info(&packet.data) {
            ports.insert(port);
        }
    }

    println!("Found UDP ports: {:?}", ports);

    let mut sockets = Vec::new();
    for &port in &ports {
        let socket = UdpSocket::bind("0.0.0.0:0")?;
        socket.set_nonblocking(true)?;
        sockets.push((port, socket));
    }

    let mut cap = Capture::from_file(&args.input)?;
    let sleep_duration = Duration::from_micros((1_000_000 / args.rate) as u64);

    let mut packet_count = 0;
    while let Ok(packet) = cap.next_packet() {
        if let Some((port, payload)) = extract_udp_info(&packet.data) {
            if let Some((_, socket)) = sockets.iter().find(|(p, _)| *p == port) {
                socket.send_to(payload, format!("{}:{}", args.target_ip, port))?;
                packet_count += 1;
                if packet_count % 1000 == 0 {
                    println!("Sent {} packets", packet_count);
                }
                std::thread::sleep(sleep_duration);
            }
        }
    }

    println!("Total packets sent: {}", packet_count);
    Ok(())
}
EOL

# Build project
echo "Building project..."
cargo build --release

echo "Project setup complete!"