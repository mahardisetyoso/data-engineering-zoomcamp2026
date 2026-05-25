from pyspark.sql import SparkSession
spark = SparkSession.builder.master("local[*]").appName("test").getOrCreate()
print(f"Spark version: {spark.version}")
spark.range(10).show()
spark.stop()
