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
futures = "0.3"
anyhow = "1.0"
tracing = "0.1"
tracing-subscriber = "0.3"
etherparse = "0.13"
ipnet = "2.7"
EOL

# Tạo source code
cat > src/main.rs << EOL
use anyhow::{Context, Result};
use clap::Parser;
use etherparse::{SlicedPacket, TransportSlice};
use pcap::Capture;
use std::collections::HashMap;
use std::net::IpAddr;
use std::str::FromStr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::net::UdpSocket;
use tokio::sync::Mutex;
use tokio::time::{interval, interval_at, Instant as TokioInstant};
use tracing::{info, warn};

#[derive(Parser, Debug)]
#[command(author, version, about = "PCAP replayer for performance testing", long_about = None)]
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

    /// Concurrent tasks
    #[arg(short, long, default_value = "10")]
    concurrent: usize,

    /// Number of times to loop the PCAP file (e.g., 5, 10, 15) or "infinite"
    #[arg(short, long, default_value = "1")]
    loops: String,
}

struct Stats {
    sent: u64,
    failed: u64,
    total_time: Duration,
    window_sent: u64, // Packets sent in the current time window
}

async fn send_packet(
    socket: Arc<Mutex<UdpSocket>>,
    payload: Vec<u8>, // Owned payload
    target: String,  // Owned target
    stats: Arc<Mutex<Stats>>,
) -> Result<()> {
    let socket = socket.lock().await;
    match socket.send_to(&payload, &target).await {
        Ok(_) => {
            let mut stats = stats.lock().await;
            stats.sent += 1;
            stats.window_sent += 1;
            Ok(())
        }
        Err(e) => {
            stats.lock().await.failed += 1;
            Err(anyhow::anyhow!("Failed to send packet: {}", e))
        }
    }
}

fn extract_udp_info(packet_data: &[u8]) -> Option<(u16, Vec<u8>)> {
    match SlicedPacket::from_ethernet(packet_data) {
        Ok(packet) => {
            if let Some(TransportSlice::Udp(udp)) = packet.transport {
                Some((udp.destination_port(), packet.payload.to_vec())) // Copy payload to owned Vec
            } else {
                None
            }
        }
        Err(_) => None
    }
}

async fn log_throughput(stats: Arc<Mutex<Stats>>) {
    let mut interval = interval_at(TokioInstant::now() + Duration::from_secs(1), Duration::from_secs(1));
    loop {
        interval.tick().await;
        let mut stats = stats.lock().await;
        info!("Messages sent in last second: {}", stats.window_sent);
        stats.window_sent = 0; // Reset window counter
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Khởi tạo logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let args = Args::parse();

    // Kiểm tra tham số đầu vào
    if args.rate == 0 {
        return Err(anyhow::anyhow!("Rate must be greater than 0"));
    }
    if IpAddr::from_str(&args.target_ip).is_err() {
        return Err(anyhow::anyhow!("Invalid target IP address"));
    }

    // Parse loops argument
    let max_loops = if args.loops.to_lowercase() == "infinite" {
        None // Infinite looping
    } else {
        match args.loops.parse::<u32>() {
            Ok(n) if n > 0 => Some(n),
            _ => return Err(anyhow::anyhow!("Loops must be a positive integer or 'infinite'")),
        }
    };

    // Lưu trữ sockets cho từng cổng
    let sockets: Arc<Mutex<HashMap<u16, Arc<Mutex<UdpSocket>>>>> =
        Arc::new(Mutex::new(HashMap::new()));
    let stats = Arc::new(Mutex::new(Stats {
        sent: 0,
        failed: 0,
        total_time: Duration::from_secs(0),
        window_sent: 0,
    }));

    // Start throughput logging task
    let stats_clone = stats.clone();
    tokio::spawn(log_throughput(stats_clone));

    let start_time = Instant::now();
    let mut current_loop = 0;

    loop {
        // Check if max loops reached
        if let Some(max) = max_loops {
            if current_loop >= max {
                break;
            }
        }
        current_loop += 1;
        info!("Starting loop {} of {}", current_loop, max_loops.map_or("infinite".to_string(), |n| n.to_string()));

        // Mở file PCAP
        let mut cap = Capture::from_file(&args.input)
            .with_context(|| format!("Failed to open PCAP file: {}", args.input))?;

        let mut interval = interval(Duration::from_micros(1_000_000 / args.rate as u64));
        let mut tasks = Vec::new();

        // Xử lý gói tin
        while let Ok(packet) = cap.next_packet() {
            if let Some((port, payload)) = extract_udp_info(&packet.data) {
                let target = format!("{}:{}", args.target_ip, port);
                let sockets = sockets.clone();
                let stats = stats.clone();

                // Tạo socket nếu chưa tồn tại
                {
                    let mut sockets_guard = sockets.lock().await;
                    if !sockets_guard.contains_key(&port) {
                        let socket = UdpSocket::bind("0.0.0.0:0")
                            .await
                            .with_context(|| "Failed to bind socket")?;
                        sockets_guard.insert(port, Arc::new(Mutex::new(socket)));
                        info!("Created socket for port {}", port);
                    }
                }

                // Gửi gói tin bất đồng bộ
                let socket = sockets.lock().await.get(&port).unwrap().clone();
                tasks.push(tokio::spawn(async move {
                    if let Err(e) = send_packet(socket, payload, target, stats).await {
                        warn!("Error sending packet: {}", e);
                    }
                }));

                // Giới hạn số lượng tác vụ đồng thời
                if tasks.len() >= args.concurrent {
                    futures::future::join_all(tasks.drain(..)).await;
                }

                // Giới hạn tốc độ
                interval.tick().await;
            }
        }

        // Chờ tất cả tác vụ hoàn thành
        futures::future::join_all(tasks.drain(..)).await;

        info!("Completed loop {} of {}", current_loop, max_loops.map_or("infinite".to_string(), |n| n.to_string()));
    }

    // Thống kê hiệu suất
    let stats = stats.lock().await;
    let elapsed = start_time.elapsed();
    info!(
        "Completed: {} packets sent, {} failed in {:.2?}",
        stats.sent, stats.failed, elapsed
    );
    info!(
        "Throughput: {:.2} packets/s",
        stats.sent as f64 / elapsed.as_secs_f64()
    );

    Ok(())
}
EOL

# Build project
echo "Building project..."
cargo build --release

echo "Project setup complete!"