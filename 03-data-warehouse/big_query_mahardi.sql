-- =============================================
-- CP2: Partition Demo — COMPLETED
-- =============================================
-- Step 3 Benchmark (Jun 2019 only, DISTINCT VendorID):
--   A (non-partitioned): 1.55 GB scan
--   B (partitioned):     72.81 MB scan
--   Ratio: 21.2x reduction, 95.3% saving
--
-- Step 4 Partition inspection:
--   Top 20 days by row count: 280K-290K rows/day
--   Heaviest days: Jan 11, Feb 8, Dec 19, Dec 12, Dec 13
--   Pattern: Friday + winter + holiday season = peak taxi demand
--
-- Key learning: Partition pruning hanya bekerja kalau query FILTER
-- di partition column (DATE(tpep_pickup_datetime)). 
-- Tabel partitioned + query tanpa filter = no benefit.
-- =============================================

-- Step 1: Non-partitioned baseline
CREATE OR REPLACE TABLE `dezoomcamp170426.zoomcamp.yellow_tripdata_non_partitioned` AS
SELECT * FROM `dezoomcamp170426.zoomcamp.external_yellow_tripdata`;

-- Step 3A: Non-partitioned query (1.55 GB)
SELECT DISTINCT VendorID
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata_non_partitioned`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';

-- Step 3B: Partitioned query (72.81 MB) — 21x reduction
SELECT DISTINCT VendorID
FROM `dezoomcamp170426.zoomcamp.yellow_tripdata`
WHERE DATE(tpep_pickup_datetime) BETWEEN '2019-06-01' AND '2019-06-30';

-- Step 4: Inspect partition distribution
SELECT partition_id, total_rows, total_logical_bytes
FROM `dezoomcamp170426.zoomcamp.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'yellow_tripdata'
ORDER BY total_rows DESC LIMIT 20;