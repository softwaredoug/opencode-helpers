import unittest

import hello


class HelloTests(unittest.TestCase):
    def test_hello_includes_name(self):
        result = hello.hello("Ada")
        self.assertEqual(result, "hello world Ada")


if __name__ == "__main__":
    unittest.main()
