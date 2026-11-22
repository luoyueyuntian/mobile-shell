# Port Forwarding Types Design

Add Termius-style typed port forwarding rules for personal use. Termius documents port forwarding as local, remote, and dynamic tunneling. MobileShell currently has working local forwarding, but the rule model only has one shape, so the UI cannot distinguish local from reverse tunnels and the live backend cannot start remote forwards.

## Scope

This slice adds a typed model and implements local plus remote port forwarding. Dynamic forwarding is represented as a rule type for UI/model clarity, but live SOCKS forwarding remains unsupported in this slice because it requires a SOCKS5 proxy layer separate from the existing Citadel TCP forwarding APIs.

No team vault, sync, shared rules, or policy management are included.

## Data Model

Add `PortForwardKind: String, Codable, CaseIterable, Identifiable` with:

- `local`: local listener forwards through SSH to a remote target.
- `remote`: SSH server listener forwards back to a local target.
- `dynamic`: local SOCKS-style tunnel placeholder; saved but not started yet.

Extend `PortForwardRule` with:

- `kind: PortForwardKind`, defaulting legacy decoded rules to `.local`.
- `localHost: String`, defaulting legacy decoded rules to `127.0.0.1`.

Interpret fields by kind:

- Local: `localHost:localPort -> remoteHost:remotePort`.
- Remote: `remoteHost:remotePort -> localHost:localPort`.
- Dynamic: `localHost:localPort` is the future SOCKS listener; `remoteHost` and `remotePort` are not used for live start.

The existing `localPort`, `remoteHost`, `remotePort`, and `isActive` properties remain for backwards compatibility and minimal churn.

## Store Behavior

`addPortForwardRule` and `updatePortForwardRule` accept `kind` and `localHost` with defaults so existing call sites remain source-compatible. Rule creation trims hosts, validates required fields, validates ports, and always stores new/edited rules inactive.

`togglePortForwardRule` continues to stop active rules normally. Starting a dynamic rule returns a clear `portForwardErrorMessage` and leaves the rule inactive.

## Live Backend

`CitadelPortForwardingClient` dispatches by rule kind:

- Local: existing `ServerBootstrap` listener and `createDirectTCPIPChannel` path.
- Remote: use Citadel `runRemotePortForward(host:port:forwardingTo:port:)` in a cancellable task; the session is considered started after Citadel invokes `onOpen`.
- Dynamic: throw `PortForwardingError.unsupportedKind(.dynamic)`.

The remote forwarding session owns the SSH client and remote-forwarding task. Stopping the session cancels the task and closes the SSH client.

## UI

The port forwarding editor adds a type picker. Labels adapt to the type:

- Local: "Local bind host", "Local port", "Remote target host", "Remote target port".
- Remote: "Local target host", "Local target port", "Remote bind host", "Remote bind port".
- Dynamic: "Local SOCKS host", "Local SOCKS port"; remote fields can be hidden or explained as unused.

Rows show a direction badge and route summary so a user can scan whether a rule is local, remote, or dynamic. Dynamic rows can be saved but display that live dynamic tunneling is not available yet.

## Testing

Focused tests cover:

- Legacy JSON decodes to `.local` and `127.0.0.1`.
- Adding and updating local rules keeps previous behavior.
- Adding and updating remote rules trims local/remote hosts and stores the kind.
- Starting a remote rule passes the typed rule to the injected client and marks it active.
- Starting a dynamic rule leaves it inactive with an unsupported message.
- Row summary helpers describe local, remote, and dynamic routes.

## References

- Official Termius docs: https://docs.termius.com/organize-and-connect-to-hosts/port-forwarding-and-tunneling

## Self-Review

No placeholders remain. The slice is focused on typed port forwarding and remote forwarding support. Dynamic forwarding is explicitly scoped as model/UI groundwork, not falsely claimed as live SOCKS support.
