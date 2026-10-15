package grpc

import (
	"strings"
	"testing"

	"go.uber.org/zap"
	"google.golang.org/grpc"
)

// ADR-0006 / ADR-0008: Env, Panic and Delay are the gRPC twins of the gated
// HTTP routes, so the same flag gates them.
func TestUnsafeServicesFollowTheFlag(t *testing.T) {
	unsafe := []string{"Env", "Panic", "Delay"}

	for _, enabled := range []bool{false, true} {
		s := &Server{config: &Config{EnableUnsafeEndpoints: enabled}, logger: zap.NewNop()}
		srv := grpc.NewServer()
		s.registerServices(srv)

		for _, name := range unsafe {
			found := false
			for svc := range srv.GetServiceInfo() {
				if strings.Contains(svc, name+"Service") {
					found = true
				}
			}
			if found != enabled {
				t.Errorf("enable-unsafe-endpoints=%v: %sService registered=%v", enabled, name, found)
			}
		}
		if _, ok := srv.GetServiceInfo()["token.TokenService"]; !ok {
			t.Errorf("enable-unsafe-endpoints=%v: TokenService must always be registered", enabled)
		}
	}
}
