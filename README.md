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
- Apple fallback backends for no-download setups: Apple Vision for image understanding and Image Playground for image generation
- On-device image reconstruction with Stable Diffusion 1.5 and SD1.5 LCM
- Image understanding with SigLIP2 and Qwen3.5-VL
- Image Playground style selection with `Animation`, `Illustration`, and `Sketch`
- Per-context generation prioritization for visible feeds, profiles, and post detail
- Regeneration controls for visible posts and single-post detail views
- Pro Mode semantic fidelity diagnostics for your own posts
- First-launch onboarding with backend guidance, model-install guidance, and legal consent flow
- Per-post image-understanding backend labels shown in feed and detail views
- Japanese, English, and Simplified Chinese support across major flows

## Model Notes

- The app can post and view image-based content even when no extra models are installed.
- In no-download mode, image understanding falls back to Apple Vision and image generation falls back to Image Playground.
- Qwen3.5-VL is the recommended downloadable image-understanding model when you want stronger caption / prompt quality.
- Models marked as `Using` are the active models for posting and timeline reconstruction.
- Right after installing or switching image-generation models, the app may briefly appear unresponsive while Core ML resources are loading.
- Image Playground runs in prompt-only mode in this app. If a generated prompt is rejected, the app retries with progressively simpler concept inputs.
- SigLIP2 is required for semantic fidelity scoring in Pro Mode.

## Notifications

- Push notifications are supported through APNs and the Cloudflare Worker backend.
- Development builds use the APNs development environment.
- TestFlight and App Store builds use the production environment.

## Moderation Notes

- Reporting a post hides it for the reporting viewer only.
- Reported posts remain visible to other viewers unless they also report the same post or a separate moderation action is taken on the backend.

## Build Notes

For SD1.5 + LCM Core ML artifact generation, see:

- `docs/lcm-coreml-build.md`

## License

This repository is licensed under the Apache License 2.0.
See `LICENSE` for details.
