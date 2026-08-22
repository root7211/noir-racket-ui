use anyhow::{Context, Result};
use noir_compiler::{lower_application_layout_glyph, lower_application_profile, AlertsRowState, ApplicationInput, ApplicationProfile};
use noir_ir::{canonical_layout_glyph_json, canonical_profile_json};
use std::env;
use std::fs;

fn usage() -> ! {
    eprintln!("usage:\n  noir-compiler lower APP_ID standard|compact OUTPUT\n  noir-compiler lower-layout-glyph APP_ID standard|compact OUTPUT");
    std::process::exit(2);
}

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first().map(String::as_str) else { usage() };
    if args.len() != 4 {
        usage();
    }
    let app_id = &args[1];
    let profile = ApplicationProfile::parse(&args[2])?;
    let input = ApplicationInput {
        app_id: app_id.clone(),
        profile,
        alerts_row_state: AlertsRowState::Acknowledged,
    };
    match command {
        "lower" => {
            let plan = lower_application_profile(&input)?;
            fs::write(&args[3], canonical_profile_json(&plan)?)
                .with_context(|| format!("write lowered profile plan {}", args[3]))?;
            println!("NOIR_COMPILER_PROFILE_LOWERING: PASS app={} profile={} output={}", app_id, profile.name(), args[3]);
        }
        "lower-layout-glyph" => {
            let plan = lower_application_layout_glyph(&input)?;
            fs::write(&args[3], canonical_layout_glyph_json(&plan)?)
                .with_context(|| format!("write lowered layout glyph plan {}", args[3]))?;
            println!("NOIR_COMPILER_LAYOUT_GLYPH_LOWERING: PASS app={} profile={} output={}", app_id, profile.name(), args[3]);
        }
        _ => usage(),
    }
    Ok(())
}
