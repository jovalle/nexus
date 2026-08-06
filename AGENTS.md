# techn.is Split-Horizon DNS Contract

These requirements apply whenever an agent adds, moves, repairs, or removes a publicly available service under `*.techn.is`.

## Required request paths

Public and LAN clients must use the same canonical HTTPS hostname, but DNS must send them through different paths.

### Public path

```text
Public DNS (Cloudflare-proxied hostname)
  -> Cloudflare Access
  -> Google authentication and the existing techn.is allow policy
  -> Cloudflare Tunnel
  -> owning service
  -> the service's own login, when the application provides one
```

Do not expose a public `*.techn.is` service around Cloudflare Access unless the user explicitly approves an exception.

### LAN path

```text
Technitium split-horizon A record
  -> the owning LAN host's Traefik instance
  -> owning service
  -> the service's own login, when the application provides one
```

LAN requests must bypass Cloudflare and Cloudflare Access. They must not bypass an application's native authentication.

## DNS and routing ownership

- LAN DNS is served by Technitium at `192.168.1.2` and `192.168.1.3`.
- Services owned by Nexus resolve to the Nexus LAN address, `192.168.1.3`.
- Internal DNS records are discovered from Traefik routers by `external-dns`; adding only a Cloudflare record or tunnel ingress is insufficient.
- The current internal source precedence is Nexus, then Stargate, then Mothership, with takeover of existing records enabled. Define the canonical hostname only on its intended owner so precedence does not conceal a collision.
- Public DNS must remain Cloudflare-proxied and route to the intended Cloudflare Tunnel.
- The Cloudflare Tunnel container and the destination container must share a Docker network when tunnel ingress uses a Docker service name.
- The local Traefik instance and the destination container must likewise share a reachable Docker network.
- A hostname has one canonical application owner. Before assigning a hostname, search Cloudflare DNS, Cloudflare Access, tunnel ingress, all Traefik configurations, and internal DNS for an existing use.

## Current productivity hostnames

| Hostname | Application | Nexus upstream |
| --- | --- | --- |
| `tasks.techn.is` | Vikunja | `http://vikunja:3456` |
| `links.techn.is` | Linkwarden | `http://linkwarden:3000` |
| `keep.techn.is` | Karakeep | `http://karakeep:3000` |

`links.techn.is` belongs to Linkwarden. Do not reuse it for Karakeep or another bookmarking application; Karakeep's canonical hostname is `keep.techn.is`.

## Change checklist

For every new or moved public service:

1. Select a unique canonical hostname and check for collisions everywhere listed above.
2. Add or update the local Traefik router and its upstream service.
3. Confirm `external-dns` publishes the LAN A record to both Technitium servers.
4. Add or update the proxied Cloudflare DNS record and Cloudflare Tunnel ingress.
5. Protect the hostname with a Cloudflare Access application using Google authentication and the existing techn.is allowance.
6. Preserve the application's native login where applicable and set its canonical/base URL to the public HTTPS hostname.
7. Verify both paths independently before declaring the change complete.

## Verification expectations

At minimum, verify:

```bash
# LAN resolvers must return the owning host's private address.
dig @192.168.1.2 service.techn.is A +short
dig @192.168.1.3 service.techn.is A +short

# A public resolver must return the Cloudflare-proxied result, not the LAN address.
dig @1.1.1.1 service.techn.is A +short

# From the LAN, the request must reach the local service successfully.
curl -I https://service.techn.is
```

Also test the public hostname from outside the LAN or against the public resolver and confirm that Cloudflare Access challenges an unauthenticated request before the service is reachable. After Google authentication, confirm that the service loads and still presents its own login when applicable.

When diagnosing `no available server`, check the client's resolved IP first. A stale LAN answer may send the hostname to a former Traefik owner even when the current service and router are healthy.
