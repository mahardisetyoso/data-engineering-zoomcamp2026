import argparse
from pyspark.sql import SparkSession, types
from pyspark.sql import functions as F

parser = argparse.ArgumentParser()
parser.add_argument('--input_green', required=True)
parser.add_argument('--input_yellow', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()

spark = SparkSession.builder.appName("green-yellow-revenue").getOrCreate()

df_green = spark.read.option("header", "true").csv(args.input_green)
df_yellow = spark.read.option("header", "true").csv(args.input_yellow)

# Rename timestamp columns
df_green = df_green \
    .withColumnRenamed("lpep_pickup_datetime", "pickup_datetime") \
    .withColumnRenamed("lpep_dropoff_datetime", "dropoff_datetime")
df_yellow = df_yellow \
    .withColumnRenamed("tpep_pickup_datetime", "pickup_datetime") \
    .withColumnRenamed("tpep_dropoff_datetime", "dropoff_datetime")

# Common columns + service_type
common_cols = [c for c in df_green.columns if c in df_yellow.columns]
df_green_sel = df_green.select(common_cols).withColumn("service_type", F.lit("green"))
df_yellow_sel = df_yellow.select(common_cols).withColumn("service_type", F.lit("yellow"))

df_trips = df_green_sel.unionAll(df_yellow_sel)
df_trips.createOrReplaceTempView("trips_data")

df_result = spark.sql("""
SELECT
    PULocationID AS revenue_zone,
    date_trunc('month', CAST(pickup_datetime AS TIMESTAMP)) AS revenue_month,
    service_type,
    SUM(CAST(total_amount AS DOUBLE)) AS revenue_monthly_total,
    COUNT(*) AS total_trips
FROM trips_data
WHERE pickup_datetime IS NOT NULL
GROUP BY 1, 2, 3
""")

df_result.coalesce(1).write.parquet(args.output, mode="overwrite")
print(f"Done. Output written to {args.output}")
spark.stop()
