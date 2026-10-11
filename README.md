# Mim iOS App

iOS client for Mim, a semantic communication-based social platform built around on-device semantic image reconstruction.

Project overview:
https://github.com/lube8163-lab/mim-ios

## Current app: architecture and measured performance (2026-10-11)

This section describes **Mim 2.0.0 (build 39), submitted for App Store review on 2026-10-11**. The public source tree remains the June 2026 snapshot; this is a documentation update only. The historical instructions below describe that older code and do not reproduce the current app.

日本語概要: 現在は端末内のLFM2.5-VL-450Mで写真を説明し、その意味・配置などを共有するレシピからFLUX.2 Klein 4Bで画像を再現します。以下に実機の速度、メモリ指標、対応環境を記載しています。

### How it works

1. A photo post is accepted as pending. Its source image stays in the app's private device storage; a durable queue prepares the description and generation recipe while the app is active.
2. Input image safety checks run before **LFM2.5-VL-450M / CoreAI** extracts subjects, counts, positions, relations, colors, background, lighting and medium. **Apple Foundation Models** is the fallback when CoreAI understanding is unavailable or fails, subject to device and Apple Intelligence availability.
3. The **Cloudflare Worker** stores and distributes text and recipe metadata through **D1**. Model packages are served from **R2**. The normal photo-post payload contains the description and recipe, rather than the source photograph; inference runs on the device.
4. Each viewer's device reconstructs the recipe with **FLUX.2 Klein 4B / CoreAI**. Recipe-v2 shares model identity, prompt, resolution, scheduler and generation settings, with `seedPolicy: viewerRandom`; each client persists its own random seed per post. Generated images are checked before return and cache reuse.

Photo analysis can pause browsing generation at a step boundary, release the heavy GPU models, analyze the new photo, and resume the same recipe and viewer seed. CPU tokenizer/text-condition caches avoid some repeated work. GPU analysis pauses when the app goes into the background; unfinished photo jobs resume on return.

### Models and assets

| Role | Current model / runtime | Configuration and distribution |
| --- | --- | --- |
| Preferred photo understanding | LFM2.5-VL-450M / CoreAI | INT8 decoder + FP16 vision tower; aspect-preserving 512px input; structured output up to 750 tokens. Download: **554,278,020 bytes (~554 MB)** in three fragments. Pinned model revision: `f6648f9c65402a4d5c280cae41b672f977e74e3a`. |
| Image reconstruction | FLUX.2 Klein 4B / CoreAI GPU | Derived 512px-only model, preserved 4-bit weights, **512 × 512, four steps, guidance 1, discrete-flow**. Download: **3,542,141,404 bytes (~3.54 GB)** in 18 fragments; installed files: **4,043,710,174 bytes (~4.04 GB)**. Asset revision: `coreai-512-4bit-a7f65cd-v1`. |
| Understanding fallback | Apple Foundation Models / system framework | System-supplied assets. This app's fallback is restricted to eligible iPhones with Apple Intelligence available; it is not guaranteed on every supported iPad. |
| Image safety | ImageSafetyClassifier S / Core ML + Vision | Bundled classifier, CPU / Neural Engine; checks SFW, NSFW and NSFL. Non-square input uses both full-frame and center views. Missing, invalid or blocked results are withheld. |

Downloads support resume and SHA-256 verification before atomic installation. FLUX preparation needs approximately **8 GB of free storage** for the archive, extraction and installation; this is a disk-space requirement, separate from RAM. Model weights stay outside this source repository and retain their respective licenses, including LFM Open License v1.0, FLUX Apache-2.0, and the safety classifier's MIT / backbone Apache-2.0 notices. The active distribution catalog is available as [model manifest](https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/manifest.json).

### Supported and measured devices

- App minimum: **iOS / iPadOS 27.0.1**, iPhone and iPad.
- FLUX reconstruction: a supported physical CoreAI device with **nominal RAM of at least 8 GB**. The app's physical-memory threshold is 7,500,000,000 bytes. Simulator inference is unavailable.
- Performance measurements below: **physical iPhone 17, iOS 27.0.1 (24A446)**; reported physical memory **8,045,641,728 bytes (~8.05 GB / 7.49 GiB)**.
- UI and language checks also passed on **iPad (10th generation), iPadOS 27.0.1**. That device does not meet the FLUX RAM requirement, so these checks are not iPad image-generation benchmarks.
- Seven UI languages: Japanese, English, Korean, Spanish, Brazilian Portuguese, Simplified Chinese and Traditional Chinese. First launch follows the device's preferred language; unsupported languages fall back to English. A saved in-app language takes precedence and can be changed in Settings.

### Performance through the real app's pipeline

Measured on **2026-10-11** using the app's offline `MimFluxAdoption` diagnostic in **Debug 1.7.0 / build 33**, which introduced the current FLUX pipeline. This exercised the app's installer, model manager, source-image safety, VLM, recipe builder, renderer and generated-image safety. These are recorded development-build measurements, **not a fresh benchmark of the submitted build 39**.

The fixture was the non-personal onboarding apple image. Generation used 512 × 512, four steps and fixed diagnostic seeds 42 / 43. The two columns are individual trials, not averages or a guaranteed device-wide range. No account, server post or personal photo library was involved.

| Operation / metric | First trial after installation | Later trial with prepared assets |
| --- | ---: | ---: |
| LFM photo analysis, including input safety and preparation | **15.33 s** | **7.47 s** |
| First FLUX image in that process, including preparation, output safety and PNG save | **41.22 s** | **19.22 s** |
| Later FLUX generation with the same prompt, a different seed and output safety | Not recorded | **15.72 s** |
| Photo-analysis request during generation → analysis complete | 8.68 s | 8.35 s |
| Of the preceding row: LFM analysis including input safety | 6.16 s | 6.03 s |
| Remaining wait / scheduling overhead in that row | 2.52 s | 2.32 s |
| Sampled maximum physical footprint of the **whole app run** | **1.412 GiB (~1.516 GB)** | **1.408 GiB (~1.512 GB)** |

Analysis timing includes input safety, asset inventory checks, full hashes on first use of an unchanged inventory, image normalization, model loading, inference, GPU release and structured-response validation. Generation timing excludes the separate VLM stage, network transfers and model downloads. The 15.72 s later generation ends at the checked image's return and excludes PNG encoding/saving, whereas the first-generation rows include PNG saving. Installation timing is not a general download-speed benchmark.

Memory was sampled with `task_vm_info.phys_footprint` every **100 ms**. The maximum covers the entire diagnostic run, including both models, safety checks and app overhead; **it is not the isolated RAM usage of either model, or the phone's total memory use**. Per-model peaks and a separate Apple Foundation Models latency/peak-memory benchmark have not been isolated. GB is decimal (10⁹ bytes); GiB is binary (2³⁰ bytes).

The prepared-assets trial was in **nominal** thermal state at the start, before generation and at completion. Pause/resume produced byte-identical PNGs for the same recipe/seed, while seed 43 produced a different image. The diagnostic confirmed model release on completion. First-use compilation, OS caches, thermal state, scene complexity and concurrent work can change timings; 100 ms sampling can miss instantaneous memory peaks.

### Earlier optimization experiment — separate from the app benchmark

A dedicated FLUX probe on the **same iPhone 17 / iOS 27.0.1** completed 15 safety-checked images, including a six-image sequential batch, during 2026-10-10–11. Its retained-model measurements use a different lifecycle from the real-app trial above.

| Dedicated probe measurement | Observed value |
| --- | ---: |
| Four-step image with pre-encoded text and retained models | **11.90–14.60 s** |
| Same prompt/seed in the same process: uncached → cached | **17.32 → 11.90 s** (31.3% less time; identical PNG) |
| Two-step image with reused text/models | **6.47–6.66 s** |
| Generated-image safety classification alone | **0.045–0.407 s** |
| Maximum sampled process physical footprint | **1.52 GiB (~1.63 GB)** |
| Maximum sampled Metal allocation counter, a separate metric | **5.22 GiB (~5.60 GB)** |

Per-image probe times include output safety but exclude common pipeline initialization, any batch prompt pre-encoding, VLM, network and downloads. The safety row is from these benign generated-image tests, not a complete source-photo validation or unsafe-image accuracy study. No isolated peak memory was recorded for the safety classifier. **Do not add Metal allocation to physical footprint:** they are different counters and do not establish total device RAM usage. The probe sampled memory every 100 ms. Two steps visibly weakened detail / placement, so the current app uses four steps. The 11.90 s probe result is not a measured build-39 first-image latency.

These measurements cover a limited set of benign fixtures. Broad reconstruction quality, unsafe-image detection accuracy, long-running memory behavior and image-generation performance on other devices remain unmeasured.

## Historical public source snapshot (2026-06-16)

The sections below are preserved for the public code at [commit `494e4a4`](https://github.com/lube8163-lab/mim-ios-app/tree/494e4a4d49ae9527e44bf042edce50f9554ef6dc). The SigLIP2, Qwen3.5-VL, Image Playground and SD1.5 / LCM descriptions belong to that snapshot. They are not the current app's default model configuration. Supported legacy Core ML recipes still have a compatibility path in the current app.

### Features in the source snapshot

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
- Pro Mode semantic fidelity and LPIPS perceptual diagnostics for your own posts
- First-launch onboarding with backend guidance, model-install guidance, and legal consent flow
- Per-post image-understanding backend labels shown in feed and detail views
- Japanese, English, Korean, Spanish, Brazilian Portuguese, Simplified Chinese, and Traditional Chinese support across major flows

### Model Notes

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
- LPIPS perceptual scoring is available from the bundled model.
- SigLIP2 is required for semantic fidelity scoring in Pro Mode.
- Prompt handling was tightened so placeholder text from image-understanding models is filtered and repaired before being used for reconstruction.

### Localization Workflow

- `SemanticCompression-v2/Localizable.xcstrings` is the localization source of truth.
- Generated `*.lproj/Localizable.strings` files are kept in sync with:
  - `python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/sync_localizations.py`
- Full notes are in `LOCALIZATION.md`.

### Notifications

- Push notifications are supported through APNs and the Cloudflare Worker backend.
- Development builds use the APNs development environment.
- TestFlight and App Store builds use the production environment.

### Moderation Notes

- Reporting a post hides it for the reporting viewer only.
- Reported posts remain visible to other viewers unless they also report the same post or a separate moderation action is taken on the backend.

### Build Notes

For SD1.5 + LCM Core ML artifact generation, see:

- `docs/lcm-coreml-build.md`

## License

This repository is licensed under the Apache License 2.0.
See `LICENSE` for details.
