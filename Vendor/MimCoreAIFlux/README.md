# MiM CoreAI FLUX runtime

This local Swift package adapts Apple's CoreAI diffusion runtime under the included BSD 3-Clause license. The upstream baseline is `97a14be40bb1c5b95badb08b8532530443d62d26`; it was brought into MiM from the physically tested runtime in `work/iphone17-vlm-flux-2026-10-11/Runtime`. Original source headers and license terms are preserved. The app bundles the same Apple license in `CoreAIRuntimeNotices.txt`.

MiM changes:

- Load the derived single-function 512px transformer without preloading a larger entrypoint.
- Unload the heavy transformer, text encoder and VAE between stages and after use.
- Reuse tokenizer/metadata and up to three text-conditioning entries on CPU.
- Save a one-use CPU checkpoint at diffusion boundaries or after text preparation, then resume the same configuration and random state after photo analysis.
- Reject overlong Qwen prompts rather than silently truncating them.
- Compile the runtime only where CoreAI is available outside Simulator; Simulator remains usable for the app's UI.

The direct app dependency pins swift-transformers to `91286f231bffb9d01998c7e99a8cc760b9e41546`. This package contains runtime source only. Downloaded weights and per-file pinned hashes are managed by `CoreAIFluxAssets` and the model installer.

Original model: https://huggingface.co/black-forest-labs/FLUX.2-klein-4B

Converted source: https://huggingface.co/dushandz/FLUX.2-klein-4B-CoreAI/tree/a7f65cdd6b2c8e2616dab3887efd0ae6ce983e44

The 512px asset is a derivative of that converted source with its half function extracted as main; weights stay 4-bit. This is not a new official iOS export. See `work/flux-adoption-2026-10-11/README.md` for distribution and physical-device evidence.
