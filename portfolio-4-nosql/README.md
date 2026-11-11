# Portfolio 4 — NoSQL & Advanced Data Models (MongoDB)


> **After testing:** the validator now declares `_id` (with
> `additionalProperties: false` MongoDB had rejected every document) and
> enforces each item type's required fields with `oneOf` branches (MongoDB's
> `$jsonSchema` has no if/then/else). `run_p4.sh` loads the bulk data first and
> the named seed records after it, so they are not wiped. Real output: `p4_output.log`.
**Student:** Nuhu Simbiat  **Matric:** 2026/A/MIT/0955
**Course:** MIT 8103 — Advanced Database Systems (Miva Open University)
**Case study:** ReadWell Libraries — a simulated public library network with branches in Lagos (Yaba, Ikeja), Abuja (Garki) and Kaduna. The catalogue stores **metadata records** for mixed item types: printed books, e-books, journals, theses and magazines.

## What this portfolio demonstrates

- A MongoDB catalogue (`readwell_catalog.catalogue`) that stores **polymorphic item types** in one collection — printed books, e-books, journals, theses and magazines — each with a different field shape. This is the classic document-database use case for mixed entity types.
- **JSON Schema validation** via `db.createCollection(..., {validator: ...})` with a discriminated-but-permissive schema: common required fields (`itemType`, `title`, `subject`, `authors`, `createdAt`, `tags`) plus type-specific conditional fields, with `validationLevel: 'strict'` and `validationAction: 'error'`.
- A **bulk generator** that inserts **40,000+ documents** (≈42,000) in batches of 1,000 using `insertMany(batch, {ordered:false})`, distributed across the five item types.
- Three **aggregation pipelines**: items per subject, top 10 authors (with `$unwind`), and e-book downloads grouped by subject with a total.
- An **index demonstration** showing the query planner moving from **COLLSCAN** (collection scan) to **IXSCAN** (index scan) after creating `idx_subject`, plus a compound index on `{itemType:1, subject:1}`.

## Codespaces run commands

`mongod` is installed and started by `setup.sh`. From this folder:

```bash
# Run the whole portfolio end-to-end:
bash run_p4.sh

# …or run each step manually:
mongosh readwell_catalog < 01_schema_validation.js
mongosh readwell_catalog < 02_seed_data.js
mongosh readwell_catalog < 03_bulk_generator.js
mongosh readwell_catalog < 04_aggregations.js
mongosh readwell_catalog < 05_index_demo.js
```

> Each JS file is self-contained and idempotent where it matters (`03_bulk_generator.js` clears the collection first; `05_index_demo.js` drops the index it is about to test).

## What to screenshot (as evidence)

1. **Schema validation rejection** — the `try/catch` block in `01_schema_validation.js` that tries to insert a document missing a required field. Capture the `Document failed validation` error from mongosh.
2. **Aggregation outputs** — the printed result arrays from `04_aggregations.js` (items per subject, top 10 authors, e-book downloads per subject + total).
3. **`explain()` COLLSCAN vs IXSCAN** — the winning plan from `05_index_demo.js` *before* creating `idx_subject` (COLLSCAN, `executionTimeMillis`) and *after* (IXSCAN, `executionTimeMillis`), plus the comparison summary.
4. **Count of 40,000+ documents** — the `Inserted total: …` line printed at the end of `03_bulk_generator.js` (expect ≈ 42,000 + the seed smoke-test docs).

## Git commit command

```bash
cd /workspaces/<your-repo>
git add portfolio-4-nosql/
git commit -m "Portfolio 4: NoSQL/MongoDB catalogue with schema validation, 40k+ docs, aggregations, COLLSCAN->IXSCAN"
git push
```

## Study session reference

- **Study Session 1 — NoSQL & types of NoSQL.** This portfolio is a direct artefact of that session: a document store (MongoDB) chosen because the catalogue mixes item types whose fields differ wildly, which is awkward in a single SQL table.
- **Study Session 5 — Graph databases / emerging trends.** The brief explicitly asks the portfolio to *reference* Session 5; the comparison in `06_sql_vs_nosql.md` mentions graph stores as the natural next step if ReadWell ever needs to model member→book→branch recommendation graphs.
