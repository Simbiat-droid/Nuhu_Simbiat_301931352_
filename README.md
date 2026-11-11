# Advanced Database Portfolio — ReadWell Libraries

**Student:** Nuhu Simbiat  
**Matric number:** 2026/A/MIT/0955  
**Programme:** Master of Information Technology  
**Institution:** Miva Open University  
**Course:** MIT 8103 — Advanced Database Systems  
**Session:** 2026/2027, First Semester Continuous Assessment

**GitHub link:** [GitHub link]

---

## Case study

**ReadWell Libraries** is a simulated public library network with branches in **Lagos (Yaba, Ikeja), Abuja (Garki)** and **Kaduna**. Members borrow physical copies of books, reserve titles that are out of stock, return them (or pay fines if late), and can borrow from any branch. The same case study is used consistently across all five portfolios.

## Repository structure

```
advanced-database-portfolio/
├── docs/
│   └── 00_brief_summary.md            # CA summary + portfolio ↔ study-session map
├── portfolio-1-database-design/       # ER diagram, 3NF, constraints, bulk data (50k+ loans)
├── portfolio-2-query-optimisation/    # 6-8 queries, EXPLAIN ANALYZE before/after indexes
├── portfolio-3-transactions-concurrency/  # borrow_copy() txn, race condition, isolation, deadlock
├── portfolio-4-nosql/                 # MongoDB catalogue, schema validation, 40k+ docs, IXSCAN
├── portfolio-5-distributed-cloud/    # partitioning, streaming replica, NDPA 2023 cloud design
├── setup.sh                           # installs PostgreSQL 16 + MongoDB 8 in Codespaces
├── collect_results.sh                 # gathers all real output into my_results.txt
├── CHANGES.md                         # what was fixed after testing
└── README.md                          # this file
```

## Quick start (Codespaces)

```bash
# 1. One-time environment setup (PostgreSQL 16 + MongoDB 8 + psycopg2)
bash setup.sh

# 2. Run each portfolio in order; each saves its own log and evidence
for N in 1 2 3 4 5; do
  D=$(ls -d portfolio-$N-*)
  (cd "$D" && bash run_p$N.sh 2>&1 | tee p${N}_output.log)
done

# 3. Gather the real results into one file
bash collect_results.sh && code my_results.txt
```

Evidence each runner saves in its folder: `p1_output.log`;
`p2_output.log`, `explain_before.txt`, `explain_after.txt`, `p2_timing_summary.md`;
`p3_output.log`, `race_demos_output.log`; `p4_output.log`;
`p5_output.log`, `replication_output.log`. `CHANGES.md` lists every fix made
after testing.

All PostgreSQL commands connect through the Unix socket (`host=/var/run/postgresql`) and run as the `postgres` OS user via `sudo runuser -u postgres -- ...`. Never use `sudo -u postgres`.

## Connecting

| Service | Command |
|---|---|
| PostgreSQL (primary) | `sudo runuser -u postgres -- psql -d readwell` |
| PostgreSQL (replica, after P5 setup) | `sudo runuser -u postgres -- psql -p 5433 -d readwell` |
| MongoDB | `mongosh readwell_catalog` |

## Portfolio → study session map

| Portfolio | Title | Course-note study sessions |
|---|---|---|
| 1 | Database Design and Modelling | Study Session 1 (relational design, normalisation, stages of DB design) |
| 2 | Query Processing and Optimisation | Study Session 4 (query optimisation, execution plans, file organisation) |
| 3 | Transactions and Concurrency | Study Session 1 (ACID, characteristics of a good DB) + Study Session 2 (consistency models, ACID/BASE) |
| 4 | NoSQL and Advanced Data Models | Study Session 1 (NoSQL & types of NoSQL) + Study Session 5 (graph DBs, emerging trends) |
| 5 | Distributed and Cloud Database | Study Session 2 (distributed DB, CAP, replication) + Study Session 3 (cloud DB) + Study Session 6 (data privacy, NDPA 2023) |

## Honesty declaration

- Every file that expects real database output (EXPLAIN plans, psql transcripts, mongosh `explain()` results, replica error messages) is produced by the runner scripts in the student's own Codespace and saved as a log file (listed above); any remaining `[paste real output here]` placeholder points to one of those logs.
- No output, timing, or screenshot has been invented or simulated.
- The final 2–3 page documentation (`Simbiat_Nuhu_Documentation.pdf`, inside the `Simbiat_Nuhu_2026AMIT0955` submission folder) will be produced **after** all scripts have been run and the real outputs captured.

## AI-use declaration

Declared in full in the final documentation PDF. An AI assistant drafted the scripts and documentation structure; the kit was then tested in a Codespaces-like environment and the problems found were fixed (every fix is listed in `CHANGES.md`); the student ran every script in her own Codespace and checked the real output before writing it up.
