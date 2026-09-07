// Package control invokes the Bash CLI without involving a shell.
package control

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type State struct {
	Status string `json:"status"`
	Mode   string `json:"mode"`
	Config string `json:"config"`
	Proxy  string `json:"proxy"`
}

type Client struct{ Path string }

func (c Client) Run(ctx context.Context, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 35*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, c.Path, args...)
	cmd.WaitDelay = time.Second
	output, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(output))
	if err != nil {
		if text == "" {
			text = err.Error()
		}
		return "", fmt.Errorf("%s", text)
	}
	return text, nil
}

func (c Client) Status(ctx context.Context) (State, error) {
	text, err := c.Run(ctx, "status", "--json")
	if err != nil {
		return State{}, err
	}
	return ParseState([]byte(text))
}

func ParseState(data []byte) (State, error) {
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return s, err
	}
	switch s.Status {
	case "running", "disconnected", "reconnecting", "stopping", "failed", "unknown":
		return s, nil
	default:
		return s, fmt.Errorf("unrecognized CLI status %q", s.Status)
	}
}
