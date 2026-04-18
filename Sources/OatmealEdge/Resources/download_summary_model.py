import argparse
import json
import os

from huggingface_hub import snapshot_download


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    snapshot_download(
        repo_id=args.repo_id,
        local_dir=args.output_dir,
        force_download=args.force,
    )

    print(
        json.dumps(
            {
                "repo_id": args.repo_id,
                "output_dir": args.output_dir,
                "force": args.force,
            }
        )
    )


if __name__ == "__main__":
    main()
