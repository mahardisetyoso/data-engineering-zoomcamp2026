-- =============================================
   -- CP1: External Table from GCS
   -- =============================================
   CREATE OR REPLACE EXTERNAL TABLE `dezoomcamp170426.zoomcamp.external_yellow_tripdata`
   OPTIONS (
     format = 'CSV',
     uris = [
       'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2019-*.csv',
       'gs://mahardi-dezoomcamp-kestra/yellow_tripdata_2020-*.csv'
     ]
   );