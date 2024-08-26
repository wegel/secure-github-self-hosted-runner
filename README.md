# shghr (pronouned "Sugar")

## (Secure) Self-hosted GitHub Runner

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

1. Monitoring GitHub workflows and jobs using the GitHub API.
2. When a job needs to be executed, the main program calls the appropriate executor.
3. The executor's `prepare` stage sets up the environment, typically starting a GitHub Runner instance.
4. Once the environment is ready, the main program calls the executor's `run` stage to execute the job.
5. After the job is completed, the main program calls the executor's `cleanup` stage to destroy the environment.

The main program performs two primary functions:
- Monitors for jobs that need to be run.
- Calls the executor's scripts (`prepare`, `run`, `cleanup`) with the appropriate environment variables gathered from the GitHub API.

## Key Features

- Isolated Execution: Each job runs in a clean, isolated environment.
- On-Demand Environments: Execution environments are created only when needed and destroyed after use.
- Rootless Containers: Enhanced security through rootless container execution.
- Flexible Executors: Support for different execution environments.
- Pre-Execution Filtering: Opportunity to examine and filter jobs before execution.

## Executors

Executors are responsible for preparing, running, and cleaning up the environment for each job. A key security feature of our executors is the use of rootless podman, ensuring that no part of the execution process has root access to the system.

Currently, we support two types of executors:

1. rootless `podman-in-podman`: This executor uses nested containerization, running the GitHub Runner in a nested rootless podman container.
2. rootless `libvirtd-in-podman`: This executor runs the GitHub Runner in a freshly booted virtual machine using libvirtd/qemu from within a rootless podman container.

Both executors leverage rootless podman, providing an additional layer of security by ensuring that the execution environment has no root access to the host system.

Each executor consists of three main scripts:

- `prepare.sh`: Sets up the execution environment, typically starting a GitHub Runner instance.
- `run.sh`: Executes the job within the prepared environment.
- `clean.sh`: Cleans up and destroys the environment after job completion.

The main program calls these scripts as needed for each job execution, passing the appropriate environment variables.

### Adding New Executors

The system is designed to be extensible. New executors can be added as needed by creating the three required scripts (`prepare.sh`, `run.sh`, and `clean.sh`) and integrating them into the main program. This flexibility allows for adaptation to various execution requirements and environments. When adding new executors, it's recommended to maintain the principle of using rootless containers to ensure consistent security across all execution methods.

## Security Advantages

Our process includes a pre-execution phase where we can examine workflow and job details, including the account requesting the job. This enables:

- Whitelisting of allowed accounts
- Filtering based on workflow or job information
- Custom security rules as defined by the administrator

Additionally, the use of rootless podman in our executors ensures that the execution environment has no root access to the host system, significantly enhancing overall security.

## Getting Started

```
EXECUTOR=executors/libvirtd-in-podman GITHUB_TOKEN=mytoken REPO=https://github.com/owner/reponame make run
```

## License

This project is dual-licensed:

1. For personal or non-commercial use:
   This project is licensed under the Apache License 2.0. See the [LICENSE-APACHE.txt](LICENSE-APACHE.txt) file for details.

2. For commercial use:
   A commercial license is required. Please contact me to obtain a commercial license. See the [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md) file for details.

By using this software, you agree to the terms of one of these licenses.
