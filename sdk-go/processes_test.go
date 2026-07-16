package boxkite

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

func TestStartProcess_DefaultsMaxRuntimeSecondsTo3600(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/sandboxes/sess-1/processes" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		if body["max_runtime_seconds"] != float64(3600) {
			t.Errorf("expected default max_runtime_seconds=3600, got %v", body["max_runtime_seconds"])
		}
		if body["command"] != "npm run dev" {
			t.Errorf("unexpected command: %v", body["command"])
		}
		writeJSON(t, w, 201, `{"process_id": "proc-1", "status": "running", "started_at": "2026-01-01T00:00:00Z"}`)
	})
	defer closeServer()

	result, err := client.StartProcess(context.Background(), "sess-1", "npm run dev", nil)
	if err != nil {
		t.Fatalf("StartProcess: %v", err)
	}
	if result.ProcessID != "proc-1" || result.Status != "running" {
		t.Errorf("unexpected result: %+v", result)
	}
}

func TestStartProcess_CustomOptions(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		if body["max_runtime_seconds"] != float64(1800) {
			t.Errorf("unexpected max_runtime_seconds: %v", body["max_runtime_seconds"])
		}
		if body["description"] != "dev server" {
			t.Errorf("unexpected description: %v", body["description"])
		}
		if body["expose_port"] != float64(3000) {
			t.Errorf("unexpected expose_port: %v", body["expose_port"])
		}
		writeJSON(t, w, 201, `{"process_id": "proc-2", "status": "running", "started_at": "2026-01-01T00:00:00Z"}`)
	})
	defer closeServer()

	_, err := client.StartProcess(context.Background(), "sess-1", "npm run dev", &StartProcessOptions{
		Description:       Ptr("dev server"),
		MaxRuntimeSeconds: 1800,
		ExposePort:        Ptr(3000),
	})
	if err != nil {
		t.Fatalf("StartProcess: %v", err)
	}
}

func TestListProcesses(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/v1/sandboxes/sess-1/processes" {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		writeJSON(t, w, 200, `{"processes": [{"process_id": "proc-1", "command": "npm run dev", "description": null, "status": "running", "started_at": "2026-01-01T00:00:00Z", "exit_code": null}]}`)
	})
	defer closeServer()

	result, err := client.ListProcesses(context.Background(), "sess-1")
	if err != nil {
		t.Fatalf("ListProcesses: %v", err)
	}
	if len(result.Processes) != 1 || result.Processes[0].ProcessID != "proc-1" {
		t.Errorf("unexpected result: %+v", result)
	}
}

func TestGetProcessOutput_SendsSinceOffset(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("since_offset"); got != "27" {
			t.Errorf("expected since_offset=27, got %q", got)
		}
		writeJSON(t, w, 200, `{"status": "running", "stdout_chunk": "more\n", "next_offset": 32, "truncated": false, "exit_code": null}`)
	})
	defer closeServer()

	result, err := client.GetProcessOutput(context.Background(), "sess-1", "proc-1", 27)
	if err != nil {
		t.Fatalf("GetProcessOutput: %v", err)
	}
	if result.NextOffset != 32 {
		t.Errorf("unexpected next_offset: %d", result.NextOffset)
	}
}

func TestSendProcessInput(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/sandboxes/sess-1/processes/proc-1/input" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		if body["data"] != "y\n" {
			t.Errorf("unexpected data: %v", body["data"])
		}
		writeJSON(t, w, 200, `{"bytes_written": 2}`)
	})
	defer closeServer()

	result, err := client.SendProcessInput(context.Background(), "sess-1", "proc-1", "y\n")
	if err != nil {
		t.Fatalf("SendProcessInput: %v", err)
	}
	if result.BytesWritten != 2 {
		t.Errorf("unexpected bytes_written: %d", result.BytesWritten)
	}
}

func TestStopProcess(t *testing.T) {
	client, closeServer := newTestClient(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/sandboxes/sess-1/processes/proc-1/stop" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		writeJSON(t, w, 200, `{"status": "stopped", "exit_code": 143}`)
	})
	defer closeServer()

	result, err := client.StopProcess(context.Background(), "sess-1", "proc-1")
	if err != nil {
		t.Fatalf("StopProcess: %v", err)
	}
	if result.Status != "stopped" || result.ExitCode == nil || *result.ExitCode != 143 {
		t.Errorf("unexpected result: %+v", result)
	}
}
