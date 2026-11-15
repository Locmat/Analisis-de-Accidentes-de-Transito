#!/usr/bin/env python3
"""
Pipeline de Transformación, Carga al DWH y Auditoría de Conciliación
Proyecto: DfT Accidentes BI
Motor: PostgreSQL 16+
"""

import os
import sys
import time
from pathlib import Path
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "dft_accidents_dw")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

SQL_SCRIPT_PATH = BASE_DIR / "scripts_sql" / "03_etl_load.sql"

BUSINESS_COLS = (
    "index_origen, accident_severity, accident_date, latitude, light_conditions, "
    "district_area, longitude, number_of_casualties, number_of_vehicles, "
    "road_surface_conditions, road_type, urban_or_rural_area, weather_conditions, vehicle_type"
)


def run_transform() -> None:
    if not SQL_SCRIPT_PATH.exists():
        print(f"Error: Script SQL no encontrado en {SQL_SCRIPT_PATH}")
        sys.exit(1)

    sql_content = SQL_SCRIPT_PATH.read_text(encoding="utf-8")

    with psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    ) as conn:
        t0 = time.perf_counter()
        print(f"Ejecutando {SQL_SCRIPT_PATH.name} en esquema DWH...")
        with conn.cursor() as cur:
            cur.execute(sql_content)
        elapsed = time.perf_counter() - t0
        print(f"Transformación y carga completada en {elapsed:.2f}s.\n")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT
                    COUNT(*) AS staging_rows,
                    MIN(numero_fila) AS min_fila,
                    MAX(numero_fila) AS max_fila
                FROM staging.stg_accident_data;
            """)
            stg_stats = cur.fetchone()

            cur.execute(f"""
                SELECT COUNT(*) AS unique_rows
                FROM (SELECT DISTINCT {BUSINESS_COLS} FROM staging.stg_accident_data) t;
            """)
            unique_rows = cur.fetchone()["unique_rows"]

            cur.execute("""
                SELECT
                    (SELECT COUNT(*) FROM dwh.DIM_Tiempo) AS dim_tiempo,
                    (SELECT COUNT(*) FROM dwh.DIM_Ubicacion) AS dim_ubicacion,
                    (SELECT COUNT(*) FROM dwh.DIM_Vehiculo) AS dim_vehiculo,
                    (SELECT COUNT(*) FROM dwh.DIM_Contexto_Siniestro) AS dim_contexto_siniestro;
            """)
            dim_counts = cur.fetchone()

            cur.execute("""
                SELECT
                    COUNT(*) AS fact_rows,
                    COALESCE(SUM(Cantidad_Accidentes), 0) AS total_accidentes,
                    COALESCE(SUM(Cantidad_Victimas), 0) AS total_victimas,
                    COALESCE(SUM(Cantidad_Vehiculos), 0) AS total_vehiculos,
                    COUNT(*) FILTER (WHERE ID_Tiempo = -1) AS centinela_tiempo,
                    COUNT(*) FILTER (WHERE ID_Ubicacion = -1) AS centinela_ubicacion,
                    COUNT(*) FILTER (WHERE ID_Vehiculo = -1) AS centinela_vehiculo,
                    COUNT(*) FILTER (WHERE ID_Contexto_Siniestro = -1) AS centinela_contexto
                FROM dwh.FACT_Accidentes;
            """)
            fact_stats = cur.fetchone()

            cur.execute("""
                SELECT COUNT(*) AS real_orphans
                FROM dwh.FACT_Accidentes f
                LEFT JOIN dwh.DIM_Tiempo dt ON dt.ID_Tiempo = f.ID_Tiempo
                LEFT JOIN dwh.DIM_Ubicacion du ON du.ID_Ubicacion = f.ID_Ubicacion
                LEFT JOIN dwh.DIM_Vehiculo dv ON dv.ID_Vehiculo = f.ID_Vehiculo
                LEFT JOIN dwh.DIM_Contexto_Siniestro dc ON dc.ID_Contexto_Siniestro = f.ID_Contexto_Siniestro
                WHERE dt.ID_Tiempo IS NULL
                   OR du.ID_Ubicacion IS NULL
                   OR dv.ID_Vehiculo IS NULL
                   OR dc.ID_Contexto_Siniestro IS NULL;
            """)
            real_orphans = cur.fetchone()["real_orphans"]

            cur.execute("""
                SELECT COUNT(*) AS invalid_holidays
                FROM dwh.DIM_Tiempo
                WHERE Festividad IN ('Fin de Semana', 'Día Hábil');
            """)
            invalid_holidays = cur.fetchone()["invalid_holidays"]

    stg_rows = stg_stats["staging_rows"]
    dup_exact = stg_rows - unique_rows
    fact_rows = fact_stats["fact_rows"]
    reconciled = (fact_rows == unique_rows) and (real_orphans == 0) and (invalid_holidays == 0)

    print("=== ESTADÍSTICAS DE PROCESAMIENTO Y AUDITORÍA (AVANCE 2) ===")
    print(f"Tiempo de transformación y carga : {elapsed:.2f}s")
    print(
        f"Staging (stg_accident_data)      : {stg_rows:,} filas "
        f"(trazabilidad numero_fila: {stg_stats['min_fila']}..{stg_stats['max_fila']})"
    )
    print(f"Duplicados exactos eliminados    : {dup_exact:,} (criterio: 14 columnas idénticas)")
    print(f"Filas únicas esperadas           : {unique_rows:,}")
    print(f"FACT_Accidentes cargadas         : {fact_rows:,}")
    print("\n--- Dimensiones (incluye registro centinela -1) ---")
    print(f"DIM_Tiempo                       : {dim_counts['dim_tiempo']:,}")
    print(f"DIM_Ubicacion                    : {dim_counts['dim_ubicacion']:,}")
    print(f"DIM_Vehiculo                     : {dim_counts['dim_vehiculo']:,}")
    print(f"DIM_Contexto_Siniestro           : {dim_counts['dim_contexto_siniestro']:,}")
    print("\n--- Métricas Aditivas Totales ---")
    print(f"Cantidad_Accidentes              : {fact_stats['total_accidentes']:,}")
    print(f"Cantidad_Victimas                : {fact_stats['total_victimas']:,}")
    print(f"Cantidad_Vehiculos               : {fact_stats['total_vehiculos']:,}")
    print("\n--- Integridad Referencial y Centinelas (-1) ---")
    print(
        f"Centinelas (-1) en FACT          : tiempo={fact_stats['centinela_tiempo']}, "
        f"ubicacion={fact_stats['centinela_ubicacion']}, "
        f"vehiculo={fact_stats['centinela_vehiculo']}, "
        f"contexto={fact_stats['centinela_contexto']}"
    )
    print(f"Huérfanos reales (FK sin match)  : {real_orphans}")
    print(f"Estado conciliación              : {'OK' if reconciled else 'FALLÓ'}")

    if not reconciled:
        sys.exit(1)


if __name__ == "__main__":
    run_transform()
