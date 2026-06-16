````md
# Inventory & Workflow API Design

## Purpose

This API is designed to answer the operational inventory questions that matter most in a high-throughput protein characterization lab:

- What material do we have?
- How much is usable, reserved, expired, or free?
- Where is it stored?
- Can a planned workflow run with current stock?
- Which workflow step consumed, produced, reserved, moved, or discarded inventory?
- Which material handling rules apply to each material type?

The API is intentionally domain-oriented. It exposes lab operations such as receiving stock, reserving material, checking workflow feasibility, consuming inventory, and completing workflow steps. It does not expose the database tables as raw CRUD endpoints.

## API Design Principles

| Principle | API Choice |
|---|---|
| Use intention-revealing names | Endpoints use domain words such as `availability`, `reservations`, `consumptions`, `transfers`, and `feasibility-checks`. |
| Keep endpoints small and focused | Each endpoint answers one question or records one lab action. |
| Keep the database model behind the API boundary | The frontend does not need to know whether availability comes from `InventoryLot`, `InventoryReservation`, transaction history, or material policy rules. |
| Prefer resources over verbs | Most endpoints are resource-based. Domain actions are modeled as sub-resources when they represent a real lab operation. |
| Make writes explicit and auditable | Every write creates an inventory event, transaction, reservation, or workflow state change behind the scenes. |
| Separate reads from writes | Read endpoints answer planning and lookup questions. Write endpoints record operational facts. |
| Avoid large generic endpoints | The API avoids a single `/inventory-events` endpoint where callers must know every event type and internal rule. |
| Make failures actionable | Feasibility and availability responses explain which material blocks the workflow and why. |
| Centralize material behavior | Reuse, expiry, concentration, project scope, and production rules are handled through `MaterialTypePolicy`. |

## Common Conventions

### Base URL

```http
/v1
```

### Authentication and user traceability

The authenticated user is taken from the IAM/session context. The caller should not pass `createdByUserId` in the request body. The server records the actor on audit records and inventory events.

### Idempotency

Write endpoints should support an optional idempotency key:

```http
Idempotency-Key: 7d4b6f31-0cb9-4d6d-9c02-8f98df8e9b2a
```

This prevents duplicate receives, reservations, and consumptions if a client retries after a timeout.

### Standard error shape

```json
{
  "error": {
    "code": "INSUFFICIENT_AVAILABLE_QUANTITY",
    "message": "Not enough free target protein is available for this workflow step.",
    "details": {
      "materialId": "mat_target_egfr",
      "requiredQuantity": 120,
      "availableQuantity": 80,
      "unit": "uL"
    }
  }
}
```

### Material policy error codes

| Code | Meaning |
|---|---|
| `CONCENTRATION_REQUIRED` | Material policy requires concentration, but none was provided. |
| `EXPIRY_REQUIRED` | Material policy requires expiry, but no expiry was provided or derived. |
| `MATERIAL_NOT_REUSABLE` | Caller tried to reuse or partially reserve a single-use material incorrectly. |
| `PROJECT_SCOPE_VIOLATION` | Caller tried to use project-specific stock for another project. |
| `MATERIAL_POLICY_VIOLATION` | Generic handling rule failure from `MaterialTypePolicy`. |

### Status codes

| Status | Meaning |
|---|---|
| `200 OK` | Successful read or successful state-changing action with a response body. |
| `201 Created` | New resource created. |
| `202 Accepted` | Long-running feasibility or allocation calculation accepted. Not required for V1. |
| `400 Bad Request` | Invalid input shape or impossible request. |
| `404 Not Found` | Resource does not exist. |
| `409 Conflict` | State conflict, such as over-reservation or consuming an already depleted lot. |
| `422 Unprocessable Entity` | Valid JSON, but the lab/domain rule fails. |

## Core Resource Summary

| Resource | Description |
|---|---|
| `MaterialTypePolicy` | Defines handling behavior for a material type, such as reusable, project-specific, ordered, produced in-house, concentration-required, expiry-required, or single-use. |
| `Material` | Definition of a DNA, sample, target protein, buffer, consumable, or other material. |
| `InventoryLot` | Physical or logical stock of one material at a known quantity, concentration, status, expiry, and location. |
| `InventoryReservation` | Quantity reserved from a lot for an experiment or workflow step. |
| `InventoryEvent` | A grouped inventory action, such as receive, consume, transfer, produce, discard, or adjust. |
| `InventoryTransaction` | Quantity-level effect of an event against one inventory lot. |
| `Recipe` | Definition of workflow steps and expected material inputs/outputs. |
| `WorkflowRun` | Planned or executed instance of a recipe for an experiment. |
| `WorkflowStepRun` | Planned or executed instance of a single recipe step. |
| `StorageLocation` | Lab location, freezer, shelf, rack, or other nested storage place. |
| `ContainerPosition` | Specific tube, plate well, or position where stock is located. |

---

# Material Policy API

## 0. List material type policies

```http
GET /v1/material-type-policies
```

Returns the handling rules for supported material types. For V1, these policies are read-only or admin-managed.

### Response

```json
{
  "items": [
    {
      "id": "mtp_target_protein",
      "materialType": "target_protein",
      "isReusable": true,
      "isProjectSpecific": false,
      "isOrdered": true,
      "isProducedInHouse": false,
      "requiresConcentration": true,
      "requiresExpiry": true,
      "defaultExpiryDays": null,
      "defaultStorageCondition": "freezer"
    },
    {
      "id": "mtp_consumable",
      "materialType": "consumable",
      "isReusable": false,
      "isProjectSpecific": false,
      "isOrdered": true,
      "isProducedInHouse": false,
      "requiresConcentration": false,
      "requiresExpiry": false,
      "defaultExpiryDays": null,
      "defaultStorageCondition": "room_temperature"
    }
  ]
}
```

---

# Inventory Read API

## 1. Search materials

```http
GET /v1/materials?
  type=target_protein
  &
  projectId=proj_123
  &
  query=EGFR
  &
  includeAvailability=true
  &
  includePolicy=true
```

Returns material definitions with optional summarized inventory availability.

### Response

```json
{
  "items": [
    {
      "id": "mat_target_egfr",
      "name": "EGFR Target Protein",
      "materialType": "target_protein",
      "defaultUnit": "uL",
      "handlingPolicy": {
        "isReusable": true,
        "isProjectSpecific": false,
        "isOrdered": true,
        "isProducedInHouse": false,
        "requiresConcentration": true,
        "requiresExpiry": true,
        "defaultExpiryDays": null,
        "defaultStorageCondition": "freezer"
      },
      "availability": {
        "totalQuantity": 500,
        "reservedQuantity": 120,
        "freeQuantity": 380,
        "unit": "uL",
        "usableLotCount": 3,
        "expiredLotCount": 0
      }
    }
  ]
}
```

## 2. Get material inventory lots

```http
GET /v1/materials/{materialId}/inventory-lots?
    status=available
    &
    includeLocation=true
    &
    includeReservations=true
    &
    includePolicy=true
```

Shows all lots for one material, including where they are stored and how much is free.

### Response

```json
{
  "material": {
    "id": "mat_target_egfr",
    "name": "EGFR Target Protein",
    "materialType": "target_protein",
    "defaultUnit": "uL",
    "handlingPolicy": {
      "isReusable": true,
      "isProjectSpecific": false,
      "requiresConcentration": true,
      "requiresExpiry": true
    }
  },
  "lots": [
    {
      "id": "lot_001",
      "lotCode": "EGFR-2026-06-A",
      "status": "available",
      "currentQuantity": 200,
      "reservedQuantity": 50,
      "freeQuantity": 150,
      "unit": "uL",
      "concentration": 1.2,
      "concentrationUnit": "mg/mL",
      "expiresAt": "2030-06-01",
      "location": {
        "storagePath": "Freezer 2 / Shelf B / Rack 4",
        "container": "Tube Box 11",
        "positionCode": "C7"
      }
    }
  ]
}
```

## 3. Get inventory lot detail

```http
GET /v1/inventory-lots/{lotId}
```

Returns the current state of one physical stock lot.

### Response

```json
{
  "id": "lot_001",
  "materialId": "mat_target_egfr",
  "materialName": "EGFR Target Protein",
  "materialType": "target_protein",
  "projectId": null,
  "ownershipScope": "shared_lab",
  "status": "available",
  "currentQuantity": 200,
  "reservedQuantity": 50,
  "freeQuantity": 150,
  "unit": "uL",
  "concentration": 1.2,
  "concentrationUnit": "mg/mL",
  "expiresAt": "2030-06-01",
  "receivedAt": "2026-06-10",
  "handlingPolicy": {
    "isReusable": true,
    "isProjectSpecific": false,
    "requiresConcentration": true,
    "requiresExpiry": true
  },
  "location": {
    "storageLocationId": "loc_freezer_2",
    "storagePath": "Freezer 2 / Shelf B / Rack 4",
    "containerId": "cont_tube_box_11",
    "containerType": "tube_box",
    "positionId": "pos_c7",
    "positionCode": "C7"
  }
}
```

## 4. Check availability for one material

```http
GET /v1/inventory/availability?
    materialId=mat_target_egfr
    &
    requiredQuantity=120
    &
    unit=uL&projectId=proj_123
    &
    minConcentration=1.0
    &
    requiredBy=2026-06-20
```

Answers whether enough usable, unexpired, unreserved stock exists for one material.

### Response

```json
{
  "materialId": "mat_target_egfr",
  "requiredQuantity": 120,
  "unit": "uL",
  "isAvailable": true,
  "totalUsableQuantity": 500,
  "reservedQuantity": 120,
  "freeQuantity": 380,
  "handlingPolicy": {
    "isReusable": true,
    "isProjectSpecific": false,
    "requiresConcentration": true,
    "requiresExpiry": true
  },
  "allocationSuggestion": [
    {
      "inventoryLotId": "lot_001",
      "quantity": 120,
      "unit": "uL",
      "reason": "Earliest expiry lot with sufficient concentration."
    }
  ],
  "warnings": []
}
```

## 5. List expiring or expired inventory

```http
GET /v1/inventory-lots/expiring?
    before=2026-07-16
    &
    materialType=buffer
    &
    projectId=proj_123
```

Used by lab operators and planners to find stock that is no longer viable or close to expiry.

### Response

```json
{
  "items": [
    {
      "inventoryLotId": "lot_loading_buffer_01",
      "materialId": "mat_loading_buffer",
      "materialName": "Loading Buffer",
      "materialType": "buffer",
      "currentQuantity": 35,
      "unit": "mL",
      "expiresAt": "2026-06-18",
      "daysUntilExpiry": 2,
      "status": "available",
      "location": {
        "storagePath": "Fridge 1 / Shelf A",
        "container": "Bottle LB-01"
      }
    }
  ]
}
```

## 6. Locate inventory by storage location

```http
GET /v1/storage-locations/{locationId}/contents?
  includeNested=true
  &
  materialType=dna
```

Shows what is stored in a freezer, shelf, rack, plate, tube box, or other storage area.

### Response

```json
{
  "location": {
    "id": "loc_freezer_2",
    "name": "Freezer 2",
    "locationType": "freezer"
  },
  "contents": [
    {
      "inventoryLotId": "lot_dna_123_a01",
      "materialId": "mat_dna_123",
      "materialName": "Project 123 DNA A01",
      "materialType": "dna",
      "quantity": 20,
      "unit": "uL",
      "concentration": 50,
      "concentrationUnit": "ng/uL",
      "container": "Twist Plate TP-2026-04",
      "positionCode": "A01",
      "status": "available"
    }
  ]
}
```

## 7. Get inventory event history for a lot

```http
GET /v1/inventory-lots/{lotId}/events
```

Shows how a lot was received, moved, reserved, consumed, adjusted, or discarded.

### Response

```json
{
  "inventoryLotId": "lot_001",
  "events": [
    {
      "eventId": "evt_receive_001",
      "eventType": "receive",
      "createdAt": "2026-06-10T09:30:00Z",
      "reason": "Received target protein order PO-2026-88",
      "transaction": {
        "quantityDelta": 500,
        "unit": "uL"
      },
      "workflowStepRunId": null,
      "purchaseOrderLineId": "pol_001"
    },
    {
      "eventId": "evt_consume_001",
      "eventType": "consume",
      "createdAt": "2026-06-12T14:20:00Z",
      "reason": "Binding workflow step consumed target protein",
      "transaction": {
        "quantityDelta": -120,
        "unit": "uL"
      },
      "workflowStepRunId": "step_run_binding_001"
    }
  ]
}
```

---

# Inventory Write API

## 8. Receive ordered stock

```http
POST /v1/inventory-receipts
```

Creates inventory lots when an ordered material physically arrives in the lab.

Material policy validation:

- If `requiresConcentration = true`, concentration is required.
- If `requiresExpiry = true`, `expiresAt` is required unless it can be derived from `defaultExpiryDays`.
- If `isOrdered = false`, receiving through this endpoint is rejected unless an override is allowed.
- If `isProjectSpecific = true`, `projectId` is required.

### Request

```json
{
  "purchaseOrderLineId": "pol_001",
  "materialId": "mat_target_egfr",
  "receivedAt": "2026-06-10",
  "lots": [
    {
      "lotCode": "EGFR-2026-06-A",
      "quantity": 500,
      "unit": "uL",
      "concentration": 1.2,
      "concentrationUnit": "mg/mL",
      "expiresAt": "2030-06-01",
      "containerPositionId": "pos_c7",
      "ownershipScope": "shared_lab"
    }
  ],
  "reason": "Received supplier shipment."
}
```

### Response

```json
{
  "inventoryEventId": "evt_receive_001",
  "createdLots": [
    {
      "inventoryLotId": "lot_001",
      "materialId": "mat_target_egfr",
      "currentQuantity": 500,
      "unit": "uL",
      "status": "available"
    }
  ]
}
```

## 9. Produce inventory from a workflow step

```http
POST /v1/inventory-productions
```

Creates a new lot from an in-house process, such as Twist Plate to Dilution Plate, DNA to expressed sample, or buffer preparation.

Material policy validation:

- If `isProducedInHouse = false`, production is rejected unless an override is allowed.
- If `requiresConcentration = true`, the produced lot must include concentration.
- If `requiresExpiry = true`, the produced lot must include expiry or derive it from policy.

### Request

```json
{
  "workflowStepRunId": "step_run_dilution_001",
  "outputMaterialId": "mat_dna_dilution_plate_123",
  "outputLot": {
    "lotCode": "DIL-PLATE-2026-06-16",
    "quantity": 80,
    "unit": "uL",
    "concentration": 10,
    "concentrationUnit": "ng/uL",
    "expiresAt": "2031-06-16",
    "containerPositionId": "pos_dilution_plate_a01",
    "projectId": "proj_123",
    "ownershipScope": "project"
  },
  "sourceLots": [
    {
      "inventoryLotId": "lot_twist_plate_a01",
      "quantityUsed": 20,
      "unit": "uL"
    }
  ],
  "reason": "Created dilution plate from received Twist Plate."
}
```

### Response

```json
{
  "inventoryEventId": "evt_produce_001",
  "createdLot": {
    "inventoryLotId": "lot_dilution_plate_a01",
    "materialId": "mat_dna_dilution_plate_123",
    "currentQuantity": 80,
    "unit": "uL"
  },
  "sourceTransactions": [
    {
      "inventoryLotId": "lot_twist_plate_a01",
      "quantityDelta": -20,
      "unit": "uL"
    }
  ]
}
```

## 10. Reserve inventory for a workflow step

```http
POST /v1/inventory-reservations
```

Reserves only the required quantity from one or more lots. This is important for reusable target proteins, where one tube should not be blocked entirely if enough material remains for other work.

Material policy validation:

- Reusable materials may be partially reserved.
- Non-reusable materials should usually reserve the full required unit.
- Project-specific stock cannot be allocated to another project.
- Expired, depleted, discarded, or quarantined lots cannot be reserved.
- Concentration-required materials must satisfy `minConcentration`.

### Request

```json
{
  "workflowStepRunId": "step_run_binding_001",
  "experimentId": "exp_001",
  "requirements": [
    {
      "materialId": "mat_target_egfr",
      "requiredQuantity": 120,
      "unit": "uL",
      "minConcentration": 1.0,
      "concentrationUnit": "mg/mL"
    },
    {
      "materialId": "mat_bli_plate",
      "requiredQuantity": 1,
      "unit": "plate"
    }
  ],
  "allocationMode": "system_suggested",
  "reservationExpiresAt": "2026-06-21T00:00:00Z"
}
```

### Response

```json
{
  "reservationGroupId": "res_group_001",
  "status": "reserved",
  "reservations": [
    {
      "reservationId": "res_001",
      "inventoryLotId": "lot_001",
      "materialId": "mat_target_egfr",
      "reservedQuantity": 120,
      "unit": "uL"
    },
    {
      "reservationId": "res_002",
      "inventoryLotId": "lot_bli_plate_09",
      "materialId": "mat_bli_plate",
      "reservedQuantity": 1,
      "unit": "plate"
    }
  ]
}
```

## 11. Release a reservation

```http
POST /v1/inventory-reservations/{reservationId}/release
```

Releases reserved material when a workflow step is cancelled, changed, or no longer needs the stock.

### Request

```json
{
  "reason": "Workflow step cancelled after planning change."
}
```

### Response

```json
{
  "reservationId": "res_001",
  "status": "released",
  "releasedQuantity": 120,
  "unit": "uL"
}
```

## 12. Consume inventory

```http
POST /v1/inventory-consumptions
```

Records partial or full consumption during workflow execution. Consumption may use existing reservations or directly consume from a lot when allowed by policy.

Material policy validation:

- Reusable materials may be partially consumed.
- Single-use materials should become depleted or discarded after use.
- Project-specific material cannot be consumed by another project.
- Expired or quarantined lots cannot be consumed.

### Request

```json
{
  "workflowStepRunId": "step_run_binding_001",
  "items": [
    {
      "inventoryLotId": "lot_001",
      "reservationId": "res_001",
      "quantity": 120,
      "unit": "uL"
    },
    {
      "inventoryLotId": "lot_bli_plate_09",
      "reservationId": "res_002",
      "quantity": 1,
      "unit": "plate"
    }
  ],
  "reason": "Binding experiment setup completed."
}
```

### Response

```json
{
  "inventoryEventId": "evt_consume_001",
  "status": "recorded",
  "transactions": [
    {
      "inventoryLotId": "lot_001",
      "quantityDelta": -120,
      "remainingQuantity": 380,
      "unit": "uL"
    },
    {
      "inventoryLotId": "lot_bli_plate_09",
      "quantityDelta": -1,
      "remainingQuantity": 0,
      "unit": "plate"
    }
  ]
}
```

## 13. Transfer inventory to another location

```http
POST /v1/inventory-transfers
```

Records physical movement from one container position to another.

### Request

```json
{
  "inventoryLotId": "lot_001",
  "fromContainerPositionId": "pos_c7",
  "toContainerPositionId": "pos_d4",
  "reason": "Moved target protein tube to active workflow rack."
}
```

### Response

```json
{
  "inventoryEventId": "evt_transfer_001",
  "inventoryLotId": "lot_001",
  "fromContainerPositionId": "pos_c7",
  "toContainerPositionId": "pos_d4",
  "status": "transferred"
}
```

## 14. Discard inventory

```http
POST /v1/inventory-discards
```

Marks inventory as discarded, expired, contaminated, depleted, or single-use consumed.

### Request

```json
{
  "inventoryLotId": "lot_gfp_plate_001",
  "discardQuantity": 1,
  "unit": "plate",
  "discardReason": "GFP plate used once and discarded after workflow step.",
  "workflowStepRunId": "step_run_gfp_001"
}
```

### Response

```json
{
  "inventoryEventId": "evt_discard_001",
  "inventoryLotId": "lot_gfp_plate_001",
  "quantityDelta": -1,
  "remainingQuantity": 0,
  "status": "discarded"
}
```

---

# Workflow Read API

## 15. List workflow recipes

```http
GET /v1/workflow-recipes?
    workflowType=binding
    &
    active=true
```

Returns available recipe definitions for planning workflow runs.

### Response

```json
{
  "items": [
    {
      "id": "recipe_binding_v1",
      "name": "Binding Workflow",
      "workflowType": "binding",
      "version": 1,
      "isActive": true,
      "steps": [
        {
          "id": "step_reconstitution",
          "stepKey": "target_reconstitution",
          "name": "Target Protein Reconstitution",
          "stepOrder": 1
        },
        {
          "id": "step_binding",
          "stepKey": "binding_assay",
          "name": "Binding Assay",
          "stepOrder": 2
        }
      ]
    }
  ]
}
```

## 16. Get material plan for a workflow run

```http
GET /v1/workflow-runs/{workflowRunId}/material-plan?
    includeReruns=true
    &
    includePolicy=true
```

Shows expected inputs and outputs for a workflow run before reserving stock.

### Response

```json
{
  "workflowRunId": "wr_001",
  "recipeId": "recipe_binding_v1",
  "plannedRerunCount": 1,
  "requiredMaterials": [
    {
      "recipeStepId": "step_binding",
      "materialId": "mat_target_egfr",
      "materialName": "EGFR Target Protein",
      "materialType": "target_protein",
      "requiredQuantityPerRun": 120,
      "totalRequiredQuantity": 240,
      "unit": "uL",
      "isConsumed": true,
      "handlingPolicy": {
        "isReusable": true,
        "isProjectSpecific": false,
        "requiresConcentration": true,
        "requiresExpiry": true
      }
    },
    {
      "recipeStepId": "step_binding",
      "materialId": "mat_bli_plate",
      "materialName": "BLI Plate",
      "requiredQuantityPerRun": 1,
      "totalRequiredQuantity": 2,
      "unit": "plate",
      "isConsumed": true,
      "handlingPolicy": {
        "isReusable": false,
        "isProjectSpecific": false,
        "requiresConcentration": false,
        "requiresExpiry": false
      }
    }
  ]
}
```

## 17. Check workflow feasibility

```http
POST /v1/workflow-runs/{workflowRunId}/feasibility-checks
```

Uses the recipe, workflow run, planned rerun count, existing reservations, expiry, concentration, material policy, and location rules to answer whether the workflow can run.

`POST` is used because the request can include planning assumptions and optional overrides. The endpoint does not mutate inventory unless `createReservations` is true.

### Request

```json
{
  "plannedRerunCount": 1,
  "requiredBy": "2026-06-20",
  "createReservations": false,
  "allocationMode": "earliest_expiry_first",
  "overrides": [
    {
      "materialId": "mat_target_egfr",
      "requiredQuantity": 240,
      "unit": "uL"
    }
  ]
}
```

### Response

```json
{
  "workflowRunId": "wr_001",
  "isFeasible": false,
  "summary": {
    "requiredMaterialCount": 5,
    "availableMaterialCount": 4,
    "blockedMaterialCount": 1
  },
  "materials": [
    {
      "materialId": "mat_target_egfr",
      "materialName": "EGFR Target Protein",
      "requiredQuantity": 240,
      "unit": "uL",
      "freeQuantity": 380,
      "isAvailable": true,
      "blockingReason": null,
      "handlingPolicy": {
        "isReusable": true,
        "isProjectSpecific": false,
        "requiresConcentration": true,
        "requiresExpiry": true
      },
      "allocationSuggestion": [
        {
          "inventoryLotId": "lot_001",
          "quantity": 240,
          "unit": "uL"
        }
      ]
    },
    {
      "materialId": "mat_bli_plate",
      "materialName": "BLI Plate",
      "requiredQuantity": 2,
      "unit": "plate",
      "freeQuantity": 1,
      "isAvailable": false,
      "blockingReason": "INSUFFICIENT_AVAILABLE_QUANTITY",
      "shortageQuantity": 1,
      "handlingPolicy": {
        "isReusable": false,
        "isProjectSpecific": false,
        "requiresConcentration": false,
        "requiresExpiry": false
      }
    }
  ],
  "recommendedActions": [
    {
      "type": "order_material",
      "materialId": "mat_bli_plate",
      "quantity": 1,
      "unit": "plate",
      "reason": "Only one unreserved BLI Plate is available, but two are required including planned rerun."
    }
  ]
}
```

## 18. Get workflow run detail

```http
GET /v1/workflow-runs/{workflowRunId}
```

Returns workflow state, step state, material reservations, and high-level inventory readiness.

### Response

```json
{
  "id": "wr_001",
  "experimentId": "exp_001",
  "recipeId": "recipe_binding_v1",
  "runNumber": 1,
  "status": "planned",
  "plannedRerunCount": 1,
  "steps": [
    {
      "workflowStepRunId": "step_run_binding_001",
      "recipeStepId": "step_binding",
      "stepKey": "binding_assay",
      "name": "Binding Assay",
      "status": "planned",
      "reservationStatus": "partially_reserved"
    }
  ],
  "inventoryReadiness": {
    "isFeasible": false,
    "blockingMaterialCount": 1
  }
}
```

---

# Workflow Write API

## 19. Create workflow run

```http
POST /v1/workflow-runs
```

Creates planned workflow execution from a recipe and experiment.

### Request

```json
{
  "experimentId": "exp_001",
  "recipeId": "recipe_binding_v1",
  "plannedRerunCount": 1
}
```

### Response

```json
{
  "workflowRunId": "wr_001",
  "status": "planned",
  "createdStepRuns": [
    {
      "workflowStepRunId": "step_run_reconstitution_001",
      "recipeStepId": "step_reconstitution",
      "status": "planned"
    },
    {
      "workflowStepRunId": "step_run_binding_001",
      "recipeStepId": "step_binding",
      "status": "planned"
    }
  ]
}
```

## 20. Start workflow run

```http
POST /v1/workflow-runs/{workflowRunId}/start
```

Starts a workflow run after feasibility and reservation checks pass.

### Request

```json
{
  "requireFeasibleInventory": true,
  "reason": "Starting scheduled Binding workflow."
}
```

### Response

```json
{
  "workflowRunId": "wr_001",
  "status": "in_progress",
  "startedAt": "2026-06-16T13:00:00Z"
}
```

## 21. Complete workflow step

```http
POST /v1/workflow-step-runs/{workflowStepRunId}/complete
```

Completes a workflow step and optionally records actual inventory consumption and produced output lots in one operation.

This keeps the workflow state and inventory state consistent.

### Request

```json
{
  "completedAt": "2026-06-16T15:30:00Z",
  "consumedInventory": [
    {
      "inventoryLotId": "lot_001",
      "reservationId": "res_001",
      "quantity": 120,
      "unit": "uL"
    }
  ],
  "producedInventory": [
    {
      "materialId": "mat_sample_expression_plate_123",
      "lotCode": "EXP-PLATE-2026-06-16",
      "quantity": 80,
      "unit": "uL",
      "concentration": 0.8,
      "concentrationUnit": "mg/mL",
      "expiresAt": "2026-06-30",
      "containerPositionId": "pos_expression_plate_a01",
      "projectId": "proj_123"
    }
  ],
  "qcResult": {
    "status": "passed",
    "notes": "Measured concentration within expected range."
  }
}
```

### Response

```json
{
  "workflowStepRunId": "step_run_expression_001",
  "status": "completed",
  "inventoryEvents": [
    {
      "inventoryEventId": "evt_consume_002",
      "eventType": "consume"
    },
    {
      "inventoryEventId": "evt_produce_002",
      "eventType": "produce"
    }
  ],
  "createdLots": [
    {
      "inventoryLotId": "lot_expression_plate_a01",
      "materialId": "mat_sample_expression_plate_123"
    }
  ]
}
```

## 22. Mark workflow step QC failed and plan rerun

```http
POST /v1/workflow-step-runs/{workflowStepRunId}/qc-failures
```

Records that a step failed QC and creates planning pressure for a rerun.

### Request

```json
{
  "failureReason": "Binding signal below threshold.",
  "requiresRerun": true,
  "rerunFromRecipeStepId": "step_binding",
  "reserveMaterialsForRerun": false
}
```

### Response

```json
{
  "workflowStepRunId": "step_run_binding_001",
  "status": "qc_failed",
  "rerunRequired": true,
  "recommendedNextCall": {
    "method": "POST",
    "path": "/v1/workflow-runs/wr_001/feasibility-checks"
  }
}
```

## 23. Complete workflow run

```http
POST /v1/workflow-runs/{workflowRunId}/complete
```

Completes the workflow run after all required step runs are completed or intentionally skipped.

### Request

```json
{
  "completedAt": "2026-06-16T18:00:00Z",
  "summary": "Binding workflow completed after one successful run."
}
```

### Response

```json
{
  "workflowRunId": "wr_001",
  "status": "completed",
  "completedAt": "2026-06-16T18:00:00Z"
}
```

---

# Main Use Case Mapping

## Do I have enough materials to complete my lab tasks?

Primary call:

```http
POST /v1/workflow-runs/{workflowRunId}/feasibility-checks
```

Supporting calls:

```http
GET /v1/workflow-runs/{workflowRunId}/material-plan
GET /v1/inventory/availability?materialId=...
POST /v1/inventory-reservations
```

## Do we have enough material for expected QC reruns?

Use `plannedRerunCount` on the workflow run or pass it into the feasibility check.

```json
{
  "plannedRerunCount": 1,
  "createReservations": false
}
```

## Can target proteins be reused across projects?

Primary calls:

```http
GET /v1/materials/{materialId}/inventory-lots?includeReservations=true&includePolicy=true
GET /v1/inventory/availability?materialId=...&projectId=...
POST /v1/inventory-reservations
```

The API reserves quantity, not whole lots. This allows shared target protein tubes to remain partly available when enough free quantity remains.

This behavior comes from `MaterialTypePolicy.isReusable`.

## Are materials still viable?

Primary calls:

```http
GET /v1/inventory-lots/expiring?before=...
GET /v1/inventory-lots/{lotId}
POST /v1/workflow-runs/{workflowRunId}/feasibility-checks
```

Feasibility checks should exclude expired lots and lots that expire before the required date.

This behavior uses:

- lot `expiresAt`
- lot `status`
- `MaterialTypePolicy.requiresExpiry`
- workflow `requiredBy`

## Where are materials stored?

Primary calls:

```http
GET /v1/materials/{materialId}/inventory-lots?includeLocation=true
GET /v1/storage-locations/{locationId}/contents?includeNested=true
GET /v1/inventory-lots/{lotId}
```

---

# Read vs Write Design

## Read model

The read API is optimized for planning and lab lookup. It returns computed fields such as:

- `currentQuantity`
- `reservedQuantity`
- `freeQuantity`
- `isAvailable`
- `blockingReason`
- `allocationSuggestion`
- `storagePath`
- `handlingPolicy`

These values may be backed by SQL views or query services. The frontend should not calculate availability from raw transactions.

## Write model

The write API records lab facts:

- stock was received
- stock was produced
- stock was reserved
- stock was consumed
- stock was moved
- stock was discarded
- workflow step passed or failed QC

Behind the API, these writes create durable inventory events, transactions, reservations, workflow state updates, and audit records.

## Why not expose raw CRUD for every table?

Raw CRUD would make the frontend responsible for business rules such as:

- excluding expired lots
- avoiding over-reservation
- consuming reservations correctly
- linking consumption to workflow steps
- selecting reusable target protein lots
- enforcing project-specific material scope
- requiring concentration for proteins and DNA
- requiring expiry for buffers and other expiring materials
- preserving inventory event history

That would spread domain logic across clients. The API should keep those rules server-side and expose domain-level operations.

---

# Material Policy Behavior

`MaterialTypePolicy` centralizes material behavior.

The API remains centered on materials, lots, reservations, events, and workflow runs. The policy does not require a major endpoint redesign. It mainly tells the server how to validate receive, produce, reserve, consume, discard, and feasibility operations.

This keeps rules such as reuse, expiry, concentration, and project scope out of frontend code.

## Policy fields and API impact

| Policy Field | API Impact |
|---|---|
| `isReusable` | Allows partial reservation and partial consumption while leaving remaining quantity available. |
| `isProjectSpecific` | Restricts allocation to matching project stock unless shared use is explicitly allowed. |
| `isOrdered` | Allows material to be received through `POST /v1/inventory-receipts`. |
| `isProducedInHouse` | Allows material to be created through `POST /v1/inventory-productions`. |
| `requiresConcentration` | Requires concentration on received or produced lots and checks concentration during feasibility. |
| `requiresExpiry` | Requires expiry on lots or derives expiry from `defaultExpiryDays`. |
| `defaultExpiryDays` | Allows the server to calculate expiry when explicit `expiresAt` is not provided. |
| `defaultStorageCondition` | Helps suggest or validate storage location type. |

---

# Scope Cut From V1

| Cut | Reason |
|---|---|
| Full procurement approval workflow | Purchase orders exist only as references for receiving stock. Finance and approval flows are outside this inventory API. |
| Full LIMS, ELN, robotics, or procurement integration | The API should be integration-ready, but actual integrations are not needed for this design exercise. |
| Unit conversion engine | V1 assumes each material has a canonical unit and requests must use compatible units. |
| Complex allocation optimization | V1 can allocate earliest-expiry-first and concentration-compatible lots. Cost optimization can come later. |
| Full GxP electronic signature workflow | The model is audit-ready, but formal Part 11-style signing is future scope. |
| Barcode scanning UI | Barcode identifiers can be stored, but scanner UX is outside this API design. |
| Full material policy admin UI | V1 can treat material policies as seeded/configured domain records. |