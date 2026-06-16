-- Inventory Management schema (SQLite)
-- Designed to run in https://sqliteonline.com/
-- IDs are TEXT so the application can provide UUID-like values.

PRAGMA foreign_keys = ON;

-- =========================================================
-- Identity & Compliance
-- =========================================================

CREATE TABLE user_identity (
    id TEXT PRIMARY KEY,
    iam_subject_id TEXT NOT NULL,
    iam_provider TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'locked')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (iam_provider, iam_subject_id)
);

CREATE TABLE access_role (
    id TEXT PRIMARY KEY,
    role_key TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_role_assignment (
    id TEXT PRIMARY KEY,
    user_identity_id TEXT NOT NULL,
    access_role_id TEXT NOT NULL,
    assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TEXT,
    FOREIGN KEY (user_identity_id) REFERENCES user_identity(id) ON DELETE CASCADE,
    FOREIGN KEY (access_role_id) REFERENCES access_role(id) ON DELETE RESTRICT
);

CREATE TABLE audit_entry (
    id TEXT PRIMARY KEY,
    actor_user_identity_id TEXT NOT NULL,
    target_record_type TEXT NOT NULL,
    target_record_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    change_summary TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_identity_id) REFERENCES user_identity(id) ON DELETE RESTRICT
);

CREATE TABLE approval_record (
    id TEXT PRIMARY KEY,
    actor_user_identity_id TEXT NOT NULL,
    target_record_type TEXT NOT NULL,
    target_record_id TEXT NOT NULL,
    approval_type TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'revoked')),
    comment TEXT,
    signed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_identity_id) REFERENCES user_identity(id) ON DELETE RESTRICT
);

-- =========================================================
-- Storage
-- =========================================================

CREATE TABLE storage_location (
    id TEXT PRIMARY KEY,
    parent_location_id TEXT,
    name TEXT NOT NULL,
    location_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'retired')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (parent_location_id) REFERENCES storage_location(id) ON DELETE RESTRICT
);

CREATE TABLE container (
    id TEXT PRIMARY KEY,
    storage_location_id TEXT NOT NULL,
    barcode TEXT,
    name TEXT NOT NULL,
    container_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'discarded')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (storage_location_id) REFERENCES storage_location(id) ON DELETE RESTRICT
);

CREATE TABLE container_position (
    id TEXT PRIMARY KEY,
    container_id TEXT NOT NULL,
    position_code TEXT NOT NULL,
    row_label TEXT,
    column_label TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (container_id, position_code),
    FOREIGN KEY (container_id) REFERENCES container(id) ON DELETE CASCADE
);

-- =========================================================
-- Supply
-- =========================================================

CREATE TABLE supplier (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    supplier_code TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchase_order (
    id TEXT PRIMARY KEY,
    supplier_id TEXT NOT NULL,
    order_number TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
    ordered_at TEXT,
    expected_at TEXT,
    received_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES supplier(id) ON DELETE RESTRICT
);

-- =========================================================
-- Workflow Execution
-- =========================================================

CREATE TABLE customer (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    external_reference TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE project (
    id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'on_hold', 'completed', 'cancelled', 'archived')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customer(id) ON DELETE RESTRICT
);

-- =========================================================
-- Inventory / Material master
-- =========================================================

CREATE TABLE material_type_policy (
    id TEXT PRIMARY KEY,
    material_type TEXT NOT NULL UNIQUE,
    is_reusable INTEGER NOT NULL DEFAULT 0 CHECK (is_reusable IN (0, 1)),
    is_project_specific INTEGER NOT NULL DEFAULT 0 CHECK (is_project_specific IN (0, 1)),
    is_ordered INTEGER NOT NULL DEFAULT 0 CHECK (is_ordered IN (0, 1)),
    is_produced_in_house INTEGER NOT NULL DEFAULT 0 CHECK (is_produced_in_house IN (0, 1)),
    requires_concentration INTEGER NOT NULL DEFAULT 0 CHECK (requires_concentration IN (0, 1)),
    requires_expiry INTEGER NOT NULL DEFAULT 0 CHECK (requires_expiry IN (0, 1)),
    default_expiry_days INTEGER CHECK (default_expiry_days IS NULL OR default_expiry_days >= 0),
    default_storage_condition TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE material (
    id TEXT PRIMARY KEY,
    material_type_policy_id TEXT NOT NULL,
    name TEXT NOT NULL,
    default_unit TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (material_type_policy_id) REFERENCES material_type_policy(id) ON DELETE RESTRICT
);

CREATE TABLE material_metadata (
    id TEXT PRIMARY KEY,
    material_id TEXT NOT NULL,
    metadata_key TEXT NOT NULL,
    metadata_value TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (material_id, metadata_key),
    FOREIGN KEY (material_id) REFERENCES material(id) ON DELETE CASCADE
);

CREATE TABLE purchase_order_line (
    id TEXT PRIMARY KEY,
    purchase_order_id TEXT NOT NULL,
    material_id TEXT NOT NULL,
    supplier_sku TEXT,
    ordered_quantity REAL NOT NULL CHECK (ordered_quantity > 0),
    received_quantity REAL NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
    unit TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'partially_received', 'received', 'cancelled')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_order(id) ON DELETE CASCADE,
    FOREIGN KEY (material_id) REFERENCES material(id) ON DELETE RESTRICT
);

-- =========================================================
-- Recipes
-- =========================================================

CREATE TABLE recipe (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    workflow_type TEXT NOT NULL,
    version INTEGER NOT NULL CHECK (version > 0),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (name, version)
);

CREATE TABLE recipe_step (
    id TEXT PRIMARY KEY,
    recipe_id TEXT NOT NULL,
    name TEXT NOT NULL,
    step_key TEXT NOT NULL,
    step_order INTEGER NOT NULL CHECK (step_order > 0),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (recipe_id, step_key),
    UNIQUE (recipe_id, step_order),
    FOREIGN KEY (recipe_id) REFERENCES recipe(id) ON DELETE CASCADE
);

CREATE TABLE recipe_step_dependency (
    id TEXT PRIMARY KEY,
    predecessor_recipe_step_id TEXT NOT NULL,
    successor_recipe_step_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (predecessor_recipe_step_id, successor_recipe_step_id),
    CHECK (predecessor_recipe_step_id <> successor_recipe_step_id),
    FOREIGN KEY (predecessor_recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE,
    FOREIGN KEY (successor_recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE
);

CREATE TABLE recipe_step_input (
    id TEXT PRIMARY KEY,
    recipe_step_id TEXT NOT NULL,
    material_id TEXT NOT NULL,
    required_quantity REAL NOT NULL CHECK (required_quantity > 0),
    unit TEXT NOT NULL,
    min_concentration REAL CHECK (min_concentration IS NULL OR min_concentration >= 0),
    concentration_unit TEXT,
    is_consumed INTEGER NOT NULL DEFAULT 1 CHECK (is_consumed IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE,
    FOREIGN KEY (material_id) REFERENCES material(id) ON DELETE RESTRICT
);

CREATE TABLE recipe_step_output (
    id TEXT PRIMARY KEY,
    recipe_step_id TEXT NOT NULL,
    material_id TEXT NOT NULL,
    expected_quantity REAL NOT NULL CHECK (expected_quantity > 0),
    unit TEXT NOT NULL,
    expected_container_type TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE,
    FOREIGN KEY (material_id) REFERENCES material(id) ON DELETE RESTRICT
);

CREATE TABLE experiment (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    name TEXT NOT NULL,
    experiment_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled', 'qc_failed')),
    planned_at TEXT,
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE RESTRICT
);

CREATE TABLE workflow_run (
    id TEXT PRIMARY KEY,
    experiment_id TEXT NOT NULL,
    recipe_id TEXT NOT NULL,
    run_number INTEGER NOT NULL CHECK (run_number > 0),
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled', 'qc_failed')),
    planned_rerun_count INTEGER NOT NULL DEFAULT 0 CHECK (planned_rerun_count >= 0),
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (experiment_id, run_number),
    FOREIGN KEY (experiment_id) REFERENCES experiment(id) ON DELETE RESTRICT,
    FOREIGN KEY (recipe_id) REFERENCES recipe(id) ON DELETE RESTRICT
);

CREATE TABLE workflow_step_run (
    id TEXT PRIMARY KEY,
    workflow_run_id TEXT NOT NULL,
    recipe_step_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'reserved', 'in_progress', 'completed', 'cancelled', 'qc_failed', 'skipped')),
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (workflow_run_id, recipe_step_id),
    FOREIGN KEY (workflow_run_id) REFERENCES workflow_run(id) ON DELETE CASCADE,
    FOREIGN KEY (recipe_step_id) REFERENCES recipe_step(id) ON DELETE RESTRICT
);

-- =========================================================
-- Inventory operations
-- =========================================================

CREATE TABLE inventory_event (
    id TEXT PRIMARY KEY,
    actor_user_identity_id TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('receive', 'produce', 'reserve', 'release', 'consume', 'transfer', 'discard', 'adjust', 'expire', 'quarantine')),
    purchase_order_line_id TEXT,
    workflow_step_run_id TEXT,
    reason TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actor_user_identity_id) REFERENCES user_identity(id) ON DELETE RESTRICT,
    FOREIGN KEY (purchase_order_line_id) REFERENCES purchase_order_line(id) ON DELETE SET NULL,
    FOREIGN KEY (workflow_step_run_id) REFERENCES workflow_step_run(id) ON DELETE SET NULL
);

CREATE TABLE inventory_lot (
    id TEXT PRIMARY KEY,
    material_id TEXT NOT NULL,
    project_id TEXT,
    container_position_id TEXT,
    ownership_scope TEXT NOT NULL DEFAULT 'shared_lab' CHECK (ownership_scope IN ('shared_lab', 'project', 'customer')),
    lot_code TEXT,
    current_quantity REAL NOT NULL CHECK (current_quantity >= 0),
    unit TEXT NOT NULL,
    concentration REAL CHECK (concentration IS NULL OR concentration >= 0),
    concentration_unit TEXT,
    status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'depleted', 'expired', 'discarded', 'quarantined')),
    expires_at TEXT,
    received_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (material_id) REFERENCES material(id) ON DELETE RESTRICT,
    FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE SET NULL,
    FOREIGN KEY (container_position_id) REFERENCES container_position(id) ON DELETE SET NULL
);

CREATE TABLE inventory_reservation (
    id TEXT PRIMARY KEY,
    inventory_lot_id TEXT NOT NULL,
    workflow_step_run_id TEXT,
    experiment_id TEXT,
    reserved_quantity REAL NOT NULL CHECK (reserved_quantity > 0),
    unit TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'fulfilled', 'released', 'expired', 'cancelled')),
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inventory_lot_id) REFERENCES inventory_lot(id) ON DELETE RESTRICT,
    FOREIGN KEY (workflow_step_run_id) REFERENCES workflow_step_run(id) ON DELETE SET NULL,
    FOREIGN KEY (experiment_id) REFERENCES experiment(id) ON DELETE SET NULL
);

CREATE TABLE inventory_transaction (
    id TEXT PRIMARY KEY,
    inventory_event_id TEXT NOT NULL,
    inventory_lot_id TEXT NOT NULL,
    reservation_id TEXT,
    quantity_delta REAL NOT NULL,
    unit TEXT NOT NULL,
    from_container_position_id TEXT,
    to_container_position_id TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (inventory_event_id) REFERENCES inventory_event(id) ON DELETE RESTRICT,
    FOREIGN KEY (inventory_lot_id) REFERENCES inventory_lot(id) ON DELETE RESTRICT,
    FOREIGN KEY (reservation_id) REFERENCES inventory_reservation(id) ON DELETE SET NULL,
    FOREIGN KEY (from_container_position_id) REFERENCES container_position(id) ON DELETE SET NULL,
    FOREIGN KEY (to_container_position_id) REFERENCES container_position(id) ON DELETE SET NULL
);

-- =========================================================
-- Useful read views
-- =========================================================

-- Availability invariant:
-- free_quantity = current_quantity - active reserved_quantity
CREATE VIEW inventory_lot_availability AS
SELECT
    il.id AS inventory_lot_id,
    il.material_id,
    m.name AS material_name,
    mtp.material_type,
    il.project_id,
    il.container_position_id,
    il.ownership_scope,
    il.lot_code,
    il.status,
    il.current_quantity,
    COALESCE(SUM(CASE WHEN ir.status = 'active' THEN ir.reserved_quantity ELSE 0 END), 0) AS reserved_quantity,
    il.current_quantity - COALESCE(SUM(CASE WHEN ir.status = 'active' THEN ir.reserved_quantity ELSE 0 END), 0) AS free_quantity,
    il.unit,
    il.concentration,
    il.concentration_unit,
    il.expires_at,
    il.received_at,
    mtp.is_reusable,
    mtp.is_project_specific,
    mtp.is_ordered,
    mtp.is_produced_in_house,
    mtp.requires_concentration,
    mtp.requires_expiry,
    mtp.default_expiry_days,
    mtp.default_storage_condition
FROM inventory_lot il
JOIN material m ON m.id = il.material_id
JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
LEFT JOIN inventory_reservation ir ON ir.inventory_lot_id = il.id
GROUP BY il.id;

CREATE VIEW storage_contents AS
SELECT
    sl.id AS storage_location_id,
    sl.name AS storage_location_name,
    sl.location_type,
    c.id AS container_id,
    c.name AS container_name,
    c.container_type,
    cp.id AS container_position_id,
    cp.position_code,
    il.id AS inventory_lot_id,
    il.material_id,
    m.name AS material_name,
    mtp.material_type,
    il.current_quantity,
    il.unit,
    il.status,
    il.expires_at
FROM storage_location sl
JOIN container c ON c.storage_location_id = sl.id
JOIN container_position cp ON cp.container_id = c.id
LEFT JOIN inventory_lot il ON il.container_position_id = cp.id
LEFT JOIN material m ON m.id = il.material_id
LEFT JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id;

-- =========================================================
-- Validation triggers
-- =========================================================

CREATE TRIGGER trg_inventory_lot_policy_insert
BEFORE INSERT ON inventory_lot
BEGIN
    SELECT CASE
        WHEN (
            SELECT mtp.requires_concentration
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND (NEW.concentration IS NULL OR NEW.concentration_unit IS NULL)
        THEN RAISE(ABORT, 'CONCENTRATION_REQUIRED')
    END;

    SELECT CASE
        WHEN (
            SELECT mtp.requires_expiry
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND NEW.expires_at IS NULL
        THEN RAISE(ABORT, 'EXPIRY_REQUIRED')
    END;

    SELECT CASE
        WHEN (
            SELECT mtp.is_project_specific
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND NEW.project_id IS NULL
        THEN RAISE(ABORT, 'PROJECT_ID_REQUIRED_FOR_PROJECT_SPECIFIC_MATERIAL')
    END;
END;

CREATE TRIGGER trg_inventory_lot_policy_update
BEFORE UPDATE OF material_id, concentration, concentration_unit, expires_at, project_id ON inventory_lot
BEGIN
    SELECT CASE
        WHEN (
            SELECT mtp.requires_concentration
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND (NEW.concentration IS NULL OR NEW.concentration_unit IS NULL)
        THEN RAISE(ABORT, 'CONCENTRATION_REQUIRED')
    END;

    SELECT CASE
        WHEN (
            SELECT mtp.requires_expiry
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND NEW.expires_at IS NULL
        THEN RAISE(ABORT, 'EXPIRY_REQUIRED')
    END;

    SELECT CASE
        WHEN (
            SELECT mtp.is_project_specific
            FROM material m
            JOIN material_type_policy mtp ON mtp.id = m.material_type_policy_id
            WHERE m.id = NEW.material_id
        ) = 1 AND NEW.project_id IS NULL
        THEN RAISE(ABORT, 'PROJECT_ID_REQUIRED_FOR_PROJECT_SPECIFIC_MATERIAL')
    END;
END;

CREATE TRIGGER trg_inventory_reservation_unit_insert
BEFORE INSERT ON inventory_reservation
BEGIN
    SELECT CASE
        WHEN NEW.unit <> (SELECT unit FROM inventory_lot WHERE id = NEW.inventory_lot_id)
        THEN RAISE(ABORT, 'RESERVATION_UNIT_MUST_MATCH_LOT_UNIT')
    END;
END;

CREATE TRIGGER trg_inventory_reservation_unit_update
BEFORE UPDATE OF inventory_lot_id, unit ON inventory_reservation
BEGIN
    SELECT CASE
        WHEN NEW.unit <> (SELECT unit FROM inventory_lot WHERE id = NEW.inventory_lot_id)
        THEN RAISE(ABORT, 'RESERVATION_UNIT_MUST_MATCH_LOT_UNIT')
    END;
END;

CREATE TRIGGER trg_inventory_reservation_capacity_insert
BEFORE INSERT ON inventory_reservation
WHEN NEW.status = 'active'
BEGIN
    SELECT CASE
        WHEN NEW.reserved_quantity > (
            SELECT il.current_quantity - COALESCE((
                SELECT SUM(ir.reserved_quantity)
                FROM inventory_reservation ir
                WHERE ir.inventory_lot_id = NEW.inventory_lot_id
                  AND ir.status = 'active'
            ), 0)
            FROM inventory_lot il
            WHERE il.id = NEW.inventory_lot_id
        )
        THEN RAISE(ABORT, 'INSUFFICIENT_AVAILABLE_QUANTITY')
    END;
END;

CREATE TRIGGER trg_inventory_reservation_capacity_update
BEFORE UPDATE OF inventory_lot_id, reserved_quantity, status ON inventory_reservation
WHEN NEW.status = 'active'
BEGIN
    SELECT CASE
        WHEN NEW.reserved_quantity > (
            SELECT il.current_quantity - COALESCE((
                SELECT SUM(ir.reserved_quantity)
                FROM inventory_reservation ir
                WHERE ir.inventory_lot_id = NEW.inventory_lot_id
                  AND ir.status = 'active'
                  AND ir.id <> OLD.id
            ), 0)
            FROM inventory_lot il
            WHERE il.id = NEW.inventory_lot_id
        )
        THEN RAISE(ABORT, 'INSUFFICIENT_AVAILABLE_QUANTITY')
    END;
END;

CREATE TRIGGER trg_inventory_lot_quantity_not_below_reservations
BEFORE UPDATE OF current_quantity ON inventory_lot
WHEN NEW.current_quantity < COALESCE((
    SELECT SUM(ir.reserved_quantity)
    FROM inventory_reservation ir
    WHERE ir.inventory_lot_id = NEW.id
      AND ir.status = 'active'
), 0)
BEGIN
    SELECT RAISE(ABORT, 'LOT_QUANTITY_BELOW_ACTIVE_RESERVATIONS');
END;

-- =========================================================
-- Lightweight indexes
-- =========================================================

CREATE UNIQUE INDEX ux_user_role_assignment_active
ON user_role_assignment (user_identity_id, access_role_id)
WHERE revoked_at IS NULL;

CREATE INDEX ix_container_storage_location ON container (storage_location_id);
CREATE INDEX ix_container_position_container ON container_position (container_id);
CREATE INDEX ix_purchase_order_supplier ON purchase_order (supplier_id);
CREATE INDEX ix_purchase_order_line_po ON purchase_order_line (purchase_order_id);
CREATE INDEX ix_purchase_order_line_material ON purchase_order_line (material_id);
CREATE INDEX ix_project_customer ON project (customer_id);
CREATE INDEX ix_material_policy ON material (material_type_policy_id);
CREATE INDEX ix_material_metadata_material ON material_metadata (material_id);
CREATE INDEX ix_experiment_project ON experiment (project_id);
CREATE INDEX ix_workflow_run_experiment ON workflow_run (experiment_id);
CREATE INDEX ix_workflow_step_run_workflow_run ON workflow_step_run (workflow_run_id);
CREATE INDEX ix_recipe_step_recipe ON recipe_step (recipe_id);
CREATE INDEX ix_recipe_step_input_material ON recipe_step_input (material_id);
CREATE INDEX ix_recipe_step_output_material ON recipe_step_output (material_id);
CREATE INDEX ix_inventory_event_actor ON inventory_event (actor_user_identity_id);
CREATE INDEX ix_inventory_event_workflow_step ON inventory_event (workflow_step_run_id);
CREATE INDEX ix_inventory_lot_material ON inventory_lot (material_id);
CREATE INDEX ix_inventory_lot_project ON inventory_lot (project_id);
CREATE INDEX ix_inventory_lot_position ON inventory_lot (container_position_id);
CREATE INDEX ix_inventory_lot_status_expiry ON inventory_lot (status, expires_at);
CREATE INDEX ix_inventory_reservation_lot ON inventory_reservation (inventory_lot_id);
CREATE INDEX ix_inventory_reservation_workflow_step ON inventory_reservation (workflow_step_run_id);
CREATE INDEX ix_inventory_transaction_event ON inventory_transaction (inventory_event_id);
CREATE INDEX ix_inventory_transaction_lot ON inventory_transaction (inventory_lot_id);
CREATE INDEX ix_audit_entry_actor ON audit_entry (actor_user_identity_id);
CREATE INDEX ix_audit_entry_target ON audit_entry (target_record_type, target_record_id);
CREATE INDEX ix_approval_record_actor ON approval_record (actor_user_identity_id);
CREATE INDEX ix_approval_record_target ON approval_record (target_record_type, target_record_id);

-- =========================================================
-- Seeded material policies
-- These can be changed or split into more specific policies later.
-- =========================================================

INSERT OR IGNORE INTO material_type_policy (
    id,
    material_type,
    is_reusable,
    is_project_specific,
    is_ordered,
    is_produced_in_house,
    requires_concentration,
    requires_expiry,
    default_expiry_days,
    default_storage_condition
) VALUES
    ('mtp_dna', 'dna', 0, 1, 1, 1, 1, 1, NULL, 'freezer'),
    ('mtp_sample', 'sample', 0, 1, 0, 1, 1, 1, NULL, 'freezer'),
    ('mtp_target_protein', 'target_protein', 1, 0, 1, 0, 1, 1, NULL, 'freezer'),
    ('mtp_consumable', 'consumable', 0, 0, 1, 0, 0, 0, NULL, 'room_temperature'),
    ('mtp_buffer', 'buffer', 0, 0, 0, 1, 0, 1, 30, 'cold_storage'),
    ('mtp_other_material', 'other_material', 0, 0, 1, 0, 0, 0, NULL, 'room_temperature');
