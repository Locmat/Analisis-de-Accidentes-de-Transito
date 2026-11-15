# Solución de Inteligencia de Negocios: Accidentes de Tránsito (DfT)

Arquitectura de Data Warehouse (esquema estrella) y procesos ETL en PostgreSQL + Python para el análisis de seguridad vial del Department for Transport (Reino Unido, 2019–2025).

## Requisitos Previos

- PostgreSQL 16+ (requerido por `UNIQUE NULLS NOT DISTINCT`)
- Python 3.11+

## Estructura del Proyecto

```
Analisis-de-Accidentes-de-Transito/
├── data/
│   ├── raw/             # Archivo accident_data.csv original (670,679 filas)
│   └── reference/       # Catálogos de homologación y calendario UK (.csv)
├── scripts_sql/
│   ├── 01_staging.sql   # DDL de staging con trazabilidad numero_fila y fecha_carga
│   ├── 02_dwh.sql       # DDL del esquema estrella (dwh.*)
│   └── 03_etl_load.sql  # Transformación, deduplicación exacta y carga al DWH
├── etl_python/
│   ├── extract.py       # Ingesta rápida vía PostgreSQL COPY hacia staging
│   └── transform.py     # Orquestación SQL y reporte de auditoría/conciliación
├── .env.example         # Plantilla de variables de entorno
├── requirements.txt     # Dependencias de Python
└── README.md
```

## Reglas Clave Implementadas (Avance 1)

- **Trazabilidad en Staging:** `staging.stg_accident_data` conserva `numero_fila` (línea física `2..670680` de `accident_data.csv`) y `fecha_carga`, sin alterar el grano ni las columnas del modelo `dwh`.
- **Deduplicación exacta:** `03_etl_load.sql` descarta únicamente filas idénticas en las 14 columnas de negocio (`670,679` -> `670,660`, eliminando `19` duplicados exactos) sin filtrar por `Index` repetido.
- **Geografía (`DIM_Ubicacion`):** `UNIQUE NULLS NOT DISTINCT (Distrito_Area, Area_Urbana, Latitud, Longitud)` y validación explícita de rangos (`Latitud` `[-90, 90]`, `Longitud` `[-180, 180]`).
- **Tiempo (`DIM_Tiempo`):** Festividades y Bank Holidays del Reino Unido (`Año Nuevo`, `Halloween`, `Guy Fawkes Night`, `Navidad`, `Boxing Day`, etc.) y `'Sin festividad'` por defecto.

## Orden de Ejecución

1. **Configurar entorno:**
   ```bash
   cp .env.example .env
   # Editar .env con credenciales de PostgreSQL
   python -m venv venv
   source venv/bin/activate  # En Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Crear base de datos en PostgreSQL:**
   ```sql
   CREATE DATABASE dft_accidents_dw;
   ```

3. **Ejecutar DDL:**
   - Ejecutar `scripts_sql/01_staging.sql` en `dft_accidents_dw`.
   - Ejecutar `scripts_sql/02_dwh.sql` en `dft_accidents_dw`.

4. **Ejecutar ETL y Auditoría:**
   ```bash
   python etl_python/extract.py
   python etl_python/transform.py
   ```
   *(Alternativa SQL directa para transformación: ejecutar `scripts_sql/03_etl_load.sql` tras `extract.py`).*
