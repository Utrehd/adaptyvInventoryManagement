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
    status TEXT NOT NULL DEFAULT 'active',
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
    status TEXT NOT NULL,
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
    status TEXT NOT NULL DEFAULT 'active',
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
    status TEXT NOT NULL DEFAULT 'active',
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
    status TEXT NOT NULL DEFAULT 'draft',
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
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE project (
    id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customer(id) ON DELETE RESTRICT
);

-- =========================================================
-- Inventory / Material master
-- =========================================================

CREATE TABLE material (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    material_type TEXT NOT NULL,
    default_unit TEXT NOT NULL,
    is_reusable INTEGER NOT NULL DEFAULT 0 CHECK (is_reusable IN (0, 1)),
    is_project_specific INTEGER NOT NULL DEFAULT 0 CHECK (is_project_specific IN (0, 1)),
    default_expiry_days INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    ordered_quantity REAL NOT NULL,
    received_quantity REAL NOT NULL DEFAULT 0,
    unit TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
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
    version INTEGER NOT NULL,
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
    step_order INTEGER NOT NULL,
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
    FOREIGN KEY (predecessor_recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE,
    FOREIGN KEY (successor_recipe_step_id) REFERENCES recipe_step(id) ON DELETE CASCADE
);

CREATE TABLE recipe_step_input (
    id TEXT PRIMARY KEY,
    recipe_step_id TEXT NOT NULL,
    material_id TEXT NOT NULL,
    required_quantity REAL NOT NULL,
    unit TEXT NOT NULL,
    min_concentration REAL,
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
    expected_quantity REAL NOT NULL,
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
    status TEXT NOT NULL DEFAULT 'planned',
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
    run_number INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',
    planned_rerun_count INTEGER NOT NULL DEFAULT 0,
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
    status TEXT NOT NULL DEFAULT 'planned',
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
    event_type TEXT NOT NULL,
    purchase_order_line_id TEXT,
    workflow_step_run_id TEXT,
    reason TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (purchase_order_line_id) REFERENCES purchase_order_line(id) ON DELETE SET NULL,
    FOREIGN KEY (workflow_step_run_id) REFERENCES workflow_step_run(id) ON DELETE SET NULL
);

CREATE TABLE inventory_lot (
    id TEXT PRIMARY KEY,
    material_id TEXT NOT NULL,
    project_id TEXT,
    container_position_id TEXT,
    ownership_scope TEXT NOT NULL DEFAULT 'shared_lab',
    lot_code TEXT,
    current_quantity REAL NOT NULL,
    unit TEXT NOT NULL,
    concentration REAL,
    concentration_unit TEXT,
    status TEXT NOT NULL DEFAULT 'available',
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
    reserved_quantity REAL NOT NULL,
    unit TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
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
-- Lightweight indexes
-- =========================================================

CREATE INDEX ix_container_storage_location ON container (storage_location_id);
CREATE INDEX ix_purchase_order_supplier ON purchase_order (supplier_id);
CREATE INDEX ix_purchase_order_line_po ON purchase_order_line (purchase_order_id);
CREATE INDEX ix_purchase_order_line_material ON purchase_order_line (material_id);
CREATE INDEX ix_project_customer ON project (customer_id);
CREATE INDEX ix_experiment_project ON experiment (project_id);
CREATE INDEX ix_workflow_run_experiment ON workflow_run (experiment_id);
CREATE INDEX ix_workflow_step_run_workflow_run ON workflow_step_run (workflow_run_id);
CREATE INDEX ix_recipe_step_recipe ON recipe_step (recipe_id);
CREATE INDEX ix_inventory_lot_material ON inventory_lot (material_id);
CREATE INDEX ix_inventory_lot_project ON inventory_lot (project_id);
CREATE INDEX ix_inventory_reservation_lot ON inventory_reservation (inventory_lot_id);
CREATE INDEX ix_inventory_transaction_event ON inventory_transaction (inventory_event_id);
CREATE INDEX ix_inventory_transaction_lot ON inventory_transaction (inventory_lot_id);
CREATE INDEX ix_audit_entry_actor ON audit_entry (actor_user_identity_id);
CREATE INDEX ix_audit_entry_target ON audit_entry (target_record_type, target_record_id);
CREATE INDEX ix_approval_record_actor ON approval_record (actor_user_identity_id);
CREATE INDEX ix_approval_record_target ON approval_record (target_record_type, target_record_id);
