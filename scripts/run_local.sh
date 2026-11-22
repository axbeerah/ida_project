#!/usr/bin/env bash
# Run the whole pipeline WITHOUT Docker (Linux / macOS / WSL, Python 3.12).
# Usage:  bash scripts/run_local.sh            # normal run
#         bash scripts/run_local.sh 2          # also write a 2x oversampled sales table to sandbox
set -euo pipefail
cd "$(dirname "$0")/.."
FACTOR="${1:-1}"

if [ ! -d .venv ]; then
  python3.12 -m venv .venv
  .venv/bin/pip install -q "apache-airflow==2.10.5" \
    --constraint https://raw.githubusercontent.com/apache/airflow/constraints-2.10.5/constraints-3.12.txt
  .venv/bin/pip install -q -r requirements.txt
fi

export AIRFLOW_HOME="$PWD/airflow_home"
export AIRFLOW__CORE__DAGS_FOLDER="$PWD/dags"
export AIRFLOW__CORE__LOAD_EXAMPLES=False
.venv/bin/airflow db migrate > /dev/null
.venv/bin/airflow dags test pharma_sdi_data_mart "$(date +%F)" -c "{\"oversample_factor\": $FACTOR}"
echo "Done. Warehouse: warehouse/pharma_sdi.duckdb   Query-layer exports: exports/"
