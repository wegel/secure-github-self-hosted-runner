#!/bin/sh

container_name="github-runner-${GITHUB_JOB_ID}-${GITHUB_JOB_SHORT_HASH}"
podman stop -t 0 ${container_name}
podman rm ${container_name}

echo "Cleanup complete"
