use pollster::FutureExt;

fn main() {
    let instance = wgpu::Instance::default();
    
    println!("Enumerating all adapters:");
    for adapter in instance.enumerate_adapters(wgpu::Backends::all()) {
        let info = adapter.get_info();
        println!("  - {} (backend: {:?}, device_type: {:?}, vendor: 0x{:04x}, device: 0x{:04x})",
                 info.name, info.backend, info.device_type, info.vendor, info.device);
    }
}
