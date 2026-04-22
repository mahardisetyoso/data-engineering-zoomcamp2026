# pipeline.py
import sys
import pandas as pd

month = int(sys.argv[1])

data = {
    "day": [1, 2],
    "passengers": [3, 5],
    "month": [month, month]
}
df = pd.DataFrame(data)
print(df)
df.to_parquet("output.parquet")