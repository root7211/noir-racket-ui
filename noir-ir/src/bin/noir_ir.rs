use anyhow::{bail, Context, Result};
use noir_ir::{canonical_json, parse_canonical_json, parse_profile_json, projection_from_scene_path, validate_profile_projection};
use std::env;
use std::fs;
use std::path::Path;

fn usage() -> ! {
    eprintln!("usage:\n  noir-ir project SCENE OUTPUT\n  noir-ir diff LEFT_PROJECTION RIGHT_PROJECTION\n  noir-ir verify-golden SCENE GOLDEN_PROJECTION\n  noir-ir diff-profile LEFT_PROFILE RIGHT_PROFILE\n  noir-ir verify-profile PROFILE");
    std::process::exit(2);
}

fn read_projection(path: &Path) -> Result<noir_ir::CanonicalProjection> {
    let text = fs::read_to_string(path).with_context(|| format!("read projection {}", path.display()))?;
    parse_canonical_json(&text).with_context(|| format!("parse projection {}", path.display()))
}

fn read_profile(path: &Path) -> Result<noir_ir::ProfileLoweringProjection> {
    let text = fs::read_to_string(path).with_context(|| format!("read profile projection {}", path.display()))?;
    parse_profile_json(&text).with_context(|| format!("parse profile projection {}", path.display()))
}

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let Some(command) = args.first().map(String::as_str) else { usage() };
    match command {
        "project" if args.len() == 3 => {
            let projection = projection_from_scene_path(&args[1])?;
            fs::write(&args[2], canonical_json(&projection)?)
                .with_context(|| format!("write canonical projection {}", args[2]))?;
            println!("NOIR_IR_PROJECT: PASS scene={} output={}", args[1], args[2]);
        }
        "diff" if args.len() == 3 => {
            let left = read_projection(Path::new(&args[1]))?;
            let right = read_projection(Path::new(&args[2]))?;
            if left != right {
                let left_json = canonical_json(&left)?;
                let right_json = canonical_json(&right)?;
                bail!("NOIR_IR_DIFFERENTIAL: FAIL\nleft={}\nright={}\nleft-canonical:\n{}\nright-canonical:\n{}", args[1], args[2], left_json, right_json);
            }
            println!("NOIR_IR_DIFFERENTIAL: PASS left={} right={}", args[1], args[2]);
        }
        "verify-golden" if args.len() == 3 => {
            let projection = projection_from_scene_path(&args[1])?;
            let golden = read_projection(Path::new(&args[2]))?;
            if projection != golden {
                bail!("NOIR_IR_GOLDEN: FAIL scene={} golden={}", args[1], args[2]);
            }
            println!("NOIR_IR_GOLDEN: PASS scene={} golden={}", args[1], args[2]);
        }
        "diff-profile" if args.len() == 3 => {
            let left = read_profile(Path::new(&args[1]))?;
            let right = read_profile(Path::new(&args[2]))?;
            validate_profile_projection(&left)?;
            validate_profile_projection(&right)?;
            if left != right {
                bail!("NOIR_IR_PROFILE_DIFFERENTIAL: FAIL left={} right={}", args[1], args[2]);
            }
            println!("NOIR_IR_PROFILE_DIFFERENTIAL: PASS left={} right={}", args[1], args[2]);
        }
        "verify-profile" if args.len() == 2 => {
            let profile = read_profile(Path::new(&args[1]))?;
            validate_profile_projection(&profile)?;
            println!("NOIR_IR_PROFILE: PASS profile={}", args[1]);
        }
        _ => usage(),
    }
    Ok(())
}
