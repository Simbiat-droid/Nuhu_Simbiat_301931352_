# 06 — SQL vs NoSQL: where each fits (ReadWell case study)

**Student:** Nuhu Simbiat  **Matric:** 2026/A/MIT/0955
**Case study:** ReadWell Libraries — catalogue of printed books, e-books, journals, theses and magazines across branches in Lagos, Abuja and Kaduna.

This portfolio picks **MongoDB** for the catalogue. That is a deliberate choice, not a religion — SQL would have been the right call for the *lending transactions* (Portfolio 1). The two databases solve different parts of the same library.

## When each fits

| Aspect | Relational (SQL) | Document (MongoDB) |
|---|---|---|
| Best for | Lending, fines, reservations, staff payroll — anything with strong relationships and per-row integrity. | Catalogue, product listings, content, events — anything where entities share a core but vary in shape. |
| ReadWell example | `loans`, `fines`, `members`, `branches` (Portfolios 1–3). | `catalogue` — this portfolio. |
| Shape | Fixed rows in fixed tables. | Self-describing JSON documents. |
| Schema change cost | `ALTER TABLE` + migrations + downtime risk. | Add a field — old docs simply don't have it. |

## Schema flexibility vs integrity

SQL wins on **integrity**: foreign keys, `CHECK` constraints, normalised joins and ACID guarantees are mature and enforced by the engine. MongoDB gives **flexibility**: a field can appear in one e-book record and not in another. To keep the worst chaos out, this portfolio uses **JSON Schema validation** (`validationLevel: 'strict'`, `validationAction: 'error'`) to enforce common required fields and type-check the per-type fields. That is a deliberate middle ground: flexible shape, but not the Wild West.

## The polymorphic-item-type problem — why MongoDB is natural here

ReadWell's catalogue has **five item types with different fields**:

- *printed_book* → isbn, edition, pages, shelfCode, branch
- *ebook* → fileFormat, fileSizeMB, licenceCount, downloadCount, downloadUrl
- *journal* → journalName, volume, issue, issn, publishedDate
- *thesis* → awardingInstitution, department, supervisor, degreeLevel, defenseDate
- *magazine* → issueName, issueNumber, publishedDate, frequency

In **SQL** this is awkward. Three common options, all ugly:

1. **Single table per type** (`printed_books`, `ebooks`, `journals`, …) — clean schemas, but every cross-type query (`SELECT … FROM catalogue`) becomes a 5-way `UNION ALL` and you cannot put a single index across the whole catalogue.
2. **One big table with every possible column** — a `NULL`-heavy monster where most rows are mostly `NULL`; columns multiply as new types arrive.
3. **Class-table inheritance** (`catalogue` + `catalogue_printed_book` + `catalogue_ebook` + …) — proper normalisation, but a query for "all items by Chinua Achebe" now joins 6 tables.

In **MongoDB** the same problem is a non-event: every catalogue record is one document, and a document simply *has* the fields its type needs. A printed book carries `isbn` and `shelfCode`; an e-book carries `fileFormat` and `downloadCount`. `itemType` discriminates which shape you're looking at. One collection, one index, one query — no `UNION`, no `NULL`s, no joins. This is exactly why document databases exist.

## Transactions

SQL has had ACID transactions for decades and they are the default. MongoDB gained multi-document ACID transactions in 4.0 (and distributed transactions in 4.2); for a single-document write MongoDB has always been atomic. For ReadWell's catalogue, single-document atomicity is enough — adding a new e-book is one `insertOne`. For *lending* (decrement stock, create loan, update member) you'd reach for multi-doc transactions, which both engines now support.

## Joins vs aggregations

SQL does joins natively (`JOIN`); MongoDB's `$lookup` exists but is secondary. MongoDB's superpower is the **aggregation pipeline** — a composable chain of stages (`$match → $unwind → $group → $sort → $limit`). This portfolio uses it three times: count items per subject, find the top 10 authors (after `$unwind` of the `authors` array), and sum e-book downloads per subject. Joins favour normalised relational data; pipelines favour nested, array-bearing documents. ReadWell needs both, so it uses both engines.

## Scaling

SQL scales **vertically** first (bigger box) and shards with effort (and application awareness). MongoDB scales **horizontally** out of the box via sharding on a shard key, which is why it's common for catalogues that grow to millions of items. For ReadWell's 40k+ catalogue today either is fine; MongoDB leaves the head-room.

## When to keep going — graph databases (Study Session 5)

If ReadWell ever wants "**members who borrowed this also borrowed…**" recommendation graphs, or "**which branch's collection overlaps most with member X's interests**" — that's a graph-traversal problem. Neither SQL nor MongoDB is great at multi-hop relationship queries; a graph database (Neo4j, Amazon Neptune) would be the natural next step, storing `(Member)-[BORROWED]->(Book)-[SHELVED_IN]->(Branch)` as edges and traversing them in O(hops). For the catalogue itself, though, the document model in this portfolio is the right tool today.

## Summary for ReadWell

- Catalogue (mixed item types, flexible shape, grows fast) → **MongoDB** (this portfolio).
- Lending, fines, reservations (relational, integrity-critical) → **SQL** (Portfolios 1–3).
- Future recommendation graph → **graph DB** (Study Session 5).
