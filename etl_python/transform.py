#!/usr/bin/env python3
"""
Pipeline de Transformación y Carga al Data Warehouse (Fase 2 a 5 ETL)
Proyecto: DfT Accidentes BI
Motor: PostgreSQL 16
"""

import os
import sys
from pathlib import Path
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "dft_accidents_dw")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
SQL_SCRIPT_PATH = BASE_DIR / "scripts_sql" / "03_etl_load.sql"


def run_transform():
    if not SQL_SCRIPT_PATH.exists():
        print(f"Error: Script SQL no encontrado en {SQL_SCRIPT_PATH}")
        sys.exit(1)

    print(f"Leyendo script de carga ETL: {SQL_SCRIPT_PATH.name}...")
    with open(SQL_SCRIPT_PATH, "r", encoding="utf-8") as f:
        sql_content = f.read()

    engine = create_engine(DATABASE_URL, isolation_level="AUTOCOMMIT")

    print("Ejecutando transformaciones y carga en esquema DWH...")
    with engine.connect() as conn:
        conn.execute(text(sql_content))
        print("Transformación y carga de dimensiones y tabla de hechos completada.")

        # Conciliación de volumen
        print("\n--- AUDITORÍA DE CONCILIACIÓN ---")
        res_staging = conn.execute(text("SELECT COUNT(*) FROM staging.stg_accident_data;")).scalar()
        res_facts = conn.execute(text("SELECT COUNT(*) FROM dwh.FACT_Accidentes;")).scalar()
        print(f"Total filas en Staging: {res_staging}")
        print(f"Total filas en FACT_Accidentes: {res_facts}")

        # Comprobación de huérfanos
        orphans = conn.execute(text("""
            SELECT 
                COUNT(*) FILTER (WHERE ID_Tiempo = -1) AS t_null,
                COUNT(*) FILTER (WHERE ID_Ubicacion = -1) AS u_null,
                COUNT(*) FILTER (WHERE ID_Vehiculo = -1) AS v_null,
                COUNT(*) FILTER (WHERE ID_Contexto_Siniestro = -1) AS c_null
            FROM dwh.FACT_Accidentes;
        """)).mappings().first()
        print(f"Registros con valores centinela (-1): {dict(orphans)}")


if __name__ == "__main__":
    run_transform()

