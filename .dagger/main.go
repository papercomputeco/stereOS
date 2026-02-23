// stereOS Dagger CI module
//
// Provides CI functions for the stereOS flake.

package main

import (
	"context"
	"fmt"

	"dagger/stereos/internal/dagger"
)

type StereOS struct {
	Source *dagger.Directory
}

// New creates a new stereOS module instance.
func New(
	// Directory of the flake's source
	//
	// +defaultPath="/"
	// +ignore=["build", ".git", "result", ".direnv"]
	Source *dagger.Directory,
) *StereOS {
	return &StereOS{
		Source,
	}
}

// nixOSContainer returns a NixOS-enabled container with the flake source copied
// in and a fresh git repo initialised so that Nix flake evaluation works
// regardless of whether the host checkout is a worktree or a normal clone.
//
// Nix store caching: a persistent cache volume is mounted over /nix/store
// and seeded (once, when the volume is first created) from the base image's
// store contents. The Source option on WithMountedCache only applies when
// the cache does not yet exist, so subsequent runs — even with different
// source — reuse the volume and only fetch genuinely new derivations.
func (m *StereOS) nixOSContainer(src *dagger.Directory) *dagger.Container {
	// Extract the base image's /nix directory (store + var/nix DB) BEFORE
	// any source-dependent layers. This Directory reference is stable
	// (depends only on the base image), so it never changes between runs.
	baseNix := dag.Container().
		From("nixos/nix:latest").
		Directory("/nix")

	return dag.Container().
		From("nixos/nix:latest").

		// Enable flakes via env var rather than editing /etc/nix/nix.conf,
		// because nix.conf is a symlink into /nix/store and the cache
		// mount below replaces /nix contents.
		WithEnvVariable("NIX_CONFIG", "experimental-features = nix-command flakes").

		// Persistent cache over the entire /nix tree (store paths + Nix
		// DB). Seeded once from the base image. The DB and store stay in
		// sync so Nix recognises previously downloaded paths on every run.
		WithMountedCache("/nix", dag.CacheVolume("nix"), dagger.ContainerWithMountedCacheOpts{
			Source: baseNix,
		}).

		// Copy source flake into the container.
		WithDirectory("/workspace", src).
		WithWorkdir("/workspace").

		// Create a self-contained git repo so Nix sees a valid flake root.
		// The host .git may be a worktree pointer whose target doesn't
		// exist inside the container; a fresh init side-steps that.
		WithExec([]string{
			"sh", "-c",
			"git init && " +
				"git config user.email 'ci@stereos.ai' && " +
				"git config user.name 'CI' && " +
				"git add -A && " +
				"git commit -m init-flake",
		})
}

// CheckDevshell verifies that the Nix devshell evaluates and enters
// successfully inside a NixOS container. It mounts the flake source,
// runs "nix develop", and checks that the shell's tools are available.
//
// +check
func (m *StereOS) CheckDevshell(ctx context.Context) (string, error) {
	out, err := m.nixOSContainer(m.Source).
		WithExec([]string{
			"nix", "develop", "--command",
			"sh", "-c",
			"echo 'devshell ok' && go version && qemu-system-x86_64 --version | head -1",
		}).
		Stdout(ctx)
	if err != nil {
		return "", fmt.Errorf("devshell check failed: %w", err)
	}
	return out, nil
}
