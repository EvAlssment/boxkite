//! [`Client`]/[`ClientBuilder`] and the shared request plumbing every other
//! module in this crate builds on. No behavior lives here beyond
//! request/response handling -- mirrors `sdk-python`'s `BoxkiteClient`/
//! `sdk-js`'s `BoxkiteClient` in spirit (thin HTTP wrapper, same v1 API).

use std::time::Duration;

use reqwest::{Method, RequestBuilder};
use serde::de::DeserializeOwned;

use crate::error::{api_error_from_bytes, BoxkiteError};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);
/// Extra headroom added on top of a caller-supplied `exec`/`http_request`
/// `timeout` so the HTTP client's own request timeout never fires first and
/// masks the server's own timeout response -- same constant sdk-python's
/// `EXEC_TIMEOUT_HEADROOM` / sdk-js's `EXEC_TIMEOUT_HEADROOM_MS` add.
pub(crate) const EXEC_TIMEOUT_HEADROOM: Duration = Duration::from_secs(15);

const LOCALHOST_HOSTNAMES: [&str; 3] = ["localhost", "127.0.0.1", "::1"];

/// A client for a hosted boxkite control-plane's `/v1/*` REST API.
///
/// Construct one with [`Client::new`] for the common case, or
/// [`Client::builder`] for control over the timeout or the underlying
/// `reqwest::Client` (e.g. to point it at a test server). Cheap to clone --
/// clone freely instead of wrapping in `Arc` yourself.
#[derive(Clone, Debug)]
pub struct Client {
    pub(crate) http: reqwest::Client,
    pub(crate) base_url: String,
    pub(crate) api_key: String,
}

impl Client {
    /// Shorthand for `Client::builder().base_url(base_url).api_key(api_key).build()`.
    pub fn new(
        base_url: impl Into<String>,
        api_key: impl Into<String>,
    ) -> Result<Self, BoxkiteError> {
        ClientBuilder::new()
            .base_url(base_url)
            .api_key(api_key)
            .build()
    }

    /// Start building a [`Client`] with non-default options (timeout, a
    /// preconfigured `reqwest::Client`, etc).
    pub fn builder() -> ClientBuilder {
        ClientBuilder::new()
    }

    pub(crate) fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    pub(crate) fn request(&self, method: Method, path: &str) -> RequestBuilder {
        self.http
            .request(method, self.url(path))
            .bearer_auth(&self.api_key)
    }

    /// Send a request and deserialize a JSON response body. Non-2xx
    /// responses become `BoxkiteError::Api`; the body is expected to
    /// contain valid JSON of shape `T` on success.
    pub(crate) async fn send<T: DeserializeOwned>(
        &self,
        builder: RequestBuilder,
    ) -> Result<T, BoxkiteError> {
        let resp = builder.send().await?;
        let status = resp.status();
        let bytes = resp.bytes().await?;
        if !status.is_success() {
            return Err(api_error_from_bytes(status.as_u16(), &bytes));
        }
        serde_json::from_slice(&bytes).map_err(BoxkiteError::from)
    }

    /// Like [`Client::send`], but for endpoints that may return an empty
    /// (`204`, or otherwise body-less) success response -- e.g. `list_*`
    /// endpoints that return `null` instead of `[]` when nothing exists.
    /// Returns the JSON-decoded default value (e.g. an empty `Vec`) when the
    /// body is empty rather than trying to decode nothing as `T`.
    pub(crate) async fn send_or_default<T: DeserializeOwned + Default>(
        &self,
        builder: RequestBuilder,
    ) -> Result<T, BoxkiteError> {
        let resp = builder.send().await?;
        let status = resp.status();
        let bytes = resp.bytes().await?;
        if !status.is_success() {
            return Err(api_error_from_bytes(status.as_u16(), &bytes));
        }
        if bytes.is_empty() {
            return Ok(T::default());
        }
        serde_json::from_slice(&bytes).map_err(BoxkiteError::from)
    }

    /// Send a request expecting no meaningful response body (`204 No
    /// Content`, e.g. `destroy_sandbox`/`delete_image`).
    pub(crate) async fn send_no_content(
        &self,
        builder: RequestBuilder,
    ) -> Result<(), BoxkiteError> {
        let resp = builder.send().await?;
        let status = resp.status();
        if !status.is_success() {
            let bytes = resp.bytes().await?;
            return Err(api_error_from_bytes(status.as_u16(), &bytes));
        }
        Ok(())
    }
}

/// Builder for [`Client`]. `base_url` and `api_key` are required; everything
/// else has a sensible default.
#[derive(Default)]
pub struct ClientBuilder {
    base_url: Option<String>,
    api_key: Option<String>,
    timeout: Option<Duration>,
    http_client: Option<reqwest::Client>,
}

impl ClientBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    /// The control-plane's base URL, e.g. `https://cp.example.com`. Must be
    /// `https://`, unless the host is `localhost`/`127.0.0.1`/`::1` (local
    /// dev only) -- every request sends `Authorization: Bearer <api_key>`,
    /// a full-privilege, long-lived account credential, so an `http://` URL
    /// to anything else would put it on the wire in cleartext. Trailing
    /// slashes are stripped.
    pub fn base_url(mut self, base_url: impl Into<String>) -> Self {
        self.base_url = Some(base_url.into());
        self
    }

    /// A boxkite account API key (`bxk_live_...`).
    pub fn api_key(mut self, api_key: impl Into<String>) -> Self {
        self.api_key = Some(api_key.into());
        self
    }

    /// Per-request timeout. Defaults to 30 seconds. Ignored if
    /// [`ClientBuilder::http_client`] is also set -- configure the timeout
    /// on that client instead.
    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    /// Supply a preconfigured `reqwest::Client` instead of letting this
    /// builder construct one -- e.g. one pointed at a `wiremock` mock
    /// server in tests, or with custom TLS/proxy settings. Authentication
    /// is still applied per-request via `api_key` regardless.
    pub fn http_client(mut self, http_client: reqwest::Client) -> Self {
        self.http_client = Some(http_client);
        self
    }

    /// Validate the configuration and construct the [`Client`].
    ///
    /// # Errors
    /// [`BoxkiteError::Config`] if `base_url`/`api_key` weren't set, or if
    /// `base_url` isn't a valid `https://` (or localhost-only `http://`) URL.
    pub fn build(self) -> Result<Client, BoxkiteError> {
        let base_url = self
            .base_url
            .ok_or_else(|| BoxkiteError::Config("base_url is required".to_string()))?;
        let api_key = self
            .api_key
            .ok_or_else(|| BoxkiteError::Config("api_key is required".to_string()))?;
        validate_base_url_scheme(&base_url)?;
        let base_url = base_url.trim_end_matches('/').to_string();

        let http = match self.http_client {
            Some(client) => client,
            None => reqwest::Client::builder()
                .timeout(self.timeout.unwrap_or(DEFAULT_TIMEOUT))
                .build()
                .map_err(BoxkiteError::from)?,
        };

        Ok(Client {
            http,
            base_url,
            api_key,
        })
    }
}

fn validate_base_url_scheme(base_url: &str) -> Result<(), BoxkiteError> {
    let parsed = url::Url::parse(base_url)
        .map_err(|err| BoxkiteError::Config(format!("invalid base_url {base_url:?}: {err}")))?;
    match parsed.scheme() {
        "https" => Ok(()),
        "http"
            if parsed
                .host_str()
                .is_some_and(|h| LOCALHOST_HOSTNAMES.contains(&h)) =>
        {
            Ok(())
        }
        _ => Err(BoxkiteError::Config(format!(
            "refusing to use non-https base_url {base_url:?}: this would send your API key in \
             cleartext. Use an https:// URL, or http://localhost (local dev only)."
        ))),
    }
}

/// `https://` -> `wss://`, `http://` -> `ws://`. `base_url` has already
/// passed [`validate_base_url_scheme`], so it's always one of those two.
pub(crate) fn to_ws_url(base_url: &str, path: &str) -> String {
    if let Some(rest) = base_url.strip_prefix("https://") {
        format!("wss://{rest}{path}")
    } else if let Some(rest) = base_url.strip_prefix("http://") {
        format!("ws://{rest}{path}")
    } else {
        // Unreachable in practice -- validate_base_url_scheme already
        // rejects every other scheme before a Client can be constructed.
        format!("{base_url}{path}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_plain_http_to_a_remote_host() {
        let err = Client::builder()
            .base_url("http://cp.example.com")
            .api_key("bxk_live_test")
            .build()
            .unwrap_err();
        assert!(matches!(err, BoxkiteError::Config(_)));
    }

    #[test]
    fn allows_https() {
        assert!(Client::builder()
            .base_url("https://cp.example.com")
            .api_key("bxk_live_test")
            .build()
            .is_ok());
    }

    #[test]
    fn allows_http_localhost_for_local_dev() {
        assert!(Client::builder()
            .base_url("http://localhost:8090")
            .api_key("bxk_live_test")
            .build()
            .is_ok());
    }

    #[test]
    fn allows_http_127_0_0_1_for_local_dev() {
        assert!(Client::builder()
            .base_url("http://127.0.0.1:8090")
            .api_key("bxk_live_test")
            .build()
            .is_ok());
    }

    #[test]
    fn strips_trailing_slash() {
        let client = Client::builder()
            .base_url("https://cp.example.com/")
            .api_key("k")
            .build()
            .unwrap();
        assert_eq!(client.base_url, "https://cp.example.com");
    }

    #[test]
    fn requires_base_url_and_api_key() {
        assert!(matches!(
            Client::builder().api_key("k").build().unwrap_err(),
            BoxkiteError::Config(_)
        ));
        assert!(matches!(
            Client::builder()
                .base_url("https://cp.example.com")
                .build()
                .unwrap_err(),
            BoxkiteError::Config(_)
        ));
    }

    #[test]
    fn to_ws_url_converts_scheme() {
        assert_eq!(
            to_ws_url("https://cp.example.com", "/x"),
            "wss://cp.example.com/x"
        );
        assert_eq!(
            to_ws_url("http://localhost:8090", "/x"),
            "ws://localhost:8090/x"
        );
    }
}
