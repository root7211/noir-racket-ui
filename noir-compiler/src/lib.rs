use anyhow::{bail, Result};
use noir_ir::{
    validate_profile_projection, ProfileAcknowledged, ProfileDataView, ProfileLoweringProjection,
    ProfileTransaction, ProfileView, ProfileWorkbench,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApplicationProfile {
    Standard,
    Compact,
}

impl ApplicationProfile {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "standard" => Ok(Self::Standard),
            "compact" => Ok(Self::Compact),
            other => bail!("noir-compiler unsupported profile {other}; expected standard or compact"),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::Compact => "compact",
        }
    }

    fn capacities(self) -> (usize, usize, usize, usize) {
        match self {
            Self::Standard => (10_000, 4, 2_048, 3),
            Self::Compact => (2_048, 3, 512, 3),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlertsRowState {
    Acknowledged,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApplicationInput {
    pub app_id: String,
    pub profile: ApplicationProfile,
    pub alerts_row_state: AlertsRowState,
}

impl ApplicationInput {
    pub fn acknowledged(app_id: impl Into<String>, profile: ApplicationProfile) -> Self {
        Self { app_id: app_id.into(), profile, alerts_row_state: AlertsRowState::Acknowledged }
    }
}

pub fn lower_application_profile(input: &ApplicationInput) -> Result<ProfileLoweringProjection> {
    let (systems_capacity, systems_slots, alerts_capacity, alerts_slots) = input.profile.capacities();
    let app = &input.app_id;
    let systems = data_view(app, "systems", 0, systems_capacity, systems_slots, "open-systems-detail");
    let alerts = data_view(app, "alerts", 1, alerts_capacity, alerts_slots, "acknowledge-alert");
    let projection = ProfileLoweringProjection {
        app_id: app.clone(),
        profile: input.profile.name().into(),
        workbench: ProfileWorkbench {
            id: format!("{app}-workbench"),
            rail_id: format!("{app}-rail"),
            initial_value: 0,
            views: vec![
                ProfileView { id: format!("{app}-overview-view"), value: 0 },
                ProfileView { id: format!("{app}-systems-view"), value: 1 },
                ProfileView { id: format!("{app}-alerts-view"), value: 2 },
            ],
            data_views: vec![systems, alerts.clone()],
        },
        transaction: ProfileTransaction {
            id: format!("{app}-acknowledge-alert-transaction"),
            action_id: format!("{app}-acknowledge-alert"),
            action_slot_index: 0,
            state_id: format!("{app}-alert-ack-count"),
            state_index: 0,
            delta: 1,
            source_data_view_id: alerts.id.clone(),
            source_list_id: alerts.list_id.clone(),
            source_view_id: alerts.owner_view_id.clone(),
            target_view_id: format!("{app}-overview-view"),
        },
        acknowledged_row_state: ProfileAcknowledged {
            id: format!("{app}-acknowledged-alert-state"),
            data_view_id: alerts.id.clone(),
            list_id: alerts.list_id.clone(),
            owner_view_id: alerts.owner_view_id.clone(),
            logical_capacity: alerts.logical_capacity,
            state_domain: vec!["open".into(), "acknowledged".into()],
            word_bits: 64,
            word_count: alerts.logical_capacity.div_ceil(64),
            acknowledge_action_id: format!("{app}-acknowledge-alert"),
            action_slot_index: 0,
        },
    };
    match input.alerts_row_state {
        AlertsRowState::Acknowledged => validate_profile_projection(&projection)?,
    }
    Ok(projection)
}

fn data_view(app: &str, kind: &str, list_index: usize, logical_capacity: usize, physical_slots: usize, action_suffix: &str) -> ProfileDataView {
    ProfileDataView {
        id: format!("{app}-{kind}-data-view"),
        list_id: format!("{app}-{kind}-stream"),
        owner_view_id: format!("{app}-{kind}-view"),
        list_index,
        logical_capacity,
        physical_slots,
        visible_rows: physical_slots,
        scrollbar_id: format!("{app}-{kind}-scrollbar"),
        navigation_id: format!("{app}-{kind}-navigation"),
        log_browser_id: format!("{app}-{kind}-browser"),
        row_activation_action: format!("{app}-{action_suffix}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lowers_standard_profile() {
        let plan = lower_application_profile(&ApplicationInput::acknowledged("operations", ApplicationProfile::Standard)).unwrap();
        assert_eq!(plan.workbench.data_views[0].logical_capacity, 10_000);
        assert_eq!(plan.workbench.data_views[1].logical_capacity, 2_048);
        assert_eq!(plan.acknowledged_row_state.word_count, 32);
    }

    #[test]
    fn lowers_compact_profile() {
        let plan = lower_application_profile(&ApplicationInput::acknowledged("operations-compact", ApplicationProfile::Compact)).unwrap();
        assert_eq!(plan.workbench.data_views[0].logical_capacity, 2_048);
        assert_eq!(plan.workbench.data_views[1].logical_capacity, 512);
        assert_eq!(plan.acknowledged_row_state.word_count, 8);
    }

    #[test]
    fn rejects_invalid_identifier() {
        assert!(lower_application_profile(&ApplicationInput::acknowledged("Operations", ApplicationProfile::Standard)).is_err());
    }
}
