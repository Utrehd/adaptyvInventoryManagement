# Inventory Management — Project Adaptvy

## Assumptions
- The system is the operational source of truth for current inventory state, but not for supplier management, purchasing approvals, or finance workflows.
- Integrations with LIMS, ELN, robotics, or procurement systems are out of scope.
- The system should be designed to be GxP-ready if Adaptyv later offers it in a regulated setting. Thus, the design should not block future support for auditability, traceability, controlled changes, user accountability, record integrity, electronic records, and validation-oriented workflows required under frameworks such as FDA, EU GMP, GLP, GCP, and related standards.


## Goal

Design a practical inventory management system for a high-throughput protein characterization lab.

The system should help the lab understand what materials are available, where they are stored, whether they are still usable, and whether planned lab work can be completed with the current stock.

This is not just a stock-counting problem. The lab uses different material types in different ways. Some materials are ordered, some are produced in-house, some expire quickly, some last for years, and some can be reused across projects. The goal is to model those differences clearly enough that engineers can build reliable workflows on top of it.

## Objectives

| ID | Objective | Why It Matters | Success Looks Like |
|---|---|---|---|
| OBJ-01 | Track usable and available inventory across all material types. | The lab needs a clear view of what exists, what is usable, what is already reserved for planned work, and what is still free to use. | A user can see current quantity, free quantity, reserved quantity, unit, concentration, material type, project link, and status. |
| OBJ-02 | Model material-specific behavior. | DNA, samples, target proteins, buffers, consumables, and other materials have different lifecycles. | The system supports ordered, produced, reusable, single-use, expiring, and non-expiring materials without hiding important differences. |
| OBJ-03 | Track physical storage location. | Inventory is only useful if people can find the material in the lab. | A user can locate stock down to freezer, shelf, rack, plate, tube, or well where needed. |
| OBJ-04 | Record inventory movement and consumption. | Lab workflows partially consume, create, transfer, reserve, release, and discard materials. | Each inventory change records what changed, how much, from where, why, for which workflow step, and when. |
| OBJ-05 | Check if planned lab work can be completed. | The lab needs to know before starting whether enough usable and unreserved stock exists, including possible QC re-runs, while still allowing reusable materials to be shared when enough quantity remains. | The system can answer whether a planned task or experiment has enough viable material available without double-booking the same reserved quantity. |
| OBJ-06 | Expose practical APIs for lab operations. | The frontend and other services need domain-level answers, not only raw database records. | API calls support inventory lookup, material location, expiry checks, feasibility checks, reservations, receiving stock, and recording consumption. |
| OBJ-07 | Ensure user traceability, controlled access, and GxP-ready auditability. | A regulated-ready system must attribute critical actions to specific users, restrict access by role, and preserve a reliable audit history. | All critical inventory and workflow actions can be tied to a unique user identity, controlled through IAM-based access rules, and recorded in a time-stamped audit trail. |

## User Requirements

| ID | Linked Objective | User Requirement | Reason |
|---|---|---|---|
| UR-01 | OBJ-01 | As a lab operator, I need to see the current stock for each material, so I know what physically exists in the lab. | Daily lab work depends on knowing what inventory exists. |
| UR-02 | OBJ-01 | As a lab planner, I need to see how much material is free versus reserved for planned or active processes. | Material that exists physically may not be available for new work. |
| UR-03 | OBJ-01 | As a lab operator, I need inventory status to show whether material is usable, reserved, depleted, expired, or discarded. | Quantity alone is not enough to know if material can be used. |
| UR-04 | OBJ-02 | As a lab operator, I need DNA, samples, target proteins, buffers, consumables, and other materials to be represented with their relevant properties. | Each material type has different rules for use, expiry, storage, and reuse. |
| UR-05 | OBJ-02 | As a lab planner, I need reusable materials, especially target proteins, to show remaining usable, reserved, and free stock across projects. | Expensive shared materials should not be reordered when enough stock already exists or can still be shared safely. |
| UR-06 | OBJ-02 / OBJ-05 | As a lab planner, I need target proteins to be shareable across projects when there is enough usable stock after existing reservations. | Target proteins are expensive and often relevant to multiple projects, so the system should avoid unnecessary reordering. |
| UR-07 | OBJ-02 / OBJ-05 | As a lab planner, I need reservations to reserve only the required quantity, not block the entire target protein stock item by default. | A reserved target protein tube may still contain enough remaining volume for another project. |
| UR-08 | OBJ-03 | As a lab operator, I need to see where a material is physically stored. | Finding the correct material quickly matters as lab volume grows. |
| UR-09 | OBJ-03 | As a lab operator, I need storage to support nested locations such as freezer, shelf, rack, plate, tube, and well. | Lab materials are often stored at different physical levels of precision. |
| UR-10 | OBJ-04 | As a lab operator, I need every inventory change to be recorded as a movement, creation, transfer, reservation, release, consumption, discard, or adjustment. | Inventory should be auditable and not only reflect the latest number. |
| UR-11 | OBJ-04 | As a lab operator, I need partial consumption to be supported. | Many workflow steps use only part of a plate well, tube, or buffer volume. |
| UR-12 | OBJ-04 | As a lab operator, I need reservations to be released, consumed, or adjusted when the related workflow step is completed, cancelled, or changed. | Reserved stock should stay accurate as lab plans change. |
| UR-13 | OBJ-04 | As a lab operator, I need inventory changes to be linked to the workflow step, experiment, material, source location, quantity, and timestamp. | This explains why stock changed and connects inventory to lab execution. |
| UR-14 | OBJ-05 | As a lab planner, I need to check whether a planned task has enough viable and unreserved materials before the task starts. | Missing stock should be found before lab time is committed. |
| UR-15 | OBJ-05 | As a lab planner, I need feasibility checks to include expected QC re-runs where relevant. | Failed QC can require repeating steps and consuming more material. |
| UR-16 | OBJ-05 | As a lab planner, I need the system to show which material blocks a task if stock is missing, reserved, or expired. | The user needs an actionable reason, not only a failed check. |
| UR-17 | OBJ-06 | As a frontend user, I need APIs that answer inventory questions directly. | The frontend should not rebuild lab logic from raw database tables. |
| UR-18 | OBJ-06 | As another lab service, I need APIs to receive stock, reserve material, release reservations, record consumption, locate materials, and check task feasibility. | Inventory will likely be used by workflow and automation systems, not only humans. |
| UR-19 | OBJ-07 | As a QA or compliance user, I need every critical action to be attributable to a unique user identity, so actions cannot be performed through shared or anonymous accounts. | GxP-ready traceability depends on clear user attribution. |
| UR-20 | OBJ-07 | As an IT or system administrator, I need the system to use IAM-based authentication and role-based access control, so only authorized users can view, create, modify, approve, or delete records. | Regulated-ready systems need controlled access by role and responsibility. |
| UR-21 | OBJ-07 | As a QA or compliance user, I need a secure, time-stamped audit trail for critical actions that shows who performed the action, when it happened, what record was affected, and what changed. | Critical record changes must remain traceable and reviewable over time. |
| UR-22 | OBJ-07 | As a QA or compliance user, I need approval and sign-off actions to be attributable to a specific user and linked to the affected record, so the design can support stronger electronic signature controls later without major redesign. | GxP-ready systems should not block future Part 11-style approval controls. |


## Data Model Assessment By User Requirement

Assessment only checks whether the **entities** can support the requirement in theory. It does not judge fields, enums, validation rules, or API behavior.

| ID | Linked Objective | Assessment | Supporting Entities | Reason |
|---|---|---|---|---|
| UR-01 | OBJ-01 | Covered | `Material`, `InventoryLot`, `Project`, `ContainerPosition` | The model has a material definition and physical inventory lots that can represent what stock exists in the lab. |
| UR-02 | OBJ-01 | Covered | `InventoryLot`, `InventoryReservation`, `WorkflowStepRun` | The model separates existing stock from planned reservations, so free vs reserved stock can be represented. |
| UR-03 | OBJ-01 | Covered in principle | `InventoryLot`, `InventoryReservation`, `InventoryTransaction` | Stock state can be represented through the inventory lot, reservation, and transaction history entities. |
| UR-04 | OBJ-02 | Covered | `Material`, `MaterialMetadata`, `InventoryLot` | The model has a general material entity plus metadata for type-specific material behavior. |
| UR-05 | OBJ-02 | Covered | `Material`, `InventoryLot`, `Project`, `InventoryReservation` | Reusable stock can be represented as inventory lots, with reservations showing what is already planned for use. |
| UR-06 | OBJ-02 / OBJ-05 | Covered | `Material`, `InventoryLot`, `InventoryReservation`, `Project`, `Experiment` | Target proteins can be modeled as shared material lots used by multiple projects or experiments through reservations. |
| UR-07 | OBJ-02 / OBJ-05 | Covered in principle | `InventoryLot`, `InventoryReservation` | The existence of a reservation entity allows the model to reserve stock without needing to model reservation as ownership of the whole lot. |
| UR-08 | OBJ-03 | Covered | `StorageLocation`, `Container`, `ContainerPosition`, `InventoryLot` | The model supports physical storage from lab location down to container position. |
| UR-09 | OBJ-03 | Covered | `StorageLocation`, `Container`, `ContainerPosition` | Nested storage is represented through locations containing locations, containers, and container positions. |
| UR-10 | OBJ-04 | Covered | `InventoryTransaction`, `InventoryReservation`, `InventoryLot`, `WorkflowStepRun` | Inventory changes and reservations have dedicated entities and can be connected to workflow execution. |
| UR-11 | OBJ-04 | Covered in principle | `InventoryLot`, `InventoryTransaction` | Partial consumption can be represented as a transaction against an inventory lot. |
| UR-12 | OBJ-04 | Covered | `InventoryReservation`, `WorkflowStepRun`, `InventoryTransaction` | Reservations are connected to workflow steps, so they can be consumed, released, or changed as execution changes. |
| UR-13 | OBJ-04 | Covered | `WorkflowStepRun`, `WorkflowRun`, `Experiment`, `Material`, `InventoryLot`, `InventoryTransaction` | The model connects inventory changes to real workflow execution and experiment context. |
| UR-14 | OBJ-05 | Covered | `Recipe`, `RecipeStep`, `RecipeStepInput`, `InventoryLot`, `InventoryReservation`, `WorkflowRun` | Planned work can be compared against required recipe inputs and available inventory lots/reservations. |
| UR-15 | OBJ-05 | Covered | `WorkflowRun`, `WorkflowStepRun`, `RecipeStepDependency`, `RecipeStepInput` | The model can represent planned workflow execution and reruns through workflow runs and step runs. |
| UR-16 | OBJ-05 | Covered in principle | `RecipeStepInput`, `Material`, `InventoryLot`, `InventoryReservation`, `StorageLocation` | The model has the entities needed to identify whether a blocker comes from missing stock, reserved stock, expired stock, or location issues. |
| UR-17 | OBJ-06 | Covered in principle | All domain entities | The model is domain-based, not only CRUD-shaped, so APIs can be built around inventory, location, reservation, and feasibility questions. |
| UR-18 | OBJ-06 | Covered | `PurchaseOrder`, `PurchaseOrderLine`, `InventoryLot`, `InventoryReservation`, `InventoryTransaction`, `StorageLocation`, `WorkflowStepRun` | The model has entities for receiving stock, reserving stock, releasing/resolving reservations, recording consumption, locating inventory, and checking planned work. |
| UR-19 | OBJ-07 | Covered | `UserIdentity`, `AuditEntry`, `ApprovalRecord` | The model ties critical actions and sign-off records to a unique user identity, which supports attributable user traceability. |
| UR-20 | OBJ-07 | Covered in principle | `UserIdentity`, `AccessRole`, `UserRoleAssignment` | The model includes a minimal IAM-backed identity and role structure that can represent authenticated users and role-based access control. |
| UR-21 | OBJ-07 | Covered | `AuditEntry`, `UserIdentity`, `InventoryLot`, `InventoryEvent`, `InventoryReservation`, `WorkflowRun`, `WorkflowStepRun`, `Recipe`, `PurchaseOrder`, `PurchaseOrderLine` | The model includes a dedicated audit trail entity linked to user identity and to the core controlled records that need traceability. |
| UR-22 | OBJ-07 | Covered | `ApprovalRecord`, `UserIdentity`, `InventoryEvent`, `WorkflowRun`, `Recipe`, `PurchaseOrder` | The model includes a dedicated approval/sign-off entity linked to a specific user and to the main records that may require formal review or approval. |
