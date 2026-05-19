use hbb_common::{config::Config, log};

const FS_SUPPORT_PREFILL_VERSION: &str = "1";
const DEFAULT_FS_SUPPORT_VERSION: &str = "1.0.0";

fn build_value(value: Option<&'static str>) -> String {
    value.unwrap_or("").trim().to_owned()
}

fn has_existing_server_config() -> bool {
    !Config::get_option("custom-rendezvous-server").trim().is_empty()
        || !Config::get_option("rendezvous-servers").trim().is_empty()
        || !Config::get_option("key").trim().is_empty()
}

fn set_option_if_present(key: &str, value: &str) {
    let value = value.trim();
    if !value.is_empty() {
        Config::set_option(key.to_owned(), value.to_owned());
    }
}

pub fn apply_defaults() {
    let app_name = build_value(option_env!("FS_SUPPORT_APP_NAME"));
    let app_name = if app_name.is_empty() { "FS Support".to_owned() } else { app_name };
    if !app_name.is_empty() && crate::get_app_name() == "RustDesk" {
        *hbb_common::config::APP_NAME.write().unwrap() = app_name;
    }

    let host = build_value(option_env!("FS_RUSTDESK_HOST"));
    let key = build_value(option_env!("FS_RUSTDESK_KEY"));
    if host.is_empty() || key.is_empty() {
        return;
    }

    if has_existing_server_config() {
        return;
    }

    set_option_if_present("custom-rendezvous-server", &host);
    set_option_if_present("rendezvous-servers", &host);
    set_option_if_present("key", &key);
    set_option_if_present("relay-server", &build_value(option_env!("FS_RUSTDESK_RELAY")));
    set_option_if_present("api-server", &build_value(option_env!("FS_RUSTDESK_API")));
    set_option_if_present("fs-support-prefill-version", FS_SUPPORT_PREFILL_VERSION);
    log::info!("FS Support default RustDesk server configuration applied.");
}

pub fn display_version() -> String {
    let base = build_value(option_env!("FS_SUPPORT_BASE_VERSION"));
    let base = if base.is_empty() {
        DEFAULT_FS_SUPPORT_VERSION.to_owned()
    } else {
        base
    };
    let sha = build_value(option_env!("FS_SUPPORT_BUILD_SHA"));
    let short_sha: String = sha.chars().take(12).collect();
    if short_sha.is_empty() {
        base
    } else {
        format!("{base}-fs.{short_sha}")
    }
}
