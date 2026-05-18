import pathlib
import re
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
EKS_MAIN = PROJECT_ROOT / "modules" / "eks" / "main.tf"
EKS_OUTPUTS = PROJECT_ROOT / "modules" / "eks" / "outputs.tf"


class KubeletApiSecurityTests(unittest.TestCase):
    def test_managed_nodes_use_dedicated_security_group(self):
        content = EKS_MAIN.read_text()

        self.assertIn('resource "aws_security_group" "node"', content)
        self.assertIn("vpc_security_group_ids = [aws_security_group.node.id]", content)

    def test_kubelet_https_api_is_only_allowed_from_cluster_security_group(self):
        content = EKS_MAIN.read_text()
        kubelet_rule = self._resource_block(
            content,
            "aws_security_group_rule",
            "node_kubelet_https_from_cluster",
        )

        self.assertIn("from_port                = 10250", kubelet_rule)
        self.assertIn("to_port                  = 10250", kubelet_rule)
        self.assertIn(
            "security_group_id        = aws_security_group.node.id",
            kubelet_rule,
        )
        self.assertIn(
            "source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id",
            kubelet_rule,
        )
        self.assertNotIn("cidr_blocks", kubelet_rule)

    def test_kubelet_read_only_port_is_not_opened(self):
        content = EKS_MAIN.read_text()

        self.assertNotIn("10255", content)

    def test_nodes_can_reach_private_eks_api_without_broad_kubelet_ingress(self):
        content = EKS_MAIN.read_text()
        api_rule = self._resource_block(
            content,
            "aws_security_group_rule",
            "cluster_private_endpoint_from_nodes",
        )

        self.assertIn("from_port                = 443", api_rule)
        self.assertIn("to_port                  = 443", api_rule)
        self.assertIn(
            "security_group_id        = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id",
            api_rule,
        )
        self.assertIn(
            "source_security_group_id = aws_security_group.node.id",
            api_rule,
        )
        self.assertNotIn("cidr_blocks", api_rule)

    def test_node_security_group_id_is_exposed_for_audit(self):
        content = EKS_OUTPUTS.read_text()

        self.assertIn('output "node_security_group_id"', content)
        self.assertIn("value       = aws_security_group.node.id", content)

    def _resource_block(self, content, resource_type, resource_name):
        pattern = (
            rf'resource "{resource_type}" "{resource_name}" \{{'
            rf".*?\n\}}"
        )
        match = re.search(pattern, content, re.DOTALL)
        self.assertIsNotNone(
            match,
            f"Missing resource {resource_type}.{resource_name}",
        )
        return match.group(0)


if __name__ == "__main__":
    unittest.main()
