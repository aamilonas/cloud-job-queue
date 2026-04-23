"""Submit a job via the HTTP API (base64-encodes an image and POSTs it).

Usage:
    py submit_via_api.py path/to/image.jpg

Reads the API endpoint from Terraform outputs.
"""
import base64
import json
import subprocess
import sys
import urllib.request
from pathlib import Path


def get_terraform_outputs() -> dict:
    tf_dir = Path(__file__).parent.parent / "terraform"
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=tf_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    raw = json.loads(result.stdout)
    return {k: v["value"] for k, v in raw.items()}


def main():
    if len(sys.argv) != 2:
        print("Usage: py submit_via_api.py path/to/image.jpg")
        sys.exit(1)

    image_path = Path(sys.argv[1])
    if not image_path.is_file():
        print(f"Not a file: {image_path}")
        sys.exit(1)

    outputs = get_terraform_outputs()
    api_endpoint = outputs["api_endpoint"]
    submit_url = f"{api_endpoint}/jobs"

    print(f"API: {submit_url}")
    print(f"Uploading: {image_path}")

    image_bytes = image_path.read_bytes()
    payload = json.dumps(
        {
            "imageBase64": base64.b64encode(image_bytes).decode("ascii"),
            "filename": image_path.name,
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        submit_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            print(f"HTTP {resp.status}: {body}")

            data = json.loads(body)
            job_id = data.get("jobId")
            if job_id:
                print(f"\n✓ Submitted. jobId={job_id}")
                print(f"\nCheck status:")
                print(f"  curl {api_endpoint}/jobs/{job_id}")
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
        sys.exit(1)


if __name__ == "__main__":
    main()
