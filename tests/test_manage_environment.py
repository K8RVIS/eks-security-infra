import copy
import importlib.util
import pathlib
import unittest


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "manage_environment.py"


def load_module():
    spec = importlib.util.spec_from_file_location("manage_environment", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeStateStore:
    def __init__(self, initial_state):
        self.state = copy.deepcopy(initial_state)
        self.writes = []

    def read_state(self):
        return copy.deepcopy(self.state)

    def write_state(self, state):
        snapshot = copy.deepcopy(state)
        self.writes.append(snapshot)
        self.state = snapshot


class RecordingTerraformRunner:
    def __init__(self, fail_on=None):
        self.fail_on = fail_on
        self.calls = []

    def apply_infra(self):
        self.calls.append(("apply_infra", None))
        if self.fail_on == "apply_infra":
            raise RuntimeError("infra apply failed")

    def apply_platform(self, namespaces):
        self.calls.append(("apply_platform", list(namespaces)))
        if self.fail_on == "apply_platform":
            raise RuntimeError("platform apply failed")

    def destroy_platform(self):
        self.calls.append(("destroy_platform", None))
        if self.fail_on == "destroy_platform":
            raise RuntimeError("platform destroy failed")

    def destroy_infra(self):
        self.calls.append(("destroy_infra", None))
        if self.fail_on == "destroy_infra":
            raise RuntimeError("infra destroy failed")


class OrchestratorTests(unittest.TestCase):
    def test_first_start_applies_infra_then_platform_and_records_state(self):
        module = load_module()
        state_store = FakeStateStore(module.default_state())
        terraform_runner = RecordingTerraformRunner()
        orchestrator = module.EnvironmentOrchestrator(state_store=state_store, terraform_runner=terraform_runner)

        result = orchestrator.run(
            operation="start",
            slack_user_id="U123",
            namespace="team-a",
            request_id="req-1",
        )

        self.assertEqual(terraform_runner.calls, [("apply_infra", None), ("apply_platform", ["team-a"])])
        self.assertEqual(result["infra_status"], "running")
        self.assertEqual(result["active_users"], {"U123": "team-a"})
        self.assertEqual(result["active_namespaces"], ["team-a"])
        self.assertEqual(state_store.writes[0]["pending_operation"]["operation"], "start")
        self.assertIsNone(state_store.writes[-1]["pending_operation"])

    def test_second_start_only_expands_platform_namespaces(self):
        module = load_module()
        initial_state = module.default_state()
        initial_state.update(
            {
                "infra_status": "running",
                "active_users": {"U123": "team-a"},
                "active_namespaces": ["team-a"],
            }
        )
        state_store = FakeStateStore(initial_state)
        terraform_runner = RecordingTerraformRunner()
        orchestrator = module.EnvironmentOrchestrator(state_store=state_store, terraform_runner=terraform_runner)

        result = orchestrator.run(
            operation="start",
            slack_user_id="U456",
            namespace="team-b",
            request_id="req-2",
        )

        self.assertEqual(terraform_runner.calls, [("apply_platform", ["team-a", "team-b"])])
        self.assertEqual(result["active_users"], {"U123": "team-a", "U456": "team-b"})
        self.assertEqual(result["active_namespaces"], ["team-a", "team-b"])

    def test_stop_with_remaining_users_reapplies_platform_subset(self):
        module = load_module()
        initial_state = module.default_state()
        initial_state.update(
            {
                "infra_status": "running",
                "active_users": {"U123": "team-a", "U456": "team-b"},
                "active_namespaces": ["team-a", "team-b"],
            }
        )
        state_store = FakeStateStore(initial_state)
        terraform_runner = RecordingTerraformRunner()
        orchestrator = module.EnvironmentOrchestrator(state_store=state_store, terraform_runner=terraform_runner)

        result = orchestrator.run(
            operation="stop",
            slack_user_id="U123",
            namespace="team-a",
            request_id="req-3",
        )

        self.assertEqual(terraform_runner.calls, [("apply_platform", ["team-b"])])
        self.assertEqual(result["infra_status"], "running")
        self.assertEqual(result["active_users"], {"U456": "team-b"})
        self.assertEqual(result["active_namespaces"], ["team-b"])

    def test_last_stop_destroys_platform_then_infra(self):
        module = load_module()
        initial_state = module.default_state()
        initial_state.update(
            {
                "infra_status": "running",
                "active_users": {"U123": "team-a"},
                "active_namespaces": ["team-a"],
            }
        )
        state_store = FakeStateStore(initial_state)
        terraform_runner = RecordingTerraformRunner()
        orchestrator = module.EnvironmentOrchestrator(state_store=state_store, terraform_runner=terraform_runner)

        result = orchestrator.run(
            operation="stop",
            slack_user_id="U123",
            namespace="team-a",
            request_id="req-4",
        )

        self.assertEqual(terraform_runner.calls, [("destroy_platform", None), ("destroy_infra", None)])
        self.assertEqual(result["infra_status"], "stopped")
        self.assertEqual(result["active_users"], {})
        self.assertEqual(result["active_namespaces"], [])

    def test_failure_keeps_last_success_state_and_records_last_error(self):
        module = load_module()
        initial_state = module.default_state()
        initial_state.update(
            {
                "infra_status": "running",
                "active_users": {"U123": "team-a"},
                "active_namespaces": ["team-a"],
            }
        )
        state_store = FakeStateStore(initial_state)
        terraform_runner = RecordingTerraformRunner(fail_on="apply_platform")
        orchestrator = module.EnvironmentOrchestrator(state_store=state_store, terraform_runner=terraform_runner)

        with self.assertRaisesRegex(RuntimeError, "platform apply failed"):
            orchestrator.run(
                operation="start",
                slack_user_id="U456",
                namespace="team-b",
                request_id="req-5",
            )

        self.assertEqual(state_store.state["active_users"], {"U123": "team-a"})
        self.assertEqual(state_store.state["active_namespaces"], ["team-a"])
        self.assertIsNone(state_store.state["pending_operation"])
        self.assertEqual(state_store.state["last_error"]["request_id"], "req-5")
        self.assertIn("platform apply failed", state_store.state["last_error"]["message"])


if __name__ == "__main__":
    unittest.main()
