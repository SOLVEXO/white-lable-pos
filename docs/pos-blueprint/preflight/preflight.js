#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * G1b PRE-FLIGHT — READ-ONLY, AGGREGATE COUNTS ONLY.
 *
 * Run it yourself with a READ-ONLY database user and paste the output back. It prints only counts keyed by currency code / field name:
 * no customer names, phones, e-mails, ids, store names, connection details or document contents.
 *
 *   cd solvexo-api            # (it uses that folder's node_modules/mongodb — no install needed)
 *   MONGO_URI='mongodb+srv://<read-only-user>:…@…/<db>' node ../pos/docs/pos-blueprint/preflight/preflight.js
 *
 * SAFETY, in this order:
 *  1. It asks the server what the connected user may do (`connectionStatus`, showPrivileges) and REFUSES TO RUN if that user can
 *     write anything (insert / update / remove / create / drop / index / user-management / "anyAction" …). Create a user with the built-in
 *     `read` role on the database and use that one.
 *  2. It refuses to run on an unauthenticated connection (an unauthenticated user has every privilege) — except a localhost URI with
 *     `--allow-unauthenticated-localhost` (for trying it on a local dev database only).
 *  3. It only calls `connectionStatus`, `estimatedDocumentCount`, `countDocuments` and `aggregate` (no `$out` / `$merge`). It never writes.
 *
 * What it reports: documents per collection · stores by base currency · sales and shifts by (currency, exponent snapshot) including rows
 * with NO snapshot (written before Phase 5B) · PKR sales by exponent · variants whose price / compare-at / cost are NOT a whole number of
 * minor units of their store's currency (ISO exponent) · sales / shifts with a money value genuinely off the minor-unit grid (> 1e-6 of a minor unit; float noise is not counted).
 */
const path = require('path');
let mongodb;
try {
  mongodb = require(require.resolve('mongodb', { paths: [process.cwd(), path.join(process.cwd(), 'node_modules')] }));
} catch (e) {
  console.error('Cannot find the "mongodb" package. Run this from the solvexo-api folder (cd solvexo-api) so node_modules/mongodb is found.');
  process.exit(2);
}
const { MongoClient } = mongodb;

const WRITE_ACTIONS = new Set([
  'insert', 'update', 'remove', 'createCollection', 'dropCollection', 'dropDatabase', 'createIndex', 'dropIndex', 'renameCollectionSameDB', 'collMod',
  'convertToCapped', 'createUser', 'dropUser', 'updateUser', 'grantRole', 'revokeRole', 'createRole', 'dropRole', 'dropAllUsersFromDatabase', 'dropAllRolesFromDatabase',
  'enableSharding', 'shardCollection', 'compact', 'reIndex', 'applyOps', 'bypassDocumentValidation', 'anyAction', 'setAuthenticationRestriction', 'changeOwnPassword', 'changeCustomData',
]);

// ISO-4217 minor-unit exponents (mirrors solvexo-api/src/common/currency-metadata.const.ts: 0 / 3 decimals, everything else 2)
const ZERO = ['BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF'];
const THREE = ['BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'];
const expOfCurrency = (field) => ({ $switch: { branches: [{ case: { $in: [{ $toUpper: { $ifNull: [field, 'USD'] } }, ZERO] }, then: 0 }, { case: { $in: [{ $toUpper: { $ifNull: [field, 'USD'] } }, THREE] }, then: 3 }], default: 2 } });
const factor = (expExpr) => ({ $pow: [10, expExpr] });
const offGrid = (valueExpr, expExpr) => ({ $and: [{ $isNumber: valueExpr }, { $gt: [{ $abs: { $subtract: [{ $multiply: [valueExpr, factor(expExpr)] }, { $round: [{ $multiply: [valueExpr, factor(expExpr)] }, 0] }] } }, 0.000001] }] });

async function main() {
  const uri = process.env.MONGO_URI;
  if (!uri) { console.error('Set MONGO_URI to a connection string for a READ-ONLY user.'); process.exit(2); }
  const allowLocalUnauth = process.argv.includes('--allow-unauthenticated-localhost');
  const client = await MongoClient.connect(uri, { serverSelectionTimeoutMS: 15000 });
  try {
    // ── 1/2: refuse unless the user is authenticated and cannot write ─────────────────────────────────────────────────
    const st = await client.db('admin').command({ connectionStatus: 1, showPrivileges: true });
    const users = (st.authInfo && st.authInfo.authenticatedUsers) || [];
    const privileges = (st.authInfo && st.authInfo.authenticatedUserPrivileges) || [];
    const isLocal = /^mongodb:\/\/(?:[^@/]*@)?(?:127\.0\.0\.1|localhost)[:/]/.test(uri);
    if (users.length === 0) {
      if (!(allowLocalUnauth && isLocal)) {
        console.error('REFUSING TO RUN: the connection is not authenticated (an unauthenticated connection has every privilege). Use a read-only database user.');
        process.exit(3);
      }
      console.error('(local, unauthenticated — allowed by --allow-unauthenticated-localhost; this would be refused anywhere else)');
    } else {
      const writes = new Set();
      for (const p of privileges) for (const a of p.actions || []) if (WRITE_ACTIONS.has(a)) writes.add(a);
      if (writes.size > 0) {
        console.error('REFUSING TO RUN: the connected user can WRITE (' + [...writes].sort().join(', ') + '). Use a user that has only the built-in "read" role.');
        process.exit(3);
      }
    }

    const db = client.db();
    const names = new Set((await db.listCollections({}, { nameOnly: true }).toArray()).map((c) => c.name));
    const has = (n) => names.has(n);
    const out = { generatedAt: new Date().toISOString().slice(0, 10), readOnlyUserVerified: users.length > 0 };

    // ── documents per collection ──────────────────────────────────────────────────────────────────────────────────────
    out.documentsPerCollection = {};
    for (const c of ['stores', 'sales', 'registersessions', 'pospayments', 'posrefunds', 'posauditlogs', 'employees', 'posdevices', 'products', 'productvariants', 'variantpricehistories']) {
      if (has(c)) out.documentsPerCollection[c] = await db.collection(c).estimatedDocumentCount();
    }

    // ── stores by base currency ───────────────────────────────────────────────────────────────────────────────────────
    if (has('stores')) {
      out.storesByBaseCurrency = Object.fromEntries((await db.collection('stores').aggregate([{ $group: { _id: { $ifNull: ['$baseCurrency', 'null'] }, n: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray()).map((r) => [r._id, r.n]));
    }

    // ── sales / shifts / refunds by currency + exponent snapshot ─────────────────────────────────────────────────────
    const bySnapshot = async (coll) => Object.fromEntries((await db.collection(coll).aggregate([{ $group: { _id: { c: { $ifNull: ['$currency', 'NO_SNAPSHOT'] }, e: { $ifNull: ['$currencyExponent', 'NO_SNAPSHOT'] } }, n: { $sum: 1 } } }, { $sort: { '_id.c': 1, '_id.e': 1 } }]).toArray()).map((r) => [`${r._id.c}/exp:${r._id.e}`, r.n]));
    if (has('sales')) {
      out.salesByCurrencyExponent = await bySnapshot('sales');
      out.salesPre5B_noExponentSnapshot = await db.collection('sales').countDocuments({ $or: [{ currencyExponent: { $exists: false } }, { currencyExponent: null }] });
      out.salesWithRefundsMissingExponent = (await db.collection('sales').aggregate([{ $match: { 'refunds.0': { $exists: true } } }, { $unwind: '$refunds' }, { $match: { $or: [{ 'refunds.currencyExponent': { $exists: false } }, { 'refunds.currencyExponent': null }] } }, { $count: 'n' }]).toArray())[0]?.n ?? 0;
      out.salesAlreadyDualWritten = await db.collection('sales').countDocuments({ totalMinor: { $exists: true } });
      out.pkrSalesByExponent = Object.fromEntries((await db.collection('sales').aggregate([{ $match: { currency: 'PKR' } }, { $group: { _id: { $ifNull: ['$currencyExponent', 'NO_SNAPSHOT'] }, n: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray()).map((r) => [`exp:${r._id}`, r.n]));
      // money values off the minor-unit grid (float drift), using the row's snapshot or the ISO table via the currency code
      const salesExp = { $ifNull: ['$currencyExponent', expOfCurrency('$currency')] };
      const off = (f) => offGrid('$' + f, salesExp);
      const r = (await db.collection('sales').aggregate([{ $group: { _id: null, anyOffGridTotalFields: { $sum: { $cond: [{ $or: [off('subtotal'), off('discount'), off('tax'), off('total'), off('refundedAmount'), off('changeGiven')] }, 1, 0] } } } }]).toArray())[0];
      out.salesWithAnyMoneyFieldOffGrid = r ? r.anyOffGridTotalFields : 0;
    }
    if (has('registersessions')) {
      out.shiftsByCurrencyExponent = await bySnapshot('registersessions');
      out.shiftsPre5B_noExponentSnapshot = await db.collection('registersessions').countDocuments({ $or: [{ currencyExponent: { $exists: false } }, { currencyExponent: null }] });
      out.shiftsAlreadyDualWritten = await db.collection('registersessions').countDocuments({ openingCashMinor: { $exists: true } });
      const sExp = { $ifNull: ['$currencyExponent', expOfCurrency('$currency')] };
      const offS = (f) => offGrid('$' + f, sExp);
      const r = (await db.collection('registersessions').aggregate([{ $group: { _id: null, n: { $sum: { $cond: [{ $or: ['cashSales', 'cardSales', 'otherSales', 'totalSales', 'totalRefunds', 'openingCash', 'closingCash', 'expectedCash', 'cashDifference'].map(offS) }, 1, 0] } } } }]).toArray())[0];
      out.shiftsWithAnyMoneyFieldOffGrid = r ? r.n : 0;
      out.openShifts = await db.collection('registersessions').countDocuments({ status: 'open' });
    }
    if (has('posrefunds')) out.posRefundsByCurrencyExponent = await bySnapshot('posrefunds');
    if (has('pospayments')) out.posPaymentsByCurrencyExponent = await bySnapshot('pospayments');

    // ── variants whose prices are NOT a whole number of minor units of their store's currency ───────────────────────
    if (has('productvariants') && has('products') && has('stores')) {
      const pipeline = [
        { $addFields: { _pid: { $convert: { input: '$productId', to: 'objectId', onError: null, onNull: null } } } },
        { $lookup: { from: 'products', localField: '_pid', foreignField: '_id', as: '_p', pipeline: [{ $project: { storeId: 1 } }] } },
        { $addFields: { _sid: { $convert: { input: { $arrayElemAt: ['$_p.storeId', 0] }, to: 'objectId', onError: null, onNull: null } } } },
        { $lookup: { from: 'stores', localField: '_sid', foreignField: '_id', as: '_s', pipeline: [{ $project: { baseCurrency: 1 } }] } },
        { $addFields: { cur: { $ifNull: [{ $arrayElemAt: ['$_s.baseCurrency', 0] }, 'NO_STORE'] } } },
        { $addFields: { exp: expOfCurrency('$cur') } },
        { $group: {
          _id: '$cur', variants: { $sum: 1 },
          priceOffGrid: { $sum: { $cond: [offGrid('$price', '$exp'), 1, 0] } },
          compareAtPriceOffGrid: { $sum: { $cond: [offGrid('$compareAtPrice', '$exp'), 1, 0] } },
          costPriceOffGrid: { $sum: { $cond: [offGrid('$costPrice', '$exp'), 1, 0] } },
        } },
        { $sort: { _id: 1 } },
      ];
      out.variantsByStoreCurrency_offGridPrices = Object.fromEntries((await db.collection('productvariants').aggregate(pipeline, { allowDiskUse: true }).toArray()).map((r) => [r._id, { variants: r.variants, priceOffGrid: r.priceOffGrid, compareAtPriceOffGrid: r.compareAtPriceOffGrid, costPriceOffGrid: r.costPriceOffGrid }]));
    }

    console.log(JSON.stringify(out, null, 2));
  } finally {
    await client.close();
  }
}
main().catch((e) => { console.error('Pre-flight failed:', e && e.message ? e.message : e); process.exit(1); });
