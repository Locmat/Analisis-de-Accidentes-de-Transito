#!/usr/bin/env python3
"""
Pipeline de Extracción y Carga a Staging (Truncate & Load)
Proyecto: DfT Accidentes BI
Motor: PostgreSQL 16
"""

import os
import sys
from pathlib import Path
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Cargar variables de entorno
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "dft_accidents_dw")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
CSV_PATH = BASE_DIR / "data" / "raw" / "accident_data.csv"

COLUMNS_MAP = {
    'Index': 'index_origen',
    'Accident_Severity': 'accident_severity',
    'Accident Date': 'accident_date',
    'Latitude': 'latitude',
    'Light_Conditions': 'light_conditions',
    'District Area': 'district_area',
    'Longitude': 'longitude',
    'Number_of_Casualties': 'number_of_casualties',
    'Number_of_Vehicles': 'number_of_vehicles',
    'Road_Surface_Conditions': 'road_surface_conditions',
    'Road_Type': 'road_type',
    'Urban_or_Rural_Area': 'urban_or_rural_area',
    'Weather_Conditions': 'weather_conditions',
    'Vehicle_Type': 'vehicle_type'
}


def run_extract():
    if not CSV_PATH.exists():
        print(f"Error: Archivo fuente no encontrado en {CSV_PATH}")
        sys.exit(1)

    print(f"Iniciando extracción desde {CSV_PATH.name}...")
    engine = create_engine(DATABASE_URL)

    with engine.begin() as conn:
        print("Vaciando tabla staging.stg_accident_data...")
        conn.execute(text("TRUNCATE TABLE staging.stg_accident_data;"))

    chunksize = 50000
    total_loaded = 0

    print("Cargando por lotes a staging.stg_accident_data...")
    for chunk in pd.read_csv(CSV_PATH, dtype=str, chunksize=chunksize, keep_default_na=False):
        chunk = chunk.rename(columns=COLUMNS_MAP)
        chunk = chunk[[col for col in COLUMNS_MAP.values() if col in chunk.columns]]
        chunk.to_sql(
            name="stg_accident_data",
            schema="staging",
            con=engine,
            if_exists="append",
            index=False,
            method="multi"
        )
        total_loaded += len(chunk)
        print(f"  Lote procesado: {total_loaded} filas cargadas...")

    print(f"Extracción finalizada con éxito. Total registros en staging: {total_loaded}")


if __name__ == "__main__":
    run_extract()

