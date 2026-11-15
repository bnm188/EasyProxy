# EasyProxy

EasyProxy is a modular proxy-management package for ImmortalWrt.

## Current stage

Stage 1 is a guarded core scaffold:
- UCI configuration and validation
- CLI status/validation commands
- init integration
- separate dae and sing-box adapter interfaces

**This stage does not implement proxy traffic, firewall rules, DNS interception, node subscriptions, or a LuCI interface.** The service intentionally refuses to start a proxy until Stage 2 runtime adapters exist.

## Target

- ImmortalWrt x86_64
- Independent IPK package
- CI builds through the ImmortalWrt SDK action
- Future engines: dae and sing-box

## Build workflow

GitHub Actions runs on:
- pushes and pull requests to `main`
- manual dispatch
- weekly scheduled build
- version tags such as `v0.1.0`

The workflow builds only `easyproxy` for `x86_64`, stores the IPK as a workflow artifact, and creates a GitHub Release when a `v*` tag is pushed.

The build uses the ImmortalWrt-maintained `gh-action-sdk` action. Its documented `ARCH` and `PACKAGES` inputs are used here. The exact SDK/toolchain used by that action can evolve upstream; inspect the workflow run logs and test the resulting package on the intended ImmortalWrt release before deployment.

## Create a release

After verifying a successful build, create and push a version tag:
```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will build the package and attach the IPK plus SHA256 checksum to the release.

## Install on router

Do not install a Stage 1 scaffold expecting proxy functionality. It is for validating packaging and safe configuration interfaces only.
