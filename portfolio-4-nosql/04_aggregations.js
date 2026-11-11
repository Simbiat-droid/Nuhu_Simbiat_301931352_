// =====================================================================
// Portfolio 4 — 04_aggregations.js
// Student: Nuhu Simbiat | Matric: 2026/A/MIT/0955
// Case study: ReadWell Libraries
//
// Three aggregation pipelines, each with a print() explanation and a
// [paste real output here] placeholder for the portfolio screenshot.
//
//   A. Items per subject (group + sort desc)
//   B. Top 10 authors ($unwind authors, group, count, sort desc, limit)
//   C. E-book downloads per subject (match ebook, group sum downloadCount)
//      plus a grand-total downloads figure.
// =====================================================================

db = db.getSiblingDB('readwell_catalog');

print('Documents in catalogue: ' + db.catalogue.countDocuments());

// =====================================================================
// A. Items per subject
// =====================================================================
print('\n================ A. ITEMS PER SUBJECT ================');
print('Pipeline: $group by $subject, count, $sort count desc.');
print('Purpose : which subjects dominate the ReadWell catalogue.');

const bySubject = db.catalogue.aggregate([
  { $group: { _id: '$subject', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
]).toArray();

print('Result (' + bySubject.length + ' subjects):');
bySubject.forEach(function (row) {
  print('  ' + row._id.padEnd(20) + ' ' + row.count);
});

// Paste the real mongosh output of the above here:
// [paste real output here]

// =====================================================================
// B. Top 10 most popular authors (across all item types)
// =====================================================================
print('\n================ B. TOP 10 AUTHORS ================');
print('Pipeline: $unwind authors, $group by author, count, $sort desc, $limit 10.');
print('Purpose : which authors contribute the most catalogue records.');

const topAuthors = db.catalogue.aggregate([
  { $unwind: '$authors' },
  { $group: { _id: '$authors', count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 10 }
]).toArray();

print('Result (top 10):');
topAuthors.forEach(function (row, idx) {
  print('  ' + (idx + 1).toString().padStart(2, ' ') + '. ' +
        row._id.padEnd(28) + ' ' + row.count);
});

// Paste the real mongosh output of the above here:
// [paste real output here]

// =====================================================================
// C. E-book downloads per subject + total downloads
// =====================================================================
print('\n================ C. E-BOOK DOWNLOADS ================');
print('Pipeline: $match itemType=ebook, $group by subject summing downloadCount, $sort desc.');
print('Purpose : which subjects drive the most e-book demand at ReadWell.');

const ebookBySubject = db.catalogue.aggregate([
  { $match: { itemType: 'ebook' } },
  { $group: { _id: '$subject', downloads: { $sum: '$downloadCount' } } },
  { $sort: { downloads: -1 } }
]).toArray();

print('Result (e-book downloads per subject):');
ebookBySubject.forEach(function (row) {
  print('  ' + row._id.padEnd(20) + ' ' + row.downloads + ' downloads');
});

// Grand total downloads across all e-books (single-document $group).
const totalDownloads = db.catalogue.aggregate([
  { $match: { itemType: 'ebook' } },
  { $group: { _id: null, totalDownloads: { $sum: '$downloadCount' },
              ebookCount: { $sum: 1 } } }
]).toArray();

if (totalDownloads.length === 0) {
  print('No e-books found in catalogue.');
} else {
  const t = totalDownloads[0];
  print('TOTAL e-books            : ' + t.ebookCount);
  print('TOTAL e-book downloads   : ' + t.totalDownloads);
}

// Paste the real mongosh output of the above here:
// [paste real output here]

print('\nAggregations complete.');
