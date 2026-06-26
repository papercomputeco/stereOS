# stereOS Lambda MicroVM Source Bundle

This bundle is a Dockerfile-based source package for AWS Lambda MicroVM image
creation. It is intentionally separate from stereOS VM mixtapes: it does not
contain `stereos.img`, `stereos.qcow2`, a custom kernel, or direct-kernel boot
artifacts.

## Source Files

The checked-in build logic lives in:

- `lib/lambda-microvm.nix`: assembles the rootfs, generates the Dockerfile,
  and zips the source bundle.
- `lambda-microvm/lifecycle/`: the Rust HTTP lifecycle process, built from
  source by Nix (`buildRustPackage`) and copied into the rootfs as
  `/bin/lambda-microvm-lifecycle`.
- `flake/images.nix`: exposes the generated
  `packages.<system>.<mixtape>-lambda-microvm-source` package.

`src/Dockerfile` and `src/stereos-rootfs.tar` are generated files inside the
Nix build output; they are not checked into the repository.

## Build Locally

```bash
nix build .#packages.x86_64-linux.coder-lambda-microvm-source --impure
```

The Nix result contains:

- `src/Dockerfile`
- `src/stereos-rootfs.tar`
- `<mixtape>-lambda-microvm-source.zip`

Upload the zip to S3 and use it as the source object for
`aws lambda-microvms create-microvm-image`.

## Runtime Contract

The image starts `/bin/lambda-microvm-lifecycle` and listens on `HOOK_PORT`,
default `9000`. This follows the AWS Claude managed-agents sample image.

Endpoints:

- `GET /ready`
- `POST /ready`
- `GET /validate`
- `POST /validate`
- `GET /aws/lambda-microvms/runtime/v1/ready`
- `POST /aws/lambda-microvms/runtime/v1/ready`
- `GET /aws/lambda-microvms/runtime/v1/validate`
- `POST /aws/lambda-microvms/runtime/v1/validate`
- `POST /aws/lambda-microvms/runtime/v1/run`
- `POST /aws/lambda-microvms/runtime/v1/suspend`
- `POST /aws/lambda-microvms/runtime/v1/resume`
- `POST /aws/lambda-microvms/runtime/v1/terminate`
- `POST /run`
- `POST /suspend`
- `POST /resume`
- `POST /terminate`
- `GET /health`

`POST /run` executes `STEREOS_RUN_COMMAND` when that environment variable is
set. The request body is passed to the command as `STEREOS_RUN_PAYLOAD`.

`POST /aws/lambda-microvms/runtime/v1/run` accepts the AWS service envelope
shape:

```json
{"microvmId":"...","runHookPayload":"{\"version\":\"1\",\"session\":{...}}"}
```

The lifecycle process records the parsed `session` object as
`last_run_dispatch`, acknowledges immediately, and runs `STEREOS_RUN_COMMAND` in
a background thread with the parsed dispatch JSON as `STEREOS_RUN_PAYLOAD`.

The default stereOS Lambda MicroVM source bundles include the Paper CLI from a
pinned public Paper Compute release artifact. They set `STEREOS_START_PAPERD=1`,
so the lifecycle process starts `paperd` when it finds the binary at
`/usr/local/bin/paperd`, `/bin/paperd`, or `/bin/paper`. Set
`STEREOS_START_PAPERD=0` in a derived image to opt out.

## Build-time Warm-up (`STEREOS_READY_COMMAND`)

When `STEREOS_READY_COMMAND` is set, the lifecycle process runs it **once**, on
the first AWS `ready` build hook, **before** responding 200 — so its disk writes
are captured in the image snapshot and every launched MicroVM starts warm. It
runs as the agent user (uid/gid `1000`) with an agent-rooted login environment
(`HOME`/XDG under `/home/agent`), via `/bin/bash -lc`, bounded by
`STEREOS_READY_TIMEOUT_SECONDS` (default `240`, kept under the AWS
`readyTimeoutInSeconds`). The result is logged to CloudWatch, not stored in the
snapshot's `last_run_command`.

Mixtapes built with `warmAgent = true` ship `/usr/local/bin/stereos-warm-agent`
and point `STEREOS_READY_COMMAND` at it. That script runs `claude install` to
pre-cache Claude Code's native build (no auth, no `paper`), then pre-seeds
onboarding so the first interactive run skips the theme prompt.

Warm-up must produce only **shareable** state. The Firecracker snapshot is shared
by every MicroVM created from the image, so the script strips the per-machine
identifiers `claude install` writes (`machineID`, `userID`) so they regenerate
per-VM. Never `paper login` or otherwise bake secrets/unique state during the
build. Warm-up failures (e.g. no network during build) are non-fatal: the image
just ships unwarmed.

## Native Shell / SSH Access

The Lambda MicroVM source bundle includes OpenSSH server binaries and host keys
so it can be reached with the `microvmssh` ProxyCommand pattern:

- The image includes `/usr/sbin/sshd`, `/usr/bin/echo`, and `/usr/bin/stty`
  compatibility paths.
- `sshd` is not started as a daemon.
- The local `microvmssh` client opens AWS native shell ingress, runs
  `stty raw -echo; exec /usr/sbin/sshd -i ...`, then lets a normal local
  `ssh` client speak over that shell WebSocket.

Launch the MicroVM with the AWS-managed `SHELL_INGRESS` connector to enable this
path.
