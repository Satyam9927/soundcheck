# Real-Kong differential conformance

This opt-in harness sends a fixed request matrix through a pinned Kong OSS
3.9.3 container and through Soundcheck's concrete IR evaluator, then compares
the decision, selected route, and selected service. It runs both supported
router flavors: `traditional` and `traditional_compatible`.

The matrix covers literal and regex paths, methods, hosts, exact headers, route
priority, service-less routes, default denial, HTTP/HTTPS protocol selection,
exact SNI, and Kong's HTTP bypass of SNI matching. Plugin execution remains a
follow-up slice only where it materially improves the assurance claim.

Docker is intentionally not part of `dune test`. Run the harness explicitly:

```sh
bench/kong/conformance/run.sh
```

The Kong image is pinned by version and multi-platform digest. The configured
upstream is Kong's own Admin API status endpoint, keeping the test independent
of external services and additional containers. A mismatch reports the router
flavor, probe request, and both observations.
