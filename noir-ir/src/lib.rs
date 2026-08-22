use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

pub const WORKBENCH_SCHEMA: &str = "noir-material-observability-workbench-plan-v2";
pub const TRANSACTION_SCHEMA: &str = "noir-workbench-cross-view-transaction-plan-v1";
pub const ACKNOWLEDGED_SCHEMA: &str = "noir-acknowledged-row-state-plan-v1";

#[derive(Clone, Debug, Deserialize)]
pub struct SceneWire {
    pub abi_contracts: AbiContractsWire,
    pub material_observability_workbench_plan: WorkbenchWire,
    pub workbench_cross_view_transaction_plan: TransactionWire,
    pub acknowledged_row_state_plan: AcknowledgedWire,
}

#[derive(Clone, Debug, Deserialize)]
pub struct AbiContractsWire {
    pub material_observability_workbench_plan: AbiContractWire,
    pub workbench_cross_view_transaction_plan: AbiContractWire,
    pub acknowledged_row_state_plan: AbiContractWire,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct AbiContractWire {
    pub schema: String,
    pub revision: u32,
}

#[derive(Clone, Debug, Deserialize)]
pub struct WorkbenchWire {
    pub abi_schema: String,
    pub abi_revision: u32,
    pub id: String,
    pub rail_id: String,
    pub initial_value: usize,
    pub views: Vec<ViewWire>,
    pub data_views: Vec<DataViewWire>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct ViewWire {
    pub destination_id: String,
    pub view_root_id: String,
    pub target_value: usize,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct DataViewWire {
    pub id: String,
    pub list_id: String,
    pub view_id: String,
    pub list_index: usize,
    pub logical_capacity: usize,
    pub physical_slots: usize,
    pub visible_rows: usize,
    pub scrollbar_id: String,
    pub navigation_id: String,
    pub log_browser_id: String,
    pub row_activation_action: String,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct TransactionWire {
    pub abi_schema: String,
    pub abi_revision: u32,
    pub id: String,
    pub action_id: String,
    pub action_slot_index: usize,
    pub delta: i64,
    pub event_slot: usize,
    pub source_data_view_id: String,
    pub source_list_id: String,
    pub source_view_id: String,
    pub source_row_color_offsets: Vec<usize>,
    pub source_detail_glyph_offsets: Vec<usize>,
    pub state: String,
    pub state_index: usize,
    pub target_view_id: String,
    pub target_count_glyph_offsets: Vec<usize>,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct AcknowledgedWire {
    pub abi_schema: String,
    pub abi_revision: u32,
    pub id: String,
    pub data_view_id: String,
    pub list_id: String,
    pub owner_view_id: String,
    pub logical_capacity: usize,
    pub state_domain: Vec<String>,
    pub word_bits: usize,
    pub word_count: usize,
    pub acknowledge_action_id: String,
    pub action_slot_index: usize,
    pub row_color_offsets: Vec<usize>,
    pub detail_glyph_offsets: Vec<usize>,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalProjection {
    pub contracts: CanonicalContracts,
    pub workbench: CanonicalWorkbench,
    pub transaction: CanonicalTransaction,
    pub acknowledged_row_state: CanonicalAcknowledged,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalContracts {
    pub workbench: AbiContractWire,
    pub transaction: AbiContractWire,
    pub acknowledged_row_state: AbiContractWire,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalWorkbench {
    pub schema: String,
    pub revision: u32,
    pub id: String,
    pub rail_id: String,
    pub initial_value: usize,
    pub views: Vec<CanonicalView>,
    pub data_views: Vec<CanonicalDataView>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalView {
    pub destination_id: String,
    pub view_root_id: String,
    pub target_value: usize,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalDataView {
    pub id: String,
    pub list_id: String,
    pub view_id: String,
    pub list_index: usize,
    pub logical_capacity: usize,
    pub physical_slots: usize,
    pub visible_rows: usize,
    pub scrollbar_id: String,
    pub navigation_id: String,
    pub log_browser_id: String,
    pub row_activation_action: String,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalTransaction {
    pub schema: String,
    pub revision: u32,
    pub id: String,
    pub action_id: String,
    pub action_slot_index: usize,
    pub delta: i64,
    pub event_slot: usize,
    pub source_data_view_id: String,
    pub source_list_id: String,
    pub source_view_id: String,
    pub source_row_color_offsets: Vec<usize>,
    pub source_detail_glyph_offsets: Vec<usize>,
    pub state: String,
    pub state_index: usize,
    pub target_view_id: String,
    pub target_count_glyph_offsets: Vec<usize>,
    pub tile_ids: Vec<usize>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanonicalAcknowledged {
    pub schema: String,
    pub revision: u32,
    pub id: String,
    pub data_view_id: String,
    pub list_id: String,
    pub owner_view_id: String,
    pub logical_capacity: usize,
    pub state_domain: Vec<String>,
    pub word_bits: usize,
    pub word_count: usize,
    pub acknowledge_action_id: String,
    pub action_slot_index: usize,
    pub row_color_offsets: Vec<usize>,
    pub detail_glyph_offsets: Vec<usize>,
    pub tile_ids: Vec<usize>,
}

pub fn projection_from_scene_path(path: impl AsRef<Path>) -> Result<CanonicalProjection> {
    let path = path.as_ref();
    let text = fs::read_to_string(path).with_context(|| format!("read Scene {}", path.display()))?;
    projection_from_scene_str(&text).with_context(|| format!("decode Scene {}", path.display()))
}

pub fn projection_from_scene_str(text: &str) -> Result<CanonicalProjection> {
    let scene: SceneWire = serde_json::from_str(text).context("deserialize constrained Scene IR")?;
    projection_from_wire(scene)
}

pub fn projection_from_wire(scene: SceneWire) -> Result<CanonicalProjection> {
    let contracts = CanonicalContracts {
        workbench: scene.abi_contracts.material_observability_workbench_plan,
        transaction: scene.abi_contracts.workbench_cross_view_transaction_plan,
        acknowledged_row_state: scene.abi_contracts.acknowledged_row_state_plan,
    };
    verify_contract("workbench", &contracts.workbench, WORKBENCH_SCHEMA, 2)?;
    verify_contract("transaction", &contracts.transaction, TRANSACTION_SCHEMA, 1)?;
    verify_contract("acknowledged-row-state", &contracts.acknowledged_row_state, ACKNOWLEDGED_SCHEMA, 1)?;

    let workbench = CanonicalWorkbench {
        schema: scene.material_observability_workbench_plan.abi_schema,
        revision: scene.material_observability_workbench_plan.abi_revision,
        id: scene.material_observability_workbench_plan.id,
        rail_id: scene.material_observability_workbench_plan.rail_id,
        initial_value: scene.material_observability_workbench_plan.initial_value,
        views: scene.material_observability_workbench_plan.views.into_iter().map(|view| CanonicalView {
            destination_id: view.destination_id,
            view_root_id: view.view_root_id,
            target_value: view.target_value,
            tile_ids: view.tile_ids,
        }).collect(),
        data_views: scene.material_observability_workbench_plan.data_views.into_iter().map(|view| CanonicalDataView {
            id: view.id,
            list_id: view.list_id,
            view_id: view.view_id,
            list_index: view.list_index,
            logical_capacity: view.logical_capacity,
            physical_slots: view.physical_slots,
            visible_rows: view.visible_rows,
            scrollbar_id: view.scrollbar_id,
            navigation_id: view.navigation_id,
            log_browser_id: view.log_browser_id,
            row_activation_action: view.row_activation_action,
            tile_ids: view.tile_ids,
        }).collect(),
    };
    verify_workbench(&workbench)?;

    let transaction = CanonicalTransaction {
        schema: scene.workbench_cross_view_transaction_plan.abi_schema,
        revision: scene.workbench_cross_view_transaction_plan.abi_revision,
        id: scene.workbench_cross_view_transaction_plan.id,
        action_id: scene.workbench_cross_view_transaction_plan.action_id,
        action_slot_index: scene.workbench_cross_view_transaction_plan.action_slot_index,
        delta: scene.workbench_cross_view_transaction_plan.delta,
        event_slot: scene.workbench_cross_view_transaction_plan.event_slot,
        source_data_view_id: scene.workbench_cross_view_transaction_plan.source_data_view_id,
        source_list_id: scene.workbench_cross_view_transaction_plan.source_list_id,
        source_view_id: scene.workbench_cross_view_transaction_plan.source_view_id,
        source_row_color_offsets: scene.workbench_cross_view_transaction_plan.source_row_color_offsets,
        source_detail_glyph_offsets: scene.workbench_cross_view_transaction_plan.source_detail_glyph_offsets,
        state: scene.workbench_cross_view_transaction_plan.state,
        state_index: scene.workbench_cross_view_transaction_plan.state_index,
        target_view_id: scene.workbench_cross_view_transaction_plan.target_view_id,
        target_count_glyph_offsets: scene.workbench_cross_view_transaction_plan.target_count_glyph_offsets,
        tile_ids: scene.workbench_cross_view_transaction_plan.tile_ids,
    };
    verify_transaction(&transaction, &workbench)?;

    let acknowledged_row_state = CanonicalAcknowledged {
        schema: scene.acknowledged_row_state_plan.abi_schema,
        revision: scene.acknowledged_row_state_plan.abi_revision,
        id: scene.acknowledged_row_state_plan.id,
        data_view_id: scene.acknowledged_row_state_plan.data_view_id,
        list_id: scene.acknowledged_row_state_plan.list_id,
        owner_view_id: scene.acknowledged_row_state_plan.owner_view_id,
        logical_capacity: scene.acknowledged_row_state_plan.logical_capacity,
        state_domain: scene.acknowledged_row_state_plan.state_domain,
        word_bits: scene.acknowledged_row_state_plan.word_bits,
        word_count: scene.acknowledged_row_state_plan.word_count,
        acknowledge_action_id: scene.acknowledged_row_state_plan.acknowledge_action_id,
        action_slot_index: scene.acknowledged_row_state_plan.action_slot_index,
        row_color_offsets: scene.acknowledged_row_state_plan.row_color_offsets,
        detail_glyph_offsets: scene.acknowledged_row_state_plan.detail_glyph_offsets,
        tile_ids: scene.acknowledged_row_state_plan.tile_ids,
    };
    verify_acknowledged(&acknowledged_row_state, &transaction, &workbench)?;

    Ok(CanonicalProjection { contracts, workbench, transaction, acknowledged_row_state })
}

pub fn canonical_json(projection: &CanonicalProjection) -> Result<String> {
    Ok(format!("{}\n", serde_json::to_string_pretty(projection).context("serialize canonical noir-ir projection")?))
}

pub fn parse_canonical_json(text: &str) -> Result<CanonicalProjection> {
    serde_json::from_str(text).context("deserialize canonical noir-ir projection")
}

fn verify_contract(name: &str, actual: &AbiContractWire, schema: &str, revision: u32) -> Result<()> {
    if actual.schema != schema || actual.revision != revision {
        bail!("noir-ir {name} contract mismatch: got {}@{}, expected {}@{}", actual.schema, actual.revision, schema, revision);
    }
    Ok(())
}

fn verify_workbench(workbench: &CanonicalWorkbench) -> Result<()> {
    if workbench.schema != WORKBENCH_SCHEMA || workbench.revision != 2 {
        bail!("noir-ir workbench payload ABI mismatch");
    }
    if workbench.views.len() != 3 || workbench.data_views.len() != 2 {
        bail!("noir-ir requires exactly three resident views and two declared data views");
    }
    let expected_targets = [0, 1, 2];
    if workbench.views.iter().map(|view| view.target_value).collect::<Vec<_>>() != expected_targets {
        bail!("noir-ir workbench resident view targets must be [0, 1, 2]");
    }
    for (expected, view) in workbench.data_views.iter().enumerate() {
        if view.list_index != expected || view.logical_capacity == 0 || view.physical_slots == 0 || view.visible_rows != view.physical_slots {
            bail!("noir-ir data-view {} violates fixed list index/capacity/slot contract", view.id);
        }
        if view.tile_ids.is_empty() || view.scrollbar_id.is_empty() || view.navigation_id.is_empty() || view.log_browser_id.is_empty() || view.row_activation_action.is_empty() {
            bail!("noir-ir data-view {} has incomplete fixed resource witnesses", view.id);
        }
    }
    Ok(())
}

fn verify_transaction(transaction: &CanonicalTransaction, workbench: &CanonicalWorkbench) -> Result<()> {
    if transaction.schema != TRANSACTION_SCHEMA || transaction.revision != 1 || transaction.delta != 1 {
        bail!("noir-ir transaction payload ABI or delta mismatch");
    }
    let source = workbench.data_views.get(1).context("noir-ir missing Alerts data-view")?;
    let overview = workbench.views.first().context("noir-ir missing Overview view")?;
    if transaction.source_data_view_id != source.id || transaction.source_list_id != source.list_id || transaction.source_view_id != source.view_id || transaction.target_view_id != overview.view_root_id {
        bail!("noir-ir transaction owner/view witnesses disagree with workbench endpoints");
    }
    if transaction.source_row_color_offsets.len() != source.physical_slots || transaction.source_detail_glyph_offsets.len() != 29 || transaction.target_count_glyph_offsets.len() != 8 || transaction.tile_ids.is_empty() {
        bail!("noir-ir transaction fixed write-set geometry mismatch");
    }
    Ok(())
}

fn verify_acknowledged(ack: &CanonicalAcknowledged, transaction: &CanonicalTransaction, workbench: &CanonicalWorkbench) -> Result<()> {
    if ack.schema != ACKNOWLEDGED_SCHEMA || ack.revision != 1 || ack.state_domain != ["open", "acknowledged"] || ack.word_bits != 64 {
        bail!("noir-ir acknowledged row-state ABI/domain mismatch");
    }
    let source = workbench.data_views.get(1).context("noir-ir missing Alerts data-view")?;
    if ack.data_view_id != source.id || ack.list_id != source.list_id || ack.owner_view_id != source.view_id || ack.logical_capacity != source.logical_capacity {
        bail!("noir-ir acknowledged row-state owner/capacity mismatch");
    }
    if ack.word_count != ack.logical_capacity.div_ceil(ack.word_bits) {
        bail!("noir-ir acknowledged row-state word geometry mismatch");
    }
    if ack.acknowledge_action_id != transaction.action_id || ack.action_slot_index != transaction.action_slot_index || ack.row_color_offsets != transaction.source_row_color_offsets || ack.detail_glyph_offsets != transaction.source_detail_glyph_offsets || !transaction.tile_ids.iter().all(|tile| ack.tile_ids.contains(tile)) {
        bail!("noir-ir acknowledged row-state transaction witnesses mismatch");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_wrong_word_geometry() {
        let ack = CanonicalAcknowledged {
            schema: ACKNOWLEDGED_SCHEMA.into(), revision: 1, id: "x".into(), data_view_id: "d".into(), list_id: "l".into(), owner_view_id: "v".into(),
            logical_capacity: 65, state_domain: vec!["open".into(), "acknowledged".into()], word_bits: 64, word_count: 1,
            acknowledge_action_id: "a".into(), action_slot_index: 0, row_color_offsets: vec![1], detail_glyph_offsets: vec![2], tile_ids: vec![0],
        };
        assert_eq!(ack.logical_capacity.div_ceil(ack.word_bits), 2);
    }
}
