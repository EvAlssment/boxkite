// Package boxkite is a Go client for a hosted boxkite control-plane -- the
// same v1 HTTP API sdk-python's BoxkiteClient and sdk-js's BoxkiteClient
// wrap (see docs/API.md in the boxkite repo). It is a thin request/response
// client: create sandboxes, run commands, edit files, stream the audit log,
// take over a sandbox's shell over a WebSocket -- all over HTTP against
// *someone else's* running control-plane. It is not a client for the
// boxkite package itself (SandboxManager, embedded directly against a
// Kubernetes cluster).
package boxkite

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// DefaultTimeout is the default per-request timeout, matching
// sdk-python/sdk-js's 30-second default.
const DefaultTimeout = 30 * time.Second

// ExecTimeoutHeadroom is added on top of a caller-supplied exec/http-request
// timeout so the HTTP client's own deadline never fires before the
// control-plane's -- mirrors sdk-python's EXEC_TIMEOUT_HEADROOM / sdk-js's
// EXEC_TIMEOUT_HEADROOM_MS.
const ExecTimeoutHeadroom = 15 * time.Second

var localhostHostnames = map[string]bool{
	"localhost": true,
	"127.0.0.1": true,
	"::1":       true,
}

// Client is a synchronous client for a hosted boxkite control-plane. Safe
// for concurrent use by multiple goroutines (it holds no mutable state
// beyond a shared *http.Client).
type Client struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
	timeout    time.Duration
	wsDialer   *websocket.Dialer
}

// Option configures a Client constructed via NewClient.
type Option func(*Client)

// WithHTTPClient overrides the *http.Client used for requests. Primarily
// useful for tests (point it at an httptest.Server) or for customizing
// transport-level behavior (proxies, custom TLS config).
func WithHTTPClient(hc *http.Client) Option {
	return func(c *Client) {
		c.httpClient = hc
	}
}

// WithTimeout overrides the default per-request timeout (DefaultTimeout).
func WithTimeout(d time.Duration) Option {
	return func(c *Client) {
		c.timeout = d
	}
}

// WithWebSocketDialer overrides the *websocket.Dialer used by Takeover.
// Primarily useful for tests.
func WithWebSocketDialer(d *websocket.Dialer) Option {
	return func(c *Client) {
		c.wsDialer = d
	}
}

// NewClient constructs a Client for a hosted control-plane at baseURL,
// authenticating every request with apiKey (a boxkite account API key,
// `bxk_live_...`, sent as `Authorization: Bearer <apiKey>`).
//
// baseURL must be https://, or http://localhost (local dev only) -- an
// apiKey is a full-privilege, long-lived credential, so anything else would
// put it on the wire in cleartext. Mirrors sdk-python's
// _validate_base_url_scheme / sdk-js's validateBaseUrlScheme.
func NewClient(baseURL, apiKey string, opts ...Option) (*Client, error) {
	if err := validateBaseURLScheme(baseURL); err != nil {
		return nil, err
	}
	c := &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		apiKey:  apiKey,
		timeout: DefaultTimeout,
	}
	for _, opt := range opts {
		opt(c)
	}
	if c.httpClient == nil {
		c.httpClient = &http.Client{Timeout: c.timeout}
	}
	if c.wsDialer == nil {
		c.wsDialer = websocket.DefaultDialer
	}
	return c, nil
}

func validateBaseURLScheme(baseURL string) error {
	parsed, err := url.Parse(baseURL)
	if err != nil {
		return fmt.Errorf("invalid base_url %q: %w", baseURL, err)
	}
	if parsed.Scheme == "https" {
		return nil
	}
	if parsed.Scheme == "http" && localhostHostnames[parsed.Hostname()] {
		return nil
	}
	return fmt.Errorf(
		"refusing to use non-https base_url %q: this would send your API key in "+
			"cleartext. Use an https:// URL, or http://localhost (local dev only)",
		baseURL,
	)
}

// wsURL rewrites the client's baseURL (https:// or http://, already
// validated by validateBaseURLScheme) plus a path suffix into the
// corresponding wss:///ws:// URL.
func (c *Client) wsURL(path string) string {
	switch {
	case strings.HasPrefix(c.baseURL, "https://"):
		return "wss://" + strings.TrimPrefix(c.baseURL, "https://") + path
	case strings.HasPrefix(c.baseURL, "http://"):
		return "ws://" + strings.TrimPrefix(c.baseURL, "http://") + path
	default:
		// Unreachable: validateBaseURLScheme already restricted baseURL to
		// one of the two schemes above.
		return c.baseURL + path
	}
}

// errorEnvelope mirrors the control-plane's `{"error": {code, message}}`
// error response shape (docs/API.md's "Error codes" section).
type errorEnvelope struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// requestOptions carries the handful of per-call overrides needed by exec
// and http_request (a longer read timeout, an Authorization override for
// resend_verification's dashboard-JWT call).
type requestOptions struct {
	timeout      time.Duration
	authOverride string
	query        url.Values
}

// doJSON issues one HTTP request against the control-plane and decodes a
// successful JSON response body into out (a pointer; pass nil for routes
// with no response body, e.g. a 204). reqBody, if non-nil, is marshaled as
// the JSON request body.
func (c *Client) doJSON(ctx context.Context, method, path string, reqBody any, out any, opts *requestOptions) error {
	var bodyReader io.Reader
	if reqBody != nil {
		encoded, err := json.Marshal(reqBody)
		if err != nil {
			return fmt.Errorf("boxkite: encoding request body: %w", err)
		}
		bodyReader = bytes.NewReader(encoded)
	}

	fullURL := c.baseURL + path
	if opts != nil && len(opts.query) > 0 {
		fullURL += "?" + opts.query.Encode()
	}

	req, err := http.NewRequestWithContext(ctx, method, fullURL, bodyReader)
	if err != nil {
		return &ConnectionError{Message: err.Error(), Err: err}
	}
	authValue := "Bearer " + c.apiKey
	if opts != nil && opts.authOverride != "" {
		authValue = "Bearer " + opts.authOverride
	}
	req.Header.Set("Authorization", authValue)
	if reqBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	httpClient := c.httpClient
	if opts != nil && opts.timeout > 0 {
		clientCopy := *c.httpClient
		clientCopy.Timeout = opts.timeout
		httpClient = &clientCopy
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return &ConnectionError{Message: err.Error(), Err: err}
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return &ConnectionError{Message: err.Error(), Err: err}
	}

	if resp.StatusCode >= 400 {
		return apiErrorFromResponse(resp.StatusCode, respBody)
	}

	if out != nil && len(respBody) > 0 {
		if err := json.Unmarshal(respBody, out); err != nil {
			return fmt.Errorf("boxkite: decoding response body: %w", err)
		}
	}
	return nil
}

func apiErrorFromResponse(statusCode int, body []byte) error {
	code := "error"
	message := fmt.Sprintf("HTTP %d", statusCode)
	var envelope errorEnvelope
	if err := json.Unmarshal(body, &envelope); err == nil && envelope.Error.Code != "" {
		code = envelope.Error.Code
		message = envelope.Error.Message
	}
	return &APIError{StatusCode: statusCode, Code: code, Message: message}
}
