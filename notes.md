# Open Design Notes

## Endpoint style choice

Some write endpoints use domain action resources such as `inventory-consumptions`, `inventory-transfers`, and `feasibility-checks`. This is intentional. A perfectly generic REST design would expose `POST /inventory-events`, but that would force callers to understand too much internal event structure.

The chosen design keeps the API clean at the boundary: each endpoint has one reason to change and maps to one lab operation.

## Reservation choice

Reservations are first-class resources because physical stock and available stock are not the same. This is especially important for reusable target proteins, where one tube can be partially reserved while the remaining volume stays available for another project.

## Material policy choice

Material behavior is centralized in `MaterialTypePolicy`.

This avoids duplicating fields like `isReusable`, `isProjectSpecific`, and `requiresConcentration` across every material record. A material still describes what the thing is. The policy describes how that kind of thing behaves.

This keeps the design flexible without hiding important lab rules in generic metadata.

## Workflow choice

Workflow APIs are centered on `WorkflowRun` and `WorkflowStepRun`, not on individual database writes. This keeps the lab process readable: users plan a run, check feasibility, reserve material, execute steps, record consumption/output, and handle reruns if QC fails.

## Unit handling choice

V1 does not implement a full unit conversion engine.

Each material has a canonical unit, and requests must use compatible units. APIs may accept display units later, but persistence should use the canonical unit per material.
````
