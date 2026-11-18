# Solución de Inteligencia de Negocios: Accidentes de Tránsito (DfT)

Proyecto de Data Warehouse con esquema estrella y proceso ETL para analizar accidentes de tránsito del Department for Transport (Reino Unido) entre 2019 y 2025. La solución utiliza PostgreSQL para las capas de *staging* y DWH, y Python para ejecutar y auditar la carga.

## Requisitos

- PostgreSQL 16 o superior, requerido por `UNIQUE NULLS NOT DISTINCT`.
- Python 3.11 o superior.
- El archivo `data/raw/accident_data.csv` incluido en el proyecto.

## Estructura del proyecto

```text
Analisis-de-Accidentes-de-Transito/
├── data/
│   └── raw/
│       └── accident_data.csv  # Fuente original: 670.679 filas
├── etl_python/
│   ├── extract.py             # Carga del CSV hacia staging mediante COPY
│   └── transform.py           # Transformación, carga y auditoría
├── scripts_sql/
│   ├── 01_staging.sql         # Creación del esquema y tabla de staging
│   ├── 02_dwh.sql             # Creación del modelo dimensional
│   └── 03_etl_load.sql        # Reglas de transformación y carga al DWH
├── .env.example               # Plantilla de conexión a PostgreSQL
├── .gitignore
├── requirements.txt
└── README.md
```

## Componentes implementados en el Avance 2

- **Staging y trazabilidad:** `staging.stg_accident_data` conserva el número de fila original mediante `numero_fila` y registra `fecha_carga`.
- **Modelo dimensional:** esquema estrella compuesto por `FACT_Accidentes`, `DIM_Tiempo`, `DIM_Ubicacion`, `DIM_Vehiculo` y `DIM_Contexto_Siniestro`.
- **Deduplicación exacta:** se eliminan únicamente las filas idénticas en las 14 columnas de negocio. De 670.679 registros se obtienen 670.660 filas únicas, eliminando 19 duplicados.
- **Transformación y homologación:** normalización de fechas, ubicación, vehículos, severidad y condiciones del siniestro.
- **Integridad:** validación de coordenadas, claves foráneas y registros centinela con identificador `-1`.
- **Auditoría:** conciliación automática entre las filas únicas de staging y los registros cargados en la tabla de hechos.

## Configuración en Windows PowerShell

Desde la carpeta raíz del proyecto, ejecutar:

```powershell
Copy-Item .env.example .env
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Editar `.env` e ingresar las credenciales de PostgreSQL:

```dotenv
DB_HOST=localhost
DB_PORT=5432
DB_NAME=dft_accidents_dw
DB_USER=postgres
DB_PASSWORD=tu_password
```

El archivo `.env` contiene información local y no debe subirse al repositorio.

## Orden de ejecución

### 1. Crear la base de datos

Ejecutar en PostgreSQL o pgAdmin:

```sql
CREATE DATABASE dft_accidents_dw;
```

### 2. Crear staging y el Data Warehouse

Conectarse a `dft_accidents_dw` y ejecutar, en este orden:

1. `scripts_sql/01_staging.sql`
2. `scripts_sql/02_dwh.sql`

Estos scripts eliminan y vuelven a crear las tablas correspondientes, por lo que reemplazan cualquier contenido anterior.

### 3. Ejecutar la extracción

```powershell
.\.venv\Scripts\python.exe .\etl_python\extract.py
```

Este proceso vacía `staging.stg_accident_data` y carga las 670.679 filas de `accident_data.csv`.

### 4. Ejecutar la transformación, carga y auditoría

```powershell
.\.venv\Scripts\python.exe .\etl_python\transform.py
```

El proceso ejecuta `scripts_sql/03_etl_load.sql`, reconstruye el contenido del modelo dimensional y muestra la conciliación final en consola.

## Resultado esperado

| Objeto | Registros esperados |
|---|---:|
| `staging.stg_accident_data` | 670.679 |
| `dwh.DIM_Tiempo` | 2.558 |
| `dwh.DIM_Ubicacion` | 582.091 |
| `dwh.DIM_Vehiculo` | 16 |
| `dwh.DIM_Contexto_Siniestro` | 1.470 |
| `dwh.FACT_Accidentes` | 670.660 |

La ejecución correcta debe finalizar con cero claves foráneas huérfanas y el mensaje `Estado conciliación : OK`.

## Ejecución alternativa de la transformación

Después de ejecutar `extract.py`, también es posible ejecutar directamente `scripts_sql/03_etl_load.sql` desde PostgreSQL. Esta alternativa realiza la transformación y carga, pero no imprime el reporte de auditoría generado por `transform.py`.
