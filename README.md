# Mim iOS App

iOS client for Mim, a semantic communication-based social platform built around on-device semantic image reconstruction.

Project overview:
https://github.com/lube8163-lab/mim-ios

## Current Features

- Timeline, following feed, my posts, and liked posts
- Email OTP sign-in, guest mode, logout, and account deletion
- Public profiles, follow / unfollow, block management, and profile editing
- Post details, threaded comments, report flow, and notification inbox
- In-app model management for image understanding and image generation
- On-device image reconstruction with Stable Diffusion 1.5 and SD1.5 LCM
- Image understanding with SigLIP2 and Qwen3.5-VL
- Per-context generation prioritization for visible feeds, profiles, and post detail
- Regeneration controls for visible posts and single-post detail views
- Pro Mode semantic fidelity diagnostics for your own posts
- Japanese, English, and Simplified Chinese support across major flows

## Model Notes

- Models marked as `Using` are the active models for posting and timeline reconstruction.
- Right after installing or switching image-generation models, the app may briefly appear unresponsive while Core ML resources are loading.
- SigLIP2 is required for semantic fidelity scoring in Pro Mode.

## Notifications

- Push notifications are supported through APNs and the Cloudflare Worker backend.
- Development builds use the APNs development environment.
- TestFlight and App Store builds use the production environment.

## Build Notes

For SD1.5 + LCM Core ML artifact generation, see:

- `docs/lcm-coreml-build.md`

## License

This repository is licensed under the Apache License 2.0.
See `LICENSE` for details.
