# Screenshots / evidence to capture (from YOUR Codespace only)

The runner scripts already save the real output as logs. For the PDF,
evidence images are made from these logs (never typed or simulated):

| # | What | Source file |
|---|---|---|
| 1 | All constraint tests PASS + row counts (64k+ loans) | portfolio-1-database-design/p1_output.log |
| 2 | ER diagram (renders on GitHub) | portfolio-1-database-design/er_diagram.md |
| 3 | Before/after timings table | portfolio-2-query-optimisation/p2_timing_summary.md |
| 4 | One plan before (Seq Scan) and after (Index/Bitmap scan), e.g. Q9 | explain_before.txt / explain_after.txt |
| 5 | Race bug + EXCLUDE + FOR UPDATE fixes | portfolio-3-transactions-concurrency/race_demos_output.log |
| 6 | Deadlock detected (SQLSTATE 40P01) | race_demos_output.log (Part 6) |
| 7 | Validator rejection + COLLSCAN vs IXSCAN table | portfolio-4-nosql/p4_output.log |
| 8 | Partition list + pruning EXPLAIN | portfolio-5-distributed-cloud/p5_output.log |
| 9 | Replica rejects write, row arrives, lag | portfolio-5-distributed-cloud/replication_output.log |
| 10 | GitHub commit history (several commits over time) | GitHub > Commits |
