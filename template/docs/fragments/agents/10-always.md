## 3. Commands the agent MUST run before declaring done

```bash
make build            # iOS app target
make test             # {{app_name}}Tests via the {{app_name}} scheme
make lint             # format + architecture + version gates
```

Schemes: {{schemes_list}}.
