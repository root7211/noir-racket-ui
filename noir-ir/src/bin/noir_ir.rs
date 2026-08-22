use anyhow::{bail, Context, Result};
use noir_ir::{canonical_json, parse_canonical_json, projection_from_scene_path};
use std::env;
use std::fs;
use std::path::Path;

fn usage() -> ! {
    eprintln!("usage:\n  noir-ir project SCENE OUTPUT\n  noir-ir diff LEFT_PROJECTION RIGHT_PROJECTION\n  noir-ir verify-golden SCENE GOLDEN_PROJECTION");
    std::process::exit(2);
}

fn read_projection(path: &Path) -> Result<noir_ir::CanonicalProjection> {
    let text = fs::read_to_string(path).with_context(|| format!("read projection {}", path.display()))?;
    parse_canonical_json(&text).with_context(|| format!("parse projection {}", path.display()))
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
        _ => usage(),
    }
    Ok(())
}
