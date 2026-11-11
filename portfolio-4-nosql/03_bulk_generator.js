// =====================================================================
// Portfolio 4 — 03_bulk_generator.js
// Student: Nuhu Simbiat | Matric: 2026/A/MIT/0955
// Case study: ReadWell Libraries
//
// Bulk generator. Inserts 42,000 catalogue records in batches of 1,000
// using db.catalogue.insertMany(batch, {ordered:false}).
//
// Distribution (rough):
//   printed_book  ~50%   (21,000)
//   ebook         ~20%   ( 8,400)
//   journal       ~15%   ( 6,300)
//   magazine      ~10%   ( 4,200)
//   thesis        ~ 5%   ( 2,100)
//
// Idempotent: clears the catalogue first with deleteMany({}). Schema
// validation created by 01_schema_validation.js is preserved.
//
// Dates use: new Date(Date.now() - Math.random() * 3 * 365 * 24 * 3600 * 1000)
// (i.e. somewhere within the last ~3 years).
// =====================================================================

db = db.getSiblingDB('readwell_catalog');

// ---- idempotency ----------------------------------------------------
print('Clearing catalogue (deleteMany) so the run is reproducible...');
db.catalogue.deleteMany({});
print('Cleared. Documents remaining: ' + db.catalogue.countDocuments());

// ---- realistic lookup data -----------------------------------------

// Ordered by popularity (pickSkewed favours the front of the list).
// 'Computer Science' is kept near the end so the 05_index_demo.js query on it
// is SELECTIVE (~6% of documents) - an index only beats a COLLSCAN when it
// skips most of the collection.
const SUBJECTS = [
  'Literature', 'History', 'Religion', 'Medicine', 'Engineering',
  'Law', 'Economics', 'Computer Science', 'Mathematics', 'Biology'
];

const TITLE_PREFIX = [
  'Foundations of', 'Advances in', 'Introduction to', 'Principles of',
  'Applied', 'Modern', 'Contemporary', 'Emerging Trends in',
  'Case Studies in', 'A Critical Review of', 'Handbook of',
  'Lectures on', 'Studies in', 'Readings in', 'Elements of'
];

const TAG_POOL = [
  'reference', 'textbook', 'research', 'africa', 'nigeria',
  'introductory', 'advanced', 'practical', 'theoretical', 'review',
  'undergraduate', 'postgraduate', 'case-study', 'data-driven'
];

const AUTHORS = [
  // Nigerian / African
  'Chinua Achebe', 'Chimamanda Ngozi Adichie', 'Wole Soyinka',
  'Ngozi Okonjo-Iweala', 'Toyin Falola', 'Adeyemi Adisa',
  'Ngozi Okoro', 'Sani Abdullahi', 'Bisi Olawuyi', 'Yetunde Akinleye',
  'Emeka Obi', 'Amina Bello', 'Hauwa Mohammed', 'Ibrahim Musa',
  'Oluwatobi Banjoko', 'Folakemi Emeka', 'Suleiman Danladi',
  'Olufemi Ogunde', 'Adebowale Adeyemi', 'Fatima Ibrahim',
  // International
  'Donald Knuth', 'Martin Kleppmann', 'Robert C. Martin',
  'Thomas H. Cormen', 'Andrew S. Tanenbaum', 'Linus Torvalds',
  'Donald Norman', 'Stephen Hawking', 'Yuval Noah Harari',
  'Jane Austen', 'George Orwell', 'Albert Einstein'
];

const INSTITUTIONS = [
  'University of Lagos', 'Ahmadu Bello University', 'University of Ibadan',
  'Covenant University', 'University of Nigeria Nsukka',
  'Obafemi Awolowo University', 'Bayero University Kano',
  'Federal University of Technology Minna', 'Miva Open University'
];

const DEPARTMENTS = [
  'Computer Sciences', 'Electrical Engineering', 'Mechanical Engineering',
  'Civil Engineering', 'History', 'Medicine', 'Law',
  'Economics', 'Mathematics', 'Biological Sciences',
  'Water Resources & Environmental Engineering', 'Religious Studies'
];

const SUPERVISORS = [
  'Prof. Olufemi Ogunde', 'Prof. Suleiman Danladi', 'Dr. Folakemi Emeka',
  'Dr. Bisi Olawuyi', 'Prof. Amina Bello', 'Dr. Emeka Obi',
  'Prof. Yetunde Akinleye', 'Dr. Sani Abdullahi', 'Prof. Hauwa Mohammed'
];

const JOURNAL_NAMES = [
  'Nigerian Journal of Engineering',
  'African Journal of Health Sciences',
  'Journal of West African History',
  'Lagos Law Review',
  'Journal of Nigerian Economics',
  'Journal of Pure and Applied Mathematics',
  'West African Biological Sciences Journal',
  'International Journal of Computer Science Research'
];

const MAGAZINE_ISSUE_NAMES = [
  'Technology Special', 'Health & Wellness', 'Business Review',
  'Arts & Culture', 'Science Digest', 'Education Matters',
  'Law & Society', 'Economic Outlook'
];

const BRANCHES = ['Lagos-Yaba', 'Lagos-Ikeja', 'Abuja-Garki', 'Kaduna'];

const FILE_FORMATS = ['pdf', 'epub', 'mobi'];

const DEGREE_LEVELS = ['MSc', 'PhD', 'BSc'];

const FREQUENCIES = ['weekly', 'monthly'];

// ---- helpers --------------------------------------------------------

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function pickMany(arr, n) {
  const out = [];
  const used = {};
  let count = 0;
  while (count < n) {
    const v = pick(arr);
    if (!used[v]) {
      used[v] = true;
      out.push(v);
      count++;
    }
    if (Object.keys(used).length >= arr.length) break; // avoid infinite loop
  }
  return out;
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randDateLast3Years() {
  // ~3 years back, as required by the brief
  return new Date(Date.now() - Math.random() * 3 * 365 * 24 * 3600 * 1000);
}

function randIsbn() {
  // pseudo-ISBN-13: 978-XXXXXXXXXX
  let s = '978-';
  for (let i = 0; i < 10; i++) s += randInt(0, 9);
  return s;
}

function randIssn() {
  let s = randInt(1000, 9999) + '-';
  for (let i = 0; i < 4; i++) s += randInt(0, 9);
  return s;
}

function makeTitle(subject) {
  return pick(TITLE_PREFIX) + ' ' + subject + ' (Vol. ' + randInt(1, 30) + ')';
}

// Skewed pick: earlier entries are chosen more often, so subjects,
// authors and branches have realistic, UNEQUAL counts (a uniform pick
// gave ~4,200 of every subject, which looks fabricated).
function pickSkewed(arr) {
  return arr[Math.floor(Math.pow(Math.random(), 1.8) * arr.length)];
}
function pickManySkewed(arr, n) {
  const out = [];
  let guard = 0;
  while (out.length < n && guard++ < 50) {
    const a = pickSkewed(arr);
    if (out.indexOf(a) === -1) out.push(a);
  }
  return out;
}
function ordinal(n) {
  return n + (n === 1 ? 'st' : n === 2 ? 'nd' : n === 3 ? 'rd' : 'th');
}

// Decide item type from a uniform random draw, matching the target mix.
function pickItemType() {
  const r = Math.random();
  if (r < 0.50) return 'printed_book';      // 50%
  if (r < 0.70) return 'ebook';             // 20%
  if (r < 0.85) return 'journal';           // 15%
  if (r < 0.95) return 'magazine';          // 10%
  return 'thesis';                          //  5%
}

// Build a single catalogue document of the given type.
function makeDoc(i) {
  const itemType = pickItemType();
  const subject = pickSkewed(SUBJECTS);
  const createdAt = randDateLast3Years();
  const tags = pickMany(TAG_POOL, randInt(1, 3));

  // 1–3 authors per record
  const nAuthors = randInt(1, 3);
  const authors = pickManySkewed(AUTHORS, nAuthors);
  if (authors.length === 0) authors.push(pick(AUTHORS)); // never empty

  const doc = {
    itemType: itemType,
    title: makeTitle(subject),
    subject: subject,
    authors: authors,
    createdAt: createdAt,
    tags: tags
  };

  switch (itemType) {

    case 'printed_book':
      doc.isbn = randIsbn();
      doc.edition = ordinal(randInt(1, 5));   // FIX: was '1th', '2th'
      doc.pages = NumberInt(randInt(80, 900));
      doc.shelfCode = subject.substring(0, 3).toUpperCase() + '-' +
                      String(i).padStart(6, '0');
      doc.branch = pickSkewed(BRANCHES);
      break;

    case 'ebook':
      doc.fileFormat = pick(FILE_FORMATS);
      doc.fileSizeMB = Math.round(Math.random() * 50 * 10) / 10; // 0.0–500.0
      doc.licenceCount = NumberInt(randInt(5, 50));
      doc.downloadCount = NumberInt(randInt(0, 5000));
      doc.downloadUrl = 'https://readwell.example.org/ebooks/' +
                        itemType + '-' + i + '.' + doc.fileFormat;
      break;

    case 'journal':
      doc.journalName = pick(JOURNAL_NAMES);
      doc.volume = NumberInt(randInt(1, 40));
      doc.issue = NumberInt(randInt(1, 12));
      doc.issn = randIssn();
      doc.publishedDate = randDateLast3Years();
      break;

    case 'thesis':
      doc.awardingInstitution = pick(INSTITUTIONS);
      doc.department = pick(DEPARTMENTS);
      doc.supervisor = pick(SUPERVISORS);
      doc.degreeLevel = pick(DEGREE_LEVELS);
      doc.defenseDate = randDateLast3Years();
      break;

    case 'magazine':
      doc.issueName = pick(MAGAZINE_ISSUE_NAMES);
      doc.issueNumber = NumberInt(randInt(1, 300));
      doc.publishedDate = randDateLast3Years();
      doc.frequency = pick(FREQUENCIES);
      break;
  }

  return doc;
}

// ---- main bulk-insert loop -----------------------------------------

const TOTAL = 42000;
const BATCH = 1000;
let inserted = 0;
const start = Date.now();

print('Generating ' + TOTAL + ' documents in batches of ' + BATCH + '...');

for (let i = 0; i < TOTAL; i += BATCH) {
  const end = Math.min(i + BATCH, TOTAL);
  const batch = new Array(end - i);

  for (let j = i; j < end; j++) {
    batch[j - i] = makeDoc(j);
  }

  const res = db.catalogue.insertMany(batch, { ordered: false });
  inserted += Object.keys(res.insertedIds).length;

  // Progress log every 5,000 docs
  if (inserted % 5000 < BATCH) {
    print('  inserted ~' + inserted + ' / ' + TOTAL +
          '  (elapsed ' + (Date.now() - start) + ' ms)');
  }
}

const elapsed = Date.now() - start;

// ---- summary --------------------------------------------------------

const counts = db.catalogue.aggregate([
  { $group: { _id: '$itemType', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
]).toArray();

print('\n================ BULK GENERATION SUMMARY ================');
print('Target total : ' + TOTAL);
print('Inserted     : ' + inserted);
print('In DB now    : ' + db.catalogue.countDocuments());
print('Elapsed (ms) : ' + elapsed);
print('Per-type counts:');
counts.forEach(function (c) {
  print('  ' + c._id.padEnd(14) + ' : ' + c.count);
});
print('Inserted total: ' + db.catalogue.countDocuments());
print('========================================================');

// ---------------------------------------------------------------------
// Where real mongosh output (the summary above, including the final
// "Inserted total: …" line, which should be 40000+) would appear in the
// portfolio screenshot, paste it here:
//
// [paste real output here]
// ---------------------------------------------------------------------
