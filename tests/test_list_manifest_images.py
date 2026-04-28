import importlib.util
import pathlib
import tempfile
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "list_manifest_images.py"


def load_module():
    spec = importlib.util.spec_from_file_location("list_manifest_images", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ListManifestImagesTests(unittest.TestCase):
    def test_collects_unique_images_from_yaml_manifests(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            (root / "deployment.yaml").write_text(
                """
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: web
          image: nginx:1.27.5
        - name: api
          image: "ealen/echo-server"
""",
                encoding="utf-8",
            )
            nested = root / "nested"
            nested.mkdir()
            (nested / "statefulset.yml").write_text(
                """
apiVersion: apps/v1
kind: StatefulSet
spec:
  template:
    spec:
      containers:
        - name: db
          image: 'redis:7'
        - name: duplicate
          image: nginx:1.27.5
""",
                encoding="utf-8",
            )

            self.assertEqual(
                module.collect_images([root]),
                ["ealen/echo-server", "nginx:1.27.5", "redis:7"],
            )

    def test_ignores_comments_and_non_yaml_files(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            (root / "notes.txt").write_text("image: ignored:latest\n", encoding="utf-8")
            (root / "pod.yaml").write_text(
                """
# image: comment:latest
containers:
  - name: app
    image: busybox:1.36 # inline comment
""",
                encoding="utf-8",
            )

            self.assertEqual(module.collect_images([root]), ["busybox:1.36"])


if __name__ == "__main__":
    unittest.main()
