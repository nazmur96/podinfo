package http

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// ADR-0006 / ADR-0008: gated routes must 404 when the flag is off (default).
func TestUnsafeEndpointsOffByDefault(t *testing.T) {
	srv := NewMockServer()
	srv.registerHandlers()

	cases := []struct {
		method string
		path   string
	}{
		{"GET", "/env"},
		{"GET", "/configs"},
		{"GET", "/debug/pprof/"},
		{"GET", "/panic"},
		{"GET", "/delay/1"},
		{"GET", "/chunked"},
		{"POST", "/store"},
		{"POST", "/fault_injection/enable"},
		{"POST", "/readyz/disable"},
	}

	for _, tc := range cases {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			rr := httptest.NewRecorder()
			srv.router.ServeHTTP(rr, req)
			if rr.Code != http.StatusNotFound {
				t.Fatalf("%s %s returned %d, want 404 (unsafe routes off)", tc.method, tc.path, rr.Code)
			}
		})
	}

	// Safe routes still work.
	req := httptest.NewRequest("GET", "/readyz", nil)
	rr := httptest.NewRecorder()
	srv.router.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK && rr.Code != http.StatusServiceUnavailable {
		t.Fatalf("GET /readyz returned %d, want 200 or 503", rr.Code)
	}
}

func TestUnsafeEndpointsOnWhenEnabled(t *testing.T) {
	srv := NewMockServer()
	srv.config.EnableUnsafeEndpoints = true
	srv.registerHandlers()

	req := httptest.NewRequest("GET", "/env", nil)
	rr := httptest.NewRecorder()
	srv.router.ServeHTTP(rr, req)
	if rr.Code == http.StatusNotFound {
		t.Fatal("GET /env returned 404 with enable-unsafe-endpoints=true; route should be registered")
	}
}
