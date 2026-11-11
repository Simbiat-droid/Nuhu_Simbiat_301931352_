# 00 — Brief Summary of the CA

**Course:** MIT 8103 Advanced Database Systems · **Marks:** 40 · **Type:** Individual Practical Database Portfolio  
**Student:** Nuhu Simbiat (2026/A/MIT/0955) · **Case study:** ReadWell Libraries (library book lending)

## What the CA requires

- **5 practical portfolios** (7 + 7 + 7 + 7 + 6 = 34 marks) plus a **final documentation** of 2–3 pages (6 marks).
- Each portfolio uses the **same case study consistently** (here: ReadWell Libraries, a simulated public library network with branches in Lagos, Abuja and Kaduna).
- Evidence is practical: SQL scripts, schemas, ER diagrams, NoSQL implementations, execution plans, screenshots, configuration files, README files. Simply pasting screenshots or copied code without understanding earns no marks.
- **Submission:** LMS + GitHub. A **private GitHub repository** named `advanced-database-portfolio/` with one folder per portfolio plus a top-level `README.md`. **Progressive commits** are expected — dumping everything at the deadline reduces the evidence of continuous development.
- **LMS submission:** a 2–3 page documentation describing all five activities, the selected case study, the GitHub link, and supporting screenshots/evidence. The GitHub link must work for the assessor before LMS submission.
- **Page limit:** the documentation is **2–3 pages**.
- **Naming rules:** repository folder structure must follow `advanced-database-portfolio/{portfolio-1..5}/` plus `README.md`. The LMS form wants a folder `Surname_Firstname_StudentID` with no slashes (here `Simbiat_Nuhu_2026AMIT0955`) containing `Simbiat_Nuhu_Documentation.pdf`, plus a separate `Simbiat_Nuhu_README.txt`.
- **Individual work:** general discussion is allowed, but all implementation, scripts, analysis and conclusions must be the student's own.
- **AI use:** permitted as a learning aid, but must be declared — tool used, what it was used for, and how the output was reviewed/corrected/verified. AI use does not remove the student's responsibility for accuracy and understanding.
- **Similarity / integrity:** all sources, code, datasets, libraries and external resources must be referenced; copied or unclear submissions may be selected for individual technical verification (no full-class viva).
- **Marking rubric (40):** technical correctness 8 · database design quality 6 · practical implementation 8 · query/performance analysis 5 · advanced concepts 5 · documentation & GitHub organisation 5 · technical reflection 3.

## Portfolio ↔ course-note study-session map

| Portfolio | Activity | Course-note study sessions applied |
|---|---|---|
| **P1** Database Design and Modelling | ER diagram, relational schema, 3NF, constraints, bulk data | **Study Session 1** — Review of Traditional Relational DBs: stages of DB design, normalisation, characteristics of a good DB, limitations of traditional DBMS, intro to NoSQL |
| **P2** Query Processing and Optimisation | 6–8 analytical queries, EXPLAIN ANALYZE before/after indexing | **Study Session 4** — Query Optimisation: queries, execution plans, cost estimation, file organisation & indexes |
| **P3** Transactions and Concurrency | `borrow_copy()` transaction, COMMIT/ROLLBACK, two-terminal race condition + 2 fixes, isolation levels, deadlock | **Study Session 1** (ACID, characteristics of a good DB) + **Study Session 2** (consistency models, ACID vs BASE) |
| **P4** NoSQL and Advanced Data Models | MongoDB catalogue with polymorphic item types, schema validation, aggregations, 40k+ docs, COLLSCAN→IXSCAN | **Study Session 1** (NoSQL & types of NoSQL databases) + **Study Session 5** (emerging trends: graph DBs, knowledge graphs) |
| **P5** Distributed and Cloud Database | Monthly partitioning, primary + streaming read replica, NDPA 2023 cloud architecture, CAP & sync/async trade-offs, branch-offline design | **Study Session 2** (distributed DB architecture, fragmentation, replication, CAP, ACID/BASE) + **Study Session 3** (cloud database systems, big data) + **Study Session 6** (data privacy, NDPA 2023) |

## How to read the rest of the zip

Each portfolio folder contains its own short `README.md` (commands, what to screenshot, git commit, study session) and a `run_pN.sh` script. The top-level `setup.sh` installs PostgreSQL 16 and MongoDB 8 in a Codespace. Real database outputs are captured by the student and pasted into the `[paste real output here]` placeholders before the final documentation PDF is written.
