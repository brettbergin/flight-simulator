"""Download integrity and extraction tests; never use the network."""
import importlib.util
from pathlib import Path
import tempfile, unittest, zipfile
spec = importlib.util.spec_from_file_location("flight_bootstrap",Path(__file__).with_name("bootstrap.py"))
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)
class BootstrapTests(unittest.TestCase):
    def test_unsafe_names(self):
        for name in ("../escape","/absolute","C:/escape","folder\\escape"):
            with self.subTest(name=name), self.assertRaises(ValueError): bootstrap.safe_name(name)
    def test_corrupt_cache_is_not_extracted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache = root/"cache"
            cache.mkdir()
            h = "0"*64
            (cache/(h+".archive")).write_bytes(b"unexpected")
            with self.assertRaisesRegex(ValueError,"checksum mismatch"):
                bootstrap.acquire({"id":"test","version":"1","sha256":h},root/"out",cache,True)
            self.assertFalse((root/"out").exists())
    def test_valid_cache_and_detected_source_tamper(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root/"input.zip"
            with zipfile.ZipFile(archive,"w") as out: out.writestr("probe/data.txt","trusted")
            h = bootstrap.digest(archive)
            cache = root/"cache"
            cache.mkdir()
            archive.rename(cache/(h+".archive"))
            item = {"id":"probe","version":"1","url":"https://example.invalid/source","sha256":h,"archive_root":"probe"}
            dest = root/"out"
            bootstrap.acquire(item,dest,cache,True)
            bootstrap.acquire(item,dest,cache,True)
            (dest/"data.txt").write_text("changed")
            with self.assertRaisesRegex(ValueError,"dependency changed"): bootstrap.acquire(item,dest,cache,True)
    def test_zip_cannot_escape_staging(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            archive=root/"evil.zip"
            with zipfile.ZipFile(archive,"w") as out: out.writestr("../escape.txt","invalid")
            with self.assertRaises(ValueError): bootstrap.extract(archive,root/"stage")
            self.assertFalse((root/"escape.txt").exists())
if __name__ == "__main__": unittest.main()
