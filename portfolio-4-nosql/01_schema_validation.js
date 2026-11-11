// =====================================================================
// Portfolio 4 — 01_schema_validation.js
// Student: Nuhu Simbiat | Matric: 2026/A/MIT/0955
// Case study: ReadWell Libraries (Lagos-Yaba, Lagos-Ikeja, Abuja-Garki, Kaduna)
//
// Creates the `catalogue` collection with JSON Schema validation
// (db.createCollection with validator, validationLevel 'strict',
//  validationAction 'error').
//
// The catalogue is POLYMORPHIC: one collection holds metadata records
// for five item types — printed_book, ebook, journal, thesis, magazine —
// each with a DIFFERENT field shape.
//
// MongoDB's $jsonSchema does NOT support if/then/else, so:
//   - common required fields are enforced for ALL documents;
//   - per-type fields are declared in `properties` (type-checked);
//   - per-type REQUIRED fields are enforced with one `oneOf` branch
//     per itemType (exactly one branch must match).
//
// Common (required for every doc):
//   itemType (enum), title (string), subject (string),
//   authors (array<string>), createdAt (date), tags (array<string>).
//
// Per-type conditional fields (documented):
//   printed_book: isbn, edition, pages(int), shelfCode, branch
//   ebook:        fileFormat(enum), fileSizeMB, licenceCount(int),
//                 downloadCount(int), downloadUrl
//   journal:      journalName, volume(int), issue(int), issn, publishedDate(date)
//   thesis:       awardingInstitution, department, supervisor,
//                 degreeLevel(enum MSc/PhD/BSc), defenseDate(date)
//   magazine:     issueName, issueNumber(int), publishedDate(date),
//                 frequency(enum weekly/monthly)
// =====================================================================

db = db.getSiblingDB('readwell_catalog');

// Drop if it already exists so the script is idempotent.
if (db.getCollectionNames().indexOf('catalogue') !== -1) {
  db.catalogue.drop();
  print('Dropped existing catalogue collection.');
}

// ---------------------------------------------------------------------
// JSON Schema validator.
// `bsonType` values match the BSON type names mongosh expects.
// ---------------------------------------------------------------------
const validator = {
  $jsonSchema: {
    bsonType: 'object',
    title: 'ReadWell catalogue record',
    description:
      'Polymorphic catalogue record. itemType discriminates the shape; ' +
      'common fields are required for every record, type-specific fields ' +
      'are declared in properties and type-checked when present.',
    required: ['itemType', 'title', 'subject', 'authors', 'createdAt', 'tags'],
    properties: {
      // _id must be declared because additionalProperties is false
      // (FIX: without this line MongoDB rejected EVERY document).
      _id: { bsonType: 'objectId' },
      // ---- common fields (required for every record) ----
      itemType: {
        enum: ['printed_book', 'ebook', 'journal', 'thesis', 'magazine'],
        description: 'Discriminator for the record type. Required.'
      },
      title:    { bsonType: 'string',  description: 'Title of the item. Required.' },
      subject:  { bsonType: 'string',  description: 'Subject / category. Required.' },
      authors: {
        bsonType: 'array',
        items: { bsonType: 'string' },
        description: 'List of author names. Required (may be empty array).'
      },
      createdAt: { bsonType: 'date', description: 'When the record was created. Required.' },
      tags: {
        bsonType: 'array',
        items: { bsonType: 'string' },
        description: 'Free-form tags. Required (may be empty array).'
      },

      // ---- printed_book conditional fields ----
      isbn:      { bsonType: 'string' },
      edition:   { bsonType: 'string' },
      pages:     { bsonType: 'int' },
      shelfCode: { bsonType: 'string' },
      branch:    { bsonType: 'string' },

      // ---- ebook conditional fields ----
      fileFormat: {
        enum: ['pdf', 'epub', 'mobi'],
        description: 'E-book file format.'
      },
      fileSizeMB:     { bsonType: 'number' },
      licenceCount:   { bsonType: 'int' },
      downloadCount:  { bsonType: 'int' },
      downloadUrl:    { bsonType: 'string' },

      // ---- journal conditional fields ----
      journalName:   { bsonType: 'string' },
      volume:        { bsonType: 'int' },
      issue:         { bsonType: 'int' },
      issn:          { bsonType: 'string' },
      publishedDate: { bsonType: 'date' },   // used by journal AND magazine

      // ---- thesis conditional fields ----
      awardingInstitution: { bsonType: 'string' },
      department:          { bsonType: 'string' },
      supervisor:          { bsonType: 'string' },
      degreeLevel: {
        enum: ['MSc', 'PhD', 'BSc'],
        description: 'Thesis degree level.'
      },
      defenseDate: { bsonType: 'date' },

      // ---- magazine conditional fields ----
      issueName:   { bsonType: 'string' },
      issueNumber: { bsonType: 'int' },
      frequency: {
        enum: ['weekly', 'monthly'],
        description: 'Magazine publication frequency.'
      }
    },
    // Do NOT allow arbitrary extra top-level keys beyond what is declared.
    additionalProperties: false,
    // Per-type REQUIRED fields. $jsonSchema has no if/then/else, so each
    // itemType is one oneOf branch; exactly one branch must match.
    oneOf: [
      { properties: { itemType: { enum: ['printed_book'] } },
        required: ['isbn', 'pages', 'shelfCode', 'branch'] },
      { properties: { itemType: { enum: ['ebook'] } },
        required: ['fileFormat', 'fileSizeMB', 'licenceCount', 'downloadCount'] },
      { properties: { itemType: { enum: ['journal'] } },
        required: ['journalName', 'volume', 'issue', 'issn', 'publishedDate'] },
      { properties: { itemType: { enum: ['thesis'] } },
        required: ['awardingInstitution', 'department', 'supervisor', 'degreeLevel', 'defenseDate'] },
      { properties: { itemType: { enum: ['magazine'] } },
        required: ['issueName', 'issueNumber', 'publishedDate', 'frequency'] }
    ]
  }
};

db.createCollection('catalogue', {
  validator: validator,
  validationLevel: 'strict',
  validationAction: 'error'
});

print('Created collection `catalogue` with JSON schema validation.');
print('Validation level: strict | Validation action: error');

// ---------------------------------------------------------------------
// Smoke test: insert ONE valid document of each of the 5 types.
// ---------------------------------------------------------------------
const now = new Date();

const smokeDocs = [
  {
    itemType: 'printed_book',
    title: 'Things Fall Apart',
    subject: 'Literature',
    authors: ['Chinua Achebe'],
    createdAt: now,
    tags: ['african-literature', 'classic'],
    isbn: '978-0385474542',
    edition: '2nd',
    pages: NumberInt(209),
    shelfCode: 'LIT-ACHE-001',
    branch: 'Lagos-Yaba'
  },
  {
    itemType: 'ebook',
    title: 'Introduction to Algorithms',
    subject: 'Computer Science',
    authors: ['Thomas H. Cormen', 'Charles E. Leiserson'],
    createdAt: now,
    tags: ['algorithms', 'textbook'],
    fileFormat: 'pdf',
    fileSizeMB: 24.8,
    licenceCount: NumberInt(30),
    downloadCount: NumberInt(0),
    downloadUrl: 'https://readwell.example.org/ebooks/intro-algorithms.pdf'
  },
  {
    itemType: 'journal',
    title: 'Power System Stability: A Review',
    subject: 'Engineering',
    authors: ['Adeyemi Adisa', 'Ngozi Okoro'],
    createdAt: now,
    tags: ['power-systems', 'review'],
    journalName: 'Nigerian Journal of Engineering',
    volume: NumberInt(28),
    issue: NumberInt(2),
    issn: '0331-3247',
    publishedDate: now
  },
  {
    itemType: 'thesis',
    title: 'Machine Learning for Malaria Diagnosis from Microscopy Images',
    subject: 'Computer Science',
    authors: ['Ibrahim Musa'],
    createdAt: now,
    tags: ['machine-learning', 'medical-imaging'],
    awardingInstitution: 'University of Lagos',
    department: 'Computer Sciences',
    supervisor: 'Dr. Folakemi Emeka',
    degreeLevel: 'MSc',
    defenseDate: now
  },
  {
    itemType: 'magazine',
    title: 'ReadWell Weekly — Technology in Africa',
    subject: 'Technology',
    authors: ['ReadWell Editorial'],
    createdAt: now,
    tags: ['current-affairs', 'technology'],
    issueName: 'Technology Special',
    issueNumber: NumberInt(142),
    publishedDate: now,
    frequency: 'weekly'
  }
];

const smoke = db.catalogue.insertMany(smokeDocs);
print('Smoke test inserted ' + Object.keys(smoke.insertedIds).length + ' valid documents (one per item type).');
print('Inserted _ids: ' + JSON.stringify(smoke.insertedIds, null, 2));

// ---------------------------------------------------------------------
// Negative test: try to insert an INVALID document (missing `subject`,
// a required common field, and also sneaking in a forbidden key to show
// additionalProperties:false in action). Wrap in try/catch and print
// the rejection. Do NOT let the script fail.
// ---------------------------------------------------------------------
const invalidDoc = {
  itemType: 'printed_book',
  title: 'Missing Subject On Purpose',
  // subject intentionally omitted — should fail validation
  authors: ['Anonymous'],
  createdAt: now,
  tags: [],
  isbn: '000-0000000000',
  rogueField: 'this key is not in the schema'
};

print('\n=== Negative test: inserting a document that violates the schema ===');
print('Document being inserted: ' + JSON.stringify(invalidDoc, null, 2));

try {
  db.catalogue.insertOne(invalidDoc);
  print('UNEXPECTED: the invalid document was accepted!');
} catch (e) {
  print('REJECTED as expected.');
  print('Error name : ' + e.name);
  print('Error code : ' + e.code);
  print('Error msg  : ' + e.message);
  if (e.errInfo) {
    print('errInfo    : ' + JSON.stringify(e.errInfo, null, 2));
  }
}

// Negative test 2: a printed_book with every COMMON field but no isbn /
// shelfCode / branch -> rejected by the oneOf per-type branch.
const invalidDoc2 = {
  itemType: 'printed_book', title: 'Book With No ISBN', subject: 'Fiction',
  authors: ['Anonymous'], createdAt: now, tags: [], pages: NumberInt(120)
};
print('\n=== Negative test 2: printed_book missing its per-type fields ===');
try {
  db.catalogue.insertOne(invalidDoc2);
  print('UNEXPECTED: the invalid document was accepted!');
} catch (e) {
  print('REJECTED as expected (oneOf per-type rule). Error code : ' + e.code);
}

// ---------------------------------------------------------------------
// Where real mongosh output / the rejected-document error object would
// appear in the portfolio screenshot, paste it here:
//
// [paste real output here]
// ---------------------------------------------------------------------

print('\nSchema validation step complete. Collection ready for seeding.');
