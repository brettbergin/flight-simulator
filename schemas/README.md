# Contract schemas

These are product wire contracts, not flight-dynamics models. `registry.json` is the local version/hash lock; SHA-256 of its exact UTF-8 bytes is the contract-set fingerprint. `definitions.mjs` is authoritative; `generate.mjs --check` proves generated JSON is current. Schema IDs use the reserved `.invalid` domain and are identifiers, never download endpoints.

From repository root, with Node 20 or newer:

```text
npm ci --ignore-scripts --prefix schemas
npm --prefix schemas run check
node --test tests/contracts/schema.test.mjs
node schemas/validate.mjs tests/contracts/fixtures/ControlCommand.json ControlCommand
```

`validateContract(value, expectedType)` performs strict JSON Schema validation **and** cross-field semantic checks. Consumers must use both stages; an Ajv shape result alone is insufficient. The validator does not coerce, apply defaults, remove fields, modify input, load remote references, or execute content. Test dependencies are pinned Ajv 8.20.0 and ajv-formats 3.0.1, both MIT; they are development tools and are not native runtime dependencies. Their matching license files are included by npm under their respective installed packages.

Author schemas through a contract PR, run `node schemas/generate.mjs`, then `node tests/contracts/make-fixtures.mjs`, and review the schema and fixture hash changes. Do not regenerate fingerprints at application startup or modify an installed schema silently. See [the normative contract specification](../docs/contracts.md) for ownership, clock, frame, unit and compatibility policy.

Content manifests describe rights and hashes. A schema passing does not grant redistribution permission, verify referenced file contents, prove aviation data currency, or prove aircraft fidelity. Installation separately requires checked archive/resource limits, filesystem containment, source/license approval and matching file bytes; those consumer checks belong to the content delivery task.
