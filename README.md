# Solución de Inteligencia de Negocios: Accidentes de Tránsito (DfT)

Arquitectura de Data Warehouse y procesos ETL para el análisis de seguridad vial del Department for Transport (Reino Unido).

## Requisitos Previos

- PostgreSQL 16.x
- Python 3.11+
- Power BI Desktop

## Estructura del Proyecto

```
bi_project_dft/
├── data/
│   ├── raw/             # Archivo accident_data.csv original
│   └── reference/       # Catálogos de homologación (.csv)
├── scripts_sql/
│   ├── 01_staging.sql   # DDL de la zona de staging
│   ├── 02_dwh.sql       # DDL del modelo dimensional (esquema estrella)
│   └── 03_etl_load.sql  # Procedimientos y scripts de transformación y carga
├── etl_python/
│   ├── extract.py       # Ingesta masiva desde CSV hacia staging
│   └── transform.py     # Orquestación de transformación y conciliación
├── bi_dashboards/
│   └── dft_dashboard.pbix # Dashboard táctico en Power BI
├── .env.example         # Plantilla de variables de entorno
├── requirements.txt     # Dependencias de Python
└── README.md
```

## Orden de Ejecución

1. **Configurar entorno:**
   ```bash
   cp .env.example .env
   # Editar .env con tus credenciales de PostgreSQL
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

4. **Ejecutar ETL:**
   ```bash
   python etl_python/extract.py
   python etl_python/transform.py
   ```
   *(Alternativa 100% SQL: ejecutar directamente `scripts_sql/03_etl_load.sql` en pgAdmin / DBeaver tras la ingesta de staging).*

