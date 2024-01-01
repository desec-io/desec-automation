#!python3

import desec

def float_format(fl):
    return f"{fl:.0f}"

print("Querying...")
data = desec.replication_status()
print(desec.replication_lag(data).to_string(float_format=float_format, na_rep='???'))
