-- =============================================
-- Module 3: Data Warehouse — Learning Journey CP1-CP3
-- =============================================
-- Project:  dezoomcamp170426
-- Dataset:  zoomcamp
-- Bucket:   gs://mahardi-dezoomcamp-kestra
-- Author:   Mahardi
-- Course:   DataTalksClub Data Engineering Zoomcamp 2026
-- =============================================

-- =============================================
-- CONTEXT: From Module 2 to Module 3
-- =============================================
-- Module 2 left yellow_tripdata in BQ with:
--   - 109,047,518 rows (Jan 2019 - Dec 2020)
--   - Already PARTITIONED by DATE(tpep_pickup_datetime)
--   - VendorID stored as STRING (Module 2 explicit schema)
-- Module 3 explores: external tables, partition impact, clustering, BQML

-- =============================================
-- COST FRAMEWORK (internalized through CP1-CP3)
-- =============================================
-- Cost equation:
--   Cost = Bytes scanned × ($5 / TB on-demand US region)
--
-- 4 Optimization levers (priority order):
--   1. Column projection (no SELECT *)            30-90% reduction
--   2. Partition pruning (filter partition col)   50-99% reduction
--   3. Cluster filtering (filter cluster col)     10-50% reduction
--   4. Metadata-only queries (COUNT(*) no filter) 100% (0 bytes)
--
-- Pre-flight check before every query:
--   - Look at top-right estimate ("This query will process X")
--   - Iterate: column listing, partition filter, cluster filter
--   - Run only when estimate is acceptable
--
-- Minimum billing: 10 MB per query (even if scan is smaller)

-- =============================================
-- CP1: External Table from GCS — COMPLETED
-- =============================================
-- Goal: Bridge data lake (GCS) to warehouse (BQ) via external table
-- Mental model:
--   external table = pointer (metadata only, data stays in GCS)
--   native table   = data + metadata (data lives in BQ Colossus)

CREATE OR REPLACE EXTERNAL TABLE `dezoomcamp170426.zoomcamp.external_yellow_tripdata`
OPTIONS (
  format = 'CSV',
  uris = [
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2019-*.csv',
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2020-*.csv'
  ]
);

-- Verify: Details panel shows NO Table Size, NO Number of Rows
-- Confirms external = metadata only; data not materialized in Colossus
-- External Data Configuration section lists: format, URIs, file paths

-- Cost observations:
--   COUNT(*) external_yellow_tripdata: 9.38 GB scanned (full file read in GCS)
--   COUNT(*) yellow_tripdata (native): 0 B (metadata-only, row count in catalog)
--   SELECT *   + DATE filter (17 cols): 50.94 MB
--   SELECT 3 cols + DATE filter:         9.07 MB
--   → 82% reduction from column projection alone
--
-- Math check: 3/17 cols = 17.6% expected; actual 9.07/50.94 = 17.8%
-- Conclusion: Capacitor columnar storage scans ONLY requested columns
--             (vs row-oriented DB that would scan all columns regardless)

-- WARNING — schema auto-inference trap:
--   external_yellow_tripdata.VendorID = INT64 (auto-detected from CSV "1", "2")
--   Module 2 yellow_tripdata.VendorID = STRING (explicit categorical typing)
--   → causes type mismatch when comparing tables
--   Production fix: always define schema explicitly in CREATE EXTERNAL TABLE
--   See LESSONS section at bottom for production-grade version


-- =============================================
-- CP2: Partition Demo — COMPLETED
-- =============================================
-- Goal: Demonstrate impact of partitioning vs non-partitioned baseline

-- Step 1: Create non-partitioned baseline (for comparison only)
CREATE OR REPLACE TABLE `dezoomcamp170426.zoomcamp.yellow_tripdata_non_partitioned` AS
SELECT * FROM `dezoomcamp170426.zoomcamp.external_yellow_tripdata`;

-- Storage comparison (observed in Details panel):
--   yellow_tripdata (Module 2 MERGE-built, partitioned):
--     Rows: 109,047,518 | Partitions: 770
--     Logical: 24.44 GB | Physical: 2.92 GB (compression 8.4x)
--   yellow_tripdata_non_partitioned (single-shot CTAS):
--     Rows: 109,047,518
--     Logical: 13.84 GB | Physical: TBD (lazy metric, settles after few minutes)
--
-- INSIGHT: Module 2 table's logical bytes 77% larger than CTAS version
--   Cause: 24 MERGE transactions accumulated overhead
--          + 2 extra cols (unique_row_id BYTES, filename STRING for audit)
--          + 7-day time travel window keeps recent state
--
-- Production lesson: incrementally-built tables accumulate overhead vs
--                    single-shot rebuilds. Periodic compaction needed at scale.

-- Step 2: Benchmark queries (Jun 2019 only)

-- A: Non-partitioned — scans ALL partitions despite date filter
SELECT DISTINCT VendorID
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata_non_partitioned`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';
-- Pre-execution estimate: 1.55 GB

-- B: Partitioned — scans ONLY 30 partitions of June 2019
SELECT DISTINCT VendorID
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';
-- Pre-execution estimate: 72.81 MB
--
-- RESULT: 21.2x reduction, 95.3% saving (better than instructor's 15x demo)
--
-- Cost translation:
--   Single query:    $0.0076 → $0.00036 per execution
--   10,000 queries/mo: $77 → $3.6 = $73/month savings per query pattern
--   100 patterns:     $87,600/year saved — equivalent to mid-level engineer salary

-- Step 3: Inspect partition distribution
SELECT partition_id, total_rows, total_logical_bytes
FROM `dezoomcamp170426.zoomcamp.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'yellow_tripdata'
ORDER BY total_rows DESC LIMIT 20;
-- Top 20 days: 280K-290K rows/day
-- Heaviest: Jan 11, Feb 8, Dec 19, Dec 12, Dec 13
-- Pattern: Friday + winter + holiday season = peak taxi demand
-- Real-world signal: data shape mirrors actual behavior, useful for QA eyeballing

-- KEY LEARNING: Partition pruning ONLY works if query FILTERS on partition column
--               Partitioned table + query without DATE filter = same cost as non-partitioned
--               Schema enforces structure, but query author must use it correctly


-- =============================================
-- CP3: Cluster Demo — COMPLETED
-- =============================================
-- Goal: Add clustering on top of partitioning; measure incremental benefit

-- Step 1: Create partitioned + clustered table
CREATE OR REPLACE TABLE `dezoomcamp170426.zoomcamp.yellow_tripdata_partitioned_clustered`
PARTITION BY DATE(tpep_pickup_datetime)
CLUSTER BY VendorID AS
SELECT * FROM `dezoomcamp170426.zoomcamp.external_yellow_tripdata`;

-- Step 2: VendorID selectivity analysis (run BEFORE deciding on cluster column)
SELECT VendorID, COUNT(*) AS rows
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2020-12-31'
GROUP BY VendorID
ORDER BY rows DESC;
-- Distribution (71.5M rows in date range):
--   VendorID=2:    46.2M rows (64.6%)  — dominant, low selectivity
--   VendorID=1:    24.2M rows (33.9%)  — moderate selectivity
--   null:          1.06M rows (1.5%)
--   VendorID=4:    36K rows   (0.05%)  — high selectivity but spread thin

-- Step 3: Benchmark — moderate selectivity (VendorID=1, single day)
-- TYPE NOTE:
--   yellow_tripdata.VendorID = STRING → use '1' (quoted)
--   yellow_tripdata_partitioned_clustered.VendorID = INT64 → use 1 (unquoted)

-- A: Partitioned only
SELECT COUNT(*) AS trips
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata`
WHERE DATE(tpep_pickup_datetime) = '2019-06-15' AND VendorID = '1';
-- Estimate: 2.32 MB | Elapsed: 347 ms | Records read: 221,153

-- B: Partitioned + clustered
SELECT COUNT(*) AS trips
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata_partitioned_clustered`
WHERE DATE(tpep_pickup_datetime) = '2019-06-15' AND VendorID = 1;
-- Estimate: 3.37 MB | Elapsed: 322 ms | Records read: 221,153
--
-- INSIGHT: Records read IDENTICAL between A and B
--   Cluster does NOT reduce records accessed for this query
--   Slight runtime improvement (~7%) = layout cache-friendliness, not scan reduction
--   Daily partition (200K rows) is small enough that partition pruning dominates

-- Step 4: Benchmark — high selectivity (VendorID=4, 19 months)

-- A: Partitioned only
SELECT COUNT(*) AS trips
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2020-12-31'
  AND VendorID = '4';
-- Records read: 20,716,863 | Elapsed: 268 ms

-- B: Partitioned + clustered
SELECT COUNT(*) AS trips
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata_partitioned_clustered`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2020-12-31'
  AND VendorID = 4;
-- Records read: 18,309,507 | Elapsed: 335 ms
--
-- INSIGHT: 11.6% reduction in records read — modest, NOT dramatic
-- Why not dramatic: VendorID=4 spread THIN but EVENLY across all 580 days
--   ~63 trips/day on average — every partition has some VendorID=4
--   Cluster only skips BLOCKS within partition, can't skip partitions themselves
--   Cluster shines when filter col is CONCENTRATED in few partitions, not just RARE

-- =============================================
-- CLUSTER DECISION RULES (learned)
-- =============================================
-- | Condition                                         | Cluster benefit |
-- | High selectivity (<5%) + LARGE partition (M rows) | DRAMATIC 50-90% |
-- | Moderate selectivity (10-30%) + LARGE partition   | MODEST 20-40%   |
-- | Low selectivity (>30%) OR small partition         | MINOR <10%      |
-- | Filter NOT on cluster column                      | ZERO            |
--
-- For taxi data (daily partitions ~200K rows):
--   Partition pruning does 90% of optimization work
--   Cluster is incremental, mostly cache/latency benefit
--   Production trade-off: cluster maintenance cost vs modest savings


-- =============================================
-- TODO: AFTER MODULE 3 COMPLETION (cleanup)
-- =============================================
-- Drop intermediate tables from CP2-CP3 + leftover from backfill:
--
-- Pattern to drop: (yellow|green)_tripdata_YYYY_MM and _ext suffixes
-- Plus consider dropping:
--   - yellow_tripdata_non_partitioned (CP2 baseline, no production value)
--   - yellow_tripdata_partitioned_clustered (CP3 demo, optional to keep)
--
-- Cleanup approach (BQ scripting):
/*
FOR row IN
(
  SELECT table_name
  FROM `dezoomcamp170426.zoomcamp.INFORMATION_SCHEMA.TABLES`
  WHERE REGEXP_CONTAINS(table_name, r'^(yellow|green)_tripdata_\d{4}_\d{2}(_ext)?$')
)
DO
  EXECUTE IMMEDIATE FORMAT(
    'DROP TABLE IF EXISTS `dezoomcamp170426.zoomcamp.%s`',
    row.table_name
  );
END FOR;
*/


-- =============================================
-- KEY MENTAL MODELS (transferable to other DE projects)
-- =============================================
-- 1. Storage and compute are SEPARATE in modern data warehouse
--    Decoupling enables independent scaling — fundamental BQ architecture
--    Without it: every storage growth forces compute upgrade (legacy MPP problem)
--
-- 2. External tables = catalog entry POINTING to data elsewhere
--    Permanent in catalog, data lives in lake (GCS/S3)
--    Best for: low-frequency queries, lakehouse architecture, federated access
--    NOT a substitute for native tables in production hot paths
--
-- 3. Partition is for cost predictability + partition-level operations
--    Cluster is for query performance within partitions
--    Decision: filter pattern + selectivity + partition size dictates which to use
--    Schema decisions are UPFRONT (re-partitioning later is expensive)
--
-- 4. Auto schema inference = convenient but TREACHEROUS
--    Categorical IDs detected as INT64 → wrong semantics, breaks ML feature engineering
--    Leading zeros lost ("0812345" → 812345)
--    Phone-like or product-code strings auto-converted to numbers
--    PRACTICE: always define explicit schema for production tables
--
-- 5. Pre-execution estimate ≠ actual scan
--    Bytes scanned is the ground truth cost metric
--    "Records read" in execution details shows what BQ actually accessed
--    Caching skews benchmarks — disable cache when measuring
--
-- 6. Engineer vs Analyst separation of concerns:
--    Engineer creates external/native tables, manages schema, owns ingestion
--    Analyst queries curated layer (gold/silver views), doesn't write DDL
--    Modern tools (dbt sources, Iceberg) automate self-service patterns


-- =============================================
-- PRODUCTION-GRADE VERSION (for reference)
-- =============================================
-- If rebuilding for production, define schema explicitly (matches Module 2):
/*
CREATE OR REPLACE EXTERNAL TABLE `dezoomcamp170426.zoomcamp.external_yellow_tripdata`
(
  VendorID STRING,
  tpep_pickup_datetime TIMESTAMP,
  tpep_dropoff_datetime TIMESTAMP,
  passenger_count INTEGER,
  trip_distance NUMERIC,
  RatecodeID STRING,
  store_and_fwd_flag STRING,
  PULocationID STRING,
  DOLocationID STRING,
  payment_type INTEGER,
  fare_amount NUMERIC,
  extra NUMERIC,
  mta_tax NUMERIC,
  tip_amount NUMERIC,
  tolls_amount NUMERIC,
  improvement_surcharge NUMERIC,
  total_amount NUMERIC,
  congestion_surcharge NUMERIC
)
OPTIONS (
  format = 'CSV',
  uris = [
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2019-*.csv',
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2020-*.csv'
  ],
  skip_leading_rows = 1,
  ignore_unknown_values = TRUE
);
*/