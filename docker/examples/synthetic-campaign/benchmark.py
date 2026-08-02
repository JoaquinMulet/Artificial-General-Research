#!/usr/bin/env python3
"""Synthetic campaign benchmark - example for agr-docker.

Contract: the stack runs AGR_BENCH_CMD and parses stdout lines of the form
    key: float
into ref_<key>. AGR_METRIC_KEY selects which one becomes ref_total.

This example sleeps briefly and prints two metrics plus a correctness line.
Replace with your real benchmark; keep the "key: float" stdout contract.
"""
import time


def bench_alpha():
    time.sleep(0.05)
    return 0.05


def bench_beta():
    time.sleep(0.08)
    return 0.08


if __name__ == "__main__":
    a = bench_alpha()
    b = bench_beta()
    print(f"bench_alpha: {a:.6f}")
    print(f"bench_beta: {b:.6f}")
    print(f"total_time_s: {a + b:.6f}")
    print("correctness: PASS")
