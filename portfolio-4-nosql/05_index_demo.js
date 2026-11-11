// =====================================================================
// Portfolio 4 — 05_index_demo.js
// Student: Nuhu Simbiat | Matric: 2026/A/MIT/0955
// Case study: ReadWell Libraries
//
// Demonstrates the MongoDB query planner moving from COLLSCAN
// (collection scan) to IXSCAN (index scan) after creating an index on
// `subject`, plus a compound index on {itemType:1, subject:1} for a
// filtered query.
//
// We use explain('executionStats') so we get both the winning plan
// AND the timing/scan counts. We print the relevant fields rather than
// dumping the whole explain object (which is huge).
//
// HONESTY: real explain output / timings are NOT invented here. The
// placeholders [paste real output here] are where the portfolio
// screenshot of the actual mongosh output should be pasted.
// =====================================================================

db = db.getSiblingDB('readwell_catalog');

print('Documents in catalogue: ' + db.catalogue.countDocuments());

// Helper: pull the human-readable essentials out of an explain object.
function summariseExplain(explainObj, label) {
  const stage = explainObj.queryPlanner.winningPlan.stage;

  // Recursively find the actual input stage (COLLSCAN / IXSCAN / FETCH / etc.)
  function findInputStage(plan) {
    if (!plan) return null;
    if (plan.stage === 'COLLSCAN' || plan.stage === 'IXSCAN' ||
        plan.stage === 'FETCH'    || plan.stage === 'PROJECTION_COVERED') {
      return plan;
    }
    return findInputStage(plan.inputStage) ||
           findInputStage(plan.inputStages && plan.inputStages[0]);
  }

  const inputStage = findInputStage(explainObj.queryPlanner.winningPlan);
  const exec = explainObj.executionStats || {};

  print('\n----- ' + label + ' -----');
  print('winningPlan.stage          : ' + stage);
  if (inputStage) {
    print('input stage                : ' + inputStage.stage);
    if (inputStage.indexName) {
      print('indexName                  : ' + inputStage.indexName);
    }
    if (inputStage.indexBounds) {
      print('indexBounds                : ' + JSON.stringify(inputStage.indexBounds));
    }
    if (inputStage.direction) {
      print('direction                  : ' + inputStage.direction);
    }
    if (typeof inputStage.docsExamined === 'number') {
      print('docsExamined (input stage) : ' + inputStage.docsExamined);
    }
  }
  print('nReturned                  : ' + exec.nReturned);
  print('totalDocsExamined          : ' + exec.totalDocsExamined);
  print('totalKeysExamined          : ' + exec.totalKeysExamined);
  print('executionTimeMillis        : ' + exec.executionTimeMillis);
}

// =====================================================================
// STEP 0 — make sure no idx_subject exists before we start.
// (Idempotent: dropping a non-existent index is a no-op.)
// =====================================================================
print('\n================ STEP 0: drop idx_subject if it exists ================');
try {
  db.catalogue.dropIndex('idx_subject');
  print('Dropped existing idx_subject.');
} catch (e) {
  print('No idx_subject to drop (' + e.codeName + '). OK, continuing.');
}

// Also drop the compound index we will create later, for idempotency.
try {
  db.catalogue.dropIndex('idx_itemType_subject');
  print('Dropped existing idx_itemType_subject.');
} catch (e) {
  print('No idx_itemType_subject to drop (' + e.codeName + '). OK, continuing.');
}

// =====================================================================
// STEP 1 — query WITHOUT the index. Expect COLLSCAN.
// =====================================================================
print('\n================ STEP 1: find({subject:"Computer Science"}) WITHOUT index ================');
print('Expected winning plan: COLLSCAN (the whole collection is scanned).');

const explainBefore = db.catalogue
  .find({ subject: 'Computer Science' })
  .explain('executionStats');

summariseExplain(explainBefore, 'BEFORE index (expect COLLSCAN)');

// Where the real explain output (winning plan + executionTimeMillis) for
// the COLLSCAN run should be pasted in the portfolio:
// [paste real output here]

// =====================================================================
// STEP 2 — create the index on `subject`.
// =====================================================================
print('\n================ STEP 2: createIndex({subject:1}) ================');
const idxRes = db.catalogue.createIndex({ subject: 1 }, { name: 'idx_subject' });
print('createIndex result: ' + JSON.stringify(idxRes));
print('Indexes now: ' + JSON.stringify(
  db.catalogue.getIndexes().map(function (i) { return i.name; })
));

// =====================================================================
// STEP 3 — re-run the SAME query. Expect IXSCAN (with FETCH).
// =====================================================================
print('\n================ STEP 3: find({subject:"Computer Science"}) WITH idx_subject ================');
print('Expected winning plan: IXSCAN on idx_subject, then FETCH.');

const explainAfter = db.catalogue
  .find({ subject: 'Computer Science' })
  .explain('executionStats');

summariseExplain(explainAfter, 'AFTER index (expect IXSCAN)');

// Where the real explain output (winning plan + executionTimeMillis) for
// the IXSCAN run should be pasted in the portfolio:
// [paste real output here]

// =====================================================================
// STEP 4 — comparison summary (we DO print the numbers we just observed;
// the honesty rule forbids inventing them, so the script reads them from
// the explain objects it just produced).
// =====================================================================
print('\n================ STEP 4: COLLSCAN vs IXSCAN comparison ================');
const beforeStats = explainBefore.executionStats || {};
const afterStats  = explainAfter.executionStats  || {};
const beforeInputStage = (function findCollScan(p) {
  if (!p) return null;
  if (p.stage === 'COLLSCAN' || p.stage === 'IXSCAN') return p;
  return findCollScan(p.inputStage) ||
         findCollScan(p.inputStages && p.inputStages[0]);
})(explainBefore.queryPlanner.winningPlan);
const afterInputStage = (function findScan(p) {
  if (!p) return null;
  if (p.stage === 'COLLSCAN' || p.stage === 'IXSCAN') return p;
  return findScan(p.inputStage) ||
         findScan(p.inputStages && p.inputStages[0]);
})(explainAfter.queryPlanner.winningPlan);

print('Metric                       | BEFORE (no idx)      | AFTER (idx_subject)');
print('-----------------------------|----------------------|----------------------');
print('Input stage                  | ' +
  String(beforeInputStage ? beforeInputStage.stage : 'n/a').padEnd(20) + ' | ' +
  String(afterInputStage  ? afterInputStage.stage  : 'n/a').padEnd(20));
print('nReturned                    | ' +
  String(beforeStats.nReturned).padEnd(20) + ' | ' +
  String(afterStats.nReturned).padEnd(20));
print('totalDocsExamined            | ' +
  String(beforeStats.totalDocsExamined).padEnd(20) + ' | ' +
  String(afterStats.totalDocsExamined).padEnd(20));
print('totalKeysExamined            | ' +
  String(beforeStats.totalKeysExamined).padEnd(20) + ' | ' +
  String(afterStats.totalKeysExamined).padEnd(20));
print('executionTimeMillis          | ' +
  String(beforeStats.executionTimeMillis).padEnd(20) + ' | ' +
  String(afterStats.executionTimeMillis).padEnd(20));

print('\nObservation: the COLLSCAN run examined every document in the collection');
print('(totalDocsExamined ≈ collection size); the IXSCAN run examined only the');
print('matching documents (plus the index keys), which is why indexed reads are');
print('dramatically faster as the catalogue grows past ~40,000 documents.');

// =====================================================================
// STEP 5 — compound index demo on {itemType:1, subject:1}.
// A typical ReadWell query: "all e-books in Computer Science".
// =====================================================================
print('\n================ STEP 5: compound index {itemType:1, subject:1} ================');

const compoundIdx = db.catalogue.createIndex(
  { itemType: 1, subject: 1 },
  { name: 'idx_itemType_subject' }
);
print('createIndex result: ' + JSON.stringify(compoundIdx));

const filteredExplain = db.catalogue
  .find({ itemType: 'ebook', subject: 'Computer Science' })
  .explain('executionStats');

summariseExplain(filteredExplain, 'Compound-index query (expect IXSCAN on idx_itemType_subject)');

print('\nThis query has an equality on itemType and an equality on subject,');
print('both of which are leading keys of idx_itemType_subject, so the planner');
print('should use the compound index instead of falling back to idx_subject or');
print('a COLLSCAN. This is the leftmost-prefix rule in action.');

// Paste the real explain output for the compound-index query here:
// [paste real output here]

print('\nIndex demo complete.');
