open System
open System.Text
open System.Net.Http
open System.Threading.Tasks
open System.Text.Json
open System.Collections.Generic
open System.Diagnostics
open Microsoft.Extensions.Logging
open System.Security.Cryptography
open SimpleBase

let parseRepoUrl (url: string) =
    let parts = url.Split('/')
    parts[3], parts[4]

let getGithubAppToken () =
    Environment.GetEnvironmentVariable("GITHUB_TOKEN")

type WorkflowRun = {
    Id: int64
    CreatedAt: DateTime
    RawJson: string
}

type Job = {
    Id: int64
    RunId: int64
    Status: string
    Name: string
    RawJson: string
}

type RateLimitInfo = {
    Remaining: int
    Reset: int64
    Limit: int
}

type EtagResponse<'T> = {
    Data: 'T option
    Etag: string option
}

type ExecutorStage =
    | Prepare
    | Run
    | Cleanup

type ExecutorConfig = {
    PrepareScript: string
    RunScript: string
    CleanupScript: string
    BaseDirectory: string
}

type JobExecutionContext = {
    JobId: int64
    RunId: int64
    EnvironmentVariables: Map<string, string>
    ExecutorConfig: ExecutorConfig
}

type SingleLineLogger(categoryName: string, minLevel: LogLevel) =
    let formatMessage (logLevel: LogLevel) (message: string) =
        let shortLogLevel = 
            match logLevel with
            | LogLevel.Trace -> "TRCE"
            | LogLevel.Debug -> "DBUG"
            | LogLevel.Information -> "INFO"
            | LogLevel.Warning -> "WARN"
            | LogLevel.Error -> "FAIL"
            | LogLevel.Critical -> "CRIT"
            | _ -> "UNKN"
        sprintf "[%s] %s: %s" (DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm:ss")) shortLogLevel message

    interface ILogger with
        member _.Log<'TState>(logLevel: LogLevel, eventId: EventId, state: 'TState, exc: Exception, formatter: Func<'TState, Exception, string>) =
            if logLevel >= minLevel then
                let message = formatter.Invoke(state, exc)
                Console.WriteLine(formatMessage logLevel message)

        member _.IsEnabled(logLevel: LogLevel) = logLevel >= minLevel

        member _.BeginScope<'TState>(state: 'TState) = { new IDisposable with member _.Dispose() = () }

type SingleLineLoggerProvider(minLevel: LogLevel) =
    interface ILoggerProvider with
        member _.CreateLogger(categoryName: string) =
            SingleLineLogger(categoryName, minLevel) :> ILogger

    interface IDisposable with
        member _.Dispose() = ()

let deserialize<'T> (json: string) =
    JsonSerializer.Deserialize<'T>(json, JsonSerializerOptions(PropertyNameCaseInsensitive = true))

let parseWorkflowRuns (logger: ILogger) (content: string) =
    let json = JsonDocument.Parse(content)
    let workflowRuns = json.RootElement.GetProperty("workflow_runs")
    let runs = 
        workflowRuns.EnumerateArray()
        |> Seq.map (fun run -> 
            {
                Id = run.GetProperty("id").GetInt64()
                CreatedAt = run.GetProperty("created_at").GetDateTime()
                RawJson = JsonSerializer.Serialize(run)
            })
        |> Seq.toArray
    logger.LogInformation("Parsed {RunCount} workflow runs", runs.Length)
    runs

let parseJobs (logger: ILogger) (content: string) =
    let json = JsonDocument.Parse(content)
    let jobsArray = json.RootElement.GetProperty("jobs")
    
    let jobs = 
        jobsArray.EnumerateArray() 
        |> Seq.map (fun job -> 
            { 
                Id = job.GetProperty("id").GetInt64()
                RunId = job.GetProperty("run_id").GetInt64()
                Status = job.GetProperty("status").GetString()
                Name = job.GetProperty("name").GetString()
                RawJson = JsonSerializer.Serialize(job)
            }) 
        |> Seq.toArray
    logger.LogInformation("Parsed {JobCount} jobs", jobs.Length)
    jobs

let makeRequest (logger: ILogger) (client: HttpClient) (url: string) (etag: string option) =
    task {
        let request = new HttpRequestMessage(HttpMethod.Get, url)
        match etag with
        | Some tag -> request.Headers.Add("If-None-Match", tag)
        | None -> ()

        let! response = client.SendAsync(request)
        let newEtag = 
            response.Headers.ETag 
            |> Option.ofObj 
            |> Option.map (fun e -> e.Tag)

        if response.StatusCode = System.Net.HttpStatusCode.NotModified then
            logger.LogDebug("No changes since last request to {Url} (304 Not Modified).", url)
            return { Data = None; Etag = newEtag }
        else
            let! content = response.Content.ReadAsStringAsync()
            logger.LogDebug("Received response from {Url}", url)
            return { Data = Some content; Etag = newEtag }
    }

let getRecentWorkflowRuns (logger: ILogger) (client: HttpClient) (owner: string) (repo: string) (accessToken: string) (etag: string option) =
    task {
        let url = sprintf "https://api.github.com/repos/%s/%s/actions/runs?status=queued" owner repo
        logger.LogDebug("Requesting workflow runs: {Url}", url)
        client.DefaultRequestHeaders.Authorization <- new Headers.AuthenticationHeaderValue("token", accessToken)

        let! response = makeRequest logger client url etag
        return 
            match response.Data with
            | Some content -> { Data = Some (parseWorkflowRuns logger content); Etag = response.Etag }
            | None -> { Data = None; Etag = response.Etag }
    }

let getJobsForRun (logger: ILogger) (client: HttpClient) (owner: string) (repo: string) (runId: int64) (accessToken: string) (etag: string option) =
    task {
        let url = sprintf "https://api.github.com/repos/%s/%s/actions/runs/%d/jobs" owner repo runId
        logger.LogDebug("Requesting jobs for run {RunId}: {Url}", runId, url)
        client.DefaultRequestHeaders.Authorization <- new Headers.AuthenticationHeaderValue("token", accessToken)

        let! response = makeRequest logger client url etag
        return 
            match response.Data with
            | Some content -> { Data = Some (parseJobs logger content); Etag = response.Etag }
            | None -> { Data = None; Etag = response.Etag }
    }

let getRateLimitInfo (logger: ILogger) (client: HttpClient) (accessToken: string) =
    task {
        let url = "https://api.github.com/rate_limit"
        client.DefaultRequestHeaders.Authorization <- new Headers.AuthenticationHeaderValue("token", accessToken)
        let! response = client.GetStringAsync(url)
        
        let rateLimitResponse = deserialize<{| Resources: {| Core: RateLimitInfo |} |}> response
        let rateLimit = rateLimitResponse.Resources.Core
        
        logger.LogTrace("Rate limit remaining: {Remaining}, reset time: {ResetTime}, limit: {Limit}", 
                              rateLimit.Remaining, rateLimit.Reset, rateLimit.Limit)
        return rateLimit
    }

let executeStage (logger: ILogger) (stage: ExecutorStage) (context: JobExecutionContext) =
    task {
        let scriptPath = 
            match stage with
            | Prepare -> context.ExecutorConfig.PrepareScript
            | Run -> context.ExecutorConfig.RunScript
            | Cleanup -> context.ExecutorConfig.CleanupScript

        let fullPath = System.IO.Path.Combine(context.ExecutorConfig.BaseDirectory, scriptPath)
        
        logger.LogInformation("Executing {Stage} stage for job {JobId}", stage, context.JobId)
        
        let startInfo = new ProcessStartInfo()
        startInfo.FileName <- fullPath
        startInfo.UseShellExecute <- false
        startInfo.RedirectStandardOutput <- true
        startInfo.RedirectStandardError <- true
        startInfo.WorkingDirectory <- context.ExecutorConfig.BaseDirectory

        // Set environment variables
        for KeyValue(key, value) in context.EnvironmentVariables do
            startInfo.EnvironmentVariables.[key] <- value

        use process = new Process()
        process.StartInfo <- startInfo
        process.OutputDataReceived.Add(fun args -> 
            if not (isNull args.Data) then 
                logger.LogInformation("[{Stage}] {Output}\r", stage, args.Data))
        process.ErrorDataReceived.Add(fun args -> 
            if not (isNull args.Data) then 
                logger.LogInformation("[{Stage}] {Error}\r", stage, args.Data))

        process.Start() |> ignore
        process.BeginOutputReadLine()
        process.BeginErrorReadLine()
        do! process.WaitForExitAsync()

        return process.ExitCode
    }

let executeJob (logger: ILogger) (context: JobExecutionContext) =
    task {
        let mutable success = true
        
        // Execute Prepare stage
        let! prepareExitCode = 
            if success then
                executeStage logger Prepare context
            else
                Task.FromResult 0

        if prepareExitCode <> 0 then
            logger.LogError("Prepare stage failed with exit code {ExitCode}", prepareExitCode)
            success <- false

        if success then
            let! runExitCode = executeStage logger Run context
            if runExitCode <> 0 then
                logger.LogError("Run stage failed with exit code {ExitCode}", runExitCode)
                success <- false

        // Always execute Cleanup stage
        let! cleanupExitCode = executeStage logger Cleanup context
        if cleanupExitCode <> 0 then
            logger.LogError("Cleanup stage failed with exit code {ExitCode}", cleanupExitCode)
            // Note: We don't set success to false here as it would override previous failures

        return success
    }

let handlePendingJob (logger: ILogger) (run: WorkflowRun) (job: Job) (executorConfig: ExecutorConfig) (owner: string) (repo: string) (ghToken: string) =
    task {
        logger.LogInformation("Job ID: {JobId}, Name: {JobName}, Status: {JobStatus}, Run ID: {RunId}", 
                              job.Id, job.Name, job.Status, job.RunId)

        let envVars = Map [
            "GITHUB_TOKEN", ghToken
            "GITHUB_URL", $"https://github.com/{owner}/{repo}"
            "GITHUB_RUN", run.RawJson
            "GITHUB_JOB", job.RawJson
            "RUNNER_NAME", $"runner-{job.Id}"
            "RUNNER_WORK_DIRECTORY", $"_work_{job.Id}"
            "SCRIPTS_DIR", executorConfig.BaseDirectory
        ]

        let context = {
            JobId = job.Id
            RunId = job.RunId
            EnvironmentVariables = envVars
            ExecutorConfig = executorConfig
        }

        let! success = executeJob logger context
        if success then
            logger.LogInformation("Job {JobId} executed successfully", job.Id)
        else
            logger.LogError("Job {JobId} execution failed", job.Id)
    }

let waitForRateLimit (logger: ILogger) (rateLimit: RateLimitInfo) =
    task {
        if rateLimit.Remaining < 10 then
            let waitTime = rateLimit.Reset - DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            logger.LogWarning("Approaching rate limit. Waiting for {WaitTime} seconds.", waitTime)
            do! Task.Delay ((int waitTime + 1) * 1000)  // Wait a bit longer to ensure the limit resets
        else
            logger.LogDebug("Sleeping for 1000 milliseconds")
            do! Task.Delay 1000
    }

let pollGitHub (logger: ILogger) (client: HttpClient) (owner: string) (repo: string) (accessToken: string) (executorConfig: ExecutorConfig) =
    task {
        let etagStore = Dictionary<string, string>()
        let mutable lastKnownRuns: WorkflowRun[] option = None

        while true do
            logger.LogTrace("Polling GitHub for workflow runs...")
            let runsUrl = sprintf "https://api.github.com/repos/%s/%s/actions/runs?status=queued" owner repo
            let! runsResponse = getRecentWorkflowRuns logger client owner repo accessToken (etagStore.TryGetValue(runsUrl) |> snd |> Some)

            match runsResponse.Etag with
            | Some etag -> etagStore.[runsUrl] <- etag
            | None -> ()

            let currentRuns = 
                match runsResponse.Data with
                | Some runs -> 
                    lastKnownRuns <- Some runs
                    runs
                | None -> 
                    match lastKnownRuns with
                    | Some runs -> 
                        logger.LogTrace("No changes in workflow runs, using last known runs.")
                        runs
                    | None -> 
                        logger.LogWarning("No workflow run data available.")
                        Array.empty

            for run in currentRuns do
                let jobsUrl = sprintf "https://api.github.com/repos/%s/%s/actions/runs/%d/jobs" owner repo run.Id
                let! jobsResponse = getJobsForRun logger client owner repo run.Id accessToken (etagStore.TryGetValue(jobsUrl) |> snd |> Some)
                
                match jobsResponse.Etag with
                | Some etag -> etagStore.[jobsUrl] <- etag
                | None -> ()

                match jobsResponse.Data with
                | Some jobs ->
                    let pendingJobs = jobs |> Array.filter (fun job -> job.Status = "queued" || job.Status = "in_progress")
                    if pendingJobs.Length > 0 then
                        logger.LogInformation("Found {PendingJobCount} pending jobs:", pendingJobs.Length)
                        for job in pendingJobs do
                            handlePendingJob logger run job executorConfig owner repo accessToken

                | None -> 
                    logger.LogInformation("No new job data for run {RunId}.", run.Id)

                let! rateLimit = getRateLimitInfo logger client accessToken
                logger.LogTrace("Rate Limit Remaining: {RemainingLimit}", rateLimit.Remaining)
                logger.LogTrace("Rate Limit Reset Time: {ResetTime}", 
                    DateTimeOffset.FromUnixTimeSeconds(rateLimit.Reset).ToString("yyyy-MM-dd HH:mm:ss"))
                do! waitForRateLimit logger rateLimit

            let! finalRateLimit = getRateLimitInfo logger client accessToken
            do! waitForRateLimit logger finalRateLimit
    }

[<EntryPoint>]
let main argv =
    match argv with
    | [| repoUrl; baseScriptDir |] ->
        let loggerFactory = LoggerFactory.Create(fun builder ->
            builder.AddProvider(new SingleLineLoggerProvider(LogLevel.Information))
                   .SetMinimumLevel(LogLevel.Information)
            |> ignore
        )
        let logger = loggerFactory.CreateLogger("GitHubPoller")
        
        logger.LogInformation("Starting GitHub poller...")
        let owner, repo = parseRepoUrl repoUrl
        let accessToken = getGithubAppToken()
        logger.LogInformation("Polling repository: {Owner}/{Repo}", owner, repo)
        logger.LogInformation("Using scripts from directory: {ScriptDir}", baseScriptDir)
        
        use client = new HttpClient()
        client.DefaultRequestHeaders.UserAgent.ParseAdd("FSharp-Poller")
        
        let executorConfig = {
            PrepareScript = "prepare.sh"
            RunScript = "run.sh"
            CleanupScript = "cleanup.sh"
            BaseDirectory = baseScriptDir
        }
        
        pollGitHub logger client owner repo accessToken executorConfig
        |> Async.AwaitTask 
        |> Async.RunSynchronously
        0
    | _ ->
        printfn "Usage: dotnet run <github-repo-url> <base-script-directory>"
        1
