import pathlib
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
K8S_BASE_MAIN = PROJECT_ROOT / "modules" / "k8s-base" / "main.tf"


class K8sBaseModuleTests(unittest.TestCase):
    def test_webhook_sensitive_addons_wait_for_aws_load_balancer_controller(self):
        main_tf = K8S_BASE_MAIN.read_text()

        self.assertGreaterEqual(
            main_tf.count("helm_release.aws_load_balancer_controller"),
            2,
            "ingress-nginx and external-secrets must wait for the AWS Load Balancer Controller webhook endpoints.",
        )
        self.assertIn('resource "helm_release" "ingress_nginx"', main_tf)
        self.assertIn('resource "helm_release" "external_secrets"', main_tf)
        self.assertIn("depends_on = [helm_release.aws_load_balancer_controller]", main_tf)

    def test_encrypted_gp3_storage_class_is_declared(self):
        main_tf = K8S_BASE_MAIN.read_text()

        self.assertIn('kubernetes_storage_class_v1" "encrypted_gp3"', main_tf)
        self.assertIn('metadata {', main_tf)
        self.assertIn('name = "encrypted-gp3"', main_tf)
        self.assertIn('storage_provisioner = "ebs.csi.aws.com"', main_tf)
        self.assertIn('reclaim_policy      = "Delete"', main_tf)
        self.assertIn('volume_binding_mode = "WaitForFirstConsumer"', main_tf)
        self.assertIn('type      = "gp3"', main_tf)
        self.assertIn('encrypted = "true"', main_tf)


if __name__ == "__main__":
    unittest.main()
