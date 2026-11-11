"""Verify approved archive, immutable originals and byte-identical deployed assets."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[1]
brand = root / "docs/brand/quartel-digital-v1"
record = json.loads((brand / "SHA256SUMS.json").read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()
archive = brand / record["archive"]
assert digest(archive.read_bytes()) == record["archive_sha256"], "Archive changed"
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None, "ZIP CRC failure"
    assert set(package.namelist()) == set(record["files"]), "Archive inventory mismatch"
    assert len(record["files"]) == 44, "Expected 44 approved files"
    for name, sha in record["files"].items():
        assert digest(package.read(name)) == sha, name
        assert digest((brand / "originals" / name).read_bytes()) == sha, name
approved = set(record["files"].values())
for asset in (root / "public/assets/brand/quartel-digital-v1").iterdir():
    assert digest(asset.read_bytes()) in approved, str(asset)
assert digest((root / "src/app/favicon.ico").read_bytes()) == record["files"]["03_Favicons/favicon.ico"]
print("PASS: archive CRC, 44 originals, deployed copies and favicon match approved SHA-256 hashes")
