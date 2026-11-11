# ReadWell Libraries — ER Diagram (Mermaid)

This is the **only** ER diagram file for Portfolio 1. It is plain Mermaid text
(no images), so it renders in any Markdown viewer that supports Mermaid and can
be diffed in git.

```mermaid
---
title: ReadWell Libraries - ER Diagram
---
erDiagram
    branch {
        BIGINT      branch_id   PK
        TEXT        name
        TEXT        city
        TEXT        address
        TEXT        phone
        TIMESTAMPTZ created_at
    }
    author {
        BIGINT      author_id   PK
        TEXT        name
        TEXT        country
        TIMESTAMPTZ created_at
    }
    book {
        BIGINT      book_id          PK
        TEXT        title
        TEXT        isbn             UK
        TEXT        category
        TEXT        publisher
        INT         publication_year
        TIMESTAMPTZ created_at
    }
    book_author {
        BIGINT      book_id     PK,FK
        BIGINT      author_id   PK,FK
    }
    copy {
        BIGINT      copy_id     PK
        BIGINT      book_id     FK
        BIGINT      branch_id   FK
        TEXT        barcode     UK
        TEXT        status
        TIMESTAMPTZ acquired_at
    }
    member {
        BIGINT      member_id       PK
        TEXT        first_name
        TEXT        last_name
        TEXT        email           UK
        TEXT        phone
        BIGINT      home_branch_id  FK
        TIMESTAMPTZ joined_at
    }
    loan {
        BIGINT      loan_id     PK
        BIGINT      copy_id     FK
        BIGINT      member_id   FK
        TIMESTAMPTZ loan_date
        TIMESTAMPTZ due_date
        TIMESTAMPTZ return_date
        TSTZRANGE   loan_range
    }
    reservation {
        BIGINT      reservation_id       PK
        BIGINT      book_id             FK
        BIGINT      member_id           FK
        BIGINT      branch_id           FK
        TIMESTAMPTZ reserved_at
        TIMESTAMPTZ fulfilled_at
        BIGINT      fulfilled_by_copy_id FK
    }
    fine {
        BIGINT      fine_id     PK
        BIGINT      loan_id     FK
        NUMERIC     amount
        BOOLEAN     paid
        TIMESTAMPTZ created_at
        TIMESTAMPTZ paid_at
    }

    branch   ||--o{ copy        : "holds"
    branch   ||--o{ member      : "registers"
    book     ||--o{ copy        : "has"
    book     ||--o{ book_author : "written by"
    author   ||--o{ book_author : "writes"
    copy     ||--o{ loan        : "borrowed as"
    member   ||--o{ loan        : "borrows"
    loan     ||--o{ fine        : "incurs"
    book     ||--o{ reservation : "reserved as"
    member   ||--o{ reservation : "makes"
    branch   ||--o{ reservation : "picked up at"
    copy     ||--o{ reservation : "fulfilled by"
```

## Legend

| Marker | Meaning |
|--------|---------|
| `PK`   | Primary Key |
| `FK`   | Foreign Key |
| `PK,FK`| Part of a composite primary key that is also a foreign key |
| `UK`   | Unique constraint |
| `||--o{` | One-to-many: one parent row → zero or more child rows |

## Notes on the model

- A `book` is a *logical* title (an ISBN); a `copy` is the *physical* artefact on a shelf. The exclusion constraint on `loan` therefore keys on `copy_id`, not `book_id`.
- `book_author` is a pure many-to-many junction table (composite PK `book_id, author_id`) so a book may have several authors and vice-versa.
- `loan.loan_range` is a `TSTZRANGE`; the GiST `EXCLUDE` constraint prevents a copy being on two overlapping loans at once.
- `reservation.fulfilled_by_copy_id` is nullable: it stays NULL until a staff member assigns a physical copy to fulfil the reservation.
- `fine` is its own table (not a column on `loan`) because a loan may have zero, one, or several fines, and the fine lifecycle (paid / paid_at) is independent of the loan lifecycle.
