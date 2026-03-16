# Mim iOS App

iOS client for Mim, a semantic communication-based social platform.

Project overview:
https://github.com/lube8163-lab/mim-ios

## Highlights

- On-device image reconstruction workflow
- In-app model install and selection
- Stable Diffusion 1.5 and Stable Diffusion 1.5 (LCM) support
- SigLIP2 and Qwen3.5-VL image understanding support
- Semantic fidelity scoring for your own posts in Pro Mode

## Recent Changes

- Added Qwen3.5-VL as an on-device image understanding option
- Added SHA256 verification for model downloads
- Added model-aware generation behavior and model-specific cache handling
- Added semantic similarity scoring with SigLIP2 for regenerated images in Pro Mode
- Added Pro Mode UI for semantic fidelity, processing time, and memory footprint visibility
- Added safer cache controls and model install error messaging

## Planned

- Additional similarity metrics such as LPIPS
- More VLM experiments
- Further evaluation and diagnostics tooling for semantic compression workflows

## Build Notes

For SD1.5 + LCM Core ML artifact generation, see:

- `docs/lcm-coreml-build.md`

## License

This repository is licensed under the Apache License 2.0.
See `LICENSE` for details.
