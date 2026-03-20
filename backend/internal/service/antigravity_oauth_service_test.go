package service

import (
	"testing"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/antigravity"
)

func TestResolveDefaultTierID(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		loadRaw map[string]any
		want    string
	}{
		{
			name:    "nil loadRaw",
			loadRaw: nil,
			want:    "",
		},
		{
			name: "missing allowedTiers",
			loadRaw: map[string]any{
				"paidTier": map[string]any{"id": "g1-pro-tier"},
			},
			want: "",
		},
		{
			name:    "empty allowedTiers",
			loadRaw: map[string]any{"allowedTiers": []any{}},
			want:    "",
		},
		{
			name: "tier missing id field",
			loadRaw: map[string]any{
				"allowedTiers": []any{
					map[string]any{"isDefault": true},
				},
			},
			want: "",
		},
		{
			name: "allowedTiers but no default",
			loadRaw: map[string]any{
				"allowedTiers": []any{
					map[string]any{"id": "free-tier", "isDefault": false},
					map[string]any{"id": "standard-tier", "isDefault": false},
				},
			},
			want: "",
		},
		{
			name: "default tier found",
			loadRaw: map[string]any{
				"allowedTiers": []any{
					map[string]any{"id": "free-tier", "isDefault": true},
					map[string]any{"id": "standard-tier", "isDefault": false},
				},
			},
			want: "free-tier",
		},
		{
			name: "default tier id with spaces",
			loadRaw: map[string]any{
				"allowedTiers": []any{
					map[string]any{"id": "  standard-tier  ", "isDefault": true},
				},
			},
			want: "standard-tier",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			got := resolveDefaultTierID(tc.loadRaw)
			if got != tc.want {
				t.Fatalf("resolveDefaultTierID() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestBuildAntigravityRefreshTokenInfo_UsesReturnedRefreshToken(t *testing.T) {
	t.Parallel()

	now := time.Unix(1_700_000_000, 0)
	tokenInfo := buildAntigravityRefreshTokenInfo(&antigravity.TokenResponse{
		AccessToken:  "access-new",
		RefreshToken: "refresh-new",
		ExpiresIn:    3600,
		TokenType:    "Bearer",
	}, "refresh-old", now)

	if tokenInfo.AccessToken != "access-new" {
		t.Fatalf("AccessToken = %q, want %q", tokenInfo.AccessToken, "access-new")
	}
	if tokenInfo.RefreshToken != "refresh-new" {
		t.Fatalf("RefreshToken = %q, want %q", tokenInfo.RefreshToken, "refresh-new")
	}
	if tokenInfo.ExpiresAt != now.Unix()+3600-300 {
		t.Fatalf("ExpiresAt = %d, want %d", tokenInfo.ExpiresAt, now.Unix()+3600-300)
	}
}

func TestBuildAntigravityRefreshTokenInfo_FallsBackToSubmittedRefreshToken(t *testing.T) {
	t.Parallel()

	now := time.Unix(1_700_000_000, 0)
	tokenInfo := buildAntigravityRefreshTokenInfo(&antigravity.TokenResponse{
		AccessToken: "access-new",
		ExpiresIn:   3600,
		TokenType:   "Bearer",
	}, "refresh-old", now)

	if tokenInfo.RefreshToken != "refresh-old" {
		t.Fatalf("RefreshToken = %q, want %q", tokenInfo.RefreshToken, "refresh-old")
	}
	if tokenInfo.ExpiresAt != now.Unix()+3600-300 {
		t.Fatalf("ExpiresAt = %d, want %d", tokenInfo.ExpiresAt, now.Unix()+3600-300)
	}
}
