# Trajectory + Monte Carlo benchmark

Generated 2026-11-22 01:44. Times are per decision (6 targets).

## Part 1: trajectory solver (solve only)

Accuracy = re-fly each solution with the reference integrator (RK4, dt 1/4000), worst case over all scenarios.

| Config | Solve (ms) | Flights / solve | Landing err (cm) | Net height err (cm) | Apex err (cm) | Flight time err (ms) | Availability mismatches |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A prototype: euler 1/240 + bisection | 34.28 | 302 | 27.2 | 6.7 | 15.2 | 33.8 | 0 |
| B euler 1/240 + illinois | 5.69 | 47 | 27.3 | 6.7 | 15.2 | 33.8 | 0 |
| C euler 1/240 + illinois + warm start | 3.85 | 32 | 27.3 | 6.7 | 15.2 | 33.9 | 0 |
| D rk2 1/120 + illinois + warm start | 2.78 | 31 | 0.5 | 0.1 | 0.3 | 0.9 | 0 |
| E rk2 1/60 + illinois + warm start | 1.45 | 30 | 2.8 | 0.3 | 1.4 | 4.0 | 0 |
| F rk2 1/30 + illinois + warm start | 0.74 | 30 | 13.1 | 1.5 | 6.3 | 18.0 | 0 |

## Part 2: Monte Carlo (solve + probabilities, trajectory config E)

Ground truth = fine integrator (rk2 1/480), 4096 quasi-random samples, every sample flown.
Error = worst absolute difference in any of success / net / long / wide, in percentage points.

| Method | Decision (ms) | Speedup vs M1 | Flights / target | Max err, skilled (pp) | Max err, rookie (pp) | Mean success err (pp) |
| --- | --- | --- | --- | --- | --- | --- |
| M1 full, random 150 (previous) | 6.98 | 1.0x | 159 | 3.1 | 6.3 | 1.48 |
| M2 full, halton 150 | 7.03 | 1.0x | 159 | 3.8 | 4.5 | 1.05 |
| M3 full, halton 64 | 3.90 | 1.8x | 85 | 4.3 | 3.7 | 1.47 |
| M4 surrogate, halton 64 | 1.81 | 3.9x | 35 | 4.3 | 4.3 | 1.38 |
| M5 surrogate, halton 256 | 1.96 | 3.6x | 35 | 3.1 | 2.0 | 0.70 |
| M6 surrogate, halton 1024 | 2.62 | 2.7x | 35 | 2.3 | 1.5 | 0.39 |

## Shot outputs (ground truth)

| Scenario | Dist (m) | Angle | Speed (m/s) | Flight (s) | Over net (m) | Apex (m) | Descent | Skilled success % | Rookie net / long / wide % | Rookie success % |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Straight clear | 11.6 | +37.2 deg | 43.8 | 2.24 | +4.96 | 7.00 | 83 deg | 99.3 | 0.0 / 1.5 / 14.2 | 84.3 |
| Cross clear | 12.2 | +35.4 deg | 48.4 | 2.23 | +4.93 | 7.00 | 83 deg | 99.2 | 0.0 / 2.5 / 14.8 | 82.7 |
| Straight drop | 7.3 | +7.6 deg | 17.1 | 1.08 | +0.25 | 2.78 | 61 deg | 92.7 | 30.1 / 0.0 / 3.4 | 66.6 |
| Cross drop | 8.2 | +5.3 deg | 21.8 | 1.06 | +0.25 | 2.74 | 59 deg | 91.4 | 31.7 / 0.0 / 4.8 | 63.6 |
| Straight smash | 9.4 | -7.3 deg | 45.0 | 0.69 | +0.08 | 2.60 | 39 deg | 77.6 | 39.1 / 0.0 / 6.3 | 54.5 |
| Cross smash | 10.1 | -4.0 deg | 45.0 | 0.82 | +0.33 | 2.60 | 44 deg | 99.6 | 13.5 / 0.0 / 10.3 | 76.2 |
| Late smash | 9.4 | unavailable: can't clear the net | | | | | | | | |
| Straight lift | 7.3 | +55.9 deg | 26.4 | 2.08 | +1.19 | 5.50 | 82 deg | 100.0 | 0.0 / 2.1 / 4.6 | 93.3 |
| Cross lift | 8.2 | +51.9 deg | 29.3 | 2.07 | +1.13 | 5.50 | 82 deg | 100.0 | 0.0 / 2.4 / 6.1 | 91.5 |
| Straight net | 3.0 | +51.3 deg | 7.0 | 1.07 | +0.12 | 1.67 | 70 deg | 95.1 | 27.2 / 0.0 / 0.0 | 72.8 |
| Cross net | 4.8 | +35.4 deg | 10.2 | 1.07 | +0.12 | 1.68 | 62 deg | 95.8 | 27.5 / 0.0 / 1.9 | 70.6 |
| Push | 5.1 | +46.5 deg | 11.8 | 1.34 | +0.40 | 2.48 | 71 deg | 100.0 | 0.0 / 0.0 / 0.9 | 99.1 |
| Drive | 7.2 | unavailable: can't clear the net | | | | | | | | |
| Push clear | 9.4 | +28.8 deg | 26.0 | 1.53 | +1.49 | 3.50 | 72 deg | 99.9 | 0.0 / 1.5 / 9.5 | 89.0 |

Wobble skilled: angle 1.0 deg, direction 1.5 deg, speed 4% (1 sigma).
Wobble rookie: angle 2.5 deg, direction 3.5 deg, speed 10% (1 sigma).
