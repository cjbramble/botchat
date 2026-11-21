# Tiltfile: botchat on the local cluster (Step 12b). Start with `tilt up`, stop with `tilt down`.

# Never touch any other cluster, production included.
if k8s_context() != "kind-botchat":
    fail("this Tiltfile only runs against kind-botchat, not %s; run scripts/local-cluster.sh" % k8s_context())

k8s_yaml(kustomize("deploy/k8s/overlays/local"))

# Build each image from its Dockerfile. Tilt rebuilds on file changes and pushes to the
# local registry; it replaces `image: chat` (and game, bots) in the manifests with the result.
docker_build("chat", "chat")
docker_build("game", "game")
docker_build("bots", "bots")

k8s_resource("postgres", labels=["data"])
k8s_resource("game", resource_deps=["postgres"], labels=["services"])
k8s_resource(
    "chat",
    resource_deps=["postgres", "game"],
    port_forwards=["4000:4000", "4001:4001"],  # the viewer, and the bot socket for smoke tests
    links=[link("http://localhost:4000", "viewer")],
    labels=["services"],
)
local_resource(
    "seed",
    cmd="./scripts/seed-local.sh",
    resource_deps=["chat"],
    labels=["setup"],
)
k8s_resource("bots", resource_deps=["seed"], labels=["services"])
