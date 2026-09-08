import unittest

from analyze_native import analyze, estimate


class AnalysisTests(unittest.TestCase):
    def rows(self):
        rows = []
        for rep in range(7):
            base = {"phase": "test", "case": "constant", "repetition": rep, "strategy": "vectored",
                    "seed": rep, "layer": "runtime", "pages": None, "writers": 1, "durable": False,
                    "file_bytes": 4096, "bytes_per_write": 4096, "source_count": 1,
                    "mib_per_second": 10 + rep, "cpu_ns_per_op": 1000 + rep}
            rows += [base, {**base, "strategy": "pool", "mib_per_second": base["mib_per_second"] * 2,
                            "cpu_ns_per_op": base["cpu_ns_per_op"] / 2}]
        return rows

    def test_ratio_direction_and_constant_interval(self):
        result = analyze(self.rows())[0]
        self.assertEqual(result["throughput"]["ratio"], 2)
        self.assertEqual(result["throughput"]["ci95"], [2, 2])
        self.assertEqual(result["cpu_cost"]["ratio"], .5)
        self.assertEqual(estimate([.5, 2])["ratio"], 1)

    def test_rejects_incomplete_or_duplicate_pairs(self):
        rows = self.rows()
        with self.assertRaises(ValueError):
            analyze(rows[:-1])
        with self.assertRaises(ValueError):
            analyze(rows + rows[:1])

    def test_rejects_different_workload_in_a_pair(self):
        rows = self.rows()
        rows[1]["bytes_per_write"] *= 2
        with self.assertRaises(ValueError):
            analyze(rows)


if __name__ == "__main__":
    unittest.main()
