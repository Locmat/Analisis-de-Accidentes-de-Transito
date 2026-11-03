-- =============================================================================
-- PROYECTO BI: Department for Transport (DfT) - Seguridad Vial
-- SCRIPT 03: Procedimientos y Scripts de Transformación y Carga (ETL)
-- Motor: PostgreSQL 16
-- =============================================================================

-- =============================================================================
-- PASO 1: Poblamiento de DIM_Tiempo (2019-01-01 a 2025-12-31)
-- =============================================================================
TRUNCATE TABLE dwh.DIM_Tiempo CASCADE;

-- Registro centinela para fechas no especificadas
INSERT INTO dwh.DIM_Tiempo (ID_Tiempo, Fecha, Anio, Mes, Dia, Dia_Semana, Festividad)
VALUES (-1, '1900-01-01', 1900, 1, 1, 'N/A', 'Sin información')
ON CONFLICT (ID_Tiempo) DO NOTHING;

-- Generación de serie temporal completa
INSERT INTO dwh.DIM_Tiempo (ID_Tiempo, Fecha, Anio, Mes, Dia, Dia_Semana, Festividad)
SELECT 
    TO_CHAR(d, 'YYYYMMDD')::INT AS ID_Tiempo,
    d::DATE AS Fecha,
    EXTRACT(YEAR FROM d)::INT AS Anio,
    EXTRACT(MONTH FROM d)::INT AS Mes,
    EXTRACT(DAY FROM d)::INT AS Dia,
    CASE EXTRACT(ISODOW FROM d)
        WHEN 1 THEN 'Lunes'
        WHEN 2 THEN 'Martes'
        WHEN 3 THEN 'Miércoles'
        WHEN 4 THEN 'Jueves'
        WHEN 5 THEN 'Viernes'
        WHEN 6 THEN 'Sábado'
        WHEN 7 THEN 'Domingo'
    END AS Dia_Semana,
    CASE 
        WHEN EXTRACT(MONTH FROM d) = 1 AND EXTRACT(DAY FROM d) = 1 THEN 'Año Nuevo'
        WHEN EXTRACT(MONTH FROM d) = 12 AND EXTRACT(DAY FROM d) = 25 THEN 'Navidad'
        WHEN EXTRACT(MONTH FROM d) = 12 AND EXTRACT(DAY FROM d) = 26 THEN 'Boxing Day'
        WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'Fin de Semana'
        ELSE 'Día Hábil'
    END AS Festividad
FROM generate_series('2019-01-01'::DATE, '2025-12-31'::DATE, '1 day'::INTERVAL) AS d
ON CONFLICT (ID_Tiempo) DO NOTHING;

-- =============================================================================
-- PASO 2: Registros Centinela (Valores por defecto para datos faltantes)
-- =============================================================================
INSERT INTO dwh.DIM_Ubicacion (ID_Ubicacion, Distrito_Area, Area_Urbana, Latitud, Longitud)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'Sin información', 'Sin información', NULL, NULL)
ON CONFLICT DO NOTHING;

INSERT INTO dwh.DIM_Vehiculo (ID_Vehiculo, Categoria_Vehiculo, Tipo_Vehiculo)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'No Especificado', 'Sin información')
ON CONFLICT DO NOTHING;

INSERT INTO dwh.DIM_Contexto_Siniestro (ID_Contexto_Siniestro, Condicion_Luz, Condicion_Clima, Condicion_Superficie, Tipo_Calzada, Severidad)
OVERRIDING SYSTEM VALUE
VALUES (-1, 'No Registrado', 'No Registrado', 'No Especificado', 'No Especificado', 'Sin información')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- PASO 3: Poblamiento de DIM_Ubicacion desde Staging
-- =============================================================================
INSERT INTO dwh.DIM_Ubicacion (Distrito_Area, Area_Urbana, Latitud, Longitud)
SELECT DISTINCT
    COALESCE(NULLIF(TRIM(district_area), ''), 'Sin información') AS Distrito_Area,
    CASE 
        WHEN urban_or_rural_area ILIKE 'Urban' THEN 'Urbano'
        WHEN urban_or_rural_area ILIKE 'Rural' THEN 'Rural'
        ELSE 'Sin información'
    END AS Area_Urbana,
    CASE 
        WHEN latitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN latitude::DECIMAL(10,6)
        ELSE NULL
    END AS Latitud,
    CASE 
        WHEN longitude ~ '^-?[0-9]+(\.[0-9]+)?$' THEN longitude::DECIMAL(10,6)
        ELSE NULL
    END AS Longitud
FROM staging.stg_accident_data
WHERE district_area IS NOT NULL
ON CONFLICT (Distrito_Area, Area_Urbana, Latitud, Longitud) DO NOTHING;

-- =============================================================================
-- PASO 4: Poblamiento de DIM_Vehiculo con Reglas de Homologación
-- =============================================================================
INSERT INTO dwh.DIM_Vehiculo (Categoria_Vehiculo, Tipo_Vehiculo)
SELECT DISTINCT
    CASE 
        WHEN vehicle_type = 'Car' THEN 'Particular'
        WHEN vehicle_type IN ('Taxi/Private hire car', 'Bus or coach (17 or more pass seats)', 'Minibus (8 - 16 passenger seats)') THEN 'Público'
        WHEN vehicle_type IN ('Van / Goods 3.5 tonnes mgw or under', 'Goods over 3.5t. and under 7.5t', 'Goods 7.5 tonnes mgw and over') THEN 'Carga'
        WHEN vehicle_type LIKE 'Motorcycle%' THEN 'Motos'
        WHEN vehicle_type IN ('Pedal cycle', 'Ridden horse') THEN 'No motorizado'
        WHEN vehicle_type = 'Agricultural vehicle' THEN 'Especial / Agrícola'
        WHEN vehicle_type = 'Other vehicle' THEN 'Otro'
        ELSE 'No Especificado'
    END AS Categoria_Vehiculo,
    CASE 
        WHEN vehicle_type = 'Car' THEN 'Automóvil'
        WHEN vehicle_type = 'Taxi/Private hire car' THEN 'Taxi / Transporte privado'
        WHEN vehicle_type = 'Bus or coach (17 or more pass seats)' THEN 'Autobús / Microbús'
        WHEN vehicle_type = 'Minibus (8 - 16 passenger seats)' THEN 'Minibús'
        WHEN vehicle_type = 'Van / Goods 3.5 tonnes mgw or under' THEN 'Furgón / Camioneta hasta 3.5t'
        WHEN vehicle_type = 'Goods over 3.5t. and under 7.5t' THEN 'Camión mediano (3.5t a 7.5t)'
        WHEN vehicle_type = 'Goods 7.5 tonnes mgw and over' THEN 'Camión pesado (7.5t o más)'
        WHEN vehicle_type = 'Agricultural vehicle' THEN 'Vehículo agrícola'
        WHEN vehicle_type = 'Motorcycle 50cc and under' THEN 'Motocicleta hasta 50cc'
        WHEN vehicle_type = 'Motorcycle 125cc and under' THEN 'Motocicleta hasta 125cc'
        WHEN vehicle_type = 'Motorcycle over 125cc and up to 500cc' THEN 'Motocicleta 125cc a 500cc'
        WHEN vehicle_type = 'Motorcycle over 500cc' THEN 'Motocicleta sobre 500cc'
        WHEN vehicle_type = 'Pedal cycle' THEN 'Bicicleta'
        WHEN vehicle_type = 'Ridden horse' THEN 'Tracción animal'
        WHEN vehicle_type = 'Other vehicle' THEN 'Otro vehículo'
        ELSE 'Sin información'
    END AS Tipo_Vehiculo
FROM staging.stg_accident_data
ON CONFLICT (Categoria_Vehiculo, Tipo_Vehiculo) DO NOTHING;

-- =============================================================================
-- PASO 5: Poblamiento de DIM_Contexto_Siniestro (Junk Dimension)
-- =============================================================================
INSERT INTO dwh.DIM_Contexto_Siniestro (Condicion_Luz, Condicion_Clima, Condicion_Superficie, Tipo_Calzada, Severidad)
SELECT DISTINCT
    CASE 
        WHEN light_conditions = 'Daylight' THEN 'Luz de día'
        WHEN light_conditions = 'Darkness - lights lit' THEN 'Oscuridad con alumbrado encendido'
        WHEN light_conditions = 'Darkness - lights unlit' THEN 'Oscuridad con alumbrado apagado'
        WHEN light_conditions = 'Darkness - no lighting' THEN 'Oscuridad sin alumbrado'
        WHEN light_conditions = 'Darkness - lighting unknown' THEN 'Oscuridad con alumbrado desconocido'
        ELSE 'No Registrado'
    END AS Condicion_Luz,
    CASE 
        WHEN weather_conditions = 'Fine no high winds' THEN 'Despejado sin viento fuerte'
        WHEN weather_conditions = 'Fine + high winds' THEN 'Despejado con viento fuerte'
        WHEN weather_conditions = 'Raining no high winds' THEN 'Lluvia sin viento fuerte'
        WHEN weather_conditions = 'Raining + high winds' THEN 'Lluvia con viento fuerte'
        WHEN weather_conditions = 'Snowing no high winds' THEN 'Nieve sin viento fuerte'
        WHEN weather_conditions = 'Snowing + high winds' THEN 'Nieve con viento fuerte'
        WHEN weather_conditions = 'Fog or mist' THEN 'Niebla o neblina'
        WHEN weather_conditions = 'Other' THEN 'Otro'
        ELSE 'No Registrado'
    END AS Condicion_Clima,
    CASE 
        WHEN road_surface_conditions = 'Dry' THEN 'Seca'
        WHEN road_surface_conditions = 'Wet or damp' THEN 'Mojada o húmeda'
        WHEN road_surface_conditions = 'Snow' THEN 'Nieve'
        WHEN road_surface_conditions = 'Frost or ice' THEN 'Escarcha o hielo'
        WHEN road_surface_conditions = 'Flood over 3cm. deep' THEN 'Inundación (más de 3 cm)'
        ELSE 'No Especificado'
    END AS Condicion_Superficie,
    CASE 
        WHEN road_type = 'Single carriageway' THEN 'Calzada simple'
        WHEN road_type = 'Dual carriageway' THEN 'Calzada doble'
        WHEN road_type = 'Roundabout' THEN 'Rotonda'
        WHEN road_type = 'One way street' THEN 'Calle de un solo sentido'
        WHEN road_type = 'Slip road' THEN 'Vía de incorporación'
        ELSE 'No Especificado'
    END AS Tipo_Calzada,
    CASE 
        WHEN accident_severity = 'Slight' THEN 'Leve'
        WHEN accident_severity = 'Serious' THEN 'Grave'
        WHEN accident_severity = 'Fatal' THEN 'Fatal'
        ELSE 'Sin información'
    END AS Severidad
FROM staging.stg_accident_data
ON CONFLICT (Condicion_Luz, Condicion_Clima, Condicion_Superficie, Tipo_Calzada, Severidad) DO NOTHING;

-- =============================================================================
-- PASO 6: Carga de FACT_Accidentes (Transform & Load)
-- =============================================================================
TRUNCATE TABLE dwh.FACT_Accidentes;

INSERT INTO dwh.FACT_Accidentes (
    ID_Tiempo,
    ID_Ubicacion,
    ID_Vehiculo,
    ID_Contexto_Siniestro,
    Cantidad_Accidentes,
    Cantidad_Victimas,
    Cantidad_Vehiculos
)
SELECT 
    COALESCE(dt.ID_Tiempo, -1) AS ID_Tiempo,
    COALESCE(du.ID_Ubicacion, -1) AS ID_Ubicacion,
    COALESCE(dv.ID_Vehiculo, -1) AS ID_Vehiculo,
    COALESCE(dc.ID_Contexto_Siniestro, -1) AS ID_Contexto_Siniestro,
    1 AS Cantidad_Accidentes,
    GREATEST(0, COALESCE(NULLIF(TRIM(stg.number_of_casualties), '')::INT, 0)) AS Cantidad_Victimas,
    GREATEST(1, COALESCE(NULLIF(TRIM(stg.number_of_vehicles), '')::INT, 1)) AS Cantidad_Vehiculos
FROM staging.stg_accident_data stg

-- Lookup DIM_Tiempo
LEFT JOIN dwh.DIM_Tiempo dt 
    ON dt.Fecha = TO_DATE(stg.accident_date, 'DD-MM-YYYY')

-- Lookup DIM_Ubicacion
LEFT JOIN dwh.DIM_Ubicacion du
    ON du.Distrito_Area = COALESCE(NULLIF(TRIM(stg.district_area), ''), 'Sin información')
    AND du.Area_Urbana = (CASE 
                            WHEN stg.urban_or_rural_area ILIKE 'Urban' THEN 'Urbano'
                            WHEN stg.urban_or_rural_area ILIKE 'Rural' THEN 'Rural'
                            ELSE 'Sin información'
                         END)
    AND (
        (du.Latitud = stg.latitude::DECIMAL(10,6) AND du.Longitud = stg.longitude::DECIMAL(10,6))
        OR (du.Latitud IS NULL AND stg.latitude IS NULL)
    )

-- Lookup DIM_Vehiculo
LEFT JOIN dwh.DIM_Vehiculo dv
    ON dv.Categoria_Vehiculo = (
        CASE 
            WHEN stg.vehicle_type = 'Car' THEN 'Particular'
            WHEN stg.vehicle_type IN ('Taxi/Private hire car', 'Bus or coach (17 or more pass seats)', 'Minibus (8 - 16 passenger seats)') THEN 'Público'
            WHEN stg.vehicle_type IN ('Van / Goods 3.5 tonnes mgw or under', 'Goods over 3.5t. and under 7.5t', 'Goods 7.5 tonnes mgw and over') THEN 'Carga'
            WHEN stg.vehicle_type LIKE 'Motorcycle%' THEN 'Motos'
            WHEN stg.vehicle_type IN ('Pedal cycle', 'Ridden horse') THEN 'No motorizado'
            WHEN stg.vehicle_type = 'Agricultural vehicle' THEN 'Especial / Agrícola'
            WHEN stg.vehicle_type = 'Other vehicle' THEN 'Otro'
            ELSE 'No Especificado'
        END
    )
    AND dv.Tipo_Vehiculo = (
        CASE 
            WHEN stg.vehicle_type = 'Car' THEN 'Automóvil'
            WHEN stg.vehicle_type = 'Taxi/Private hire car' THEN 'Taxi / Transporte privado'
            WHEN stg.vehicle_type = 'Bus or coach (17 or more pass seats)' THEN 'Autobús / Microbús'
            WHEN stg.vehicle_type = 'Minibus (8 - 16 passenger seats)' THEN 'Minibús'
            WHEN stg.vehicle_type = 'Van / Goods 3.5 tonnes mgw or under' THEN 'Furgón / Camioneta hasta 3.5t'
            WHEN stg.vehicle_type = 'Goods over 3.5t. and under 7.5t' THEN 'Camión mediano (3.5t a 7.5t)'
            WHEN stg.vehicle_type = 'Goods 7.5 tonnes mgw and over' THEN 'Camión pesado (7.5t o más)'
            WHEN stg.vehicle_type = 'Agricultural vehicle' THEN 'Vehículo agrícola'
            WHEN stg.vehicle_type = 'Motorcycle 50cc and under' THEN 'Motocicleta hasta 50cc'
            WHEN stg.vehicle_type = 'Motorcycle 125cc and under' THEN 'Motocicleta hasta 125cc'
            WHEN stg.vehicle_type = 'Motorcycle over 125cc and up to 500cc' THEN 'Motocicleta 125cc a 500cc'
            WHEN stg.vehicle_type = 'Motorcycle over 500cc' THEN 'Motocicleta sobre 500cc'
            WHEN stg.vehicle_type = 'Pedal cycle' THEN 'Bicicleta'
            WHEN stg.vehicle_type = 'Ridden horse' THEN 'Tracción animal'
            WHEN stg.vehicle_type = 'Other vehicle' THEN 'Otro vehículo'
            ELSE 'Sin información'
        END
    )

-- Lookup DIM_Contexto_Siniestro
LEFT JOIN dwh.DIM_Contexto_Siniestro dc
    ON dc.Condicion_Luz = (
        CASE 
            WHEN stg.light_conditions = 'Daylight' THEN 'Luz de día'
            WHEN stg.light_conditions = 'Darkness - lights lit' THEN 'Oscuridad con alumbrado encendido'
            WHEN stg.light_conditions = 'Darkness - lights unlit' THEN 'Oscuridad con alumbrado apagado'
            WHEN stg.light_conditions = 'Darkness - no lighting' THEN 'Oscuridad sin alumbrado'
            WHEN stg.light_conditions = 'Darkness - lighting unknown' THEN 'Oscuridad con alumbrado desconocido'
            ELSE 'No Registrado'
        END
    )
    AND dc.Condicion_Clima = (
        CASE 
            WHEN stg.weather_conditions = 'Fine no high winds' THEN 'Despejado sin viento fuerte'
            WHEN stg.weather_conditions = 'Fine + high winds' THEN 'Despejado con viento fuerte'
            WHEN stg.weather_conditions = 'Raining no high winds' THEN 'Lluvia sin viento fuerte'
            WHEN stg.weather_conditions = 'Raining + high winds' THEN 'Lluvia con viento fuerte'
            WHEN stg.weather_conditions = 'Snowing no high winds' THEN 'Nieve sin viento fuerte'
            WHEN stg.weather_conditions = 'Snowing + high winds' THEN 'Nieve con viento fuerte'
            WHEN stg.weather_conditions = 'Fog or mist' THEN 'Niebla o neblina'
            WHEN stg.weather_conditions = 'Other' THEN 'Otro'
            ELSE 'No Registrado'
        END
    )
    AND dc.Condicion_Superficie = (
        CASE 
            WHEN stg.road_surface_conditions = 'Dry' THEN 'Seca'
            WHEN stg.road_surface_conditions = 'Wet or damp' THEN 'Mojada o húmeda'
            WHEN stg.road_surface_conditions = 'Snow' THEN 'Nieve'
            WHEN stg.road_surface_conditions = 'Frost or ice' THEN 'Escarcha o hielo'
            WHEN stg.road_surface_conditions = 'Flood over 3cm. deep' THEN 'Inundación (más de 3 cm)'
            ELSE 'No Especificado'
        END
    )
    AND dc.Tipo_Calzada = (
        CASE 
            WHEN stg.road_type = 'Single carriageway' THEN 'Calzada simple'
            WHEN stg.road_type = 'Dual carriageway' THEN 'Calzada doble'
            WHEN stg.road_type = 'Roundabout' THEN 'Rotonda'
            WHEN stg.road_type = 'One way street' THEN 'Calle de un solo sentido'
            WHEN stg.road_type = 'Slip road' THEN 'Vía de incorporación'
            ELSE 'No Especificado'
        END
    )
    AND dc.Severidad = (
        CASE 
            WHEN stg.accident_severity = 'Slight' THEN 'Leve'
            WHEN stg.accident_severity = 'Serious' THEN 'Grave'
            WHEN stg.accident_severity = 'Fatal' THEN 'Fatal'
            ELSE 'Sin información'
        END
    );

-- =============================================================================
-- PASO 7: Validaciones y Auditoría de Conciliación
-- =============================================================================
SELECT 'staging.stg_accident_data' AS tabla, COUNT(*) AS total_registros FROM staging.stg_accident_data
UNION ALL
SELECT 'dwh.FACT_Accidentes' AS tabla, COUNT(*) AS total_registros FROM dwh.FACT_Accidentes;

-- Verificación de claves foráneas huérfanas (debe retornar 0 en todas)
SELECT 
    COUNT(*) FILTER (WHERE ID_Tiempo = -1) AS huerfanos_tiempo,
    COUNT(*) FILTER (WHERE ID_Ubicacion = -1) AS huerfanos_ubicacion,
    COUNT(*) FILTER (WHERE ID_Vehiculo = -1) AS huerfanos_vehiculo,
    COUNT(*) FILTER (WHERE ID_Contexto_Siniestro = -1) AS huerfanos_contexto
FROM dwh.FACT_Accidentes;

