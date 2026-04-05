# Mim iOS App

iOS client for Mim, a semantic communication-based social platform built around on-device semantic image reconstruction.

Project overview:
https://github.com/lube8163-lab/mim-ios

## Current Features

- Timeline, following feed, my posts, and liked posts
- Email OTP sign-in, guest mode, logout, and account deletion
- Public profiles, follow / unfollow, block management, and profile editing
- Post details, threaded comments, report flow, and notification inbox
- Post deletion for your own posts from feed and detail views
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
- OTP verification now uses challenge-based verification between start / verify requests.
- Models marked as `Using` are the active models for posting and timeline reconstruction.
- Stable Diffusion backend changes from Settings are applied on next app launch / restart so the UI can switch cleanly without forcing an immediate heavy reload.
- Switching image-generation backends no longer regenerates already-generated images automatically. Existing rendered images stay visible until you manually regenerate or open posts that still need generation.
- Stable Diffusion uses deterministic seeds per post / model / prompt so the same input is more reproducible on the same device.
- For L2-L4 posts, Settings includes an option to force Stable Diffusion text-to-image generation instead of using an init image.
- Image Playground runs in prompt-only mode in this app. If a generated prompt is rejected, the app retries with progressively simpler concept inputs.
- Image Playground can fail on some prompts, may restrict person-related content, and the app now shows a short failure reason directly on the post card when generation fails.
- The onboarding flow and settings screens document fallback behavior, model restrictions, and Image Playground style controls.
- SigLIP2 is required for semantic fidelity scoring in Pro Mode.
- Prompt handling was tightened so placeholder text from image-understanding models is filtered and repaired before being used for reconstruction.

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
