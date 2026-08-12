-- Seed del catálogo de Cold Day (data-driven, v2 - flujo Luis Santander).
--
-- Categorías nuevas: Neveras, Cuartos fríos, Aire acondicionado, Lavadoras,
-- Electricidad, Electrónica, Instalación de cámaras.
-- El flujo del cliente llega hasta la selección Residencial/Industrial
-- (ya NO hay precios en esta fase). La tecnología (conventional/inverter)
-- aplica solo a algunos equipos y se guarda en equipment_categories.technologies.
--
-- Ejecutar con:
--   psql -h localhost -U postgres -d coldday -f scripts/seed_catalog_v2.sql
BEGIN;

-- 1) Migración: agregar columna technologies si no existe
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'equipment_categories' AND column_name = 'technologies'
  ) THEN
    ALTER TABLE equipment_categories ADD COLUMN technologies JSON;
  END IF;
END $$;

-- 2) Limpiar referencias dependientes (bids/requests apuntan a equipments)
DELETE FROM technician_bids;
DELETE FROM service_requests;
DELETE FROM service_pricings;
DELETE FROM equipments;
DELETE FROM equipment_categories;

-- 3) Categorías con tecnología (pedidos por Luis)
INSERT INTO equipment_categories (id, name, icon, technologies) VALUES
  (1,  'Neveras',             'kitchen',                 '["conventional", "inverter"]'),
  (2,  'Cuartos fríos',       'snow',                   '["conventional", "inverter"]'),
  (3,  'Aire acondicionado',  'air_wave',               '["conventional", "inverter"]'),
  (4,  'Lavadoras',           'laundry',                '["conventional", "inverter"]'),
  (5,  'Electricidad',        'electricity',            NULL),
  (6,  'Electrónica',         'devices',                NULL),
  (7,  'Instalación de cámaras','videocam',             NULL)
ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      icon = EXCLUDED.icon,
      technologies = EXCLUDED.technologies;

-- 4) Equipos por categoría y sector.
-- Sector "residential" / "industrial".
INSERT INTO equipments (category_id, sector, name, description) VALUES
  -- Neveras, residencial
  (1, 'residential', 'Nevera clásica', 'Nevera convencional'),
  (1, 'residential', 'Nevera inverter', 'Nevera inverter'),
  -- Neveras, industrial
  (1, 'industrial', 'Nevera comercial', 'Nevera comercial / vitrina'),
  -- Cuartos fríos, industrial
  (2, 'industrial', 'Cámara de frío', 'Cámara para conservación'),
  -- Aire acondicionado, residencial
  (3, 'residential', 'Split', 'Aire acondicionado split residencial'),
  (3, 'residential', 'Ventana', 'Aire acondicionado de ventana'),
  -- Aire acondicionado, industrial
  (3, 'industrial', 'Cassette', 'Aire acondicionado cassette'),
  (3, 'industrial', 'Chiller', 'Sistema de agua helada'),
  -- Lavadoras, residencial
  (4, 'residential', 'Lavadora doméstica', 'Lavadora de uso doméstico'),
  -- Lavadoras, industrial
  (4, 'industrial', 'Lavadora industrial', 'Lavadora de uso industrial'),
  -- Electricidad
  (5, 'residential', 'Electricidad residencial', 'Instalación y reparación'),
  (5, 'industrial', 'Electricidad industrial', 'Instalación y reparación'),
  -- Electrónica
  (6, 'residential', 'TV y audio', 'Electrónica de hogar'),
  (6, 'industrial', 'Electrónica industrial', 'Electrónica de uso industrial'),
  -- Instalación de cámaras
  (7, 'residential', 'Cámaras CCTV', 'Instalación de cámaras'),
  (7, 'industrial', 'Cámaras CCTV', 'Instalación de cámaras');

COMMIT;