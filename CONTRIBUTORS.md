# Contributors Guide

## Prerequisites

Dependencies are managed with [pixi](https://pixi.sh). Install pixi, then run:

```bash
pixi install
```

This provides `nextflow`, `nf-core`, `nf-test`, and `gh` at the pinned versions
declared in `pixi.toml`.

## Linting

Use `-exclude .pixi` to avoid linting the pixi environment's nf-core templates:

```bash
nextflow lint -exclude .pixi .
```

> **Note:** Warnings about variables declared in `main:` being "unused" are a known
> linter false positive. The Nextflow spec guarantees those variables are in scope in
> the `publish:` section.

## Testing

Tests use [nf-test](https://nf-test.com) and pull public sarscov2 test data from
the nf-core test-datasets repository — no large files are committed to this repo.

### Run all tests

```bash
nf-test test --profile docker
```

### Run tests for a single entry workflow

```bash
# Stage 1 — trimming & QC
nf-test test tests/clean_data.nf.test --profile docker

# Stage 2 — quantification
nf-test test tests/quant_data.nf.test --profile docker

# End-to-end pipeline
nf-test test tests/main.nf.test --profile docker
```

### Fast smoke-tests (stub mode, no containers needed)

Each test file includes a `stub` variant that validates process wiring without
executing any tools. These run in seconds and require no container runtime:

```bash
nf-test test --filter stub
```

### Update snapshots

After intentional output changes, regenerate the snapshot files:

```bash
nf-test test --update-snapshot --profile docker
```

Snapshots are stored alongside the test files as `*.nf.test.snap` and should be
committed to version control.
