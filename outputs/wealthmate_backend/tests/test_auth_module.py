import unittest


class AuthModuleBoundaryTest(unittest.TestCase):
    def test_auth_module_exposes_the_existing_auth_routes(self):
        from app.auth.router import router

        paths = {route.path for route in router.routes}
        self.assertEqual(
            paths,
            {
                "/auth/login",
                "/auth/me",
                "/auth/password",
            },
        )

    def test_auth_service_exposes_auth_use_cases(self):
        from app.auth import service

        for name in (
            "login",
            "get_current_user",
            "update_profile",
            "change_password",
        ):
            self.assertTrue(callable(getattr(service, name)))


if __name__ == "__main__":
    unittest.main()
