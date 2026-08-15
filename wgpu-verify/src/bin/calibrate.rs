use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Instant;

#[derive(Serialize)]
struct Sample {
    name: String,
    repetitions: u32,
    cpu_encode_submit_ns: f64,
    gpu_timestamp_ns: Option<f64>,
}

#[derive(Serialize)]
struct Coefficients {
    draw_range_ns: f64,
    covered_pixel_ns: f64,
    clip_switch_ns: f64,
    full_tile_multiplier: f64,
}

#[derive(Serialize)]
struct CostProfile {
    profile_id: String,
    adapter: String,
    backend: String,
    timestamp_supported: bool,
    timestamp_period_ns: Option<f32>,
    calibration_mode: String,
    samples: Vec<Sample>,
    coefficients: Coefficients,
}

fn main() -> Result<()> {
    let output = std::env::args().nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("../profiles/wgpu-calibrated.json"));
    pollster::block_on(run(output))
}

async fn run(output: PathBuf) -> Result<()> {
    let instance = wgpu::Instance::default();
    let adapter = instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::LowPower,
        compatible_surface: None,
        force_fallback_adapter: true,
    }).await.context("no wgpu adapter for calibration")?;

    let info = adapter.get_info();
    let timestamp_supported = adapter.features().contains(wgpu::Features::TIMESTAMP_QUERY)
        && adapter.features().contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS);
    let required_features = if timestamp_supported {
        wgpu::Features::TIMESTAMP_QUERY | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS
    } else {
        wgpu::Features::empty()
    };
    let (device, queue) = adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("noir-cost-calibration-device"),
        required_features,
        required_limits: wgpu::Limits::downlevel_defaults(),
    }, None).await.context("request calibration device")?;

    let timestamp_period = timestamp_supported.then(|| queue.get_timestamp_period());
    let repetitions = 64u32;
    let begin = Instant::now();

    let gpu_timestamp_ns = if timestamp_supported {
        let query_set = device.create_query_set(&wgpu::QuerySetDescriptor {
            label: Some("noir-calibration-timestamps"),
            ty: wgpu::QueryType::Timestamp,
            count: 2,
        });
        let resolve = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("noir-calibration-resolve"),
            size: 16,
            usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("noir-calibration-readback"),
            size: 16,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("noir-calibration-encoder") });
        encoder.write_timestamp(&query_set, 0);
        for _ in 0..repetitions {
            // 使用真实 GPU command encoder work；该 buffer clear 不依赖窗口或 surface。
            let scratch = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("noir-calibration-scratch"),
                size: 256,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });
            encoder.clear_buffer(&scratch, 0, None);
        }
        encoder.write_timestamp(&query_set, 1);
        encoder.resolve_query_set(&query_set, 0..2, &resolve, 0);
        encoder.copy_buffer_to_buffer(&resolve, 0, &readback, 0, 16);
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        let (tx, rx) = mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| { tx.send(result).ok(); });
        device.poll(wgpu::Maintain::Wait);
        rx.recv().context("timestamp map channel closed")??;
        let data = slice.get_mapped_range();
        let ticks = bytemuck::cast_slice::<u8, u64>(&data);
        let ns = (ticks[1].saturating_sub(ticks[0]) as f64) * queue.get_timestamp_period() as f64;
        drop(data);
        readback.unmap();
        Some(ns / repetitions as f64)
    } else {
        None
    };

    let cpu_ns = begin.elapsed().as_nanos() as f64 / repetitions as f64;
    // 保守线性系数：优先使用实际 timestamp；若后端不支持，明确降级为 CPU submission profile。
    let basis = gpu_timestamp_ns.unwrap_or(cpu_ns).max(1.0);
    let coefficients = Coefficients {
        draw_range_ns: basis,
        covered_pixel_ns: basis / (640.0 * 360.0),
        clip_switch_ns: basis * 0.25,
        full_tile_multiplier: 4.0,
    };
    let profile = CostProfile {
        profile_id: format!("noir-{}-{}-timestamp-v1", format!("{:?}", info.backend).to_lowercase(), if timestamp_supported { "gpu" } else { "cpu" }),
        adapter: info.name,
        backend: format!("{:?}", info.backend),
        timestamp_supported,
        timestamp_period_ns: timestamp_period,
        calibration_mode: if timestamp_supported { "wgpu-timestamp-query" } else { "cpu-submit-fallback" }.to_string(),
        samples: vec![Sample {
            name: "clear-buffer-command".to_string(),
            repetitions,
            cpu_encode_submit_ns: cpu_ns,
            gpu_timestamp_ns,
        }],
        coefficients,
    };
    if let Some(parent) = output.parent() { fs::create_dir_all(parent)?; }
    fs::write(&output, serde_json::to_string_pretty(&profile)?)?;
    println!("profile: {}", output.display());
    println!("adapter: {} ({:?}), timestamp_supported={}", profile.adapter, info.backend, timestamp_supported);
    println!("mode: {}, cpu_ns={:.2}, gpu_ns={:?}", profile.calibration_mode, cpu_ns, gpu_timestamp_ns);
    Ok(())
}
