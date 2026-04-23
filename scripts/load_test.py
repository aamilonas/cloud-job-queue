"""Submit N jobs in parallel via the HTTP API to trigger auto-scaling.

Usage:
    py load_test.py path/to/image.jpg [count]

Default count is 25 jobs, which should trigger the scale-up all the way
to the max (5 workers).
"""
import base64
import json
import subprocess
import sys
import threading
import time
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


def submit_one(submit_url: str, payload: bytes, results: list, idx: int):
    req = urllib.request.Request(
        submit_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            results[idx] = body.get("jobId")
    except Exception as e:
        results[idx] = f"ERROR: {e}"


def main():
    if len(sys.argv) < 2:
        print("Usage: py load_test.py path/to/image.jpg [count]")
        sys.exit(1)

    image_path = Path(sys.argv[1])
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 25

    if not image_path.is_file():
        print(f"Not a file: {image_path}")
        sys.exit(1)

    outputs = get_terraform_outputs()
    api_endpoint = outputs["api_endpoint"]
    submit_url = f"{api_endpoint}/jobs"

    print(f"API: {submit_url}")
    print(f"Submitting {count} jobs...")
    print()

    image_bytes = image_path.read_bytes()
    payload = json.dumps(
        {
            "imageBase64": base64.b64encode(image_bytes).decode("ascii"),
            "filename": image_path.name,
        }
    ).encode("utf-8")

    results = [None] * count
    threads = []
    start = time.time()

    for i in range(count):
        t = threading.Thread(target=submit_one, args=(submit_url, payload, results, i))
        t.start()
        threads.append(t)
        # Small stagger to avoid Lambda cold-start pileup (real users don't
        # submit 25 things at the exact same millisecond anyway)
        time.sleep(0.2)

    for t in threads:
        t.join()

    elapsed = time.time() - start
    successes = sum(1 for r in results if r and not str(r).startswith("ERROR"))
    failures = count - successes

    print(f"Submitted {successes}/{count} jobs in {elapsed:.1f}s")
    if failures:
        print(f"Failures: {failures}")
        for r in results:
            if r and str(r).startswith("ERROR"):
                print(f"  {r}")

    print()
    print("Watch the scale-up:")
    print(f"  curl.exe {api_endpoint}/metrics")
    print()
    print("Or in a loop:")
    print(f"  while ($true) {{ curl.exe -s {api_endpoint}/metrics; echo ''; sleep 5 }}")


if __name__ == "__main__":
    main()