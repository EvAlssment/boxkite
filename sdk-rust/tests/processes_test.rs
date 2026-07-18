mod common;

use boxkite_client::StartProcessOptions;
use serde_json::json;
use wiremock::matchers::{body_json, method, path, query_param};
use wiremock::{Mock, ResponseTemplate};

#[tokio::test]
async fn start_process_sends_only_set_optional_fields() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("POST"))
        .and(path("/v1/sandboxes/sess-1/processes"))
        .and(body_json(json!({
            "command": "npm run dev",
            "max_runtime_seconds": 3600
        })))
        .respond_with(ResponseTemplate::new(201).set_body_json(json!({
            "process_id": "proc_1", "status": "running", "started_at": "2026-01-01T00:00:00Z"
        })))
        .mount(&server)
        .await;

    let result = client
        .start_process("sess-1", "npm run dev", StartProcessOptions::new())
        .await
        .expect("start_process should succeed");

    assert_eq!(result.process_id, "proc_1");
    assert_eq!(result.status, "running");
}

#[tokio::test]
async fn start_process_sends_all_set_optional_fields() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("POST"))
        .and(path("/v1/sandboxes/sess-1/processes"))
        .and(body_json(json!({
            "command": "npm run dev",
            "description": "dev server",
            "max_runtime_seconds": 1800,
            "expose_port": 3000
        })))
        .respond_with(ResponseTemplate::new(201).set_body_json(json!({
            "process_id": "proc_2", "status": "running", "started_at": "2026-01-01T00:00:00Z"
        })))
        .mount(&server)
        .await;

    let options = StartProcessOptions::new()
        .description("dev server")
        .max_runtime_seconds(1800)
        .expose_port(3000);

    client
        .start_process("sess-1", "npm run dev", options)
        .await
        .expect("start_process should succeed");
}

#[tokio::test]
async fn list_processes_returns_all_tracked_processes() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("GET"))
        .and(path("/v1/sandboxes/sess-1/processes"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "processes": [
                {
                    "process_id": "proc_1", "command": "npm run dev", "description": null,
                    "status": "running", "started_at": "2026-01-01T00:00:00Z",
                    "exit_code": null, "expose_port": 3000
                },
                {
                    "process_id": "proc_2", "command": "sleep 1", "description": "quick nap",
                    "status": "exited", "started_at": "2026-01-01T00:00:00Z",
                    "exit_code": 0, "expose_port": null
                }
            ]
        })))
        .mount(&server)
        .await;

    let result = client
        .list_processes("sess-1")
        .await
        .expect("list_processes should succeed");

    assert_eq!(result.processes.len(), 2);
    assert_eq!(result.processes[0].expose_port, Some(3000));
    assert_eq!(result.processes[1].expose_port, None);
    assert_eq!(result.processes[1].exit_code, Some(0));
}

#[tokio::test]
async fn get_process_output_sends_since_offset_as_query_param() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("GET"))
        .and(path("/v1/sandboxes/sess-1/processes/proc_1/output"))
        .and(query_param("since_offset", "42"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "status": "running", "stdout_chunk": "hello\n", "next_offset": 48,
            "truncated": false, "exit_code": null
        })))
        .mount(&server)
        .await;

    let result = client
        .get_process_output("sess-1", "proc_1", 42)
        .await
        .expect("get_process_output should succeed");

    assert_eq!(result.stdout_chunk, "hello\n");
    assert_eq!(result.next_offset, 48);
}

#[tokio::test]
async fn send_process_input_returns_bytes_written() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("POST"))
        .and(path("/v1/sandboxes/sess-1/processes/proc_1/input"))
        .and(body_json(json!({"data": "y\n"})))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"bytes_written": 2})))
        .mount(&server)
        .await;

    let result = client
        .send_process_input("sess-1", "proc_1", "y\n")
        .await
        .expect("send_process_input should succeed");

    assert_eq!(result.bytes_written, 2);
}

#[tokio::test]
async fn stop_process_returns_exit_code() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("POST"))
        .and(path("/v1/sandboxes/sess-1/processes/proc_1/stop"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "status": "stopped", "exit_code": 0
        })))
        .mount(&server)
        .await;

    let result = client
        .stop_process("sess-1", "proc_1")
        .await
        .expect("stop_process should succeed");

    assert_eq!(result.status, "stopped");
    assert_eq!(result.exit_code, Some(0));
}

#[tokio::test]
async fn get_process_output_maps_unknown_process_id_to_404() {
    let server = common::mock_server().await;
    let client = common::client_for(&server);

    Mock::given(method("GET"))
        .and(path("/v1/sandboxes/sess-1/processes/proc_missing/output"))
        .respond_with(ResponseTemplate::new(404).set_body_json(json!({
            "error": {"code": "not_found", "message": "Process not found"}
        })))
        .mount(&server)
        .await;

    let err = client
        .get_process_output("sess-1", "proc_missing", 0)
        .await
        .unwrap_err();

    assert_eq!(err.code(), Some("not_found"));
    assert_eq!(err.status(), Some(404));
}
