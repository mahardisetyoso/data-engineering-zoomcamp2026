-- =============================================
-- CP1: External Table from GCS — COMPLETED
-- =============================================
-- External table = pointer ke file CSV di GCS, no data copy ke BQ
-- Details panel: tidak ada Table Size / Number of Rows fields
-- 
-- Cost observations:
--   COUNT(*) external  : 9.38 GB scanned (full file read)
--   COUNT(*) native    : 0 B (metadata only - row count in catalog)
--   SELECT * (17 cols) : 50.94 MB / partition
--   SELECT 3 cols      : 9.07 MB / partition (82% reduction = column projection)
-- =============================================

CREATE OR REPLACE EXTERNAL TABLE `dezoomcamp170426.zoomcamp.external_yellow_tripdata`
OPTIONS (
  format = 'CSV',
  uris = [
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2019-*.csv',
    'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2020-*.csv'
  ]
);