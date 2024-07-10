# Secure GitHub Self-Hosted Runner

## The Problem

[GitHub's documentation states](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#self-hosted-runner-security):

> We recommend that you only use self-hosted runners with private repositories. This is because forks of
> your public repository can potentially run dangerous code on your self-hosted runner machine by creating
> a pull request that executes the code in a workflow.
>
> This is not an issue with GitHub-hosted runners because each GitHub-hosted runner is always a clean isolated
> virtual machine, and it is destroyed at the end of the job execution.

## The Solution

Starting something on-demand for every job is not that hard... So, why don't we do exactly that ourselves?

This is precisely what this project accomplishes.

With Secure GitHub Self-Hosted Runner, it's now safe to run a self-hosted runner for a public repository.

## How It Works

This project provides a solution by:

1. Starting a rootless runner container on demand, without any host mounts.
2. This container starts the GitHub Runner.
3. The GitHub Runner can then use podman (podman-in-podman) to start yet another container for the job (if the job is configured to run in a container).
4. After the job is executed, the container is deleted.

We use the GitHub API to monitor workflows and jobs, starting a container only when one is needed to execute a job.

## Key Features

- Isolated Execution: Each job runs in a clean, isolated environment.
- On-Demand Containers: Containers are created only when needed and destroyed after use.
- Rootless Containers: Enhanced security through rootless container execution.
- Podman-in-Podman: Nested containerization when jobs are configured to run in containers.
- Pre-Execution Filtering: Opportunity to examine and filter jobs before execution.

## Security Advantages

Our process includes a pre-execution phase where we can examine workflow and job details, including the account requesting the job. This enables:

- Whitelisting of allowed accounts
- Filtering based on workflow or job information
- Custom security rules as defined by the administrator

## Getting Started

```
GITHUB_TOKEN=mytoken REPO=https://github.com/owner/reponame make run
```

## License

This project is dual-licensed:

1. For personal or non-commercial use:
   This project is licensed under the Apache License 2.0. See the [LICENSE-APACHE.txt](LICENSE-APACHE.txt) file for details.

2. For commercial use:
   A commercial license is required. Please contact me to obtain a commercial license. See the [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md) file for details.

By using this software, you agree to the terms of one of these licenses.
