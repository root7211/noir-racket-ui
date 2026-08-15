//! Minimal adapter visibility probe for real-GPU and WSL diagnostics.
//!
//! This binary deliberately creates no surface and consumes no Noir Scene. It answers one
//! narrow question: which adapters does the exact wgpu version used by Noir enumerate?

fn main() {
    pollster::block_on(async {
        let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle_from_env();
        descriptor.flags |= wgpu::InstanceFlags::ALLOW_UNDERLYING_NONCOMPLIANT_ADAPTER;
        let backends = descriptor.backends;
        let instance = wgpu::Instance::new(descriptor);
        let adapters = instance.enumerate_adapters(backends).await;

        if adapters.is_empty() {
            eprintln!("noir-wgpu-probe: no adapters enumerated by wgpu 30");
            std::process::exit(2);
        }

        println!("noir-wgpu-probe: wgpu=30 requested-backends={backends:?} adapter-count={}", adapters.len());
        for (index, adapter) in adapters.into_iter().enumerate() {
            let info = adapter.get_info();
            println!(
                "adapter[{index}]: backend={:?} type={:?} name={:?} vendor=0x{:04x} device=0x{:04x} driver={:?} driver_info={:?}",
                info.backend,
                info.device_type,
                info.name,
                info.vendor,
                info.device,
                info.driver,
                info.driver_info,
            );
        }
    });
}
