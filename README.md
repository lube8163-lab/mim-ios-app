# Mim iOS App

iOS client for Mim, a semantic communication-based social platform built around on-device semantic image reconstruction.

Project overview:
https://github.com/lube8163-lab/mim-ios

## Repository role and build preparation

This repository contains the public iOS client. [mim-ios](https://github.com/lube8163-lab/mim-ios) hosts support and legal pages; [SemanticCompression-v2-public](https://github.com/lube8163-lab/SemanticCompression-v2-public) is an archived predecessor. Backend implementation is maintained privately.

Use Xcode with the iOS 27.0.1 SDK and restore the required, pinned safety classifier before building:

```sh
python3 scripts/restore_safety_model.py
open SemanticCompression-v2.xcodeproj
```

The script verifies all classifier file sizes and SHA-256 values against `docs/image-safety-assets.json`. The image pipeline withholds results when the classifier is missing or invalid. Generation and understanding model weights remain outside Git and use the existing in-app download flow. License texts and provenance are retained under `licenses/`, the client resources and each vendored package.

Offline source checks:

```sh
swift test
python3 scripts/check_localization_coverage.py
python3 scripts/check_xcstrings_sync.py
```

`PUBLIC_EXPORT.json` inventories the reviewed client files. It does not assert a new App Store release or a production backend deployment.

## Current app: architecture and measured performance (2026-10-11)

This section describes **Mim 2.0.0 (build 39), submitted for App Store review on 2026-10-11**. The public client source was refreshed on 2026-10-18 from the current Mac development tree. It includes changes after build 39 and is not claimed to be the exact source used for that App Store archive. Backend implementation, credentials and operational state are excluded.

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

## Current Features

- Timeline, following feed, my posts, and liked posts
- Home side-swipe menu and a floating compose button; flat post rows with consistent author, text, media and action alignment
- Email OTP sign-in, guest mode, logout, and account deletion
- Public profiles, follow / unfollow, block management, and profile editing
- Post details, threaded comments, report flow, and notification inbox
- Post deletion for your own posts from feed and detail views
- In-app model management for image understanding and image generation
- CoreAI reconstruction with FLUX.2 Klein 4B at 512px and four steps; old Core ML recipes remain compatible
- CoreAI photo understanding with LFM2.5-VL-450M and Apple Foundation Models as the fallback; model comparison controls are available only in a diagnostic DEBUG launch
- Photo posts submit without waiting for understanding or reconstruction; a durable on-device queue publishes the preparation result afterward
- Per-context generation prioritization for visible feeds, profiles, and post detail
- Regeneration controls for visible posts and single-post detail views
- First-launch onboarding and legal consent flow
- Per-post image-understanding backend labels shown in feed and detail views
- Japanese, English, Korean, Spanish, Brazilian Portuguese, Simplified Chinese, and Traditional Chinese support across major flows

## Model Notes

- The current target is the iPhone app `SemanticCompression-v2` on iOS 27.0.1 or later, not an Apple Watch app. FLUX requires a supported physical device with at least 8 GB RAM.
- Apple Foundation Models is the implemented fallback and a diagnostic comparison baseline. Its physical-device path requires an eligible iPhone with at least 8 GB RAM and Apple Intelligence availability.
- Reconstruction requires verified model assets. Photo posts require the server's `backgroundPhotoPosts` capability and publish a pending placeholder before analysis. Source photos stay in the app's private container, and only text and recipe metadata are uploaded. A preview is optional and available only for diagnostic comparisons.
- CoreAI understanding runs on physical iOS 27.0.1+ devices using a pinned INT8 decoder and FP16 vision tower. Settings downloads the 554 MB package from Cloudflare R2; the installer resumes across three files, verifies the combined archive and every model file, and installs atomically. Model weights remain outside Git. The package includes the LFM Open License v1.0 and attribution.
- Understanding uses AFM while CoreAI is unavailable or fails; cancellation does not start fallback. The small VLM can misclassify shapes or omit details, so its output is not an exact reconstruction guarantee. Invalid or incomplete scene responses fail into AFM. The runtime is released after analysis so image generation can use the memory.
- CoreAI understanding verifies full model hashes once per unchanged file inventory in each process. Preparation and inference durations are recorded separately. Images retain their aspect ratio inside the 512px vision input; the 750-token structured output budget is retained. Shortening the schema instruction broke structured outputs in the iPhone 17 check and was not adopted.
- New posts use FLUX.2 Klein 4B with the derived 512px-only main function and preserved 4-bit weights, four discrete-flow steps, and guidance 1. The R2 package is 3.54 GB across 18 resumable fragments; the combined archive hash and 17 pinned file hashes are checked before atomic installation. Installed assets use about 4.04 GB, and initial preparation needs about 8 GB free storage. Weights remain outside Git. The earlier unsplit assets failed on iPhone; the derived assets passed subsequent physical-device checks.
- FLUX prompts combine the VLM generation paragraph with subject counts, placement, relations, colors, background, lighting and medium. They use the model's Qwen tokenizer, reject inputs over 512 tokens, and do not use the old SD 77-token limit. The bundled model manifest lets photo posting proceed without downloading the image generator. Legacy SD prompts retain their CLIP budget and path compatibility without changing their serialized digests.
- A submitted photo receives priority at a FLUX step boundary or after text preparation. CPU checkpoint state preserves the exact recipe and viewer seed while the heavy models unload, the VLM analyzes the photo, and generation resumes. Tokenizer and recent text conditions are cached on CPU; GPU models unload between stages. Cancellation, app backgrounding and memory warnings discard retained generation state.
- The bundled ImageSafetyClassifier S checks the input before understanding, and generated images before renderer return and cache reuse. Non-square inputs use both whole-frame and center views; a blocked, missing or invalid result is withheld. Classification includes NSFW and NSFL. Decision-boundary tests and benign physical-device fixtures pass; detection accuracy on an unsafe-image validation set has not been measured. Model provenance and licenses are in `docs/image-safety-assets.json` and `Resources/ImageSafetyNotices.txt`.
- Photo preparation runs at utility priority while the app is active; leaving the app cancels GPU analysis and unfinished jobs resume on return. Source encoding runs off the UI thread. Prompt display is off by default and can be enabled under Settings → Image display; model-free viewers see the photo description.
- Comparison JSON v2 separates model/runtime identity, raw and edited prompts, and understanding/generation measurements. Unmeasured peak memory remains null.
- OTP verification now uses challenge-based verification between start / verify requests.
- New recipe-v2 posts share prompt, model manifest, resolution, scheduler and generation settings, with `seedPolicy: viewerRandom` and no seed. Each client keeps a random seed per post locally; explicit regeneration replaces it. Local cache identity includes that seed. Legacy recipe-v1 posts retain their published seed.
- Provider/model changes invalidate the composer preview; understanding-provider changes also invalidate the extracted scene.
- Watch LCM experiments are a separate project and are not MiM targets, resources or model choices. Old SD1.5 LCM conversion scripts are historical tooling, not the current MiM build workflow.
- The 2026-10-06 iPhone 17 smoke check completed AFM understanding and two real SD1.5 Core ML renders (512px, 25 steps) with different local seeds. Shared recipe-v2 JSON omitted the seed, local seed persistence and separate cache keys passed. This is a functional check; broad image quality and peak memory are not validated.
- After updating to iOS 27.0.1, the app downloaded and verified the new R2 package, ran CoreAI understanding, then completed two Core ML renders with different local seeds. The graphic test preserved the subjects and left/right placement but called the square a rectangle. The app also recognized two versus one apple in synthetic photographs, and the structured AFM fallback service completed the same three cases on iOS 27.0.1. This is a limited functional check, not broad VLM accuracy validation.
- Some compiled Core ML decoders omit their output shape. Asset validation checks both latent input shapes; declared output shapes must match, and the renderer always checks the generated image dimensions.

## Posting and UI Notes

- Photo jobs persist across interruption and use a stable client post ID. The server checks ownership, idempotency and recipe immutability when accepting preparation results. Failed jobs retain their source photo for retry; completed jobs remove it after acknowledgement.
- Analysis runs after the composer closes. This build pauses GPU work when iOS backgrounds the app and resumes on return; it does not guarantee inference while the phone is locked. Network work uses a finite UIKit background assertion.
- The 2026-10-07 production Worker advertises `backgroundPhotoPosts: true`. Cleanup removed 252 posts without recipes and their dependent/orphan rows, preserving the existing recipe-v2 post. Account, authentication and follow data were preserved.
- The R2 download catalog lists LFM2.5-VL-450M and FLUX.2 Klein 4B. Fragmented files are parts of one archive for each model, required for combined digest verification. Older weight objects remain outside the active catalog for rollback and old recipes.
- UI research and implementation criteria are recorded in [ui-ux-reference.json](docs/ui-ux-reference.json), using official X/Threads material, Apple layout guidance and coding-agent design research. The renewed model assessment is in [generation-model-review.json](docs/generation-model-review.json).
- `server/` contains the public recipe contract, tests, model catalog and per-device APNs routing helper. `apply-push-routing.mjs` applies that helper to a locally saved Worker module and refuses changed or already patched anchors. The production Worker's implementation and deployment configuration stay outside this public checkout; files committed to a public GitHub repository cannot be hidden from its readers.

## Localization Workflow

- `SemanticCompression-v2/Localizable.xcstrings` is the localization source of truth.
- Generated `*.lproj/Localizable.strings` files are kept in sync with:
  - `python3 /Users/tasuku/Desktop/SemanticCompression-v2/scripts/sync_localizations.py`
- Full notes are in `LOCALIZATION.md`.

## Notifications

- Push notifications are supported through APNs and the Cloudflare Worker backend.
- The signed provisioning profile determines the APNs environment, including development-signed Release builds installed by Xcode. TestFlight and App Store builds use production APNs.
- Registration includes that environment and the selected app language. The Worker routes each device separately; legacy registrations retain the existing Worker environment.
- Like and reply notifications open their post; follow notifications open the actor's profile. Post and profile destinations share a sheet so a follow can replace an already open post.
- Notification delegate completion handlers return on the main actor, including when a background notification opens the app.
- Logout unregisters the device before clearing authentication tokens.

## Moderation Notes

- Reporting a post hides it for the reporting viewer only.
- Reported posts remain visible to other viewers unless they also report the same post or a separate moderation action is taken on the backend.

## Build Notes

Build the `SemanticCompression-v2` scheme for iPhoneOS or iPhoneSimulator.
New photo recipes use recipe-v2, `mim-coreai-flux2-t2i-v1` and `scene-en-flux2-v1`. The app also accepts legacy recipe-v1/v2 DPM-Solver and Sana trigflow settings; it does not load Watch LCM assets.
Retained LCM conversion material is labeled historical and must not be used as the current app preparation procedure.

A DEBUG launch with `--mim-device-smoke` runs the preferred understanding provider and SD1.5 seed-variation checks. It requires installed SD1.5 assets, skips account restoration and push configuration, and saves JSON plus test PNGs to `Documents/MimDeviceSmoke`. Add `--mim-vlm-download` to prepare and verify the R2 VLM package and use `MimDeviceSmokeCoreAI`; add `--mim-afm-baseline` to check AFM directly in `MimDeviceSmokeAFM`. `--mim-understanding-only` skips image generation. Optional synthetic fixtures named `two-apples.png` and `one-apple.png` in `Documents/MimVLMTestImages` are analyzed alongside the graphic. Diagnostic runtime selectors and comparison exports require `--mim-model-comparison`.

A DEBUG launch with `--mim-ui-review` uses synthetic offline feed fixtures and skips account restoration, push setup and model inference. `--mim-ui-review-screen` accepts `compose`, `menu`, `profile`, `models`, `settings`, `notifications`, or the three `onboarding-*` steps. Add `--mim-ui-review-photo` for a photo-only compose check; the bundled `OnboardingPhoto` fixture is available without a device file transfer. Review mode does not authorize publishing fixture data or persisting legal consent.

A DEBUG launch with `--mim-live-validation` uses the normal account, live feed and APNs flow, recording token-free events under `Documents/MimSocialValidation`. An additional `--mim-use-validation-session` imports a private `session.json` only for an unauthenticated guest and a `mim-validation-` account; an existing account is retained. Credential fixtures and UI-test runner resources stay outside this checkout. Release builds exclude these diagnostics.

`Tests/DeviceUI/SocialLiveUITests.swift` checks live feed scrolling, drawer restoration and real like, follow and reply notifications. Run it in a temporary UI-test target with a private `social-test-config.json` resource containing the controlled actor session and recipient/post IDs. The optional `commentText` keeps the test reply relevant to its post. Never include that credential resource in a public checkout or distribution build.

For the separate synthetic iPhone check, combine `--mim-ui-review --mim-refinement-check`. It records CoreAI scene extraction, token-bounded prompts, SD seed comparisons, image-safety overhead, sampled memory and a main-actor timer responsiveness proxy in `Documents/MimRefinementCheck`. `--mim-refinement-vision-only` skips generation, and `--mim-refinement-catalog-only` checks installed versus bundled asset identities. These are explicit DEBUG diagnostics, not the normal posting workflow.

Combine `--mim-ui-review --mim-flux-adoption-check` for the offline physical-device check through the app's installer, VLM, recipe and FLUX renderer. It records download resume, pinned asset verification, source understanding, safe generation, mid-step VLM priority, identical output after checkpoint resume and viewer-seed variation under `Documents/MimFluxAdoption`. `--mim-flux-interrupt-download` verifies cancellation with partial bytes retained; `--mim-flux-download-only` skips inference. No accounts or posts are used. See [adoption evidence](work/flux-adoption-2026-10-11/README.md).

The local `Vendor/MimCoreAIRuntime` and `Vendor/MimCoreAIFlux` packages preserve upstream licenses. CoreAI inference is unavailable on Simulator. Runtime license notices are also bundled in the app's License screen. The direct swift-transformers dependency is pinned to revision `91286f231bffb9d01998c7e99a8cc760b9e41546`.

## License

MiM's original code is licensed under the Apache License 2.0. Vendored runtimes and downloaded model assets retain their own licenses.
See `LICENSE` for details.
