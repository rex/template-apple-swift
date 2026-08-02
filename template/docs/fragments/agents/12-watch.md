`make build-watch` additionally builds `{{app_name}}Watch`. The watch app is a
`dependencies:` entry on `{{app_name}}` — remove that edge and the watch app
still builds and signs but is silently absent from the `.ipa`.
