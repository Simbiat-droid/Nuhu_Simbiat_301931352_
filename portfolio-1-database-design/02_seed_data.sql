-- =============================================================================
-- 02_seed_data.sql
-- ReadWell Libraries - Seed Data (Portfolio 1)
-- Student: Nuhu Simbiat - 2026/A/MIT/0955
--
-- Inserts:
--   4 branches   (Yaba, Ikeja, Garki, Kaduna)
--  25 authors    (Nigerian + international)
--  42 books      (real titles, valid-looking ISBN-13; 2 fictional co-edited
--                 anthologies so book_author demonstrates M:N)
--  44 book_author rows (40 books -> 1 author, 2 books -> 2 authors)
--  60 copies     (distributed across the 4 branches)
--  15 members    (realistic Nigerian first+last names, unique emails)
--
-- Idempotent: TRUNCATE every table at the top, in reverse dependency order.
-- Branches/books/authors inserted without explicit IDs so BIGSERIAL starts at 1;
-- the bulk generator (03) uses (gs % count) + 1 to reference them.
-- =============================================================================

TRUNCATE TABLE
    fine,
    reservation,
    loan,
    copy,
    book_author,
    book,
    author,
    member,
    branch
RESTART IDENTITY CASCADE;

-- =============================================================================
-- 1. BRANCHES (4)
-- =============================================================================
INSERT INTO branch (name, city, address, phone) VALUES
('Yaba',    'Lagos',  '234 Herbert Macaulay Way, Yaba, Lagos',   '+2348011111111'),
('Ikeja',   'Lagos',  '12 Obafemi Awolowo Way, Ikeja, Lagos',   '+2348022222222'),
('Garki',   'Abuja',  '45 Constitution Avenue, Garki, Abuja',   '+2348033333333'),
('Kaduna',  'Kaduna', '78 Ahmadu Bello Way, Kaduna, Kaduna',    '+2348044444444');

-- =============================================================================
-- 2. AUTHORS (25) - mix of Nigerian and international
-- =============================================================================
INSERT INTO author (name, country) VALUES
('Chimamanda Ngozi Adichie', 'Nigeria'),
('Wole Soyinka',             'Nigeria'),
('Chinua Achebe',            'Nigeria'),
('Cyprian Ekwensi',          'Nigeria'),
('Buchi Emecheta',           'Nigeria'),
('Ben Okri',                 'Nigeria'),
('Helon Habila',             'Nigeria'),
('Sefi Atta',                'Nigeria'),
('Elnathan John',            'Nigeria'),
('Elechi Amadi',             'Nigeria'),
('Adaobi Tricia Nwaubani',   'Nigeria'),
('Dan Brown',                'USA'),
('J.K. Rowling',             'UK'),
('George R.R. Martin',       'USA'),
('Stephen King',             'USA'),
('Margaret Atwood',          'Canada'),
('Khaled Hosseini',          'Afghanistan'),
('Haruki Murakami',          'Japan'),
('Toni Morrison',            'USA'),
('John Green',               'USA'),
('Yuval Noah Harari',        'Israel'),
('Malcolm Gladwell',         'Canada'),
('James Clear',              'USA'),
('Stephen Hawking',          'UK'),
('Rick Warren',              'USA');

-- =============================================================================
-- 3. BOOKS (42)
--    ISBNs are valid-looking ISBN-13 strings (all start with 978).
--    Categories: Fiction, Literature, Science, History, Religion, Business,
--    Children, Biography, Technology, Health.
--    Books 41 and 42 are fictional co-edited anthologies (clearly marked) so
--    the book_author M:N relationship has at least two multi-author rows.
-- =============================================================================
INSERT INTO book (title, isbn, category, publisher, publication_year) VALUES
-- Fiction (Nigerian)
('Half of a Yellow Sun',                  '9789780230001', 'Fiction',     'Farafina',           2006),
('Americanah',                            '9789780230002', 'Fiction',     'Farafina',           2013),
('Purple Hibiscus',                       '9789780230003', 'Fiction',     'Algonquin Books',    2003),
('The Famished Road',                     '9789780230004', 'Fiction',     'Jonathan Cape',      1991),
('Songs of Enchantment',                  '9789780230005', 'Fiction',     'Vintage',            1993),
('Waiting for an Angel',                  '9789780230006', 'Fiction',     'Penguin',            2002),
('Measuring Time',                        '9789780230007', 'Fiction',     'Penguin',            2007),
('Everything Good Will Come',             '9789780230008', 'Fiction',     'Interlink Books',    2005),
('A Bit of Difference',                  '9789780230009', 'Fiction',     'Interlink Books',    2013),
('Born on a Tuesday',                     '9789780230010', 'Fiction',     'Cassava Republic',   2015),
('I Do Not Come to You by Chance',        '9789780230011', 'Fiction',     'Cassava Republic',   2009),
-- Literature (Nigerian classics)
('Things Fall Apart',                     '9789780230012', 'Literature',  'Heinemann',          1958),
('No Longer at Ease',                     '9789780230013', 'Literature',  'Heinemann',          1960),
('Anthills of the Savannah',              '9789780230014', 'Literature',  'Heinemann',          1987),
('A Man of the People',                   '9789780230015', 'Literature',  'Heinemann',          1966),
('Death and the King''s Horseman',        '9789780230016', 'Literature',  'W.W. Norton',        1975),
('The Interpreters',                      '9789780230017', 'Literature',  'Andre Deutsch',      1965),
('The Joys of Motherhood',                '9789780230018', 'Literature',  'Allison & Busby',    1979),
('The Slave Girl',                        '9789780230019', 'Literature',  'George Braziller',  1977),
('People of the City',                    '9789780230020', 'Literature',  'Heinemann',          1954),
('Jagua Nana',                            '9789780230021', 'Literature',  'Heinemann',          1961),
('The Concubine',                         '9789780230022', 'Literature',  'Heinemann',          1966),
('The Great Ponds',                       '9789780230023', 'Literature',  'Heinemann',          1969),
-- Fiction (international)
('The Da Vinci Code',                     '9780307474278', 'Fiction',     'Doubleday',          2003),
('Angels & Demons',                       '9780743493931', 'Fiction',     'Atria Books',        2000),
('A Game of Thrones',                     '9780553103540', 'Fiction',     'Bantam Books',       1996),
('The Shining',                           '9780385121675', 'Fiction',     'Doubleday',          1977),
('The Handmaid''s Tale',                  '9780385490818', 'Fiction',     'McClelland & Stewart', 1985),
('The Kite Runner',                       '9781594480003', 'Fiction',     'Riverhead Books',    2003),
('The Fault in Our Stars',                '9780525478812', 'Fiction',     'Dutton Books',       2012),
-- Children
('Harry Potter and the Philosopher''s Stone', '9780747532699', 'Children', 'Bloomsbury',       1997),
('Harry Potter and the Chamber of Secrets',  '9780747538493', 'Children', 'Bloomsbury',        1998),
-- Literature (international)
('Norwegian Wood',                        '9780375704024', 'Literature',  'Vintage',            2000),
('Beloved',                               '9781400033416', 'Literature',  'Vintage',            1987),
-- History
('Sapiens: A Brief History of Humankind', '9780062316097', 'History',     'Harper',             2015),
-- Business
('Outliers: The Story of Success',        '9780316017930', 'Business',    'Little, Brown',      2008),
('Atomic Habits',                         '9780735211292', 'Business',    'Avery',              2018),
-- Science
('A Brief History of Time',               '9780553380163', 'Science',     'Bantam Books',       1998),
-- Religion
('The Purpose Driven Life',               '9780310205715', 'Religion',    'Zondervan',          2002),
-- Biography
('Ake: The Years of Childhood',           '9789780230024', 'Biography',   'Random House',       1981),
-- Fictional co-edited anthologies (M:N demonstration)
('African Voices Anthology',              '9789780230041', 'Literature',  'Farafina',           2018),
('New Nigerian Writing',                  '9789780230042', 'Fiction',     'Cassava Republic',  2020);

-- =============================================================================
-- 4. book_author (44 rows: 40 single-author + 2 multi-author books x2 authors)
--    book_id 1..40 -> single author; book 41 -> authors 1+2; book 42 -> authors 7+8
-- =============================================================================
INSERT INTO book_author (book_id, author_id) VALUES
(1,1),(2,1),(3,1),
(4,6),(5,6),
(6,7),(7,7),
(8,8),(9,8),
(10,9),
(11,11),
(12,3),(13,3),(14,3),(15,3),
(16,2),(17,2),
(18,5),(19,5),
(20,4),(21,4),
(22,10),(23,10),
(24,12),(25,12),
(26,14),
(27,15),
(28,16),
(29,17),
(30,20),
(31,13),(32,13),
(33,18),
(34,19),
(35,21),
(36,22),
(37,23),
(38,24),
(39,25),
(40,2),
-- Anthologies: M:N rows (two authors per book)
(41,1),(41,2),
(42,7),(42,8);

-- =============================================================================
-- 5. COPIES (60) distributed across the 4 branches
--    Barcodes RW00000001..RW00000060. Book chosen round-robin; branch round-robin.
--    Note: 03_bulk_generator.sql will TRUNCATE copy (and member) before inserting
--    the 5 000 bulk copies, so these seed copies only matter for standalone 02 runs.
-- =============================================================================
INSERT INTO copy (book_id, branch_id, barcode, status, acquired_at)
SELECT
    ((gs - 1) % 42) + 1,
    ((gs - 1) % 4)  + 1,
    'RW' || lpad(gs::text, 8, '0'),
    'available',
    NOW() - (random() * INTERVAL '3 years')
FROM generate_series(1, 60) AS gs;

-- =============================================================================
-- 6. MEMBERS (15) with realistic Nigerian names + unique emails
-- =============================================================================
INSERT INTO member (first_name, last_name, email, phone, home_branch_id, joined_at) VALUES
('Aisha',    'Bello',      'aisha.bello@example.com',     '+2348031110001', 1, NOW() - INTERVAL '18 months'),
('Tunde',    'Adeyemi',    'tunde.adeyemi@example.com',   '+2348031110002', 1, NOW() - INTERVAL '2 years'),
('Chidi',    'Okafor',     'chidi.okafor@example.com',    '+2348031110003', 2, NOW() - INTERVAL '14 months'),
('Fatima',   'Mohammed',   'fatima.mohammed@example.com', '+2348031110004', 2, NOW() - INTERVAL '22 months'),
('Bola',     'Oyelaran',   'bola.oyelaran@example.com',   '+2348031110005', 3, NOW() - INTERVAL '9 months'),
('Emeka',    'Eze',        'emeka.eze@example.com',       '+2348031110006', 3, NOW() - INTERVAL '16 months'),
('Zainab',   'Ibrahim',    'zainab.ibrahim@example.com',  '+2348031110007', 4, NOW() - INTERVAL '11 months'),
('Kunle',    'Nwosu',      'kunle.nwosu@example.com',     '+2348031110008', 4, NOW() - INTERVAL '20 months'),
('Amina',    'Sani',       'amina.sani@example.com',      '+2348031110009', 1, NOW() - INTERVAL '7 months'),
('Chinwe',   'Okonkwo',    'chinwe.okonkwo@example.com',  '+2348031110010', 2, NOW() - INTERVAL '13 months'),
('Yakubu',   'Adamu',      'yakubu.adamu@example.com',    '+2348031110011', 3, NOW() - INTERVAL '19 months'),
('Ifeoma',   'Uche',       'ifeoma.uche@example.com',     '+2348031110012', 4, NOW() - INTERVAL '8 months'),
('Sadiq',    'Hamza',      'sadiq.hamza@example.com',     '+2348031110013', 1, NOW() - INTERVAL '15 months'),
('Bisi',     'Adebayo',    'bisi.adebayo@example.com',    '+2348031110014', 2, NOW() - INTERVAL '10 months'),
('Musa',     'Aliyu',      'musa.aliyu@example.com',      '+2348031110015', 3, NOW() - INTERVAL '12 months');

-- =============================================================================
-- End of seed data
-- =============================================================================
