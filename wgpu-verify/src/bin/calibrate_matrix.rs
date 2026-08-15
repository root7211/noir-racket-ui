use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::Instant;

#[derive(Serialize, Clone)]
struct Sample {
    name: String,
    repetitions: u32,
    command_count: u32,
    bytes_per_command: u64,
    cpu_encode_submit_ns: f64,
    gpu_timestamp_ns: Option<f64>,
}

#[derive(Serialize, Clone)]
struct Coefficients {
    draw_range_ns: f64,
    covered_pixel_ns: f64,
    clip_switch_ns: f64,
    full_tile_multiplier: f64,
}

#[derive(Serialize, Clone)]
struct MatchKey {
    backend: String,
    adapter: String,
    width: u32,
    height: u32,
}

#[derive(Serialize, Clone)]
struct Profile {
    profile_id: String,
    matcher: MatchKey,
    timestamp_supported: bool,
    timestamp_period_ns: Option<f32>,
    calibration_mode: String,
    samples: Vec<Sample>,
    coefficients: Coefficients,
}

#[derive(Serialize)]
struct Registry {
    registry_version: u32,
    profiles: Vec<Profile>,
}

fn main() -> Result<()> {
    let output = std::env::args().nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("../profiles/registry.json"));
    pollster::block_on(run(output))
}

async fn run(output: PathBuf) -> Result<()> {
    let instance = wgpu::Instance::default();
    let adapter = instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::LowPower,
        compatible_surface: None,
        force_fallback_adapter: true,
    }).await.context("no wgpu adapter for calibration matrix")?;
    let info = adapter.get_info();
    let timestamp_supported = adapter.features().contains(wgpu::Features::TIMESTAMP_QUERY)
        && adapter.features().contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS);
    let required_features = if timestamp_supported {
        wgpu::Features::TIMESTAMP_QUERY | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS
    } else { wgpu::Features::empty() };
    let (device, queue) = adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("noir-calibration-matrix-device"),
        required_features,
        required_limits: wgpu::Limits::downlevel_defaults(),
    }, None).await.context("request matrix device")?;

    // 每项是可重复的 command workload 代理；它们分别对应 Noir Schedule 中的 range、glyph 上传、clip/tile 工作。
    let matrix = [
        ("quad-range-submit", 1u32, 256u64),
        ("glyph-atlas-upload-proxy", 3, 512),
        ("clip-switch-proxy", 8, 256),
        ("tile-small-proxy", 8, 4096),
        ("tile-large-proxy", 8, 65536),
        ("query-resolve", 1, 256),
    ];
    let samples = matrix.iter().map(|(name, commands, bytes)| {
        measure_workload(&device, &queue, timestamp_supported, *name, *commands, *bytes, 64)
    }).collect::<Result<Vec<_>>>()?;

    let sample = |name: &str| samples.iter().find(|s| s.name == name).expect("matrix sample");
    let ns = |s: &Sample| s.gpu_timestamp_ns.unwrap_or(s.cpu_encode_submit_ns).max(1.0);
    let draw_range_ns = ns(sample("quad-range-submit"));
    let clip_switch_ns = ns(sample("clip-switch-proxy")) / 8.0;
    let covered_pixel_ns = ns(sample("tile-large-proxy")) / (640.0 * 360.0);
    let full_tile_multiplier = (ns(sample("tile-large-proxy")) / ns(sample("tile-small-proxy"))).clamp(1.0, 8.0);
    let profile = Profile {
        profile_id: format!("noir-{}-{}-matrix-v1", format!("{:?}", info.backend).to_lowercase(), if timestamp_supported { "gpu" } else { "cpu" }),
        matcher: MatchKey {
            backend: format!("{:?}", info.backend),
            adapter: info.name.clone(),
            width: 640,
            height: 360,
        },
        timestamp_supported,
        timestamp_period_ns: timestamp_supported.then(|| queue.get_timestamp_period()),
        calibration_mode: if timestamp_supported { "wgpu-timestamp-query-matrix" } else { "cpu-submit-fallback-matrix" }.to_string(),
        samples,
        coefficients: Coefficients { draw_range_ns, covered_pixel_ns, clip_switch_ns, full_tile_multiplier },
    };
    if let Some(parent) = output.parent() { fs::create_dir_all(parent)?; }
    fs::write(&output, serde_json::to_string_pretty(&Registry { registry_version: 1, profiles: vec![profile.clone()] })?)?;
    println!("registry: {}", output.display());
    println!("profile={} adapter={} backend={:?} timestamp={}", profile.profile_id, profile.matcher.adapter, info.backend, timestamp_supported);
    for sample in &profile.samples {
        println!("  {:24} cpu={:9.2}ns gpu={:?}", sample.name, sample.cpu_encode_submit_ns, sample.gpu_timestamp_ns);
    }
    Ok(())
}

fn measure_workload(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    timestamps: bool,
    name: &str,
    command_count: u32,
    bytes: u64,
    repetitions: u32,
) -> Result<Sample> {
    let scratch = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(name), size: bytes.max(256),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let start = Instant::now();
    let gpu_timestamp_ns = if timestamps {
        let queries = device.create_query_set(&wgpu::QuerySetDescriptor { label: Some(name), ty: wgpu::QueryType::Timestamp, count: 2 });
        let resolve = device.create_buffer(&wgpu::BufferDescriptor { label: Some("matrix-resolve"), size: 16, usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC, mapped_at_creation: false });
        let readback = device.create_buffer(&wgpu::BufferDescriptor { label: Some("matrix-readback"), size: 16, usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(name) });
        encoder.write_timestamp(&queries, 0);
        for _ in 0..repetitions {
            for _ in 0..command_count { encoder.clear_buffer(&scratch, 0, None); }
        }
        encoder.write_timestamp(&queries, 1);
        encoder.resolve_query_set(&queries, 0..2, &resolve, 0);
        encoder.copy_buffer_to_buffer(&resolve, 0, &readback, 0, 16);
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        let (tx, rx) = mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| { tx.send(result).ok(); });
        device.poll(wgpu::Maintain::Wait);
        rx.recv().context("matrix timestamp map channel closed")??;
        let data = slice.get_mapped_range();
        let ticks = bytemuck::cast_slice::<u8, u64>(&data);
        let value = (ticks[1].saturating_sub(ticks[0]) as f64) * queue.get_timestamp_period() as f64
            / (repetitions as f64 * command_count as f64);
        drop(data);
        readback.unmap();
        Some(value)
    } else {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(name) });
        for _ in 0..repetitions {
            for _ in 0..command_count { encoder.clear_buffer(&scratch, 0, None); }
        }
        queue.submit(Some(encoder.finish()));
        None
    };
    Ok(Sample {
        name: name.to_string(), repetitions, command_count, bytes_per_command: bytes,
        cpu_encode_submit_ns: start.elapsed().as_nanos() as f64 / (repetitions as f64 * command_count as f64),
        gpu_timestamp_ns,
    })
}
