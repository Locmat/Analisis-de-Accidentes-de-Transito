#!/usr/bin/env python3
"""
Pipeline de Extracción y Carga a Staging (Truncate & Load vía PostgreSQL COPY)
Proyecto: DfT Accidentes BI
Motor: PostgreSQL 16+
"""

import csv
import io
import os
import sys
import time
from pathlib import Path
import psycopg2
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "dft_accidents_dw")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

CSV_PATH = BASE_DIR / "data" / "raw" / "accident_data.csv"
BATCH_SIZE = 50_000

COLUMNS_MAP = {
    "Index": "index_origen",
    "Accident_Severity": "accident_severity",
    "Accident Date": "accident_date",
    "Latitude": "latitude",
    "Light_Conditions": "light_conditions",
    "District Area": "district_area",
    "Longitude": "longitude",
    "Number_of_Casualties": "number_of_casualties",
    "Number_of_Vehicles": "number_of_vehicles",
    "Road_Surface_Conditions": "road_surface_conditions",
    "Road_Type": "road_type",
    "Urban_or_Rural_Area": "urban_or_rural_area",
    "Weather_Conditions": "weather_conditions",
    "Vehicle_Type": "vehicle_type",
}


def flush_batch(cur, copy_sql: str, buf: io.StringIO) -> None:
    buf.seek(0)
    cur.copy_expert(copy_sql, buf)
    buf.seek(0)
    buf.truncate(0)


def run_extract() -> None:
    if not CSV_PATH.exists():
        print(f"Error: Archivo fuente no encontrado en {CSV_PATH}")
        sys.exit(1)

    t0 = time.perf_counter()
    print(f"Iniciando extracción desde {CSV_PATH.name}...")

    target_cols = ["numero_fila", *COLUMNS_MAP.values()]
    copy_sql = (
        f"COPY staging.stg_accident_data ({', '.join(target_cols)}) "
        "FROM STDIN WITH (FORMAT csv)"
    )

    total_loaded = 0
    with psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    ) as conn:
        with conn.cursor() as cur, open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
            print("Vaciando tabla staging.stg_accident_data...")
            cur.execute("TRUNCATE TABLE staging.stg_accident_data;")

            reader = csv.reader(f)
            header = next(reader, None)
            if not header:
                print("Error: El archivo CSV está vacío.")
                sys.exit(1)

            missing = [col for col in COLUMNS_MAP if col not in header]
            if missing:
                print(f"Error: Faltan columnas esperadas en CSV: {missing}")
                sys.exit(1)

            col_indices = [header.index(col) for col in COLUMNS_MAP]
            buf = io.StringIO()
            writer = csv.writer(buf)

            print("Cargando por lotes vía COPY a staging.stg_accident_data...")
            for line_num, row in enumerate(reader, start=2):
                writer.writerow([line_num, *(row[i] for i in col_indices)])
                total_loaded += 1
                if total_loaded % BATCH_SIZE == 0:
                    flush_batch(cur, copy_sql, buf)
                    print(f"  Lote procesado: {total_loaded:,} filas cargadas...")

            if buf.tell() > 0:
                flush_batch(cur, copy_sql, buf)

    elapsed = time.perf_counter() - t0
    print(
        f"Extracción finalizada con éxito en {elapsed:.2f}s. "
        f"Total registros en staging: {total_loaded:,}"
    )


if __name__ == "__main__":
    run_extract()
