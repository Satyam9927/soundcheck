# Real-Kong differential conformance

This opt-in harness sends a fixed request matrix through a pinned Kong OSS
3.9.3 container and through Soundcheck's concrete IR evaluator, then compares
the decision, selected route, and selected service. It runs both supported
router flavors: `traditional` and `traditional_compatible`.

The initial slice covers literal and regex paths, methods, hosts, exact headers,
route priority, service-less routes, and default denial. HTTPS/SNI and plugin
execution require additional runtime setup and remain follow-up slices.

Docker is intentionally not part of `dune test`. Run the harness explicitly:

```sh
bench/kong/conformance/run.sh
```

The Kong image is pinned by version and multi-platform digest. The configured
upstream is Kong's own Admin API status endpoint, keeping the test independent
of external services and additional containers. A mismatch reports the router
flavor, probe request, and both observations.
