#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import torch
from diffusers import LCMScheduler, StableDiffusionPipeline
from transformers import CLIPTokenizer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge SD1.5 and LCM LoRA into a fused Hugging Face diffusion model directory."
    )
    parser.add_argument(
        "--base-model",
        required=True,
        help="Base SD1.5 model id or local path (example: runwayml/stable-diffusion-v1-5).",
    )
    parser.add_argument(
        "--lora-model",
        required=True,
        help="LCM LoRA model id or local path (example: latent-consistency/lcm-lora-sdv1-5).",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory for merged model output.",
    )
    parser.add_argument(
        "--lora-scale",
        type=float,
        default=1.0,
        help="LoRA scale when fusing LCM weights.",
    )
    parser.add_argument(
        "--dtype",
        choices=["float16", "float32"],
        default="float16",
        help="Torch dtype used while loading and saving.",
    )
    return parser.parse_args()


def ensure_optional_dependencies() -> None:
    try:
        import peft  # noqa: F401
    except Exception as exc:
        raise RuntimeError(
            "Missing dependency 'peft'. Install with: python3 -m pip install peft>=0.10"
        ) from exc


def main() -> None:
    args = parse_args()
    ensure_optional_dependencies()

    out_dir = Path(args.output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    dtype = torch.float16 if args.dtype == "float16" else torch.float32

    pipe = StableDiffusionPipeline.from_pretrained(
        args.base_model,
        torch_dtype=dtype,
        safety_checker=None,
        requires_safety_checker=False,
    )

    # Keep tokenizer in "slow" format (vocab.json / merges.txt) to avoid
    # tokenizers ABI/version mismatches between merge and conversion environments.
    pipe.tokenizer = CLIPTokenizer.from_pretrained(
        args.base_model,
        subfolder="tokenizer",
    )

    pipe.load_lora_weights(args.lora_model)
    pipe.fuse_lora(lora_scale=args.lora_scale)
    pipe.unload_lora_weights()

    # Ensure scheduler config is LCM-ready before Core ML conversion.
    pipe.scheduler = LCMScheduler.from_config(pipe.scheduler.config)

    pipe.save_pretrained(out_dir, safe_serialization=True)
    pipe.tokenizer.save_pretrained(out_dir / "tokenizer")

    metadata = {
        "base_model": args.base_model,
        "lora_model": args.lora_model,
        "lora_scale": args.lora_scale,
        "dtype": args.dtype,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    (out_dir / "lcm_merge_metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=True, indent=2),
        encoding="utf-8",
    )

    print(f"[ok] merged model exported to: {out_dir}")


if __name__ == "__main__":
    main()
