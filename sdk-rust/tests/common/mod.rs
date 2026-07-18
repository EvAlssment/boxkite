//! Shared test helpers: spin up a `wiremock` mock control-plane and build a
//! `Client` pointed at it -- mirrors `sdk-python`'s `_client_with(handler)`
//! using `httpx.MockTransport`, but against a real local HTTP server
//! instead of an in-process transport shim.

use boxkite_client::Client;
use wiremock::MockServer;

pub const TEST_API_KEY: &str = "bxk_live_test";

pub async fn mock_server() -> MockServer {
    MockServer::start().await
}

pub fn client_for(server: &MockServer) -> Client {
    Client::new(server.uri(), TEST_API_KEY).expect("valid test client config")
}
