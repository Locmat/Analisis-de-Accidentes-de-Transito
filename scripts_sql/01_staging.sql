-- =============================================================================
-- PROYECTO BI: Department for Transport (DfT) - Seguridad Vial
-- SCRIPT 01: Creación de Esquema y Tabla de Staging
-- Motor: PostgreSQL 16
-- Objetivo: Área de aterrizaje temporal con tipos genéricos tolerantes a fallos.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;

DROP TABLE IF EXISTS staging.stg_accident_data;

CREATE TABLE staging.stg_accident_data (
    index_origen             VARCHAR(100),
    accident_severity        VARCHAR(100),
    accident_date            VARCHAR(50),
    latitude                 VARCHAR(100),
    light_conditions         VARCHAR(150),
    district_area            VARCHAR(150),
    longitude                VARCHAR(100),
    number_of_casualties     VARCHAR(50),
    number_of_vehicles       VARCHAR(50),
    road_surface_conditions  VARCHAR(150),
    road_type                VARCHAR(150),
    urban_or_rural_area      VARCHAR(100),
    weather_conditions       VARCHAR(150),
    vehicle_type             VARCHAR(150),
    fecha_carga              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON SCHEMA staging IS 'Zona de aterrizaje temporal para datos crudos sin restricciones de integridad.';
COMMENT ON TABLE staging.stg_accident_data IS 'Copia fiel de accident_data.csv en formato texto para prevenir fallos en ingesta masiva.';

